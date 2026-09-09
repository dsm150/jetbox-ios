import WidgetKit
import SwiftUI

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: VPNStatusEntry

    var body: some View {
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
                WidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                WidgetEntryView(entry: entry)
                    .padding()
            }
        }
        .configurationDisplayName("JetBox")
        .description("Подключение и отключение JetBox одним касанием.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
