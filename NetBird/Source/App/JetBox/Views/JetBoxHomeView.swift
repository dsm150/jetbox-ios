//
//  JetBoxHomeView.swift
//  JetBox
//
//  Главный экран простого режима: состояние защиты, коробка, выход и одна
//  кнопка. Апстримовые вкладки (Peers, Resources, Settings) сюда не приходят —
//  они живут в расширенном режиме и включаются тумблером в настройках.
//

import SwiftUI

#if os(iOS)

struct JetBoxHomeView: View {
    @EnvironmentObject var viewModel: ViewModel
    /// Вложенный ObservableObject сам по себе перерисовку не вызывает —
    /// наблюдаем за списком маршрутов явно, как это делает апстрим
    /// в ExitNodeSelectorCard.
    @ObservedObject var routes: RoutesViewModel
    @State private var showsSettings = false
    @State private var showsExitPicker = false

    private var box: JetBoxBox? { JetBoxStore.currentBox }

    var body: some View {
        ZStack {
            JBColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer(minLength: 12)

                shield
                    .padding(.bottom, 8)

                Text(statusText)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(JBColor.text)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)

                if let box {
                    boxCard(box)
                        .frame(maxWidth: 420)
                } else {
                    noBoxCard
                        .frame(maxWidth: 420)
                }

                Spacer(minLength: 16)

                if box != nil {
                    actionButton
                        .frame(maxWidth: 420)
                        .padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showsSettings) {
            JetBoxSettingsView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showsExitPicker) {
            JetBoxExitSheet(routes: routes)
                .environmentObject(viewModel)
        }
        .onAppear {
            // Селектор выхода читается только через расширение: пока туннеля
            // нет, список пуст — это нормально, обновимся после подключения.
            if viewModel.vpnDisplayState == .connected {
                routes.getRoutes()
            }
        }
    }

    // MARK: - Части экрана

    private var header: some View {
        HStack {
            JetBoxLogo(markHeight: 34)
            Spacer()
            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundColor(JBColor.muted)
                    .padding(8)
            }
            .accessibilityLabel(JBText.settingsTitle)
        }
        .padding(.top, 8)
    }

    private var shield: some View {
        ZStack {
            Circle()
                .fill(shieldColor.opacity(0.12))
                .frame(width: 168, height: 168)
            Image(systemName: shieldSymbol)
                .font(.system(size: 74, weight: .regular))
                .foregroundColor(shieldColor)
                .symbolRenderingMode(.hierarchical)
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.vpnDisplayState)
    }

    private func boxCard(_ box: JetBoxBox) -> some View {
        JBCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(JBText.settingsSectionBox)
                    .font(.footnote)
                    .foregroundColor(JBColor.muted)
                Text(box.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(JBColor.text)
                    .lineLimit(2)
                Divider().overlay(JBColor.line)
                HStack {
                    Text(currentExitName.map { JBText.homeExit($0) } ?? JBText.homeExitNone)
                        .font(.subheadline)
                        .foregroundColor(JBColor.muted)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if viewModel.vpnDisplayState == .connected {
                        Button(JBText.homeChangeExit) { showsExitPicker = true }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(JBColor.accent)
                    }
                }
            }
        }
    }

    private var noBoxCard: some View {
        JBCard {
            VStack(spacing: 10) {
                Text(JBText.homeNoBoxTitle)
                    .font(.headline)
                    .foregroundColor(JBColor.text)
                Text(JBText.homeNoBoxBody)
                    .font(.subheadline)
                    .foregroundColor(JBColor.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var actionButton: some View {
        Group {
            switch viewModel.vpnDisplayState {
            case .connected:
                AppButton(JBText.homeDisconnect, style: .secondary) { viewModel.close() }
            case .disconnected:
                AppButton(JBText.homeConnect) { viewModel.connect() }
            case .connecting, .disconnecting:
                AppButton(statusText, style: .secondary) {}
                    .disabled(true)
                    .opacity(0.6)
            }
        }
    }

    // MARK: - Состояние

    private var currentExitName: String? {
        if let selected = routes.selectedExitNode?.name { return selected }
        return box?.exitNodeName
    }

    private var statusText: String {
        switch viewModel.vpnDisplayState {
        case .connected: return viewModel.isInternetConnected ? JBText.homeConnected : JBText.homeOffline
        case .connecting: return JBText.homeConnecting
        case .disconnecting: return JBText.homeDisconnecting
        case .disconnected: return JBText.homeDisconnected
        }
    }

    private var shieldSymbol: String {
        switch viewModel.vpnDisplayState {
        case .connected: return viewModel.isInternetConnected ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
        case .connecting, .disconnecting: return "shield.lefthalf.filled"
        case .disconnected: return "shield.slash"
        }
    }

    private var shieldColor: Color {
        switch viewModel.vpnDisplayState {
        case .connected: return viewModel.isInternetConnected ? JBColor.ok : JBColor.warn
        case .connecting, .disconnecting: return JBColor.accent
        case .disconnected: return JBColor.muted
        }
    }
}

// MARK: - Смена выхода из простого режима

struct JetBoxExitSheet: View {
    @ObservedObject var routes: RoutesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if routes.exitNodes.isEmpty {
                    Text(JBText.exitPickerEmpty)
                        .font(.subheadline)
                        .foregroundColor(JBColor.muted)
                } else {
                    ForEach(routes.exitNodes) { node in
                        Button {
                            routes.setExitNode(node)
                            JetBoxStore.rememberExitNode(node.name)
                            dismiss()
                        } label: {
                            HStack {
                                Text(node.name)
                                    .foregroundColor(JBColor.text)
                                Spacer()
                                if node.selected {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(JBColor.accent)
                                }
                            }
                        }
                    }
                    Button {
                        routes.setExitNode(nil)
                        JetBoxStore.rememberExitNode(nil)
                        dismiss()
                    } label: {
                        Text(JBText.homeExitNone)
                            .foregroundColor(JBColor.muted)
                    }
                }
            }
            .navigationTitle(JBText.exitPickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(JBText.close) { dismiss() }
                }
            }
            .onAppear { routes.getRoutes() }
        }
    }
}

#endif
