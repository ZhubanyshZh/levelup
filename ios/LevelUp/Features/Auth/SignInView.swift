import GoogleSignInSwift
import SwiftUI

struct SignInView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "chevron.up.2")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(.tint, in: .rect(cornerRadius: 24))
                Text(verbatim: "Level Up")
                    .font(.largeTitle.bold())
                Text("Задачи, дневник, цели и финансы — голосом, в одном месте.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                googleButton

                Button {
                    Task { await session.continueWithoutAccount() }
                } label: {
                    Text("Продолжить без регистрации")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Данные будут привязаны к этому iPhone. Google можно подключить позже — ничего не потеряется.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let error = session.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .disabled(session.isWorking)
            .overlay {
                if session.isWorking {
                    ProgressView()
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var googleButton: some View {
        if GoogleSignInService.isConfigured {
            GoogleSignInButton(viewModel: GoogleSignInButtonViewModel(scheme: .light, style: .wide)) {
                Task { await session.signInWithGoogle() }
            }
            .frame(height: 50)
        } else {
            VStack(spacing: 4) {
                Button {} label: {
                    Text("Войти через Google")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(true)
                Text("Google-вход не настроен: заполни GOOGLE_CLIENT_ID в ios/Config/Local.xcconfig.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
