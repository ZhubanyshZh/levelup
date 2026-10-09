import Foundation

/// Компактные данные для виджетов. Приложение пишет их в общее хранилище App Group
/// после каждого изменения, виджеты читают и меняют только отметки «готово» и «куплено».
///
/// Даты здесь не «сегодняшние», а сырые: виджет сам решает, что показать на свой день,
/// поэтому после полуночи он прав, даже если приложение давно не открывали.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct TaskEntry: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var title: String
        public var dueDate: LocalDate?
        /// «HH:MM».
        public var dueTime: String?
        public var isImportant: Bool
        public var isRepeating: Bool
        public var isDoing: Bool
        /// Отмечена в виджете в этот день, сервер ещё не подтвердил.
        public var doneOn: LocalDate?

        public init(
            id: UUID, title: String, dueDate: LocalDate? = nil, dueTime: String? = nil,
            isImportant: Bool = false, isRepeating: Bool = false, isDoing: Bool = false, doneOn: LocalDate? = nil
        ) {
            self.id = id
            self.title = title
            self.dueDate = dueDate
            self.dueTime = dueTime
            self.isImportant = isImportant
            self.isRepeating = isRepeating
            self.isDoing = isDoing
            self.doneOn = doneOn
        }

        public init(_ task: TaskItem) {
            self.init(
                id: task.id, title: task.title, dueDate: task.dueDate, dueTime: task.dueTime,
                isImportant: task.priority == .high, isRepeating: task.recurrence != nil, isDoing: task.status == .doing
            )
        }
    }

    public struct ShoppingEntry: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var quantity: String?
        public var listName: String?
        /// Вычеркнуто в виджете, сервер ещё не подтвердил.
        public var isBought: Bool

        public init(id: UUID, name: String, quantity: String? = nil, listName: String? = nil, isBought: Bool = false) {
            self.id = id
            self.name = name
            self.quantity = quantity
            self.listName = listName
            self.isBought = isBought
        }

        public init(_ item: ShoppingItem) {
            self.init(id: item.id, name: item.name, quantity: item.quantity, listName: item.listName, isBought: item.isBought)
        }
    }

    /// Занятое время из «Обо мне»: «Пт 12:30–14:00 — жума».
    public struct BusySlot: Codable, Sendable, Equatable {
        public var title: String
        public var weekdays: [Weekday]
        public var start: String
        public var end: String

        public init(title: String, weekdays: [Weekday], start: String, end: String) {
            self.title = title
            self.weekdays = weekdays
            self.start = start
            self.end = end
        }
    }

    /// Деньги за месяц и день, к которым относятся цифры.
    public struct FinanceEntry: Codable, Sendable, Equatable {
        public var currency: String
        /// Первый день месяца, за который spentMonth.
        public var month: LocalDate
        public var day: LocalDate
        public var spentMonth: Double
        public var spentToday: Double
        public var monthlyBudget: Double?

        public init(currency: String, month: LocalDate, day: LocalDate, spentMonth: Double, spentToday: Double, monthlyBudget: Double?) {
            self.currency = currency
            self.month = month
            self.day = day
            self.spentMonth = spentMonth
            self.spentToday = spentToday
            self.monthlyBudget = monthlyBudget
        }
    }

    public struct WorkoutEntry: Codable, Sendable, Equatable {
        /// Дни с тренировками за последние два месяца.
        public var days: [LocalDate]
        public var lastTitle: String?
        public var lastDate: LocalDate?
        /// Последний личный рекорд: упражнение.
        public var lastRecord: String?
        /// Тренировка идёт прямо сейчас — с этого момента.
        public var activeSince: Date?

        public init(days: [LocalDate], lastTitle: String?, lastDate: LocalDate?, lastRecord: String?, activeSince: Date?) {
            self.days = days
            self.lastTitle = lastTitle
            self.lastDate = lastDate
            self.lastRecord = lastRecord
            self.activeSince = activeSince
        }
    }

    public struct GoalEntry: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var title: String
        public var progress: Double
        public var deadline: LocalDate?
        public var icon: String?

        public init(id: UUID, title: String, progress: Double, deadline: LocalDate?, icon: String?) {
            self.id = id
            self.title = title
            self.progress = progress
            self.deadline = deadline
            self.icon = icon
        }
    }

    public struct QuestEntry: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        /// Текст задания на языке приложения.
        public var title: String
        public var isDaily: Bool
        public var periodEnd: LocalDate
        public var progress: Int
        public var target: Int
        public var reward: Int
        public var isDone: Bool

        public init(id: UUID, title: String, isDaily: Bool, periodEnd: LocalDate, progress: Int, target: Int, reward: Int, isDone: Bool) {
            self.id = id
            self.title = title
            self.isDaily = isDaily
            self.periodEnd = periodEnd
            self.progress = progress
            self.target = target
            self.reward = reward
            self.isDone = isDone
        }
    }

    public var isSignedIn: Bool
    public var displayName: String?
    public var level: Int
    public var xp: Int
    public var xpForNextLevel: Int
    public var todayXp: Int
    /// День, к которому относится todayXp.
    public var todayXpDate: LocalDate?
    public var tasks: [TaskEntry]
    public var shopping: [ShoppingEntry]
    /// Дни, за которые есть записи в дневнике (последние два месяца).
    public var journalDays: [LocalDate]
    public var busy: [BusySlot]
    public var finance: FinanceEntry?
    public var workouts: WorkoutEntry?
    /// Активные цели.
    public var goals: [GoalEntry]
    public var quests: [QuestEntry]
    public var streakDays: Int
    public var updatedAt: Date

    public init(
        isSignedIn: Bool,
        displayName: String? = nil,
        level: Int = 1,
        xp: Int = 0,
        xpForNextLevel: Int = 100,
        todayXp: Int = 0,
        todayXpDate: LocalDate? = nil,
        tasks: [TaskEntry] = [],
        shopping: [ShoppingEntry] = [],
        journalDays: [LocalDate] = [],
        busy: [BusySlot] = [],
        finance: FinanceEntry? = nil,
        workouts: WorkoutEntry? = nil,
        goals: [GoalEntry] = [],
        quests: [QuestEntry] = [],
        streakDays: Int = 0,
        updatedAt: Date = .now
    ) {
        self.isSignedIn = isSignedIn
        self.displayName = displayName
        self.level = level
        self.xp = xp
        self.xpForNextLevel = xpForNextLevel
        self.todayXp = todayXp
        self.todayXpDate = todayXpDate
        self.tasks = tasks
        self.shopping = shopping
        self.journalDays = journalDays
        self.busy = busy
        self.finance = finance
        self.workouts = workouts
        self.goals = goals
        self.quests = quests
        self.streakDays = streakDays
        self.updatedAt = updatedAt
    }

    public static let signedOut = WidgetSnapshot(isSignedIn: false, updatedAt: .distantPast)

    // Снимок от старой версии приложения читается: новых полей в нём просто нет.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isSignedIn = try c.decode(Bool.self, forKey: .isSignedIn)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 1
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        xpForNextLevel = try c.decodeIfPresent(Int.self, forKey: .xpForNextLevel) ?? 100
        todayXp = try c.decodeIfPresent(Int.self, forKey: .todayXp) ?? 0
        todayXpDate = try c.decodeIfPresent(LocalDate.self, forKey: .todayXpDate)
        tasks = try c.decodeIfPresent([TaskEntry].self, forKey: .tasks) ?? []
        shopping = try c.decodeIfPresent([ShoppingEntry].self, forKey: .shopping) ?? []
        journalDays = try c.decodeIfPresent([LocalDate].self, forKey: .journalDays) ?? []
        busy = try c.decodeIfPresent([BusySlot].self, forKey: .busy) ?? []
        finance = try c.decodeIfPresent(FinanceEntry.self, forKey: .finance)
        workouts = try c.decodeIfPresent(WorkoutEntry.self, forKey: .workouts)
        goals = try c.decodeIfPresent([GoalEntry].self, forKey: .goals) ?? []
        quests = try c.decodeIfPresent([QuestEntry].self, forKey: .quests) ?? []
        streakDays = try c.decodeIfPresent(Int.self, forKey: .streakDays) ?? 0
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

