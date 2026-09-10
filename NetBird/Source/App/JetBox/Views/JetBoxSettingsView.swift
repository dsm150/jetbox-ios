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
    @Environment(\.dismiss) private var dismiss
    @AppStorage(JetBoxAdvancedAccess.unlockedKey, store: JetBoxAdvancedAccess.defaults)
    private var advancedUnlocked = false
    @AppStorage(JetBoxAdvancedAccess.modeKey, store: JetBoxAdvancedAccess.defaults)
    private var advancedMode = false

    /// Счётчик нажатий по строке версии живёт ровно столько, сколько открыт
    /// экран: ушёл и вернулся — считаем заново.
    @State private var unlockCounter = AdvancedUnlockCounter()
    @State private var toast: String?
    @State private var toastToken = 0

    private var box: JetBoxBox? { JetBoxStore.currentBox }

    var body: some View {
        NavigationView {
            List {
                Section(JBText.settingsSectionBox) {
                    if let box {
                        JBRow(title: JBText.settingsBoxName, value: box.displayName)
                        JBRow(title: JBText.settingsServer,
                              value: URL(string: box.managementURL)?.host ?? box.managementURL)
                        JBRow(title: JBText.settingsExit,
                              value: box.effectiveExitNode ?? JBText.homeExitNone)
                    } else {
                        Text(JBText.settingsNoBox)
                            .font(.subheadline)
                            .foregroundColor(JBColor.muted)
                    }
                }

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
            }
            .jetBoxListBackground()
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
            .navigationTitle(JBText.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(JBText.close) { dismiss() }
                }
            }
        }
    }

    /// Семь быстрых нажатий по строке версии открывают расширенные настройки;
    /// начиная с четвёртого показываем, сколько осталось.
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
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    JetBoxLogo(markHeight: 40)
                    Text(JBText.aboutBody)
                        .font(.subheadline)
                        .foregroundColor(JBColor.muted)
                    Link(JBText.aboutSite, destination: URL(string: "https://jet-net.net")!)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(JBColor.accent)
                    // GPL-3.0 обязывает открыть исходники форка — ссылка
                    // стоит рядом с упоминанием лицензии в тексте выше.
                    Link(JBText.aboutSource,
                         destination: URL(string: "https://github.com/dsm150/jetbox-ios")!)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(JBColor.accent)
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

#endif
