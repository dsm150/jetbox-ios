import SwiftUI
import WidgetKit

/// Виджет в стиле «простое» (макет 20.11.2026): белая карточка, дом в
/// фиолетовой плитке, «JetBox», состояние и фиолетовый тумблер. Действия те же,
/// что у прежнего вида, — через `WidgetActionButton`.
enum SimpleWidgetStyle {
    static let accent = Color(red: 0x74 / 255, green: 0x57 / 255, blue: 0xEE / 255)
    static let accentTint = Color(red: 0xEF / 255, green: 0xEA / 255, blue: 0xFE / 255)
    static let ink = Color(red: 0x1F / 255, green: 0x1A / 255, blue: 0x2E / 255)
    static let muted = Color(red: 0x5D / 255, green: 0x58 / 255, blue: 0x70 / 255)
    static let off = Color(red: 0xD6 / 255, green: 0xD2 / 255, blue: 0xE3 / 255)

    /// Стиль выбирается в настройках приложения и лежит в App Group.
    static var isSimple: Bool {
        UserDefaults(suiteName: WidgetConstants.appGroupSuite)?.string(forKey: "jetbox.style") == "simple"
    }
}

struct SimpleWidgetView: View {
    let entry: VPNStatusEntry
    let family: WidgetFamily

    private typealias S = SimpleWidgetStyle

    var body: some View {
        if family == .systemMedium {
            HStack(spacing: 14) {
                tile(size: 58)
                VStack(alignment: .leading, spacing: 2) {
                    title
                    status
                }
                Spacer(minLength: 4)
                action(width: 64, height: 36)
            }
            .padding(.horizontal, 6)
        } else {
            VStack(spacing: 6) {
                tile(size: 46)
                title
                status
                action(width: 54, height: 30)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tile(size: CGFloat) -> some View {
        Image(systemName: "house.fill")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundColor(entry.isConnected ? .white : S.accent)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(entry.isConnected ? S.accent : S.accentTint))
    }

    private var title: some View {
        Text("JetBox")
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundColor(S.ink)
            .lineLimit(1)
    }

    private var status: some View {
        Text(entry.status.displayText)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(entry.isConnected ? S.accent : S.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func action(width: CGFloat, height: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            WidgetActionButton(entry: entry) {
                toggle(isOn: false, width: width, height: height)
            } label: { isConnected in
                toggle(isOn: isConnected, width: width, height: height)
            }
        } else if let url = entry.fallbackDeepLink {
            Link(destination: url) {
                toggle(isOn: entry.isConnected, width: width, height: height)
            }
        }
    }

    private func toggle(isOn: Bool, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? S.accent : S.off)
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                .padding(3)
        }
        .frame(width: width, height: height)
        .accessibilityLabel(isOn ? "Отключить JetBox" : "Подключить JetBox")
        .accessibilityValue(isOn ? "Вкл" : "Выкл")
        .accessibilityAddTraits(.isButton)
    }
}
