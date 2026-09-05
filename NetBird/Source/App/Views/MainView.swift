//
//  MainView.swift
//  NetBirdiOS
//
//  Created by Pascal Fischer on 01.08.23.
//

import SwiftUI
import NetworkExtension

// MARK: - Main Entry Point
/// The root view that switches between iOS and tvOS layouts.
struct MainView: View {
    @EnvironmentObject var viewModel: ViewModel

    var body: some View {
        #if os(tvOS)
        // tvOS uses a completely different navigation structure
        TVMainView()
        #else
        // iOS uses tab bar navigation
        iOSMainView()
        #endif
    }
}

#if os(iOS)

enum MainAlertType: String, Identifiable {
    case changeServer
    case serverChanged
    case preSharedKeyChanged
    case authenticationRequired
    case onDemandConflict
    case onDemandDisconnect

    var id: String { rawValue }
}

struct iOSMainView: View {
    @EnvironmentObject var viewModel: ViewModel
    // JetBox: режим «одной кнопки», приходит из NetBirdApp.
    @EnvironmentObject var jetbox: JetBoxOnboarding
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab = 0
    @State private var activeAlert: MainAlertType?

    init() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(named: "BgNavigationBar")
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(named: "TextPrimary") ?? .white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(named: "TextPrimary") ?? .white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(named: "BgNavigationBar")
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some View {
        ZStack {
            if !hasCompletedOnboarding {
                FirstLaunchView(
                    hasCompletedOnboarding: $hasCompletedOnboarding,
                    onChangeServer: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            activeAlert = .changeServer
                        }
                    }
                )
            } else {
                mainContent
            }

