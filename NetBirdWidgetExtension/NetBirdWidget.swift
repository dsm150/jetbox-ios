import WidgetKit
import SwiftUI

/// Виджет «простое» — только в сборке США; в русской его нет вовсе
/// (SimpleWidgetView.swift не собирается, слово владельца 23.11.2026).
enum WidgetLook {
    static var isSimple: Bool {
        #if JETBOX_US
        return SimpleWidgetStyle.isSimple
        #else
        return false
        #endif
    }
}

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: VPNStatusEntry

    var body: some View {
        if WidgetLook.isSimple {
            #if JETBOX_US
            SimpleWidgetView(entry: entry, family: family)
            #endif
        } else {
            classic
        }
    }

    @ViewBuilder
    private var classic: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

struct NetBirdWidget: Widget {
    let kind = "NetBirdWidgetExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VPNStatusProvider()) { entry in
            if #available(iOS 17.0, *) {
                if WidgetLook.isSimple {
                    WidgetEntryView(entry: entry)
                        .containerBackground(Color.white, for: .widget)
                } else {
                    WidgetEntryView(entry: entry)
                        .containerBackground(.fill.tertiary, for: .widget)
                }
            } else {
                WidgetEntryView(entry: entry)
                    .padding()
            }
        }
        .configurationDisplayName("JetBox")
        .description("Connect or disconnect JetBox with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
