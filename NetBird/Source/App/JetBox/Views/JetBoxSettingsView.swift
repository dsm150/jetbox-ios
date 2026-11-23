//
//  JetBoxSettingsView.swift
//  JetBox
//
//  Настройки простого режима: что за JetBox, версия и о программе.
//
//  Служебные экраны NetBird спрятаны за «семью нажатиями» по строке версии —
//  как «Для разработчиков» в Android. Обычный клиент туда не проваливается,
//  а поддержка открывает их по телефону за пять секунд. Сами экраны спрятаны
//  флагом, а не удалены, чтобы ребейз на новый тег апстрима оставался дешёвым.
//

import SwiftUI

#if os(iOS)

struct JetBoxSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel
    @EnvironmentObject private var jetbox: JetBoxOnboarding
    @Environment(\.dismiss) private var dismiss
    @AppStorage(JetBoxAdvancedAccess.unlockedKey, store: JetBoxAdvancedAccess.defaults)
    private var advancedUnlocked = false
    @AppStorage(JetBoxAdvancedAccess.modeKey, store: JetBoxAdvancedAccess.defaults)
    private var advancedMode = false
    @AppStorage(JetBoxStyle.key, store: JetBoxStyle.defaults)
    private var styleRaw = JetBoxStyle.fallback.rawValue

    /// Счётчик нажатий по строке версии живёт ровно столько, сколько открыт
    /// экран: ушёл и вернулся — считаем заново.
    @State private var unlockCounter = AdvancedUnlockCounter()
    @State private var toast: String?
    @State private var toastToken = 0
    @State private var confirmsSignOut = false
    @State private var isSigningOut = false
    @State private var confirmsDelete = false
    @State private var deleteFailed = false
    @State private var isDeleting = false

    private var box: JetBoxBox? { JetBoxStore.currentBox }

    var body: some View {
        NavigationView {
            List {
                Section {
                    if let box {
                        JBRow(title: JBText.settingsBoxName, value: box.displayName)
                    } else {
                        Text(JBText.settingsNoBox)
                            .font(.subheadline)
                            .foregroundColor(JBColor.muted)
                    }
                } header: {
                    Text(JBText.settingsSectionBox)
                }

                // Выбор стиля — только в сборке США; в русской один «техно».
                #if JETBOX_US
                Section(JBText.styleTitle) {
                    Picker(JBText.styleTitle, selection: Binding(
                        get: { JetBoxStyle.resolve(styleRaw) },
                        set: { styleRaw = $0.rawValue; JetBoxStyle.styleDidChange() }
                    )) {
                        ForEach(JetBoxStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                #endif

                Section {
                    // Строка версии — вход в расширенные настройки.
                    // Именно Button, а не .onTapGesture: в строке List нажатия
                    // по обычному тапу до вьюхи не доходят (проверено в
                    // симуляторе — соседний NavigationLink срабатывает, а
                    // onTapGesture молчит).
                    Button { tapVersion() } label: {
                        JBRow(title: JBText.settingsVersion, value: appVersion)
                            // Без contentShape нажимаются только сами надписи:
                            // между «Версия» и номером стоит Spacer, а он
                            // прозрачен для касаний — попасть в строку с
                            // седьмого раза стало бы лотереей.
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    NavigationLink(JBText.aboutTitle) { JetBoxAboutView() }
                } header: {
                    Text(JBText.settingsSectionApp)
                }

                Section(JBText.legalSection) {
                    #if JETBOX_US
                    // Сборка США: соглашение пользователя и политика (Алексей, 23.11.2026).
                    Link(JBText.legalUSAgreement, destination: JetBoxConfig.termsURL)
                    Link(JBText.legalUSPrivacy, destination: JetBoxConfig.privacyPolicyURL)
                    #else
                    Link(JBText.legalPrivacy, destination: JetBoxConfig.privacyPolicyURL)
                    Link(JBText.legalTerms, destination: JetBoxConfig.termsURL)
                    Link(JBText.legalEULA, destination: JetBoxConfig.eulaURL)
                    #endif
                }

                if box != nil {
                    Section {
                        Button(role: .destructive) { confirmsSignOut = true } label: {
                            HStack {
                                Text(JBText.settingsSignOut)
                                if isSigningOut {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSigningOut || isDeleting)
                        // Apple 5.1.1(v): удаление аккаунта — под «Sign out».
                        Button(role: .destructive) { confirmsDelete = true } label: {
                            HStack {
                                Text(JBText.settingsDeleteAccount)
                                if isDeleting {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
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
                }

#if !JETBOX_US
                if advancedUnlocked {
                    Section {
                        Button(JBText.settingsAdvanced) {
                            advancedMode = true
                            dismiss()
                        }
                        .foregroundColor(JBColor.accent)
                    } footer: {
                        Text(JBText.settingsAdvancedFooter)
                    }
                }
#endif
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(JBColor.ink.opacity(0.92)))
                        .padding(.bottom, 28)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: toast)
            .alert(JBText.settingsSignOutTitle, isPresented: $confirmsSignOut) {
                Button(JBText.settingsSignOut, role: .destructive) { signOut() }
                Button(JBText.cancel, role: .cancel) {}
            }
            .navigationTitle(JBText.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(JBText.close) { dismiss() }
                }
            }
        }
    }

    /// Выход: туннель выключен, профиль стёрт, главный экран — как у свежей установки.
    private func signOut() {
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
        isDeleting = true
        Task {
            let result = await jetbox.deleteAccount(viewModel: viewModel)
            isDeleting = false
            if result == .failed { deleteFailed = true } else { dismiss() }
        }
    }

    /// Семь быстрых нажатий по строке версии открывают расширенные настройки;
    /// начиная с четвёртого показываем, сколько осталось.
    private func tapVersion() {
        // Сборка США: расширенного режима нет — строка версии просто строка.
        #if !JETBOX_US
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
        #endif
    }

    private func show(_ text: String) {
        toast = text
        toastToken += 1
        let token = toastToken
        // 2,5 с: русская подсказка длиннее английской, за полторы секунды
        // её не успеваешь прочесть.
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

struct JetBoxAboutView: View {
    var body: some View {
        #if JETBOX_US
        usAbout
        #else
        fullAbout
        #endif
    }

    #if JETBOX_US
    /// About сборки США (Алексей, 23.11.2026): фишки, соглашение, политика и
    /// правообладатель. Текст о данных — на экране согласия перед входом.
    private var usAbout: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    JetBoxLogo(markHeight: 40)
                    ForEach([JBText.simpleAboutRouter, JBText.simpleAboutGuard,
                             JBText.simpleAboutApp, JBText.simpleAboutPrivacy], id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundColor(JBColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
            }
            Section {
                Link(JBText.legalUSAgreement, destination: JetBoxConfig.termsURL)
                Link(JBText.legalUSPrivacy, destination: JetBoxConfig.privacyPolicyURL)
            } footer: {
                Text(JBText.aboutCopyrightUS(String(Calendar.current.component(.year, from: Date()))))
            }
        }
        .navigationTitle(JBText.aboutTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
    #endif

    private var fullAbout: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    JetBoxLogo(markHeight: 40)
                    Text(JBText.aboutBody)
                        .font(.subheadline)
                        .foregroundColor(JBColor.muted)
                    // Что уходит на сервер (App Review 5.1.1) — тот же текст,
                    // что за (i) на экране подключения.
                    Text(JBText.privacyNotice)
                        .font(.subheadline)
                        .foregroundColor(JBColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(JBText.aboutSite, destination: JetBoxConfig.siteURL)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(JBColor.accent)
                    // GPL-3.0 обязывает открыть исходники форка — ссылка
                    // стоит рядом с упоминанием лицензии в тексте выше.
                    Link(JBText.aboutSource, destination: JetBoxConfig.sourceCodeURL)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(JBColor.accent)
                    Link(JBText.aboutLicense, destination: JetBoxConfig.licenseURL)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(JBColor.accent)
                    // Сведения, которые GPL-3.0 §5(d) требует показывать в
                    // интерфейсе: авторские права, отсутствие гарантий, лицензия.
                    Text(JBText.aboutLegal(String(Calendar.current.component(.year, from: Date()))))
                        .font(.footnote)
                        .foregroundColor(JBColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle(JBText.aboutTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Выход из расширенных настроек — первой секцией апстримового экрана Settings.
/// Живёт здесь, а не в чужом файле: во врезку уходит одна строка.
///
/// Выключение закрывает и доступ: пункт «Расширенные настройки» исчезает,
/// и чтобы вернуться, снова нужны семь нажатий. Иначе «выключил» превращается
/// в «спрятал на один тап», а именно от этого режим и прячут.
#if !JETBOX_US
struct JetBoxAdvancedModeSection: View {
    @Binding var advancedMode: Bool

    var body: some View {
        Section {
            Button(JBText.settingsAdvancedOff) {
                JetBoxAdvancedAccess.lock()
                advancedMode = false
            }
            .foregroundColor(JBColor.accent)
        } footer: {
            Text(JBText.settingsAdvancedOffFooter)
        }
    }
}
#endif  // !JETBOX_US

#endif
