import LevelUpKit
import SwiftUI

/// Свой ключ ИИ (BYOK): Gemini или OpenAI, модель и проверка.
struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var newKeys: [AIProviderKind: String] = [:]
    @State private var replacing: Set<AIProviderKind> = []

    var body: some View {
        @Bindable var ai = store.ai
        List {
            Section {
                Text("Level Up работает на твоём собственном ключе ИИ. Ключ хранится на сервере в зашифрованном виде и обратно не показывается.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let settings = ai.settings {
                let withKeys = settings.providers.filter(\.hasKey)
                if withKeys.count > 1 {
                    Section {
                        Picker("Активный помощник", selection: Binding(
                            get: { settings.activeProvider ?? withKeys[0].provider },
                            set: { provider in Task { await ai.setActive(provider) } }
                        )) {
                            ForEach(withKeys, id: \.provider) { info in
                                Text(verbatim: info.provider.title).tag(info.provider)
                            }
                        }
                    }
                }
                ForEach(AIProviderKind.allCases) { provider in
                    if let info = settings.info(for: provider) {
                        providerSection(info, isActive: settings.activeProvider == provider)
                    }
                }
                Section {
                    Text("Gemini бесплатен в Google AI Studio, но на бесплатном тарифе Google может использовать запросы для улучшения своих моделей. Учитывай это для личных записей.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("ИИ-помощник")
        .overlay(alignment: .bottom) { ErrorBanner(message: $ai.errorMessage) }
        .task {
            await ai.load()
            for provider in AIProviderKind.allCases {
                await ai.loadModels(provider)
            }
        }
    }

    @ViewBuilder
    private func providerSection(_ info: AIProviderInfo, isActive: Bool) -> some View {
        let provider = info.provider
        Section {
            if info.hasKey && !replacing.contains(provider) {
                LabeledContent("Ключ", value: info.keyHint ?? "")
                Picker("Модель", selection: Binding(
                    get: { info.model },
                    set: { model in Task { await store.ai.setModel(model, for: provider) } }
                )) {
                    ForEach(modelOptions(info), id: \.self) { Text(verbatim: $0).tag($0) }
                }
                Button {
                    Task { await store.ai.test(provider) }
                } label: {
                    HStack {
                        Text("Проверить ключ")
                        Spacer()
                        testStatus(provider)
                    }
                }
                Button("Заменить ключ") { replacing.insert(provider) }
                Button("Удалить ключ", role: .destructive) {
                    Task { await store.ai.deleteKey(for: provider) }
                }
            } else {
                SecureField("Вставь API-ключ", text: Binding(
                    get: { newKeys[provider] ?? "" },
                    set: { newKeys[provider] = $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button("Сохранить ключ") {
                    Task {
                        if await store.ai.saveKey(newKeys[provider] ?? "", for: provider) {
                            newKeys[provider] = nil
                            replacing.remove(provider)
                        }
                    }
                }
                .disabled((newKeys[provider] ?? "").trimmingCharacters(in: .whitespaces).count < 20)
                Link(destination: provider.keysURL) {
                    Label("Где взять ключ", systemImage: "arrow.up.right.square")
                }
                if replacing.contains(provider) {
                    Button("Отмена") { replacing.remove(provider) }
                }
            }
        } header: {
            HStack {
                Text(verbatim: provider.title)
                if isActive {
                    Text("· активный")
                }
                Spacer()
                if store.ai.busyProvider == provider {
                    ProgressView()
                }
            }
        } footer: {
            if !info.hasKey {
                switch provider {
                case .gemini: Text("Бесплатно: войди в Google AI Studio и нажми «Create API key».")
                case .openai: Text("Платно: ключ создаётся на platform.openai.com, нужен баланс на счёте.")
                }
            }
        }
    }

    private func modelOptions(_ info: AIProviderInfo) -> [String] {
        let loaded = store.ai.models[info.provider] ?? []
        return loaded.contains(info.model) ? loaded : [info.model] + loaded
    }

    @ViewBuilder
    private func testStatus(_ provider: AIProviderKind) -> some View {
        if store.ai.busyProvider == provider {
            ProgressView()
        } else if let result = store.ai.testResults[provider] {
            if result.ok && result.modelAvailable != false {
                Label("Работает", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if result.ok {
                Label("Модели нет — выбери другую", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label(ErrorText.capture(result.errorCode), systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }
}