// MARK: - Сборка снимка из данных приложения

extension WidgetSnapshot {
    /// Задачи, которые могут понадобиться виджетам в ближайшие дни: просроченные,
    /// на ближайшую неделю и те, что в работе.
    public static func taskEntries(_ tasks: [TaskItem], today: LocalDate = .today()) -> [TaskEntry] {
        let horizon = today.adding(days: 7)
        return tasks
            .filter { task in
                guard !task.isDone else { return false }
                if let due = task.dueDate { return due <= horizon }
                return task.status == .doing
            }
            .map(TaskEntry.init)
            .sorted(by: TaskEntry.byDue)
            .prefix(60)
            .map { $0 }
    }

    public static func shoppingEntries(_ items: [ShoppingItem]) -> [ShoppingEntry] {
        items
            .filter { !$0.isBought }
            .sorted { $0.position < $1.position }
            .prefix(60)
            .map(ShoppingEntry.init)
    }

    public static func journalDays(_ entries: [JournalEntry], today: LocalDate = .today()) -> [LocalDate] {
        let since = today.adding(days: -60)
        return Array(Set(entries.map(\.entryDate).filter { $0 >= since })).sorted()
    }

    public static func busySlots(_ facts: [ProfileFact]) -> [BusySlot] {
        facts.compactMap { fact in
            guard fact.isActive, let schedule = fact.schedule, schedule.busy else { return nil }
            return BusySlot(title: fact.text, weekdays: schedule.weekdays, start: schedule.start, end: schedule.end)
        }
    }

