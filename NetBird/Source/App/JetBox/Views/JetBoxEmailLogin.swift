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
        }
    }

    private func send() {
        fieldFocused = false
        Task { await model.submit() }
    }

    // MARK: Экран 1b — «проверьте почту»

    private func checkEmail(_ email: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(JBSimple.accent)
                .frame(width: 150, height: 150)
                .background(Circle().fill(JBSimple.accentTint))
                .padding(.top, 30)
                .accessibilityHidden(true)

            Text(JBText.loginSentTitle)
                .font(JBSimple.font(30, .black))
                .foregroundColor(JBSimple.ink)
                .multilineTextAlignment(.center)

            Text(JBText.loginSentBody(email))
                .font(JBSimple.secondary)
                .foregroundColor(JBSimple.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(JBText.loginSentNote)
                .font(JBSimple.font(17, .semibold))
                .foregroundColor(JBSimple.muted)
                .multilineTextAlignment(.center)

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
