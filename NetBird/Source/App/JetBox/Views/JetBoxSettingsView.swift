//
//  JetBoxSettingsView.swift
//  JetBox
//
//  Настройки простого режима: что за коробка, версия, о программе и один
//  ненавязчивый тумблер «расширенный режим». Включённый тумблер возвращает
//  апстримовые вкладки NetBird целиком — они спрятаны флагом, а не удалены,
//  чтобы ребейз на новый тег апстрима оставался дешёвым.
//

import SwiftUI

#if os(iOS)

struct JetBoxSettingsView: View {
    @EnvironmentObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(JetBoxStore.advancedModeKey) private var advancedMode = false

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
                    JBRow(title: JBText.settingsVersion, value: appVersion)
                    NavigationLink(JBText.aboutTitle) { JetBoxAboutView() }
                } header: {
                    Text(JBText.settingsSectionApp)
                }

                JetBoxAdvancedModeSection(advancedMode: $advancedMode)
            }
            .jetBoxListBackground()
            .navigationTitle(JBText.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(JBText.close) { dismiss() }
                }
            }
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
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle(JBText.aboutTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Тумблер простого/расширенного режима для апстримового экрана настроек.
/// Живёт здесь, а не в чужом файле: во врезку уходит одна строка.
struct JetBoxAdvancedModeSection: View {
    @Binding var advancedMode: Bool

    var body: some View {
        Section {
            Toggle(JBText.settingsAdvanced, isOn: $advancedMode)
                .tint(JBColor.accent)
        } footer: {
            Text(JBText.settingsAdvancedFooter)
        }
    }
}

#endif