    public mutating func apply(_ progress: LevelProgress, today: LocalDate = .today()) {
        level = progress.level
        xp = progress.xpInLevel
        xpForNextLevel = progress.xpForNextLevel
        todayXp = progress.todayXp
        todayXpDate = today
    }

    /// Отметки из виджетов, которые ещё не дошли до сервера, поверх данных с сервера.
    public mutating func apply(_ pending: [WidgetAction], today: LocalDate = .today()) {
        for action in pending {
            switch action {
            case .task(let id, let done):
                if let index = tasks.firstIndex(where: { $0.id == id }) {
                    tasks[index].doneOn = done ? today : nil
                }
            case .shopping(let id, let bought):
                if let index = shopping.firstIndex(where: { $0.id == id }) {
                    shopping[index].isBought = bought
                }
            }
        }
    }

    /// То же содержимое, без учёта времени записи: чтобы не перерисовывать виджеты зря.
    public func hasSameContent(as other: WidgetSnapshot) -> Bool {
        var lhs = self, rhs = other
        lhs.updatedAt = .distantPast
        rhs.updatedAt = .distantPast
        return lhs == rhs
    }
}

// MARK: - Что показать на конкретный день

extension WidgetSnapshot {
    /// Задачи дня: просроченные и на этот день, плюс те, что в работе.
    /// Отмеченные в виджете остаются зачёркнутыми до конца дня.
    public func tasks(on day: LocalDate) -> [TaskEntry] {
        tasks.filter { task in
            if let doneOn = task.doneOn, doneOn != day { return false }
            if let due = task.dueDate { return due <= day }
            return task.isDoing
        }
    }

