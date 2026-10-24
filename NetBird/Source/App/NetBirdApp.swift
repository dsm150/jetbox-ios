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
        // JetBox: разрешение на уведомления спрашивается не при запуске, а когда
        // защита впервые включилась — JetBoxNotifications.requestIfNeeded().

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

#if os(tvOS)
/// Live mirror of the tvOS scene phase.
///
/// `scenePhase` is an `@Environment` value on the App *struct*, so the activation task
/// captures a copy of the struct and keeps reading the phase as it was when the closure
/// was created — the guards after each `await` would re-check a snapshot, not the app.
/// A reference type is read through, so those guards see the phase the app is actually in.
/// iOS reads `UIApplication.shared.applicationState` live and needs none of this; tvOS has
/// no equivalent. Written and read on the main thread only, from the scene callbacks and
/// the `@MainActor` activation task.
private final class ScenePhaseMirror {
    var isActive = false
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

    #if os(tvOS)
    @State private var scenePhaseMirror = ScenePhaseMirror()
    #endif

    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    #endif

    init() {
        // Must run before any Go SDK call so a Go panic during startup is captured too.
        GoCrashCapture.redirect()
        #if os(iOS)
        // JetBox: разовые настройки при запуске — чистка старого флага
        // расширенного режима и «напрямую по умолчанию» (JetBoxStartup).
        JetBoxStartup.run()
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
                        // Seed the mirror before anything can read it: the activation task
                        // below bails out immediately if it still says inactive.
                        scenePhaseMirror.isActive = scenePhase == .active
                        if scenePhase == .active {
                            startActivation(viewModel: viewModel)
                        }
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        // Update the mirror first — it is what the in-flight activation
                        // task re-checks after each await to notice it has been superseded.
                        scenePhaseMirror.isActive = newPhase == .active
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
                // early — taking every side effect of the state with it. Apply them here
                // instead.
                //
                // Launching (or foregrounding) onto an already-connected tunnel would
                // otherwise leave the exit node selector stuck on "No exit nodes
                // available" until the user visits the Resources tab, whose own onAppear
                // does the fetch. Foregrounding onto a tunnel that dropped while the app
                // was away is the mirror case: the routes are never cleared, so the
                // selector stays enabled over nodes the core can no longer apply. And a
                // tunnel that connected while the app was away — the usual end of a
                // login-required cycle, which disarms On Demand at the manager — needs its
                // On Demand rules put back, which is the other half of this call.
                //
                // loadCurrentConnectionState can await past this activation's lifetime:
                // its 200 ms retry sleep uses `try?`, which swallows cancellation. The
                // assignment above is a cheap local update, but the work below is IPC —
                // don't do it for an activation already superseded.
                guard isAppActive, !Task.isCancelled else { return }
                viewModel.applyStatusSideEffects(for: initialStatus)
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
            viewModel.checkMDMPolicyAppliedFlag()
            // The OS writes managed configuration from another process, and
            // UserDefaults.didChangeNotification does not cross that boundary,
            // so the in-process observer never fires for it. Re-read on every
            // activation, which is when a policy pushed while the app was away
            // has to take effect - not least so disableAutoConnect disarms the
            // On Demand rules.
            viewModel.refreshMDMRestrictions()
            #endif
            viewModel.startPollingDetails()
        }
    }

    private func stopActivation(viewModel: ViewModel) {
        activationTask?.cancel()
        activationTask = nil
        viewModel.stopPollingDetails()
    }

    /// The app's *current* foreground state, safe to re-check after an `await`.
    private var isAppActive: Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .active
        #else
        // Not `scenePhase`: see ScenePhaseMirror.
        scenePhaseMirror.isActive
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
