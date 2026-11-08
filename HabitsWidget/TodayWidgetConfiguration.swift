import AppIntents
import WidgetKit

// Настройка виджета «Сегодня»: все привычки или одна группа.

struct HabitGroupEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Group"
    static let defaultQuery = HabitGroupQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct HabitGroupQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [HabitGroupEntity] {
        Self.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [HabitGroupEntity] {
        Self.all()
    }

    private static func all() -> [HabitGroupEntity] {
        (DataFile.loadIfAvailable()?.sortedGroups ?? []).map { HabitGroupEntity(id: $0.id, name: $0.name) }
    }
}

struct TodayWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Today's habits"
    static let description = IntentDescription("Show all habits or only one group.")

    /// Пусто - все привычки.
    @Parameter(title: "Group")
    var group: HabitGroupEntity?

    init() {}
}

struct GroupHabitsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitsEntry {
        .sample
    }

    func snapshot(for configuration: TodayWidgetConfiguration, in context: Context) async -> HabitsEntry {
        if context.isPreview { return .sample }
        return HabitsProvider.timeline(groupID: configuration.group?.id).entries.first ?? .sample
    }

    func timeline(for configuration: TodayWidgetConfiguration, in context: Context) async -> Timeline<HabitsEntry> {
        HabitsProvider.timeline(groupID: configuration.group?.id)
    }
}
