//
//  JetBoxHelpView.swift
//  JetBox
//
//  «Help» в настройках (1.0 (34)): поле, «Attach diagnostics», раскрывашка
//  «What's included» с ровно тем текстом, что уйдёт, и «Send». Модель общая,
//  вида два — «простое» и «техно».
//

import SwiftUI

#if os(iOS)

@MainActor
final class JetBoxHelpModel: ObservableObject {
    enum Phase: Equatable {
        case editing
        case sending
        /// Отправлено в Кабинет: обещание срока ответа.
        case sent(String)
        /// Письмо не открылось: адрес — показать и дать скопировать.
        case mailFailed(String)
    }

    @Published var message = ""
    @Published var attach = true
    @Published private(set) var phase: Phase = .editing
    /// 429 — под полем, отправка остаётся доступной.
    @Published private(set) var notice: String?
    let diagnostics: String

    var api = JetBoxLoginAPI()
    var loadToken: () -> String? = { JetBoxAppToken.load() }
    var supportAddress: () -> String = { JetBoxSupportContact.current() }
    let appVersion: String

    init(diagnostics: String, appVersion: String = JetBoxHelpModel.currentVersion) {
        self.diagnostics = diagnostics
        self.appVersion = appVersion
    }

    nonisolated static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var canSend: Bool {
        phase == .editing && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Токен — Кабинет; нет токена или Кабинет не принял — письмо.
    /// `openMail` открывает mailto и говорит, открылось ли.
    func send(openMail: @escaping (URL) async -> Bool) async {
        guard canSend else { return }
        notice = nil
        phase = .sending
        let attached = attach ? diagnostics : ""
        if let token = loadToken() {
            let lang = Bundle.main.preferredLocalizations.first == "ru" ? "ru" : "en"
            switch await api.sendSupport(token: token, message: message, diagnostics: attached,
                                         version: appVersion, lang: lang) {
            case .sent(let promise):
                phase = .sent(promise ?? JBText.helpSentFallback)
                return
            case .rateLimited:
                notice = JBText.helpRateLimited
                phase = .editing
                return
            case .needsMail:
                break
            }
        }
        let address = supportAddress()
        guard let url = JetBoxDiagnostics.mailURL(to: address, appVersion: appVersion, message: message,
                                                  diagnostics: attach ? diagnostics : nil),
              await openMail(url) else {
            phase = .mailFailed(address)
            return
        }
        phase = .editing
    }

    func backToEditing() { phase = .editing }
}

// MARK: - Диагностика с этого телефона

extension JetBoxDiagnostics {
    @MainActor
    static func collect(viewModel: ViewModel, stats: JetBoxLiveStats = .shared) -> String {
        let box = JetBoxStore.currentBox
        let hasToken = JetBoxAppToken.load() != nil
        let snapshot = stats.box
        let route: String = {
            guard let snapshot else { return "unknown" }
            switch JetBoxLiveStats.route(snapshot) {
            case .direct: return "direct"
            case .relayed: return "relay"
            case .notDirect: return "not direct"
            }
        }()
        let facts = Facts(
            appVersion: JetBoxHelpModel.currentVersion,
            osVersion: UIDevice.current.systemVersion,
            language: Locale.preferredLanguages.first ?? "?",
            signIn: hasToken ? "email" : (box == nil ? "none" : "link"),
            maskedEmail: JetBoxAdvancedAccess.defaults.string(forKey: maskedEmailKey),
            hasToken: hasToken,
            tunnel: String(describing: viewModel.vpnDisplayState),
            homeAnswers: snapshot?.latencyMs != nil,
            latencyMs: snapshot?.latencyMs,
            route: route,
            uptime: stats.connectedSince.map { JetBoxLiveStats.uptime(Int(Date().timeIntervalSince($0))) },
            exit: box?.selectedExitNode,
            dns: stats.dnsVerdict?.diagnostics ?? "not checked yet")
        return text(facts, log: lastJetBoxLines(readLog() ?? ""))
    }
}

/// mailto через openURL — с ответом, открылось ли.
private func open(_ url: URL, with openURL: OpenURLAction) async -> Bool {
    await withCheckedContinuation { done in
        openURL(url) { done.resume(returning: $0) }
    }
}

// MARK: - «Простое» (только сборка США: в русской набора «простого» нет)

#if JETBOX_US

struct JetBoxSimpleHelpView: View {
    @StateObject var model: JetBoxHelpModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showsIncluded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .heavy))
                        Text(JBText.settingsTitle)
                            .font(JBSimple.font(19, .heavy))
                    }
                    .foregroundColor(JBSimple.accent)
                    .frame(minHeight: 44)
                }

                Text(JBText.helpTitle)
                    .font(JBSimple.font(30, .black))
                    .foregroundColor(JBSimple.ink)

                switch model.phase {
                case .sent(let promise):
                    result(symbol: "checkmark", text: promise)
                case .mailFailed(let address):
                    result(symbol: "envelope", text: JBText.helpMailFailed(address))
                    JBSimpleTextButton(JBText.deleteCopyAddress) { UIPasteboard.general.string = address }
                default:
                    form
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(JBSimple.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var form: some View {
        ZStack(alignment: .topLeading) {
            if model.message.isEmpty {
                Text(JBText.helpPlaceholder)
                    .font(JBSimple.font(19, .semibold))
                    .foregroundColor(JBSimple.faint)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            }
            TextEditor(text: $model.message)
                .font(JBSimple.font(19, .semibold))
                .foregroundColor(JBSimple.ink)
                .padding(10)
                .frame(minHeight: 150)
                .modifier(JBHiddenEditorBackground())
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(JBSimple.card))

        if let notice = model.notice {
            Text(notice)
                .font(JBSimple.font(17, .semibold))
                .foregroundColor(JBSimple.error)
        }

        JBSimpleCard {
            Toggle(isOn: $model.attach) {
                Text(JBText.helpAttach)
                    .font(JBSimple.font(20, .bold))
                    .foregroundColor(JBSimple.ink)
            }
            .tint(JBSimple.accent)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            JBSimpleDivider()
            Button { withAnimation { showsIncluded.toggle() } } label: {
                HStack {
                    Text(JBText.helpIncluded)
                        .font(JBSimple.font(19, .semibold))
                        .foregroundColor(JBSimple.muted)
                    Spacer()
                    Image(systemName: showsIncluded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(JBSimple.faint)
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
            }
            .buttonStyle(.plain)
            if showsIncluded {
                Text(model.diagnostics)
                    .font(.system(size: 17, design: .monospaced))
                    .foregroundColor(JBSimple.muted)
                    .textSelection(.enabled)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if model.phase == .sending {
            ProgressView().frame(maxWidth: .infinity, minHeight: 64)
        } else {
            JBSimplePrimaryButton(JBText.helpSend) {
                Task { await model.send { await open($0, with: openURL) } }
            }
            .disabled(!model.canSend)
            .opacity(model.canSend ? 1 : 0.5)
        }
    }

    private func result(symbol: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .black))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(JBSimple.accent))
            Text(text)
                .font(JBSimple.secondary)
                .foregroundColor(JBSimple.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            JBSimplePrimaryButton(JBText.close) { dismiss() }
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}

/// TextEditor на iOS 16+ рисует свой фон — прячем, чтобы был фон карточки.
private struct JBHiddenEditorBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

#endif

// MARK: - «Техно»

struct JetBoxHelpView: View {
    @StateObject var model: JetBoxHelpModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            switch model.phase {
            case .sent(let promise):
                Section {
                    Label(promise, systemImage: "checkmark.circle.fill")
                    Button(JBText.close) { dismiss() }
                }
            case .mailFailed(let address):
                Section {
                    Text(JBText.helpMailFailed(address)).textSelection(.enabled)
                    Button(JBText.deleteCopyAddress) { UIPasteboard.general.string = address }
                }
            default:
                Section {
                    ZStack(alignment: .topLeading) {
                        if model.message.isEmpty {
                            Text(JBText.helpPlaceholder)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $model.message).frame(minHeight: 140)
                    }
                } footer: {
                    if let notice = model.notice { Text(notice).foregroundColor(.red) }
                }
                Section {
                    Toggle(JBText.helpAttach, isOn: $model.attach)
                    DisclosureGroup(JBText.helpIncluded) {
                        Text(model.diagnostics)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                Section {
                    if model.phase == .sending {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Button(JBText.helpSend) {
                            Task { await model.send { await open($0, with: openURL) } }
                        }
                        .disabled(!model.canSend)
                    }
                }
            }
        }
        .navigationTitle(JBText.helpTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#endif
