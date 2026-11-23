//
//  JetBoxSimpleFlow.swift
//  JetBox
//
//  Экран по ссылке из Кабинета в стиле «простое» — только сборка США. С 26
//  он показывает лишь вход по ссылке из письма и отказы: подписанная ссылка
//  подключает сразу, ход подключения — на главном экране.
//

import SwiftUI

#if os(iOS)

struct JetBoxSimpleFlowView: View {
    @EnvironmentObject var viewModel: ViewModel
    @EnvironmentObject var jetbox: JetBoxOnboarding

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

        case .signingIn:
            progress(JBText.loginSigningIn)

        case .chooseExit:
            // В «простом» выбора выхода нет: сюда попадаем, только если стиль
            // сменили посреди сценария. Ведём себя как «Пока не выбирать».
            progress(JBText.selectingExit)
                .onAppear { jetbox.chooseExit(nil, viewModel: viewModel) }

        case .ready, .confirmSwitch, .registering, .connecting, .selectingExit, .protected:
            // «Простое» есть только в сборке США, а там эти шаги идут без экрана
            // сценария: подтверждения, замены с вопросом и «готово» нет
            // (сборка 26, решение Алексея 23.11.2026) — ход подключения
            // показывает главный экран (JetBoxOnboarding.isPresenting).
            EmptyView()

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

    // MARK: - Низ экрана

    @ViewBuilder
    private var footer: some View {
        switch jetbox.step {
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

        case .idle, .signingIn, .ready, .confirmSwitch, .registering, .connecting, .selectingExit,
             .chooseExit, .protected:
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
