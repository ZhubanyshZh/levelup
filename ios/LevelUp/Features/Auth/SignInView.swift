import SwiftUI

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var method: Method?

    private enum Method { case google, guest }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 24)
                    VStack(spacing: 16) {
                        Image(systemName: "chevron.up.2")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 96, height: 96)
                            .background(.tint, in: .rect(cornerRadius: 24))
                            .accessibilityHidden(true)
                        Text(verbatim: "Level Up")
                            .font(.largeTitle.bold())
                        Text("Задачи, дневник, цели и финансы — голосом, в одном месте.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 24)

                    VStack(spacing: 16) {
                        Button {
                            method = .google
                            Task { await session.signInWithGoogle() }
                        } label: {
                            HStack(spacing: 12) {
                                Image("GoogleLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .accessibilityHidden(true)
                                Text("Войти через Google")
                                    .font(.body.weight(.medium))
                                if session.isWorking && method == .google {
                                    ProgressView().tint(Color(red: 0.12, green: 0.12, blue: 0.12))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(GoogleAuthButtonStyle())
                        .disabled(!GoogleSignInService.isConfigured || session.isWorking)

                        if !GoogleSignInService.isConfigured {
                            Text("Вход через Google временно недоступен.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            method = .guest
                            Task { await session.continueWithoutAccount() }
                        } label: {
                            HStack(spacing: 12) {
                                Text("Продолжить без регистрации")
                                if session.isWorking && method == .guest { ProgressView() }
                            }
                            .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(session.isWorking)

                        Text("Данные будут привязаны к этому iPhone. Google можно подключить позже — ничего не потеряется.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if let error = session.errorMessage {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(proxy.size.height - 48, 0))
                .padding(24)
            }
        }
    }
}

/// Официальный цветной знак Google, белая поверхность и внутренний контур.
private struct GoogleAuthButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
            .background(configuration.isPressed ? Color(white: 0.95) : .white, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(red: 0.45, green: 0.47, blue: 0.46), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.5)
    }
}
