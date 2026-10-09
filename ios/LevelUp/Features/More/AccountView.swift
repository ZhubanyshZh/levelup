import LevelUpKit
import SwiftUI

struct AccountView: View {
    @Environment(SessionStore.self) private var session
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var session = session
        List {
            if case .signedIn(let user) = session.state {
                Section {
                    LabeledContent("Вход") {
                        if user.isGuest {
                            Text("Без регистрации")
                        } else {
                            Text(verbatim: "Google")
                        }
                    }
                    if let email = user.email {
                        LabeledContent("Email", value: email)
                    }
                    LabeledContent("Часовой пояс", value: user.timezone)
                }

                if user.isGuest {
                    Section {
                        Button {
                            Task { await session.linkGoogle() }
                        } label: {
                            Label("Подключить Google", systemImage: "person.badge.key")
                        }
                        .disabled(!GoogleSignInService.isConfigured || session.isWorking)
                    } footer: {
                        Text("Сейчас аккаунт привязан только к этому iPhone. С Google данные не потеряются при смене телефона.")
                    }
                }

                Section {
                    Button("Выйти", role: .destructive) { confirmSignOut = true }
                }
                .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                    Button("Выйти", role: .destructive) {
                        Task { await session.signOut() }
                    }
                } message: {
                    if user.isGuest {
                        Text("Вернуться в аккаунт без регистрации можно только с этого iPhone.")
                    }
                }
            }
        }
        .navigationTitle("Аккаунт")
        .overlay {
            if session.isWorking {
                ProgressView()
            }
        }
        .overlay(alignment: .bottom) { ErrorBanner(message: $session.errorMessage) }
    }
}