    /// Ближайшая задача со временем, которое ещё не прошло.
    public func nextTimedTask(after now: Date, calendar: Calendar = .current) -> TaskEntry? {
        let day = LocalDate(now, calendar: calendar)
        let clock = Self.clock(now, calendar: calendar)
        return tasks(on: day)
            .filter { $0.doneOn == nil && $0.dueDate == day && ($0.dueTime ?? "") >= clock }
            .min { ($0.dueTime ?? "") < ($1.dueTime ?? "") }
    }

    public func busySlots(on day: LocalDate) -> [BusySlot] {
        busy.filter { $0.weekdays.contains(day.weekday) }.sorted { $0.start < $1.start }
    }

    public func xpToday(on day: LocalDate) -> Int {
        todayXpDate == day ? todayXp : 0
    }

    public func hasJournal(on day: LocalDate) -> Bool {
        journalDays.contains(day)
    }

    /// Дней дневника подряд. Если сегодня ещё не писал, серия считается до вчера — день не кончился.
    public func journalStreak(on day: LocalDate) -> Int {
        let days = Set(journalDays)
        var cursor = days.contains(day) ? day : day.adding(days: -1)
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = cursor.adding(days: -1)
        }
        return streak
    }

    /// Потрачено за день (0, если снимок про другой день).
    public func spentToday(on day: LocalDate) -> Double {
        guard let finance, finance.day == day else { return 0 }
        return finance.spentToday
    }

    /// Потрачено за месяц этого дня (0, если месяц уже другой).
    public func spentMonth(on day: LocalDate) -> Double {
        guard let finance, finance.month.year == day.year, finance.month.month == day.month else { return 0 }
        return finance.spentMonth
    }

    /// Тренировок на неделе (пн–вс) этого дня.
    public func workoutsThisWeek(on day: LocalDate) -> Int {
        let monday = day.adding(days: -(Weekday.allCases.firstIndex(of: day.weekday) ?? 0))
        return (workouts?.days ?? []).filter { $0 >= monday && $0 <= day }.count
    }

    /// Квесты, которые ещё идут в этот день.
    public func quests(on day: LocalDate) -> [QuestEntry] {
        quests.filter { $0.periodEnd >= day && (!$0.isDaily || $0.periodEnd == day) }
    }

    /// Покупки к показу: невычеркнутые, затем вычеркнутые в виджете.
    public var shoppingToShow: [ShoppingEntry] {
        shopping.filter { !$0.isBought } + shopping.filter(\.isBought)
    }

    static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

extension WidgetSnapshot.TaskEntry {
    /// Сначала с ранним сроком (без срока — в конце); внутри дня — по времени, затем важные.
    public static func byDue(_ lhs: Self, _ rhs: Self) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (l?, r?) where l != r: return l < r
        case (nil, _?): return false
        case (_?, nil): return true
        default:
            let lt = lhs.dueTime ?? "99:99", rt = rhs.dueTime ?? "99:99"
            if lt != rt { return lt < rt }
            return lhs.isImportant && !rhs.isImportant
        }
    }
}

// MARK: - Хранилище

public enum SnapshotStoreError: Error {
    case appGroupUnavailable
}

public struct SnapshotStore: Sendable {
    public let appGroupID: String
    private let file: AppGroupFile<WidgetSnapshot>

    public init(appGroupID: String) {
        self.appGroupID = appGroupID
        file = AppGroupFile(appGroupID: appGroupID, name: "widget-snapshot.json")
    }

    /// false — App Group не настроена или недоступна при этой подписи.
    public var isAvailable: Bool { file.isAvailable }

    public func read() -> WidgetSnapshot? {
        file.read()
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        guard file.isAvailable else { throw SnapshotStoreError.appGroupUnavailable }
        file.write(snapshot)
    }

    /// Изменить снимок на месте (из виджета). Без снимка ничего не делает.
    public func update(_ change: (inout WidgetSnapshot) -> Void) {
        file.update { snapshot in
            guard var current = snapshot else { return }
            change(&current)
            current.updatedAt = .now
            snapshot = current
        }
    }
}
