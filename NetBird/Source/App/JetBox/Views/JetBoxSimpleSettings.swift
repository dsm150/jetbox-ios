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
    @EnvironmentObject private var viewModel: ViewModel
    @EnvironmentObject private var jetbox: JetBoxOnboarding
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
    @State private var confirmsSignOut = false
    @State private var isSigningOut = false
    @State private var confirmsDelete = false
    @State private var deleteFailed = false
    @State private var isDeleting = false

    private var boxName: String? { demoBoxName ?? JetBoxStore.currentBox?.displayName }

    /// Тумблер «весь интернет через мой JetBox» (только сборка США, 1.0 (14)).
    private var showsOwnExitToggle: Bool {
        demoBoxName == nil && JetBoxEdition.showsOwnExitToggle(box: JetBoxStore.currentBox)
    }

    private var ownExitBinding: Binding<Bool> {
        Binding(get: { jetbox.ownExitEnabled },
                set: { jetbox.setOwnExit(enabled: $0, viewModel: viewModel) })
    }

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
                            if showsOwnExitToggle {
                                JBSimpleDivider()
                                Toggle(isOn: ownExitBinding) {
                                    Text(JBText.settingsAllInternet)
                                        .font(JBSimple.font(20, .bold))
                                        .foregroundColor(JBSimple.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .tint(JBSimple.accent)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                            }
                        } else {
                            JBSimpleRow(title: JBText.settingsNoBox)
                        }
                    }
                    if showsOwnExitToggle {
                        Text(JBText.settingsAllInternetFooter)
                            .font(JBSimple.font(17, .semibold))
                            .foregroundColor(JBSimple.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
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

                    JBSimpleSectionLabel(title: JBText.legalSection)
                    JBSimpleCard {
                        Link(destination: JetBoxConfig.privacyPolicyURL) {
                            JBSimpleRow(title: JBText.legalPrivacy, chevron: true)
                        }
                        JBSimpleDivider()
                        Link(destination: JetBoxConfig.termsURL) {
                            JBSimpleRow(title: JBText.legalTerms, chevron: true)
                        }
                        JBSimpleDivider()
                        Link(destination: JetBoxConfig.eulaURL) {
                            JBSimpleRow(title: JBText.legalEULA, chevron: true)
                        }
                    }

                    if boxName != nil {
                        JBSimpleCard {
                            Button { confirmsSignOut = true } label: {
                                JBSimpleRow(title: isSigningOut ? "\(JBText.settingsSignOut)…" : JBText.settingsSignOut,
                                            titleColor: JBSimple.error)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSigningOut || isDeleting)
                            JBSimpleDivider()
                            // Apple 5.1.1(v): удаление аккаунта — под «Sign out».
                            Button { confirmsDelete = true } label: {
                                JBSimpleRow(title: isDeleting ? "\(JBText.settingsDeleteAccount)…" : JBText.settingsDeleteAccount,
                                            titleColor: JBSimple.error)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSigningOut || isDeleting)
                            // Свои alert у кнопки: два .alert на одном виде iOS 15 показывает через раз.
                            .alert(JBText.settingsDeleteTitle, isPresented: $confirmsDelete) {
                                Button(JBText.settingsDeleteAccount, role: .destructive) { deleteAccount() }
                                Button(JBText.cancel, role: .cancel) {}
                            } message: {
                                Text(JBText.settingsDeleteBody)
                            }
                            .alert(JBText.settingsDeleteFailed, isPresented: $deleteFailed) {
                                Button("OK", role: .cancel) {}
                            }
                        }
                        .padding(.top, 10)
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
            .alert(JBText.settingsSignOutTitle, isPresented: $confirmsSignOut) {
                Button(JBText.settingsSignOut, role: .destructive) { signOut() }
                Button(JBText.cancel, role: .cancel) {}
            } message: {
                Text(JBText.settingsSignOutBody)
            }
        }
        .navigationViewStyle(.stack)
        .environment(\.colorScheme, .light)
        .onAppear { if opensAbout { showsAbout = true } }
    }

    /// Выход: туннель выключен, профиль стёрт, главный экран — как у свежей установки.
    private func signOut() {
        // Демо для съёмки ничего не стирает.
        guard demoBoxName == nil else { dismiss(); return }
        isSigningOut = true
        Task {
            await jetbox.signOut(viewModel: viewModel)
            isSigningOut = false
            dismiss()
        }
    }

    /// «Delete account»: Кабинет снимает доступ, дальше — как «Sign out».
    /// Не вышло (сеть, 5xx) — ничего не стёрто, остаёмся в настройках.
    private func deleteAccount() {
        guard demoBoxName == nil else { dismiss(); return }
        isDeleting = true
        Task {
            let result = await jetbox.deleteAccount(viewModel: viewModel)
            isDeleting = false
            if result == .failed { deleteFailed = true } else { dismiss() }
        }
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
    @State private var showsLinks = false

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
                // что в «О программе» стиля «техно», но свёрнуты в одну строку
                // (замечание Алексея 21.11.2026): по нажатию — всё на месте.
                JBSimpleCard {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showsLinks.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            Text(JBText.simpleAboutLinks)
                                .font(JBSimple.font(20, .bold))
                                .foregroundColor(JBSimple.ink)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(JBSimple.muted)
                                .rotationEffect(.degrees(showsLinks ? 180 : 0))
                        }
                        .padding(.horizontal, 20)
                        .frame(minHeight: 66)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showsLinks {
                        JBSimpleDivider()
                        Link(destination: JetBoxConfig.siteURL) {
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
                        Text(JBText.aboutLegal(String(Calendar.current.component(.year, from: Date()))))
                            .font(JBSimple.font(17, .semibold))
                            .foregroundColor(JBSimple.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 6)
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
