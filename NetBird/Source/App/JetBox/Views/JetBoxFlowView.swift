//
//  JetBoxFlowView.swift
//  JetBox
//
//  Экран, который клиент видит после перехода по ссылке из Кабинета:
//  от «вот ваша коробка, нажмите одну кнопку» до «вы под защитой».
//  Перекрывает всё остальное, пока сценарий не закончится.
//

import SwiftUI

#if os(iOS)

struct JetBoxFlowView: View {
    @EnvironmentObject var viewModel: ViewModel
    @EnvironmentObject var jetbox: JetBoxOnboarding

    var body: some View {
        ZStack {
            JBColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                JetBoxLogo(markHeight: 52)
                    .padding(.bottom, 32)

                content
                    .frame(maxWidth: 420)

                Spacer(minLength: 24)

                footer
                    .frame(maxWidth: 420)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Содержимое по шагам

    @ViewBuilder
    private var content: some View {
        switch jetbox.step {
        case .idle:
            EmptyView()

        case .ready(let payload):
            VStack(spacing: 24) {
                boxCard(payload)
                Text(JBText.readyHint)
                    .font(.footnote)
                    .foregroundColor(JBColor.muted)
                    .multilineTextAlignment(.center)
                AppButton(JBText.readyButton) {
                    jetbox.connect(viewModel: viewModel)
                }
            }

        case .confirmSwitch(let payload, let current):
            VStack(spacing: 24) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 40))
                    .foregroundColor(JBColor.warn)
                Text(JBText.switchTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(JBColor.text)
                Text(JBText.switchMessage(current, payload.displayName))
                    .font(.subheadline)
                    .foregroundColor(JBColor.muted)
                    .multilineTextAlignment(.center)
                AppButton(JBText.switchConfirm) {
                    jetbox.confirmSwitch(viewModel: viewModel)
                }
            }

        case .registering:
            JBProgress(title: JBText.registering)

        case .connecting:
            JBProgress(title: JBText.connecting)

        case .selectingExit:
            JBProgress(title: JBText.selectingExit)

        case .chooseExit(_, let options):
            JetBoxExitPickerView(options: options)

        case .protected(let exitNode):
            protectedView(exitNode: exitNode)

        case .failed(let failure):
            JetBoxFailureView(failure: failure)
        }
    }

    private func boxCard(_ payload: JetBoxLinkPayload) -> some View {
        JBCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(JBText.readyCaption)
                    .font(.footnote)
                    .foregroundColor(JBColor.muted)
                Text(payload.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(JBColor.text)
                    .lineLimit(2)
                Divider().overlay(JBColor.line)
                JBRow(title: JBText.settingsServer,
                      value: URL(string: payload.managementURL)?.host ?? payload.managementURL)
                // Ключ целиком не показываем нигде: на экране только хвост,
                // чтобы поддержка могла сверить «та ли ссылка».
                JBRow(title: JBText.readyKeyLabel, value: payload.maskedKey)
            }
        }
    }

    private func protectedView(exitNode: String?) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 64))
                .foregroundColor(JBColor.ok)
            Text(JBText.protectedTitle)
                .font(.title2.weight(.semibold))
                .foregroundColor(JBColor.text)
                .multilineTextAlignment(.center)
            Text(exitNode.map { JBText.protectedExit($0) } ?? JBText.protectedNoExit)
                .font(.subheadline)
                .foregroundColor(JBColor.muted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Нижняя кнопка

    @ViewBuilder
    private var footer: some View {
        switch jetbox.step {
        case .protected:
            AppButton(JBText.done, style: .secondary) { jetbox.dismiss() }

        case .failed(let failure):
            VStack(spacing: 10) {
                if failure.isRetryable {
                    AppButton(JBText.retry) { jetbox.retry(viewModel: viewModel) }
                }
                Button(JBText.close) { jetbox.dismiss() }
                    .font(.subheadline)
                    .foregroundColor(JBColor.muted)
            }

        case .ready, .confirmSwitch:
            Button(JBText.cancel) { jetbox.dismiss() }
                .font(.subheadline)
                .foregroundColor(JBColor.muted)

        case .idle, .registering, .connecting, .selectingExit, .chooseExit:
            EmptyView()
        }
    }
}

// MARK: - Экран отказа

struct JetBoxFailureView: View {
    let failure: JetBoxFailure
    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(JBColor.warn)

            Text(failure.title)
                .font(.title3.weight(.semibold))
                .foregroundColor(JBColor.text)
                .multilineTextAlignment(.center)

            Text(failure.message)
                .font(.subheadline)
                .foregroundColor(JBColor.muted)
                .multilineTextAlignment(.center)

            // Техническая строка от ядра нужна поддержке, а не клиенту —
            // поэтому она спрятана и по-английски.
            if let details = failure.details, !details.isEmpty {
                DisclosureGroup(JBText.errDetails, isExpanded: $showsDetails) {
                    Text(details)
                        .font(.caption.monospaced())
                        .foregroundColor(JBColor.muted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .font(.footnote)
                .tint(JBColor.accent)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Выбор выхода

struct JetBoxExitPickerView: View {
    let options: [String]
    @EnvironmentObject var viewModel: ViewModel
    @EnvironmentObject var jetbox: JetBoxOnboarding

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: 40))
                .foregroundColor(JBColor.accent)

            Text(JBText.exitPickerTitle)
                .font(.title3.weight(.semibold))
                .foregroundColor(JBColor.text)

            Text(options.isEmpty ? JBText.exitPickerEmpty : JBText.exitPickerMessage)
                .font(.subheadline)
                .foregroundColor(JBColor.muted)
                .multilineTextAlignment(.center)

            if !options.isEmpty {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(options, id: \.self) { name in
                            Button {
                                jetbox.chooseExit(name, viewModel: viewModel)
                            } label: {
                                HStack {
                                    Text(name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(JBColor.text)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote)
                                        .foregroundColor(JBColor.muted)
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(JBColor.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(JBColor.line, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            Button(JBText.exitPickerSkip) {
                jetbox.chooseExit(nil, viewModel: viewModel)
            }
            .font(.subheadline)
            .foregroundColor(JBColor.muted)
        }
    }
}

#endif
