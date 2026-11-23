//
//  JetBoxSimpleKit.swift
//  JetBox
//
//  Детали стиля «простое» (макет Алексея 20.11.2026): белый фон, один
//  фиолетовый акцент, крупный округлый шрифт — ничего мельче 17 пунктов.
//  Иконки — SF Symbols в акценте: эмодзи в клиентских материалах запрещены
//  (правило владельца), раскладка макета сохранена.
//
//  Шрифт: макет набран Nunito; здесь системный округлый (SF Rounded) тех же
//  весов — он уже есть на телефоне и не утяжеляет ребейз апстрима.
//

import SwiftUI

#if os(iOS)

enum JBSimple {
    static let accent = Color(jbHex: 0x7457EE)
    static let accentTint = Color(jbHex: 0xEFEAFE)
    static let ink = Color(jbHex: 0x1F1A2E)
    static let muted = Color(jbHex: 0x5D5870)
    static let faint = Color(jbHex: 0x7A7390)
    static let background = Color.white
    static let card = Color(jbHex: 0xF6F4FB)
    static let line = Color(jbHex: 0xEBE8F2)
    static let outline = Color(jbHex: 0xE4E1EC)
    static let offFill = Color(jbHex: 0xF3F2F6)
    static let offDash = Color(jbHex: 0xD6D2E3)
    static let offSymbol = Color(jbHex: 0xB4AEC4)
    static let error = Color(jbHex: 0xC2334D)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Вторичный текст — один стиль на всё приложение: 19 / 600 / приглушённый.
    static let secondary = font(19, .semibold)
}

extension Color {
    init(jbHex hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Кнопки

/// Главная кнопка: 64 пункта, капсула, акцент с тенью.
struct JBSimplePrimaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(JBSimple.font(21, .black))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Capsule().fill(JBSimple.accent))
                .shadow(color: JBSimple.accent.opacity(0.35), radius: 14, x: 0, y: 12)
        }
        .buttonStyle(JBSimplePressStyle())
    }
}

/// Текстовая ссылка-действие: 19 / 800 / акцент.
struct JBSimpleTextButton: View {
    let title: String
    var color: Color = JBSimple.accent
    let action: () -> Void

    init(_ title: String, color: Color = JBSimple.accent, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(JBSimple.font(19, .heavy))
                .foregroundColor(color)
                .frame(minHeight: 44)
        }
    }
}

/// Пилюля «Закрыть» / «Отмена» в шапке.
struct JBSimpleCapsuleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(JBSimple.font(18, .black))
                .foregroundColor(JBSimple.ink)
                .padding(.horizontal, 18)
                .frame(minWidth: 84, minHeight: 48)
                .background(Capsule().fill(JBSimple.card))
        }
        .buttonStyle(JBSimplePressStyle())
    }
}

/// Круглая кнопка-значок шапки (шестерёнка).
struct JBSimpleIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(JBSimple.muted)
                .frame(width: 56, height: 56)
                .background(Circle().fill(JBSimple.card))
        }
        .buttonStyle(JBSimplePressStyle())
        .accessibilityLabel(label)
    }
}

struct JBSimplePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Шапка, карточки, строки

/// Шапка экрана: заголовок по центру, пилюля справа.
struct JBSimpleHeader: View {
    let title: String
    var trailingTitle: String?
    var onTrailing: (() -> Void)?

    var body: some View {
        ZStack {
            Text(title)
                .font(JBSimple.font(22, .black))
                .foregroundColor(JBSimple.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                // Место под пилюлю справа и столько же слева — заголовок по центру.
                .padding(.horizontal, 120)
            HStack {
                Spacer()
                if let trailingTitle, let onTrailing {
                    JBSimpleCapsuleButton(title: trailingTitle, action: onTrailing)
                }
            }
        }
        .frame(minHeight: 56)
    }
}

/// Карточка: фон #F6F4FB, скругление 26.
struct JBSimpleCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(JBSimple.card))
    }
}

/// Подпись секции над карточкой.
struct JBSimpleSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(JBSimple.font(18, .heavy))
            .foregroundColor(JBSimple.muted)
            .padding(.horizontal, 8)
            .padding(.top, 14)
    }
}

/// Строка настроек: подпись 20 / 700, значение 20 / 600 приглушённое, шеврон.
struct JBSimpleRow: View {
    let title: String
    var value: String?
    var chevron = false
    var titleColor: Color = JBSimple.ink

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(JBSimple.font(20, .bold))
                .foregroundColor(titleColor)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(JBSimple.font(20, .semibold))
                    .foregroundColor(JBSimple.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(JBSimple.muted)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 66)
        .contentShape(Rectangle())
    }
}

struct JBSimpleDivider: View {
    var body: some View {
        Rectangle().fill(JBSimple.line).frame(height: 1).padding(.leading, 20)
    }
}

/// Значок в акцентной плитке (вместо эмодзи макета).
struct JBSimpleIconTile: View {
    let systemName: String
    var size: CGFloat = 44
    var tint: Color = JBSimple.accent
    var fill: Color = JBSimple.accentTint

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(fill))
            .accessibilityHidden(true)
    }
}

// MARK: - Большой круг

