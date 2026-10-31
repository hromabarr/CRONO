import Charts
import SwiftUI

/// Las estadísticas de un hábito: rachas, cumplimiento por semanas y meses, y
/// el día de la semana que más se falla.
struct HabitDetailView: View {
    let habit: Habit

    private let today = Date.now.dayKey
    private let insights = HabitInsights()

    private var series: HabitSeries { HabitSeries(habit: habit, today: today) }

    var body: some View {
        let series = series
        let stats = StreakCalculator().stats(for: habit, today: today)
        let weeks = insights.weeklyRates(for: [series], weeks: 12, today: today)
        let months = insights.monthlyRates(for: [series], months: 6, today: today)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    StatTile(
                        value: "\(stats.currentStreak)",
                        caption: "Racha actual",
                        accessibilityText: "Racha actual: \(stats.currentStreak) días"
                    )
                    StatTile(
                        value: "\(stats.bestStreak)",
                        caption: "Mejor racha",
                        accessibilityText: "Mejor racha: \(stats.bestStreak) días"
                    )
                    StatTile(
                        value: percent(stats.completionRate),
                        caption: "Desde el alta",
                        accessibilityText: "\(percent(stats.completionRate)) cumplido desde el alta"
                    )
                }

                if let insight = insightText(for: series) {
                    Label(insight, systemImage: "lightbulb")
                        .font(.callout)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .groupedCard(cornerRadius: 16)
                        .padding(.top, 12)
                }

                SectionLabel("Últimas 12 semanas")
                WeeklyRateChart(rates: weeks, tint: habit.color.color)
                    .padding(16)
                    .groupedCard()

                SectionLabel("Últimos 6 meses")
                MonthlyRateChart(rates: months, tint: habit.color.color)
                    .padding(16)
                    .groupedCard()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(Text(habit.name))
        .navigationBarTitleDisplayMode(.large)
    }

    /// Una frase que diga algo que las cifras no dicen solas.
    private func insightText(for series: HabitSeries) -> String? {
        var parts: [String] = []

        if habit.hasQuantityGoal, let average = insights.averageCount(for: series, days: 30, today: today) {
            let value = average.formatted(.number.precision(.fractionLength(0...1)))
            let unit = habit.unit.isEmpty ? "" : " \(habit.unit)"
            parts.append("Media de los últimos 30 días: \(value) de \(habit.targetCount)\(unit).")
        }

        if let weakest = insights.weakestWeekday(for: series) {
            let symbols = AppCalendar.current.weekdaySymbols
            let name = symbols.indices.contains(weakest.weekday - 1) ? symbols[weakest.weekday - 1] : ""
            parts.append("Tu día flojo: los \(name) (\(percent(weakest.rate))).")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

private func percent(_ value: Double) -> String {
    "\(Int((value * 100).rounded())) %"
}

// MARK: - Gráficos

/// Barras de cumplimiento por semana. Las semanas sin nada que cumplir no
/// dibujan barra: no son un 0 %.
struct WeeklyRateChart: View {
    let rates: [PeriodRate]
    let tint: Color

    var body: some View {
        Chart(rates) { period in
            if let rate = period.rate {
                BarMark(
                    x: .value("Semana", period.date, unit: .weekOfYear),
                    y: .value("Cumplido", rate * 100)
                )
                .foregroundStyle(tint.gradient)
                .cornerRadius(4)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0) %") }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 180)
        .accessibilityLabel(Text("Cumplimiento por semana"))
    }
}

/// Línea de cumplimiento por mes.
struct MonthlyRateChart: View {
    let rates: [PeriodRate]
    let tint: Color

    var body: some View {
        Chart(rates) { period in
            if let rate = period.rate {
                LineMark(
                    x: .value("Mes", period.date, unit: .month),
                    y: .value("Cumplido", rate * 100)
                )
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Mes", period.date, unit: .month),
                    y: .value("Cumplido", rate * 100)
                )
                .foregroundStyle(tint)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0) %") }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .frame(height: 160)
        .accessibilityLabel(Text("Cumplimiento por mes"))
    }
}
