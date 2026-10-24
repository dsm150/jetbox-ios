//
//  JetBoxConnectionSheet.swift
//  JetBox
//
//  Подробности подключения — по нажатию на стеклянную панель дома. Выбор
//  выхода здесь появляется, только если сервер отдаёт больше одного выхода:
//  у клиента один дом — и выход у него один (решение владельца 24.10.2026).
//

import SwiftUI

#if os(iOS)

struct JetBoxConnectionSheet: View {
    @ObservedObject var routes: RoutesViewModel
    @ObservedObject var stats: JetBoxLiveStats
    let box: JetBoxBox
    let isConnected: Bool
    var demo: JetBoxLiveStats.Snapshot?
    var demoSince: Date?

    @Environment(\.dismiss) private var dismiss
    @State private var showsExitPicker = false

    private var snapshot: JetBoxLiveStats.Snapshot? { demo ?? stats.box }
    private var since: Date? { demoSince ?? stats.connectedSince }

    var body: some View {
        NavigationView {
            List {
                Section {
                    if isConnected {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            JBRow(title: JBText.detailsUptime, value: uptime(at: context.date))
                        }
                        JBRow(title: JBText.detailsLatency,
                              value: snapshot?.latencyMs.map(JBText.milliseconds) ?? "—")
                        JBRow(title: JBText.detailsRoute,
                              value: snapshot.map { $0.relayed ? JBText.detailsRelayed : JBText.dockDirect } ?? "—")
                        JBRow(title: JBText.detailsTraffic, value: traffic)
                    } else {
                        JBRow(title: JBText.detailsRoute, value: JBText.dockOff)
                    }
                }

                if isConnected && routes.exitNodes.count > 1 {
                    Section {
                        Button {
                            showsExitPicker = true
                        } label: {
                            HStack {
                                JBRow(title: JBText.settingsExit,
                                      value: routes.selectedExitNode?.name ?? JBText.homeExitNone)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(JBColor.muted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    JBRow(title: JBText.settingsServer,
                          value: URL(string: box.managementURL)?.host ?? box.managementURL)
                }
            }
            .navigationTitle(box.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(JBText.done) { dismiss() }
                }
            }
            .sheet(isPresented: $showsExitPicker) {
                JetBoxExitSheet(routes: routes)
            }
            .onAppear {
                if isConnected { routes.getRoutes() }
            }
        }
        .jbHalfSheet()
    }

    private func uptime(at now: Date) -> String {
        guard let since else { return "—" }
        return JetBoxLiveStats.uptime(Int(now.timeIntervalSince(since)))
    }

    private var traffic: String {
        guard let snapshot else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return "\(f.string(fromByteCount: snapshot.bytesRx)) / \(f.string(fromByteCount: snapshot.bytesTx))"
    }
}

extension View {
    /// Лист на полэкрана, где это умеет система (iOS 16+); ниже — обычный.
    @ViewBuilder
    func jbHalfSheet() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.medium, .large])
        } else {
            self
        }
    }
}

#endif
