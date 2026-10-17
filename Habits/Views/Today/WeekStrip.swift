import SwiftUI
import UIKit

/// Горизонтальная лента дней с мини-кольцами прогресса.
struct WeekStrip: View {
    @Environment(HabitStore.self) private var store
    @Binding var selected: Date

    private let calendar = Calendar.app
    private let pastDays = 60
    private let futureDays = 14

    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (-pastDays...futureDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        let progress = Stats.day(day, in: store.data, calendar: calendar)
                        DayChip(
                            day: day,
                            isSelected: calendar.isDate(day, inSameDayAs: selected),
                            isToday: calendar.isDateInToday(day),
                            progress: progress
                        )
                        .id(DayKey.make(day, calendar: calendar))
                        .onTapGesture {
                            withAnimation(.snappy) { selected = day }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
            .onAppear {
                proxy.scrollTo(DayKey.make(selected, calendar: calendar), anchor: .center)
            }
            .onChange(of: selected) { _, newValue in
                withAnimation(.snappy) {
                    proxy.scrollTo(DayKey.make(newValue, calendar: calendar), anchor: .center)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct DayChip: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let progress: DayProgress

    private var dayNumber: String {
        String(Calendar.app.component(.day, from: day))
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(Fmt.weekdayShort(day))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            ZStack {
                ProgressRing(
                    progress: progress.fraction,
                    lineWidth: 3,
                    color: isSelected ? .white : .accentColor,
                    trackOpacity: progress.total == 0 ? 0 : (isSelected ? 0.3 : 0.15)
                )
                Text(dayNumber)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(numberColor)
            }
            .frame(width: 36, height: 36)
        }
        .frame(width: 50, height: 74)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected
                      ? AnyShapeStyle(Color.accentColor.gradient)
                      : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)))
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(isSelected ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
