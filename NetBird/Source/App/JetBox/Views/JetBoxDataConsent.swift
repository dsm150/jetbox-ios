//
//  JetBoxDataConsent.swift
//  JetBox
//
//  Экран «какие данные собираем» — до входа и первого подключения в сборке
//  США (задача руководителя 22.11.2026, сборка 1.0 (18); App Review 5.1.1).
//  Перечень сверен с Privacy Policy (jetbox.ai-boss.us/legal/#privacy,
//  раздел What we collect) и PrivacyInfo.xcprivacy: email, сведения об
//  устройстве, сетевые адреса и открытый ключ. Согласие хранится в App Group,
//  а контейнер App Group в бэкап не идёт — на новом телефоне экран покажется снова.
//

import SwiftUI

#if os(iOS)

enum JetBoxDataConsent {
    static let acceptedKey = "jetbox.dataConsentAccepted.v1"

    static var defaults: UserDefaults { JetBoxAdvancedAccess.defaults }

    static var isAccepted: Bool { defaults.bool(forKey: acceptedKey) }

    static func accept(defaults: UserDefaults = defaults) {
        defaults.set(true, forKey: acceptedKey)
    }

    /// Экран нужен только в сборке США и только пока согласия нет.
    static func needsConsent(homeOnly: Bool = JetBoxEdition.homeOnly, accepted: Bool = isAccepted) -> Bool {
        homeOnly && !accepted
    }
}

struct JetBoxDataConsentView: View {
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            JBSimple.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    JetBoxLogo(markHeight: 34)
                        .padding(.top, 8)
                        .padding(.bottom, 24)

                    Text(JBText.consentTitle)
                        .font(JBSimple.font(30, .black))
                        .foregroundColor(JBSimple.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(JBText.consentIntro)
                        .font(JBSimple.secondary)
                        .foregroundColor(JBSimple.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.bottom, 22)

                    JBSimpleCard {
                        item(icon: "envelope.fill", title: JBText.consentEmailTitle, body: JBText.consentEmailBody)
                        JBSimpleDivider()
                        item(icon: "iphone", title: JBText.consentDeviceTitle, body: JBText.consentDeviceBody)
                        JBSimpleDivider()
                        item(icon: "key.fill", title: JBText.consentNetworkTitle, body: JBText.consentNetworkBody)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        JBSimpleIconTile(systemName: "eye.slash.fill")
                        Text(JBText.consentNever)
                            .font(JBSimple.font(17, .semibold))
                            .foregroundColor(JBSimple.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 22)

                    Link(destination: JetBoxConfig.privacyPolicyURL) {
                        Text(JBText.consentReadPolicy)
                            .font(JBSimple.font(19, .heavy))
                            .foregroundColor(JBSimple.accent)
                    }
                    .padding(.top, 22)
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                JBSimplePrimaryButton(JBText.consentAccept, action: onAccept)
                JBSimpleConsent()
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(JBSimple.background.ignoresSafeArea())
        }
        .environment(\.colorScheme, .light)
    }

    private func item(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            JBSimpleIconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(JBSimple.font(19, .bold))
                    .foregroundColor(JBSimple.ink)
                Text(body)
                    .font(JBSimple.font(17, .semibold))
                    .foregroundColor(JBSimple.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

#endif
