//
//  JetBoxSimpleSettings.swift
//  JetBox
//
//  Настройки и «О программе» в стиле «простое». Пункты те же, что у «техно»:
//  имя JetBox, оформление, о программе, версия (семь нажатий открывают
//  расширенные настройки — как и раньше).
//

import SwiftUI

#if os(iOS)

struct JetBoxSimpleSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(JetBoxAdvancedAccess.unlockedKey, store: JetBoxAdvancedAccess.defaults)
    private var advancedUnlocked = false
    @AppStorage(JetBoxAdvancedAccess.modeKey, store: JetBoxAdvancedAccess.defaults)
    private var advancedMode = false
    @AppStorage(JetBoxStyle.key, store: JetBoxStyle.defaults)
    private var styleRaw = JetBoxStyle.fallback.rawValue

    /// Демо для съёмки: имя дома приходит параметром, а не из хранилища.
    var demoBoxName: String?
    var opensAbout = false

    @State private var unlockCounter = AdvancedUnlockCounter()
    @State private var toast: String?
    @State private var toastToken = 0
    @State private var showsAbout = false

    private var boxName: String? { demoBoxName ?? JetBoxStore.currentBox?.displayName }

    private var style: Binding<JetBoxStyle> {
        Binding(get: { JetBoxStyle(rawValue: styleRaw) ?? JetBoxStyle.fallback },
                set: { styleRaw = $0.rawValue; JetBoxStyle.styleDidChange() })
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    JBSimpleHeader(title: JBText.settingsTitle, trailingTitle: JBText.close) { dismiss() }

                    JBSimpleSectionLabel(title: JBText.settingsSectionBox)
                    JBSimpleCard {
                        if let boxName {
                            JBSimpleRow(title: JBText.settingsBoxName, value: boxName)
                        } else {
                            JBSimpleRow(title: JBText.settingsNoBox)
                        }
                    }

                    JBSimpleSectionLabel(title: JBText.settingsSectionApp)
                    JBSimpleCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(JBText.styleTitle)
                                .font(JBSimple.font(20, .bold))
                                .foregroundColor(JBSimple.ink)
                            JBSimpleStylePicker(style: style)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        JBSimpleDivider()
                        NavigationLink(isActive: $showsAbout) {
                            JetBoxSimpleAboutView()
                        } label: {
                            JBSimpleRow(title: JBText.aboutTitle, chevron: true)
                        }
                        .buttonStyle(.plain)
                    }

                    if advancedUnlocked {
                        JBSimpleCard {
                            Button {
                                advancedMode = true
                                dismiss()
                            } label: {
                                JBSimpleRow(title: JBText.settingsAdvanced, chevron: true, titleColor: JBSimple.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 10)
                    }

                    // Строка версии — вход в расширенные настройки (семь нажатий).
                    Button { tapVersion() } label: {
                        Text("\(JBText.settingsVersion) \(appVersion)")
                            .font(JBSimple.font(17, .semibold))
                            .foregroundColor(JBSimple.muted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .background(JBSimple.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(JBSimple.font(17, .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(JBSimple.ink.opacity(0.92)))
                        .padding(.bottom, 28)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: toast)
        }
        .navigationViewStyle(.stack)
        .environment(\.colorScheme, .light)
        .onAppear { if opensAbout { showsAbout = true } }
    }

    private func tapVersion() {
        switch unlockCounter.tap(isUnlocked: advancedUnlocked) {
        case .silent:
            break
        case .hint(let remaining):
            show(JBText.settingsAdvancedHint(remaining))
        case .unlocked:
            JetBoxAdvancedAccess.unlock()
            advancedUnlocked = true
            show(JBText.settingsAdvancedUnlocked)
        case .alreadyUnlocked:
            show(JBText.settingsAdvancedAlready)
        }
    }

    private func show(_ text: String) {
        toast = text
        toastToken += 1
        let token = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if toastToken == token { toast = nil }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

struct JetBoxSimpleAboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .heavy))
                        Text(JBText.settingsTitle)
                            .font(JBSimple.font(19, .heavy))
                    }
                    .foregroundColor(JBSimple.accent)
                    .frame(minHeight: 44)
                }

                Image("jetbox-simple-app-about")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Text(JBText.simpleAboutTitle)
                    .font(JBSimple.font(30, .black))
                    .foregroundColor(JBSimple.ink)

                VStack(alignment: .leading, spacing: 16) {
                    point("shippingbox.fill", JBText.simpleAboutRouter)
                    point("shield.fill", JBText.simpleAboutGuard)
                    point("iphone", JBText.simpleAboutApp)
                    point("eye.slash.fill", JBText.simpleAboutPrivacy)
                }

                // Ссылки и сведения, которые требует GPL-3.0 (§5(d)), — те же,
                // что в «О программе» стиля «техно».
                JBSimpleCard {
                    Link(destination: URL(string: "https://jet-net.net")!) {
                        JBSimpleRow(title: JBText.aboutSite, chevron: true)
                    }
                    JBSimpleDivider()
                    Link(destination: JetBoxConfig.sourceCodeURL) {
                        JBSimpleRow(title: JBText.aboutSource, chevron: true)
                    }
                    JBSimpleDivider()
                    Link(destination: JetBoxConfig.licenseURL) {
                        JBSimpleRow(title: JBText.aboutLicense, chevron: true)
                    }
                }
                .padding(.top, 6)

                Text(JBText.aboutLegal(String(Calendar.current.component(.year, from: Date()))))
                    .font(JBSimple.font(17, .semibold))
                    .foregroundColor(JBSimple.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(JBSimple.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.colorScheme, .light)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            JBSimpleIconTile(systemName: symbol)
            Text(text)
                .font(JBSimple.font(19, .bold))
                .foregroundColor(JBSimple.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}

#endif
