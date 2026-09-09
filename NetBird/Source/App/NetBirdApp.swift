//
//  NetBirdApp.swift
//  NetBird
//
//  Created by Pascal Fischer on 01.08.23.
//
//  Main entry point for the NetBird app.
//  Supports both iOS and tvOS platforms.
//

import SwiftUI
import Combine
import UserNotifications
import NetBirdSDK

#if os(iOS)
import WidgetKit
#endif

/// True when the app was launched solely to host unit tests. XCTest sets this
/// environment variable on the test host process.
private var isRunningUnitTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

/// JetBox: телеметрия Google (Firebase Analytics / Crashlytics / Performance)
/// из форка удалена целиком — продукт про приватность, отправлять поведение
/// клиента в Google нечем и незачем. Заглушки оставлены, чтобы точки вызова
/// в жизненном цикле приложения совпадали с апстримом и ребейз был дешёвым.
private func configureFirebaseIfNeeded() {}

/// Апстрим отправлял сюда вывод Go-паники в Crashlytics. В форке паника просто
/// уходит в локальный лог приложения (см. GoCrashCapture).
private func reportPreviousGoCrashIfNeeded() {
    guard let output = GoCrashCapture.takeUnreportedCrashOutput() else { return }

    let headline = output
        .split(whereSeparator: \.isNewline)
        .first { $0.hasPrefix("panic:") || $0.hasPrefix("fatal error:") }
        .map(String.init) ?? "Go runtime crash"

    AppLogger.shared.log("Go crash from a previous session: \(headline)\n\(output)")
}

#if os(iOS)
extension Notification.Name {
    static let netbirdLoginNotificationTapped = Notification.Name("io.netbird.loginNotificationTapped")
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureFirebaseIfNeeded()
        reportPreviousGoCrashIfNeeded()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                AppLogger.shared.log("Notification authorization error: \(error.localizedDescription)")
            } else {
                AppLogger.shared.log("Notification authorization granted: \(granted)")
            }
        }

        return true
    }

    // Show notification banner even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle tap on notification — post event so the app navigates to auth flow
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == GlobalConstants.notificationLoginRequired {
            NotificationCenter.default.post(name: .netbirdLoginNotificationTapped, object: nil)
        }
        completionHandler()
    }
}
#endif

@main
struct NetBirdApp: App {
    @StateObject private var viewModelLoader = ViewModelLoader()
    #if os(iOS)
    // JetBox: состояние режима «одной кнопки» живёт на уровне приложения —
    // ссылка может прийти и до того, как ViewModel успел загрузиться.
    @StateObject private var jetbox = JetBoxOnboarding()
    #endif
    @Environment(\.scenePhase) var scenePhase
    @State private var activationTask: Task<Void, Never>?
    @State private var pendingURL: URL?

    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    #endif

