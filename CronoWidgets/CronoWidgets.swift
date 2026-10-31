import SwiftUI
import WidgetKit

/// Los widgets de Crono: el progreso de hoy y la próxima alarma.
@main
struct CronoWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

// MARK: - Línea de tiempo

struct TodayEntry: TimelineEntry {
    let date: Date
    /// `nil` si la app no ha podido dejar el resumen: grupo de apps ausente o
    /// app aún sin abrir.
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, snapshot: WidgetSnapshot.read() ?? .sample))
    }

    /// Una entrada ahora y otra a medianoche: al cambiar de día los hábitos
    /// programados son otros, aunque la app no se haya abierto.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshot.read()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now

        var entries = [TodayEntry(date: now, snapshot: snapshot)]
        // También tras la próxima alarma, para que deje de anunciar una que ya
        // sonó.
        if let next = snapshot?.nextAlarm(after: now, calendar: calendar)?.date, next < midnight {
            entries.append(TodayEntry(date: next.addingTimeInterval(60), snapshot: snapshot))
        }
        entries.append(TodayEntry(date: midnight, snapshot: snapshot))

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CronoToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Hoy en Crono")
        .description("Tus hábitos de hoy y la próxima alarma.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            let summary = snapshot.summary(on: entry.date, calendar: .current)
            let alarm = snapshot.nextAlarm(after: entry.date, calendar: .current)
            switch family {
            case .accessoryCircular:
                Gauge(value: summary.fraction) {
                    Image(systemName: "checkmark")
                } currentValueLabel: {
                    Text("\(summary.done)/\(summary.total)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hábitos: \(summary.done) de \(summary.total)")
                        .font(.headline)
                    if let alarm {
                        Label(alarm.date.formatted(date: .omitted, time: .shortened), systemImage: "alarm")
                    }
                }
            case .systemMedium:
                HStack(spacing: 16) {
                    ProgressRing(summary: summary)
                    VStack(alignment: .leading, spacing: 6) {
                        PendingList(pending: summary.pending, limit: 3)
                        Spacer(minLength: 0)
                        AlarmLine(alarm: alarm)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            default:
                VStack(spacing: 8) {
                    ProgressRing(summary: summary)
                    AlarmLine(alarm: alarm)
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                Text("Abre Crono para ver tu día")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Piezas

private struct ProgressRing: View {
    let summary: WidgetSnapshot.DaySummary

    var body: some View {
        ZStack {
            Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: summary.fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(summary.done)/\(summary.total)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(summary.total == 0 ? "Nada hoy" : "hábitos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(summary.done) de \(summary.total) hábitos hechos"))
    }
}

private struct PendingList: View {
    let pending: [WidgetSnapshot.HabitItem]
    let limit: Int

    var body: some View {
        if pending.isEmpty {
            Label("Todo hecho", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(pending.prefix(limit).enumerated()), id: \.offset) { _, habit in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: habit.colorRaw))
                            .frame(width: 8, height: 8)
                        Text(habit.name)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
                if pending.count > limit {
                    Text("y \(pending.count - limit) más")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Los mismos colores que `HabitColor`, que vive en la app.
    private func color(for raw: String) -> Color {
        switch raw {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "teal": .teal
        case "indigo": .indigo
        case "purple": .purple
        default: .blue
        }
    }
}

private struct AlarmLine: View {
    let alarm: (alarm: WidgetSnapshot.AlarmEntry, date: Date)?

    var body: some View {
        if let alarm {
            Label(alarm.date.formatted(date: .omitted, time: .shortened), systemImage: "alarm")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Datos de ejemplo

extension WidgetSnapshot {
    /// Lo que se ve en la galería de widgets antes de añadirlo.
    static var sample: WidgetSnapshot {
        let today = WidgetSnapshot.dayKey(of: .now, calendar: .current)
        return WidgetSnapshot(
            writtenAt: .now,
            dayKey: today,
            habits: [
                HabitItem(name: "Meditar", colorRaw: "indigo", weekdaysMask: 127, firstDay: 0, doneOnSnapshotDay: true),
                HabitItem(name: "Agua", colorRaw: "teal", weekdaysMask: 127, firstDay: 0, doneOnSnapshotDay: false),
                HabitItem(name: "Leer", colorRaw: "green", weekdaysMask: 127, firstDay: 0, doneOnSnapshotDay: false)
            ],
            alarms: [AlarmEntry(label: "Despertar", minuteOfDay: 7 * 60, weekdaysMask: 127)]
        )
    }
}