            // JetBox: экран «одной кнопки» перекрывает всё остальное, пока
            // идёт сценарий «ссылка из Кабинета → подключено».
            if jetbox.step != .idle {
                JetBoxConnectView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: jetbox.step)
        .alert(item: $activeAlert) { alertType in
            switch alertType {
            case .changeServer:
                return Alert(
                    title: Text("Change server"),
                    message: Text("Changing server will erase the local config and disconnect this device from the current NetBird account."),
                    primaryButton: .destructive(Text("Confirm")) {
                        viewModel.handleServerChanged()
                        viewModel.navigateToServerView = true
                    },
                    secondaryButton: .cancel()
                )
            case .serverChanged:
                return Alert(
                    title: Text("Server was changed"),
                    message: Text("Click on the connect button to continue."),
                    dismissButton: .default(Text("OK"))
                )
            case .preSharedKeyChanged:
                return Alert(
                    title: Text("Preshared key was set"),
                    message: Text("Click on the connect button to continue."),
                    dismissButton: .default(Text("OK"))
                )
            case .authenticationRequired:
                if viewModel.connectOnDemand {
                    return Alert(
                        title: Text("Authentication required"),
                        message: Text("The server requires a new authentication."),
                        primaryButton: .default(Text("Connect")) {
                            viewModel.connect()
                        },
                        secondaryButton: .cancel(Text("Later"))
                    )
                }
                return Alert(
                    title: Text("Authentication required"),
                    message: Text("The server requires a new authentication."),
                    primaryButton: .default(Text("Login")) {
                        viewModel.connect()
                    },
                    secondaryButton: .cancel(Text("Later"))
                )
            case .onDemandConflict:
                return Alert(
                    title: Text("VPN On Demand Conflict"),
                    message: Text("Your current On Demand rules prevent connecting on this network. Would you like to disable VPN On Demand and connect?"),
                    primaryButton: .default(Text("Disable & Connect")) {
                        viewModel.connectWithOnDemandDisabled()
                    },
                    secondaryButton: .cancel(Text("Edit Rules")) {
                        selectedTab = 3 // Switch to Settings tab
                    }
                )
            case .onDemandDisconnect:
                return Alert(
                    title: Text("VPN On Demand Active"),
                    message: Text("VPN On Demand is enabled and will automatically reconnect the VPN based on your rules. Do you want to disable On Demand and disconnect?"),
                    primaryButton: .destructive(Text("Disable & Disconnect")) {
                        viewModel.closeWithOnDemandDisabled()
                    },
                    secondaryButton: .default(Text("Cancel")) {
                        
                    }
                )
            }
        }
    }

    private var mainContent: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationView {
                    iOSConnectionView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
                .tag(0)

                NavigationView {
                    iOSPeersView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("Peers", systemImage: "person.3.fill")
                }
                .tag(1)

                NavigationView {
                    iOSNetworksView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("Resources", systemImage: "globe")
                }
                .tag(2)

                NavigationView {
                    iOSSettingsView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
            }
            .onChange(of: viewModel.navigateToServerView) { newValue in
                if newValue {
                    selectedTab = 0
                }
            }
            .onChange(of: viewModel.showChangeServerAlert) { show in
                if show { activeAlert = .changeServer; viewModel.showChangeServerAlert = false }
            }
            .onChange(of: viewModel.showServerChangedInfo) { show in
                if show { activeAlert = .serverChanged; viewModel.showServerChangedInfo = false }
            }
            .onChange(of: viewModel.showPreSharedKeyChangedInfo) { show in
                if show { activeAlert = .preSharedKeyChanged; viewModel.showPreSharedKeyChangedInfo = false }
            }
            .onChange(of: viewModel.showAuthenticationRequired) { show in
                if show { activeAlert = .authenticationRequired; viewModel.showAuthenticationRequired = false }
            }
            .onChange(of: viewModel.showOnDemandConflictAlert) { show in
                if show { activeAlert = .onDemandConflict; viewModel.showOnDemandConflictAlert = false }
            }
            .onChange(of: viewModel.showOnDemandDisconnectAlert) { show in
                if show { activeAlert = .onDemandDisconnect; viewModel.showOnDemandDisconnectAlert = false }
            }

            // Toast alerts
            VStack {
                Spacer()
                if viewModel.showFqdnCopiedAlert {
                    HStack {
                        Image("logo-onboarding")
                            .resizable()
                            .frame(width: 20, height: 15)
                        Text("Domain name copied!")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                    .padding(5)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
                    .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                    .animation(.default, value: viewModel.showFqdnCopiedAlert)
                    .zIndex(1)
                }

                if viewModel.showIpCopiedAlert {
                    HStack {
                        Image("logo-onboarding")
                            .resizable()
                            .frame(width: 20, height: 15)
                        Text("IP address copied!")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                    .padding(5)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
                    .transition(AnyTransition.opacity.combined(with: .move(edge: .top)))
                    .animation(.default, value: viewModel.showIpCopiedAlert)
                    .zIndex(1)
                }
                Spacer().frame(height: 80)
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}

#endif  // os(iOS)


#if os(iOS)

// MARK: - JetBox one-button screen
//
//  Добавлено форком JetBox. Всё, что видит клиент после перехода по ссылке
//  из Кабинета: имя коробки, маска ключа и одна кнопка.

struct JetBoxConnectView: View {
    @EnvironmentObject var viewModel: ViewModel
    @EnvironmentObject var jetbox: JetBoxOnboarding

    /// Туннель поднялся — показываем «Вы под защитой JetBox».
    private var isProtected: Bool {
        if case .connecting = jetbox.step { return viewModel.vpnDisplayState == .connected }
        return false
    }

    var body: some View {
        ZStack {
            Color("BgPrimary").ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Text("JetBox")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundColor(Color("TextPrimary"))

                content

                Spacer()

                if case .failed = jetbox.step {
                    Button("Закрыть") { jetbox.cancel() }
                        .foregroundColor(Color("TextSecondary"))
                        .padding(.bottom, 24)
                } else if isProtected {
                    Button("Готово") { jetbox.cancel() }
                        .foregroundColor(Color("TextSecondary"))
                        .padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch jetbox.step {
        case .idle:
            EmptyView()

        case .ready(let payload):
            VStack(spacing: 10) {
                Text("Ваша коробка")
                    .font(.footnote)
                    .foregroundColor(Color("TextSecondary"))
                Text(payload.managementURL)
                    .font(.custom("JetBrainsMono-Regular", size: 14))
                    .foregroundColor(Color("TextPrimary"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Ключ: \(payload.maskedKey)")
                    .font(.custom("JetBrainsMono-Regular", size: 13))
                    .foregroundColor(Color("TextSecondary"))
            }

            AppButton("Подключить") {
                jetbox.connect(viewModel: viewModel)
            }
            .padding(.top, 8)

        case .registering:
            progress("Регистрируем устройство…")

        case .connecting:
            if isProtected {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.green)
                    Text("Вы под защитой JetBox")
                        .font(.title3.bold())
                        .foregroundColor(Color("TextPrimary"))
                }
            } else {
                progress("Подключаем…")
            }

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.orange)
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color("TextPrimary"))
            }
        }
    }

    private func progress(_ title: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(title)
                .font(.body)
                .foregroundColor(Color("TextPrimary"))
        }
    }
}

#endif  // os(iOS)
