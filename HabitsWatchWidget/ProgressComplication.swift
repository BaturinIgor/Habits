import SwiftUI
import WidgetKit

// Компликации ZenHab на циферблате и в Смарт-стопке: сколько привычек сделано сегодня.
// Данные берутся из файла, который ведёт приложение на часах.

@main
struct HabitsWatchWidgets: WidgetBundle {
    var body: some Widget {
        ProgressComplication()
    }
}

struct ProgressEntry: TimelineEntry {
    let date: Date
    let done: Int
    let total: Int
    let next: String?
    let hasData: Bool

    var progress: Double { total > 0 ? Double(done) / Double(total) : 0 }
    var allDone: Bool { total > 0 && done >= total }
}

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: Date(), done: 2, total: 5, next: nil, hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let now = Date()
        let midnight = WatchDayKey.nextMidnight(after: now)
        // В полночь сразу показываем новый день из снимка (там есть и завтра).
        let entries = [Self.entry(for: now), Self.entry(for: midnight)]
        completion(Timeline(entries: entries, policy: .after(WatchDayKey.nextMidnight(after: midnight))))
    }

    static func entry(for date: Date) -> ProgressEntry {
        let state = WatchStateFile.load()
        guard let day = state.day(WatchDayKey.make(date)) else {
            return ProgressEntry(date: date, done: 0, total: 0, next: nil, hasData: false)
        }
        let next = day.habits.first { !$0.done && !$0.skipped }?.name
        return ProgressEntry(date: date, done: day.doneCount, total: day.plannedCount, next: next, hasData: true)
    }
}

struct ProgressComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchProgress", provider: ProgressProvider()) { entry in
            ProgressComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Today's progress")
        .description("See how many habits are done today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct ProgressComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProgressEntry

    private var fraction: String { "\(entry.done)/\(entry.total)" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.progress) {
                Image(systemName: "leaf.fill")
            } currentValueLabel: {
                if entry.allDone {
                    Image(systemName: "checkmark")
                } else {
                    Text(verbatim: fraction)
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryCorner:
            Image(systemName: entry.allDone ? "checkmark.circle.fill" : "leaf.fill")
                .font(.title2)
                .widgetAccentable()
                .widgetLabel {
                    Gauge(value: entry.progress) {
                        Text(verbatim: "ZenHab")
                    } currentValueLabel: {
                        Text(verbatim: fraction)
                    } minimumValueLabel: {
                        Text(verbatim: "\(entry.done)")
                    } maximumValueLabel: {
                        Text(verbatim: "\(entry.total)")
                    }
                }
        case .accessoryInline:
            if entry.hasData && entry.total > 0 {
                Label {
                    Text(verbatim: "ZenHab \(fraction)")
                } icon: {
                    Image(systemName: entry.allDone ? "checkmark.circle" : "leaf")
                }
            } else {
                Label {
                    Text(verbatim: "ZenHab")
                } icon: {
                    Image(systemName: "leaf")
                }
            }
        default:
            rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill")
                Text(verbatim: "ZenHab")
            }
            .font(.headline)
            .widgetAccentable()
            if !entry.hasData {
                Text("Open ZenHab on your iPhone to see your habits here.")
                    .font(.caption2)
                    .lineLimit(2)
            } else if entry.total == 0 {
                Text("No habits today")
                    .font(.body)
            } else {
                if entry.allDone {
                    Text("All done!")
                        .font(.body)
                } else {
                    Text("\(entry.done) of \(entry.total)")
                        .font(.body)
                }
                if let next = entry.next {
                    Text(next)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
