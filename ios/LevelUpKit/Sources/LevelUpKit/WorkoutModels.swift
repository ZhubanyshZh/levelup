import Foundation

public struct WorkoutSet: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var exercise: String
    public var weightKg: Double?
    public var reps: Int?
    public var durationSec: Int?
    public var distanceM: Double?
    public var isPr: Bool
}

public struct Workout: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var workoutDate: LocalDate
    public var startedAt: Date?
    public var endedAt: Date?
    public var title: String?
    public var note: String?
    public var sets: [WorkoutSet]
    public var captureId: UUID?
    public let createdAt: Date
    public var updatedAt: Date

    /// Упражнения по порядку, с их подходами.
    public var exercises: [(name: String, sets: [WorkoutSet])] {
        var order: [String] = []
        var groups: [String: [WorkoutSet]] = [:]
        for set in sets {
            if groups[set.exercise] == nil { order.append(set.exercise) }
            groups[set.exercise, default: []].append(set)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    public var hasRecord: Bool { sets.contains { $0.isPr } }

    public var duration: TimeInterval? {
        guard let startedAt, let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

public struct SetInput: Codable, Sendable, Hashable {
    public var exercise: String
    public var weightKg: Double?
    public var reps: Int?
    public var durationSec: Int?
    public var distanceM: Double?

    public init(exercise: String, weightKg: Double? = nil, reps: Int? = nil, durationSec: Int? = nil, distanceM: Double? = nil) {
        self.exercise = exercise
        self.weightKg = weightKg
        self.reps = reps
        self.durationSec = durationSec
        self.distanceM = distanceM
    }

    public var hasMeasure: Bool {
        weightKg != nil || reps != nil || durationSec != nil || distanceM != nil
    }
}

public struct WorkoutInput: Codable, Sendable {
    public var workoutDate: LocalDate
    public var startedAt: Date?
    public var endedAt: Date?
    public var title: String?
    public var note: String?
    public var sets: [SetInput]

    public init(workoutDate: LocalDate, startedAt: Date? = nil, endedAt: Date? = nil, title: String? = nil, note: String? = nil, sets: [SetInput]) {
        self.workoutDate = workoutDate
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.note = note
        self.sets = sets
    }

    private enum CodingKeys: String, CodingKey {
        case workoutDate, startedAt, endedAt, title, note, sets
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workoutDate, forKey: .workoutDate)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        // При редактировании пустые поля должны очищать прежнее значение на сервере.
        try container.encode(title, forKey: .title)
        try container.encode(note, forKey: .note)
        try container.encode(sets, forKey: .sets)
    }
}

public struct WorkoutResult: Decodable, Sendable {
    public var workout: Workout
    public var xpGained: Int
    /// Упражнения с личным рекордом.
    public var records: [String]
}

public struct ExercisePoint: Codable, Sendable, Hashable {
    public var date: LocalDate
    public var bestWeightKg: Double?
    public var bestReps: Int?
    public var volumeKg: Double
    public var bestDurationSec: Int?
    public var bestDistanceM: Double?
}

public struct ExerciseStats: Codable, Sendable, Hashable, Identifiable {
    public var key: String
    public var name: String
    public var sessions: Int
    public var lastDate: LocalDate
    public var bestWeightKg: Double?
    public var bestReps: Int?
    public var bestDurationSec: Int?
    public var bestDistanceM: Double?
    public var history: [ExercisePoint]

    public var id: String { key }
}

/// Тренировка в процессе: живёт на телефоне, на сервер уходит целиком по «Завершить».
public struct ActiveWorkout: Codable, Sendable, Equatable {
    public var startedAt: Date
    public var title: String?
    public var sets: [SetInput]
    /// Упражнение, которое сейчас делается (для Live Activity и быстрого «+ подход»).
    public var currentExercise: String?
    public var restEndsAt: Date?

    public init(startedAt: Date = .now, title: String? = nil, sets: [SetInput] = [], currentExercise: String? = nil, restEndsAt: Date? = nil) {
        self.startedAt = startedAt
        self.title = title
        self.sets = sets
        self.currentExercise = currentExercise
        self.restEndsAt = restEndsAt
    }
}
