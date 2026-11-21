//
//  JetBoxSimpleFlow.swift
//  JetBox
//
//  Экран по ссылке из Кабинета в стиле «простое». Шаги и действия те же,
//  что у `JetBoxFlowView`: меняется только вид.
//

import SwiftUI

#if os(iOS)

struct JetBoxSimpleFlowView: View {
    @EnvironmentObject var viewModel: ViewModel
    @EnvironmentObject var jetbox: JetBoxOnboarding
    @State private var showsInfo = false

    var body: some View {
        ZStack {
            JBSimple.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    content
                        .frame(maxWidth: 440)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            footer
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background(JBSimple.background.ignoresSafeArea())
        }
        .environment(\.colorScheme, .light)
    }

    // MARK: - Содержимое по шагам

    @ViewBuilder
    private var content: some View {
        switch jetbox.step {
        case .idle:
            EmptyView()

        case .ready(let payload):
            VStack(alignment: .leading, spacing: 18) {
                Image("jetbox-simple-app-connect")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .accessibilityHidden(true)
                JetBoxLogo(markHeight: 30)
                // Ключ и текст о данных — за значком (замечание Алексея
                // 21.11.2026): на экране только имя и одна кнопка.
                HStack(spacing: 6) {
                    Text(payload.displayName)
                        .font(JBSimple.font(30, .black))
                        .foregroundColor(JBSimple.ink)
                        .lineLimit(2)
                    JBSimpleInfoButton(label: JBText.simpleDetails) { showsInfo = true }
                }
                JBSimplePrimaryButton(JBText.readyButton) {
                    jetbox.connect(viewModel: viewModel)
                }
                .padding(.top, 6)
            }
            .sheet(isPresented: $showsInfo) { linkInfo(payload) }
            .onAppear {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "JetBoxFlowDemoInfo") { showsInfo = true }
                #endif
            }

        case .confirmSwitch(let payload, let current):
            centered(symbol: "arrow.triangle.2.circlepath",
                     title: JBText.switchTitle,
                     message: JBText.switchMessage(current, payload.displayName)) {
                JBSimplePrimaryButton(JBText.switchConfirm) {
                    jetbox.confirmSwitch(viewModel: viewModel)
                }
            }

        case .signingIn:
            progress(JBText.loginSigningIn)

        case .registering:
            progress(JBText.registering)

        case .connecting:
            progress(JBText.connecting)

        case .selectingExit:
            progress(JBText.selectingExit)

        case .chooseExit:
            // В «простом» выбора выхода нет: сюда попадаем, только если стиль
            // сменили посреди сценария. Ведём себя как «Пока не выбирать».
            progress(JBText.selectingExit)
                .onAppear { jetbox.chooseExit(nil, viewModel: viewModel) }

        case .protected(let exitNode):
            VStack(spacing: 14) {
                JBSimpleCircle(phase: .on, diameter: 200, accessibilityLabel: JBText.protectedTitle)
                    .padding(.top, 40)
                // Без отдельной галочки: длинный заголовок переносится, а галочка
                // уже есть на значке круга.
                Text(JBText.protectedTitle)
                    .font(JBSimple.font(28, .black))
                    .foregroundColor(JBSimple.accent)
                    .multilineTextAlignment(.center)
                JBSimpleTrafficLine()
                Text(exitNode.map { JBText.protectedExit($0) } ?? JBText.protectedNoExit)
                    .font(JBSimple.secondary)
                    .foregroundColor(JBSimple.muted)
                    .multilineTextAlignment(.center)
            }

        case .failed(let failure):
            JetBoxSimpleFailure(failure: failure)
        }
    }

    private func progress(_ title: String) -> some View {
        VStack(spacing: 14) {
            JBSimpleCircle(phase: .working(reverse: false), diameter: 200, accessibilityLabel: title)
                .padding(.top, 60)
            Text(title)
                .font(JBSimple.font(28, .black))
                .foregroundColor(JBSimple.ink)
                .multilineTextAlignment(.center)
            Text(JBText.simpleWait)
                .font(JBSimple.secondary)
                .foregroundColor(JBSimple.muted)
        }
    }

    private func centered<Action: View>(symbol: String, title: String, message: String,
                                        @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(JBSimple.accent)
                .frame(width: 150, height: 150)
                .background(Circle().fill(JBSimple.accentTint))
                .padding(.top, 60)
                .accessibilityHidden(true)
            Text(title)
                .font(JBSimple.font(30, .black))
                .foregroundColor(JBSimple.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(JBSimple.secondary)
                .foregroundColor(JBSimple.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action()
                .padding(.top, 4)
        }
    }

    /// Лист по значку (i): хвост ключа и что уходит на сервер (App Review 5.4).
    private func linkInfo(_ payload: JetBoxLinkPayload) -> some View {
        JBSimpleInfoSheet(title: JBText.errDetails) {
            // Ключ целиком не показываем: только хвост для сверки с поддержкой.
            JBSimpleInfoRow(title: JBText.readyKeyLabel, value: payload.maskedKey)
            Text(JBText.privacyNotice)
                .font(JBSimple.font(17, .semibold))
                .foregroundColor(JBSimple.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Link(JBText.privacyMore, destination: JetBoxConfig.privacyPolicyURL)
                .font(JBSimple.font(18, .heavy))
                .foregroundColor(JBSimple.accent)
        }
    }

    // MARK: - Низ экрана

    @ViewBuilder
    private var footer: some View {
        switch jetbox.step {
        case .protected:
            JBSimplePrimaryButton(JBText.done) { jetbox.dismiss() }

        case .failed(let failure):
            VStack(spacing: 6) {
                if failure.asksForNewLoginLink {
                    // Экран email — на главном, куда ведёт закрытие сценария.
                    JBSimplePrimaryButton(JBText.errLoginExpiredAction) { jetbox.dismiss() }
                } else if failure.isRetryable {
                    JBSimplePrimaryButton(JBText.retry) { jetbox.retry(viewModel: viewModel) }
                }
                JBSimpleTextButton(JBText.close, color: JBSimple.muted) { jetbox.dismiss() }
            }

        case .ready:
            VStack(spacing: 4) {
                JBSimpleTextButton(JBText.cancel, color: JBSimple.muted) { jetbox.dismiss() }
                // Согласие внизу под кнопкой — App Review 5.1.1.
                JBSimpleConsent()
            }

        case .confirmSwitch:
            JBSimpleTextButton(JBText.cancel, color: JBSimple.muted) { jetbox.dismiss() }

        case .idle, .signingIn, .registering, .connecting, .selectingExit, .chooseExit:
            EmptyView()
        }
    }
}

// MARK: - Отказ

struct JetBoxSimpleFailure: View {
    let failure: JetBoxFailure
    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(JBSimple.error)
                .frame(width: 150, height: 150)
                .background(Circle().fill(JBSimple.error.opacity(0.1)))
                .padding(.top, 60)
                .accessibilityHidden(true)
            Text(failure.title)
                .font(JBSimple.font(30, .black))
                .foregroundColor(JBSimple.ink)
                .multilineTextAlignment(.center)
            Text(failure.message)
                .font(JBSimple.secondary)
                .foregroundColor(JBSimple.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let details = failure.details, !details.isEmpty {
                DisclosureGroup(JBText.errDetails, isExpanded: $showsDetails) {
                    Text(details)
                        .font(.system(size: 17, design: .monospaced))
                        .foregroundColor(JBSimple.muted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .font(JBSimple.font(19, .heavy))
                .tint(JBSimple.accent)
            }
        }
    }
}

#endif
