import SwiftUI

/// Selector de los días de la semana en que toca un hábito.
///
/// Los días salen en el orden de presentación del usuario —lunes primero en
/// España— y las iniciales vienen del calendario, así que se traducen solas.
struct WeekdayPickerView: View {
    var isSelected: (Int) -> Bool
    var onToggle: (Int) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(WeekdaySet.weekdayOrder, id: \.self) { weekday in
                dayButton(weekday)
            }
        }
    }

    private func dayButton(_ weekday: Int) -> some View {
        let selected = isSelected(weekday)

        return Button {
            onToggle(weekday)
        } label: {
            Text(WeekdaySet.initial(forWeekday: weekday))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(
                    Circle().fill(selected ? Color.accentColor : Color(.tertiarySystemFill))
                )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(WeekdaySet.fullName(forWeekday: weekday))
        // El estado va como trait, no dentro de la etiqueta: VoiceOver ya
        // anuncia "seleccionado" en su propio idioma y con su propia entonación.
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Selector de días", traits: .sizeThatFitsLayout) {
    @Previewable @State var schedule: WeekdaySet = [.monday, .wednesday, .friday]

    VStack(alignment: .leading, spacing: 16) {
        WeekdayPickerView(
            isSelected: { schedule.contains(weekday: $0) },
            onToggle: { schedule = schedule.toggling(weekday: $0) }
        )
        Text(schedule.displayDescription)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
    .padding()
}