/// Большой круг главного экрана — он же кнопка. Не подключено: серый с
/// пунктиром; подключаемся: пульс; подключено: акцентная заливка с ореолом.
struct JBSimpleCircle: View {
    let phase: JetBoxShieldPhase
    var diameter: CGFloat = 240
    var accessibilityLabel: String = ""
    var action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Group {
            if let action {
                Button(action: action) { face }
                    .buttonStyle(JBSimplePressStyle())
                    .accessibilityLabel(accessibilityLabel)
            } else {
                face
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
            }
        }
        .frame(width: diameter + 40, height: diameter + 40)
    }

    private var isOn: Bool { phase == .on }

    private var face: some View {
        ZStack {
            if isOn {
                Circle()
                    .fill(JBSimple.accentTint)
                    .frame(width: diameter + 32, height: diameter + 32)
                Circle()
                    .fill(JBSimple.accent)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: JBSimple.accent.opacity(0.45), radius: 30, x: 0, y: 24)
            } else {
                if phase.isWorking {
                    Circle()
                        .fill(JBSimple.accentTint)
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(pulse ? (diameter + 40) / diameter : 1)
                        .opacity(pulse ? 0 : 1)
                }
                Circle()
                    .fill(JBSimple.offFill)
                    .frame(width: diameter, height: diameter)
                Circle()
                    .strokeBorder(phase.isWorking ? JBSimple.accent.opacity(0.55) : JBSimple.offDash,
                                  style: StrokeStyle(lineWidth: 3, dash: [9, 7]))
                    .frame(width: diameter, height: diameter)
            }

            Image(systemName: isOn ? "house.fill" : "house")
                .font(.system(size: diameter * 0.36, weight: .semibold))
                .foregroundColor(isOn ? .white : (phase.isWorking ? JBSimple.accent.opacity(0.7) : JBSimple.offSymbol))

            badge
                .offset(x: diameter * 0.26, y: diameter * 0.26)
        }
        .animation(.easeInOut(duration: 0.35), value: phase)
        .onAppear { startPulse() }
        .onChange(of: phase) { _ in startPulse() }
    }

    private var badge: some View {
        let size = diameter * 0.27
        return ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: JBSimple.ink.opacity(isOn ? 0.18 : 0), radius: 8, x: 0, y: 4)
            if !isOn {
                Circle().strokeBorder(JBSimple.offDash, lineWidth: 2)
            }
            Image(systemName: badgeSymbol)
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundColor(badgeTint)
        }
        .frame(width: size, height: size)
    }

    private var badgeSymbol: String {
        switch phase {
        case .on: return "checkmark.shield.fill"
        case .offline: return "exclamationmark.shield.fill"
        case .working: return "shield.lefthalf.filled"
        case .off: return "shield"
        }
    }

    private var badgeTint: Color {
        switch phase {
        case .on, .working: return JBSimple.accent
        case .offline: return JBSimple.error
        case .off: return JBSimple.offSymbol
        }
    }

    private func startPulse() {
        guard phase.isWorking, !reduceMotion else { pulse = false; return }
        pulse = false
        withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { pulse = true }
    }
}

/// Линия под статусом. `moving` — бегущий пунктир: идёт подключение, проверка
/// дома или переподключение. Иначе — неподвижная сплошная линия цвета статуса:
/// после ответа дома анимация ничего не подсказывает (замечание владельца
/// 23.11.2026, 1.0 (24): бегущий пунктир под «Protected» читался как «подключаемся»).
struct JBSimpleTrafficLine: View {
    var moving: Bool = false
    var color: Color = JBSimple.accent
    var width: CGFloat = 170

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    var body: some View {
        Group {
            if moving {
                Line()
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .butt, dash: [10, 14], dashPhase: phase))
                    .background(Line().stroke(JBSimple.accentTint, lineWidth: 4))
                    .onAppear {
                        guard !reduceMotion else { return }
                        phase = 0
                        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = -24 }
                    }
            } else {
                Line().stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
        .frame(width: width, height: 4)
        .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

/// Переключатель стиля оформления — две пилюли.
struct JBSimpleStylePicker: View {
    @Binding var style: JetBoxStyle

    var body: some View {
        HStack(spacing: 6) {
            ForEach(JetBoxStyle.allCases) { item in
                Button {
                    style = item
                } label: {
                    Text(item.title)
                        .font(JBSimple.font(18, .heavy))
                        .foregroundColor(item == style ? .white : JBSimple.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(item == style ? JBSimple.accent : Color.white))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == style ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Capsule().fill(JBSimple.line))
    }
}

// MARK: - Значок (i) и лист с подробностями

/// Небольшой значок «подробнее» рядом с текстом: второстепенное — за ним.
struct JBSimpleInfoButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(JBSimple.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

/// Компактный лист по высоте содержимого: заголовок, «Закрыть», строки.
struct JBSimpleInfoSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(JBSimple.font(22, .black))
                    .foregroundColor(JBSimple.ink)
                    .lineLimit(2)
                Spacer(minLength: 8)
                JBSimpleCapsuleButton(title: JBText.close) { dismiss() }
            }
            VStack(alignment: .leading, spacing: 12) { content }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: JBSimpleSheetHeight.self, value: proxy.size.height)
        })
        .onPreferenceChange(JBSimpleSheetHeight.self) { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(JBSimple.background.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .jbFittedSheet(height: height)
    }
}

/// Строка листа: подпись слева, значение справа.
struct JBSimpleInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(JBSimple.font(19, .semibold))
                .foregroundColor(JBSimple.muted)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(value)
                .font(JBSimple.font(20, .heavy).monospacedDigit())
                .foregroundColor(JBSimple.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
        .frame(minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(JBSimple.card))
    }
}

private struct JBSimpleSheetHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Согласие с условиями

/// «By continuing, you agree to the Terms of Use and Privacy Policy.» —
/// 17 / 600 / приглушённый, ссылки акцентом (App Review 5.1.1).
struct JBSimpleConsent: View {
    var body: some View {
        Text(LocalizedStringKey(JBText.legalConsent))
            .font(JBSimple.font(17, .semibold))
            .foregroundColor(JBSimple.muted)
            .tint(JBSimple.accent)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#endif
