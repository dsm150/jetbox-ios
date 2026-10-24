//
//  JetBoxGlass.swift
//  JetBox
//
//  Кнопки в языке Liquid Glass. На iOS 26 — системное стекло Apple
//  (.glass / .glassProminent), на iOS 15–25 — тот же силуэт: заливная
//  капсула для главного действия и материал для второстепенного.
//

import SwiftUI

#if os(iOS)
import UIKit

/// Тактильный отклик: нажатие и успешное подключение.
enum JBHaptics {
    static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// Капсула действия во всю ширину.
struct JBGlassButton: View {
    enum Role { case primary, secondary }

    let title: String
    var role: Role = .primary
    let action: () -> Void

    init(_ title: String, role: Role = .primary, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            JBGlassCapsule(title: title, role: role, action: action)
        } else {
            Button(action: action) {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(JBLegacyCapsuleStyle(role: role))
        }
    }
}

@available(iOS 26.0, *)
private struct JBGlassCapsule: View {
    let title: String
    let role: JBGlassButton.Role
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)

        if role == .primary {
            button.buttonStyle(.glassProminent).tint(JBColor.accent)
        } else {
            button.buttonStyle(.glass).foregroundStyle(JBColor.text)
        }
    }
}

private struct JBLegacyCapsuleStyle: ButtonStyle {
    let role: JBGlassButton.Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(role == .primary ? .white : JBColor.text)
            .background(
                Capsule().fill(role == .primary
                               ? AnyShapeStyle(JBColor.accent)
                               : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(
                Capsule().strokeBorder(JBColor.line.opacity(role == .primary ? 0 : 1), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Круглая кнопка-значок (настройки в шапке).
struct JBGlassIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.title3)
                    .foregroundStyle(JBColor.text)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(label)
        } else {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.title3)
                    .foregroundColor(JBColor.text)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(JBColor.line, lineWidth: 1))
            }
            .accessibilityLabel(label)
        }
    }
}

#endif
