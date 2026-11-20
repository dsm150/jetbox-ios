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
                VStack(alignment: .leading, spacing: 6) {
                    Text(JBText.readyCaption)
                        .font(JBSimple.secondary)
                        .foregroundColor(JBSimple.muted)
                    Text(payload.displayName)
                        .font(JBSimple.font(30, .black))
                        .foregroundColor(JBSimple.ink)
                        .lineLimit(2)
                }
                Text(JBText.readyHint)
                    .font(JBSimple.secondary)
                    .foregroundColor(JBSimple.muted)
                    .fixedSize(horizontal: false, vertical: true)
                JBSimpleCard {
                    // Ключ целиком не показываем: только хвост для сверки с поддержкой.
                    JBSimpleRow(title: JBText.readyKeyLabel, value: payload.maskedKey)
                }
                JBSimplePrimaryButton(JBText.readyButton) {
                    jetbox.connect(viewModel: viewModel)
                }
                .padding(.top, 2)
                privacyNotice
            }

        case .confirmSwitch(let payload, let current):
            centered(symbol: "arrow.triangle.2.circlepath",
                     title: JBText.switchTitle,
                     message: JBText.switchMessage(current, payload.displayName)) {
                JBSimplePrimaryButton(JBText.switchConfirm) {
                    jetbox.confirmSwitch(viewModel: viewModel)
                }
            }

        case .registering:
            progress(JBText.registering)

        case .connecting:
            progress(JBText.connecting)

        case .selectingExit:
            progress(JBText.selectingExit)

        case .chooseExit(_, let options):
            JetBoxSimpleFlowExits(options: options)

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

    /// Что уходит на сервер — требование App Review 5.4: до любого действия,
    /// поэтому сразу под кнопкой подключения.
    private var privacyNotice: some View {
        VStack(spacing: 4) {
            Text(JBText.privacyNotice)
                .font(JBSimple.font(17, .semibold))
                .foregroundColor(JBSimple.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link(JBText.privacyMore, destination: JetBoxConfig.privacyPolicyURL)
                .font(JBSimple.font(17, .heavy))
                .foregroundColor(JBSimple.accent)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Низ экрана

    @ViewBuilder
    private var footer: some View {
        switch jetbox.step {
        case .protected:
            JBSimplePrimaryButton(JBText.done) { jetbox.dismiss() }

        case .failed(let failure):
            VStack(spacing: 6) {
                if failure.isRetryable {
                    JBSimplePrimaryButton(JBText.retry) { jetbox.retry(viewModel: viewModel) }
                }
                JBSimpleTextButton(JBText.close, color: JBSimple.muted) { jetbox.dismiss() }
            }

        case .ready, .confirmSwitch:
            JBSimpleTextButton(JBText.cancel, color: JBSimple.muted) { jetbox.dismiss() }

        case .idle, .registering, .connecting, .selectingExit, .chooseExit:
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

// MARK: - Выбор выхода по ссылке

struct JetBoxSimpleFlowExits: View {
    let options: [String]
    @EnvironmentObject var viewModel: ViewModel
    @EnvironmentObject var jetbox: JetBoxOnboarding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(JBText.exitPickerTitle)
                .font(JBSimple.font(30, .black))
                .foregroundColor(JBSimple.ink)
                .padding(.top, 24)
            Text(options.isEmpty ? JBText.exitPickerEmpty : JBText.exitPickerMessage)
                .font(JBSimple.secondary)
                .foregroundColor(JBSimple.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
            ForEach(options, id: \.self) { name in
                Button {
                    jetbox.chooseExit(name, viewModel: viewModel)
                } label: {
                    HStack(spacing: 14) {
                        JBSimpleIconTile(systemName: "house.fill", size: 48)
                        Text(name)
                            .font(JBSimple.font(20, .bold))
                            .foregroundColor(JBSimple.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(JBSimple.muted)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 76)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(JBSimple.card))
                }
                .buttonStyle(JBSimplePressStyle())
            }
            JBSimpleTextButton(JBText.exitPickerSkip, color: JBSimple.muted) {
                jetbox.chooseExit(nil, viewModel: viewModel)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#endif