    init() {
        // Must run before any Go SDK call so a Go panic during startup is captured too.
        GoCrashCapture.redirect()
        #if os(iOS)
        // JetBox: расширенные настройки переехали из UserDefaults.standard
        // в App Group и открываются семью нажатиями. Старый флаг убираем,
        // иначе на телефоне, где режим был включён тумблером, он останется
        // включённым в обход семи нажатий.
        JetBoxAdvancedAccess.migrateLegacyFlagIfNeeded()
        #endif
        // Configure Firebase on main thread as required by Firebase
        #if os(tvOS)
        configureFirebaseIfNeeded()
        reportPreviousGoCrashIfNeeded()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if let viewModel = viewModelLoader.viewModel {
                MainView()
                    .environmentObject(viewModel)
                    #if os(iOS)
                    .environmentObject(jetbox)
                    .onOpenURL { url in
                        handleIncomingURL(url, viewModel: viewModel)
                    }
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                        if let url = activity.webpageURL {
                            handleIncomingURL(url, viewModel: viewModel)
                        }
                    }
                    .onAppear {
                        if let url = pendingURL {
                            handleIncomingURL(url, viewModel: viewModel)
                            pendingURL = nil
                        }
                        if UIApplication.shared.applicationState == .active {
                            startActivation(viewModel: viewModel)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        startActivation(viewModel: viewModel)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                        stopActivation(viewModel: viewModel)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .netbirdLoginNotificationTapped)) { _ in
                        viewModel.showAuthenticationRequired = true
                    }
                    #endif
                    #if os(tvOS)
                    .onAppear {
                        if scenePhase == .active {
                            startActivation(viewModel: viewModel)
                        }
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        if newPhase == .active {
                            startActivation(viewModel: viewModel)
                        } else {
                            stopActivation(viewModel: viewModel)
                        }
                    }
                    #endif
            } else {
                loadingView
                    #if os(iOS)
                    .onOpenURL { url in
                        pendingURL = url
                    }
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                        pendingURL = activity.webpageURL
                    }
                    #endif
            }
        }
    }

    // MARK: - Activation

    private func startActivation(viewModel: ViewModel) {
        activationTask?.cancel()
        activationTask = Task { @MainActor in
            guard isAppActive, !Task.isCancelled else { return }

            // JetBox: профиль прежней сборки назывался «NetBird Network Extension».
            // Переименовываем его до чтения состояния — иначе рядом заведётся
            // второй профиль (см. VPNProfileNaming в NetworkExtensionAdapter).
            await viewModel.networkExtensionAdapter.migrateProfileNameIfNeeded()

            if let initialStatus = await viewModel.networkExtensionAdapter.loadCurrentConnectionState() {
                // Clear stale button-press flags before applying the fresh NE state.
                // These flags are only valid for the brief gap between a button tap and
                // the corresponding NE state change; any external change (widget action,
                // On Demand trigger) makes them stale when returning to the foreground.
                viewModel.connectPressed = false
                viewModel.disconnectPressed = false
                viewModel.extensionState = initialStatus
                viewModel.updateVPNDisplayState()

                // Assigning extensionState directly means the checkExtensionState() below
                // hits applyExtensionStatus' `extensionState != status` guard and returns
                // early — taking its route side effects with it. Apply them here instead.
                //
                // Launching (or foregrounding) onto an already-connected tunnel would
                // otherwise leave the exit node selector stuck on "No exit nodes
                // available" until the user visits the Resources tab, whose own onAppear
                // does the fetch. Foregrounding onto a tunnel that dropped while the app
                // was away is the mirror case: the routes are never cleared, so the
                // selector stays enabled over nodes the core can no longer apply.
                //
                // loadCurrentConnectionState can await past this activation's lifetime:
                // its 200 ms retry sleep uses `try?`, which swallows cancellation. The
                // assignment above is a cheap local update, but the route sync below is
                // an IPC round-trip — don't make it for an activation already superseded.
                guard isAppActive, !Task.isCancelled else { return }
                viewModel.applyRouteSideEffects(for: initialStatus)
            } else {
                // No matching VPN profile found — still force a widget timeline refresh so
                // the widget doesn't stay stuck on a transitioning state from a prior
                // widget-initiated disconnect/connect while the app was closed.
                #if os(iOS)
                WidgetCenter.shared.reloadAllTimelines()
                #endif
            }

            guard isAppActive, !Task.isCancelled else { return }
            viewModel.checkExtensionState()
            #if os(iOS)
            viewModel.checkLoginRequiredFlag()
            #endif
            viewModel.startPollingDetails()
        }
    }

    private func stopActivation(viewModel: ViewModel) {
        activationTask?.cancel()
        activationTask = nil
        viewModel.stopPollingDetails()
    }

    private var isAppActive: Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .active
        #else
        scenePhase == .active
        #endif
    }

    private var loadingView: some View {
        ZStack {
            Color("BgPrimary")
                .ignoresSafeArea()
            Image("jetbox-mark")
                .resizable()
                .scaledToFit()
                .frame(width: 180)
        }
    }

    #if os(iOS)
    /// Единая точка входа для всех диплинков.
    ///
    /// JetBox-ссылка из Кабинета (`jetbox://connect#k=…`) обрабатывается первой:
    /// она приводит приложение в режим «одной кнопки». Всё остальное —
    /// апстримовые ссылки виджета.
    private func handleIncomingURL(_ url: URL, viewModel: ViewModel) {
        if jetbox.handle(url) { return }
        handleWidgetURL(url, viewModel: viewModel)
    }

    /// Handles deep link URLs from the Home Screen widget.
    private func handleWidgetURL(_ url: URL, viewModel: ViewModel) {
        guard url.scheme == "netbird" else { return }
        switch url.host {
        case "login":
            viewModel.connect()
        case "connect":
            if viewModel.vpnDisplayState == .disconnected {
                viewModel.connect()
            }
        case "disconnect":
            if viewModel.vpnDisplayState == .connected {
                viewModel.close()
            }
        default:
            break
        }
    }
    #endif
}

/// Loads ViewModel asynchronously to avoid blocking app launch.
/// The Go runtime initialization (from NetBirdSDK) can take several seconds on cold start.
/// By creating the ViewModel in an async Task, the loading screen appears immediately
/// instead of showing a black screen.
@MainActor
class ViewModelLoader: ObservableObject {
    @Published var viewModel: ViewModel?

    init() {
        Task { @MainActor in
            self.viewModel = ViewModel()
        }
    }
}
