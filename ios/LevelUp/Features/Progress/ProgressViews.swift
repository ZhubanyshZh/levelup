import LevelUpKit
import SwiftUI

/// Уровень подробно: кольцо, опыт за сегодня, за что начислено и как получить больше.
struct ProgressDetailView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let progress = store.progress.progress
        List {
            Section {
                VStack(spacing: 12) {
                    LevelRing(progress: progress)
                        .frame(width: 160, height: 160)
                    Text("Всего \(progress.totalXp) XP")
                        .font(.headline)
                    Text("До уровня \(progress.level + 1): \(progress.xpForNextLevel - progress.xpInLevel) XP")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Как получить опыт") {
                Label("Задача: 5–30 XP — чем сложнее, тем больше", systemImage: "checkmark.circle")
                Label("Запись в дневнике: 15 XP в день", systemImage: "book")
                Label("Мелкие задачи приносят опыт до 10 раз в день", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }

            if !progress.recent.isEmpty {
                Section("Недавно") {
                    ForEach(Array(progress.recent.enumerated()), id: \.offset) { _, event in
                        HStack {
                            Image(systemName: event.sourceType == "journal" ? "book" : "checkmark.circle")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .lineLimit(2)
                                Text(event.createdAt, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+\(event.amount)")
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle("Прогресс")
        .refreshable { await store.progress.load() }
    }
}

struct LevelRing: View {
    let progress: LevelProgress

    var body: some View {
        ZStack {
            Circle()
                .stroke(.fill.tertiary, lineWidth: 14)
            Circle()
                .trim(from: 0, to: Double(progress.xpInLevel) / Double(max(progress.xpForNextLevel, 1)))
                .stroke(.tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress.xpInLevel)
            VStack(spacing: 0) {
                Text("Уровень")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(progress.level, format: .number)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
        }
    }
}

/// «+15 XP» сверху экрана после действий, приносящих опыт.
struct XPToast: View {
    let gain: Int

    var body: some View {
        Label("+\(gain) XP", systemImage: "star.fill")
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.tint, in: .capsule)
            .shadow(radius: 8, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Праздник нового уровня поверх всего приложения.
struct LevelUpCelebration: View {
    let level: Int
    let onDismiss: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(spacing: 16) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.yellow, .tint)
                    .symbolEffect(.bounce, value: appeared)
                Text("Новый уровень!")
                    .font(.title2.bold())
                Text("Уровень \(level)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.tint)
                Text("Так держать — каждый шаг считается.")
                    .foregroundStyle(.secondary)
                Button("Отлично", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(.regularMaterial, in: .rect(cornerRadius: 28))
            .padding(32)
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { appeared = true }
        }
    }
}
