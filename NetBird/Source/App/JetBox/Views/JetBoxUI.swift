//
//  JetBoxUI.swift
//  JetBox
//
//  Мелкие общие детали наших экранов. Иконки только векторные:
//  фирменный знак из ассетов и SF Symbols — никаких эмодзи.
//

import SwiftUI

#if os(iOS)

enum JBColor {
    static let ink = Color("JetBoxInk")
    static let accent = Color("JetBoxAccent")
    static let surface = Color("JetBoxSurface")
    static let line = Color("JetBoxLine")
    static let ok = Color("JetBoxOk")
    static let warn = Color("JetBoxWarn")
    static let danger = Color("JetBoxDanger")
    static let background = Color("BgPrimary")
    static let text = Color("TextPrimary")
    static let muted = Color("TextSecondary")
}

/// Фирменный знак + слово. Знак — вектор из ассетов (light/dark варианты),
/// слово набирается Inter, который уже лежит в проекте.
struct JetBoxLogo: View {
    var markHeight: CGFloat = 44
    var showsWordmark: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image("jetbox-mark")
                .resizable()
                .scaledToFit()
                .frame(height: markHeight)
                .accessibilityHidden(true)

            if showsWordmark {
                Text(JBText.brand)
                    .font(.system(size: markHeight * 0.62, weight: .bold))
                    .foregroundColor(JBColor.ink)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JBText.brand)
    }
}

/// Карточка на фоне страницы: поверхность, мягкая рамка, скругление.
struct JBCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(JBColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(JBColor.line, lineWidth: 1)
            )
    }
}

/// Строка «подпись — значение» для карточек и настроек.
struct JBRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(JBColor.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(JBColor.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }
}

#endif
