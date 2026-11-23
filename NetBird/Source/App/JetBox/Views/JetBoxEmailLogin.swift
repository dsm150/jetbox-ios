//
//  JetBoxEmailLogin.swift
//  JetBox
//
//  Вход по email в сборке США: стоит на главном экране вместо пустого
//  состояния «нет подключения». Макет Алексея (экраны 1 и 1b): картинка,
//  логотип, «Log in with email», поле, кнопка сразу под полем; согласие
//  с условиями внизу экрана. После отправки — «Check your email».
//  Ссылка из письма открывает приложение сама (JetBoxOnboarding.handle).
//

import SwiftUI

#if os(iOS)

struct JetBoxEmailLoginView: View {
    @ObservedObject var model: JetBoxLoginModel
    let onSettings: () -> Void
    @FocusState private var fieldFocused: Bool
    @FocusState private var codeFocused: Bool
    @State private var showsSetupLink = false

    var body: some View {
        ZStack {
            JBSimple.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    switch model.phase {
                    case .enter, .sending:
                        enterEmail
                    case .sent(let email):
                        checkEmail(email)
                    case .code(let email):
                        enterCode(email)
                    }
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboardIfAvailable()
        }
        .safeAreaInset(edge: .bottom) {
            if case .enter = model.phase {
                // Согласие внизу экрана, кнопка — под полем (макет, App Review 5.1.1).
                JBSimpleConsent()
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(JBSimple.background.ignoresSafeArea())
            } else if case .sending = model.phase, model.lastSentAt == nil {
                JBSimpleConsent()
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(JBSimple.background.ignoresSafeArea())
            }
        }
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $showsSetupLink) {
            JetBoxSetupLinkSheet(model: model)
        }
    }

    private var header: some View {
        HStack {
            JetBoxLogo(markHeight: 34)
            Spacer()
            JBSimpleIconButton(systemName: "gearshape.fill", label: JBText.settingsTitle, action: onSettings)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: Экран 1 — адрес

    private var enterEmail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("jetbox-simple-app-connect")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .accessibilityHidden(true)
                .padding(.bottom, 22)

            Text(JBText.loginTitle)
                .font(JBSimple.font(30, .black))
                .foregroundColor(JBSimple.ink)
                .padding(.bottom, 16)

            TextField(JBText.loginField, text: $model.email)
                .font(JBSimple.font(20, .semibold))
                .foregroundColor(JBSimple.ink)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.send)
                .focused($fieldFocused)
                .onSubmit(send)
                .padding(.horizontal, 20)
                .frame(minHeight: 64)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(JBSimple.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(model.message == JBText.loginInvalidEmail ? JBSimple.error : JBSimple.outline,
                                lineWidth: 2)
                )
                .disabled(model.isSending)
                .accessibilityLabel(JBText.loginField)

            if let message = model.message {
                Text(message)
                    .font(JBSimple.font(19, .semibold))
                    .foregroundColor(JBSimple.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            JBSimplePrimaryButton(model.isSending ? JBText.loginSending : JBText.loginSend, action: send)
                .disabled(model.isSending)
                .padding(.top, 20)

            // Второй путь — ссылка подключения (решение владельца 23.11.2026).
            JBSimpleTextButton(JBText.setupLinkOpen) {
                fieldFocused = false
                showsSetupLink = true
            }
            .disabled(model.isSending)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    private func send() {
        fieldFocused = false
        Task { await model.submit() }
    }

    // MARK: Экран 1b — «проверьте почту»

    /// Компактно (замечание Алексея 23.11.2026): «Enter code manually» видна
    /// без прокрутки на iPhone SE (3-го поколения); срок ссылки — в самом
    /// письме, на экране его нет.
    private func checkEmail(_ email: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(JBSimple.accent)
                .frame(width: 92, height: 92)
                .background(Circle().fill(JBSimple.accentTint))
                .padding(.top, 8)
                .accessibilityHidden(true)

            Text(JBText.loginSentTitle)
                .font(JBSimple.font(26, .black))
                .foregroundColor(JBSimple.ink)
                .multilineTextAlignment(.center)

            Text(JBText.loginSentBody(email))
                .font(JBSimple.font(17, .semibold))
                .foregroundColor(JBSimple.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(JBText.loginSentSpam)
                .font(JBSimple.font(16, .semibold))
                .foregroundColor(JBSimple.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Запасной путь: код из того же письма (и вход проверяющего Apple).
            JBSimpleTextButton(JBText.loginCodeLink) { model.enterCodeManually() }

            JBSimplePrimaryButton(JBText.loginOpenMail) {
                if let url = URL(string: "message://") { UIApplication.shared.open(url) }
            }
            .padding(.top, 8)

            if let message = model.message {
                Text(message)
                    .font(JBSimple.font(19, .semibold))
                    .foregroundColor(JBSimple.error)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            resendControl(title: JBText.loginResend, wait: JBText.loginResendWait)

            JBSimpleTextButton(JBText.loginAnother, color: JBSimple.muted) {
                model.useAnotherEmail()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// «Отправить ещё раз» с отсчётом: не чаще раза в минуту.
    private func resendControl(title: String, wait waitText: @escaping (Int) -> String) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = model.resendWait(at: context.date)
            if model.resentNote {
                Text(JBText.loginSentAgain)
                    .font(JBSimple.font(19, .heavy))
                    .foregroundColor(JBSimple.accent)
                    .frame(minHeight: 44)
            } else if wait > 0 {
                Text(waitText(wait))
                    .font(JBSimple.font(19, .heavy))
                    .foregroundColor(JBSimple.faint)
                    .frame(minHeight: 44)
            } else {
                JBSimpleTextButton(model.isSending ? JBText.loginSending : title) {
                    Task { await model.resend() }
                }
                .disabled(model.isSending)
            }
        }
    }

    // MARK: Код вручную

    private func enterCode(_ email: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.backToLink() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .heavy))
                    Text(JBText.loginCodeBack)
                        .font(JBSimple.font(19, .heavy))
                }
                .foregroundColor(JBSimple.accent)
                .frame(minHeight: 44)
            }
            .padding(.bottom, 12)

            Text(JBText.loginCodeTitle)
                .font(JBSimple.font(30, .black))
                .foregroundColor(JBSimple.ink)
                .padding(.bottom, 10)

            Text(JBText.loginCodeBody(email))
                .font(JBSimple.secondary)
                .foregroundColor(JBSimple.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            TextField(JBText.loginCodeField, text: $model.code)
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(JBSimple.ink)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($codeFocused)
                .onChange(of: model.code) { _ in model.codeChanged() }
                .padding(.horizontal, 20)
                .frame(minHeight: 64)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(JBSimple.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(model.message == nil ? JBSimple.outline : JBSimple.error, lineWidth: 2)
                )
                .disabled(model.isVerifying)
                .accessibilityLabel(JBText.loginCodeField)

            if let message = model.message {
                Text(message)
                    .font(JBSimple.font(19, .semibold))
                    .foregroundColor(JBSimple.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            JBSimplePrimaryButton(model.isVerifying ? JBText.loginCodeChecking : JBText.loginCodeSubmit) {
                codeFocused = false
                Task { await model.submitCode() }
            }
            .disabled(model.isVerifying || model.code.count != 6)
            .opacity(model.code.count == 6 || model.isVerifying ? 1 : 0.55)
            .padding(.top, 20)

            resendControl(title: JBText.loginCodeResend, wait: JBText.loginCodeResendWait)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
        .onAppear { codeFocused = true }
    }
}

/// «Have a setup link?»: ссылка подключения вставкой в поле. Поле, а не
/// чтение буфера: iOS не спрашивает «Разрешить вставку?». Дальше — тот же
/// путь, что у `jetbox://connect#…` (JetBoxLoginModel.connectWithSetupLink).
struct JetBoxSetupLinkSheet: View {
    @ObservedObject var model: JetBoxLoginModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            JBSimple.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Spacer()
                        JBSimpleCapsuleButton(title: JBText.cancel) { dismiss() }
                    }

                    Text(JBText.setupLinkTitle)
                        .font(JBSimple.font(26, .black))
                        .foregroundColor(JBSimple.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(JBText.setupLinkBody)
                        .font(JBSimple.font(17, .semibold))
                        .foregroundColor(JBSimple.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField(JBText.setupLinkField, text: $text)
                        .font(JBSimple.font(18, .semibold))
                        .foregroundColor(JBSimple.ink)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit(connect)
                        .onChange(of: text) { _ in error = nil }
                        .padding(.horizontal, 20)
                        .frame(minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(JBSimple.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(error == nil ? JBSimple.outline : JBSimple.error, lineWidth: 2)
                        )
                        .accessibilityLabel(JBText.setupLinkField)

                    if let error {
                        Text(error)
                            .font(JBSimple.font(17, .semibold))
                            .foregroundColor(JBSimple.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if #available(iOS 16.0, *) {
                        PasteButton(payloadType: String.self) { strings in
                            Task { @MainActor in text = strings.first ?? "" }
                        }
                        .labelStyle(.titleAndIcon)
                        .tint(JBSimple.accent)
                        .buttonBorderShape(.capsule)
                    }

                    JBSimplePrimaryButton(JBText.setupLinkConnect, action: connect)
                        .disabled(isEmpty)
                        .opacity(isEmpty ? 0.55 : 1)
                        .padding(.top, 6)
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
        }
        .environment(\.colorScheme, .light)
        .onAppear { focused = true }
    }

    private func connect() {
        guard !isEmpty else { return }
        focused = false
        if let message = model.connectWithSetupLink(text) {
            error = message
        } else {
            dismiss()
        }
    }
}

private extension View {
    /// Клавиатура уходит при прокрутке (iOS 16+); на iOS 15 — как было.
    @ViewBuilder
    func scrollDismissesKeyboardIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}

#endif
