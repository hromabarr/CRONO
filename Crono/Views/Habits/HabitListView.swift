import SwiftData
import SwiftUI

/// Pantalla de gestión: crear, editar, reordenar, archivar y eliminar.
struct HabitListView: View {
    @Query(HabitQueries.active) private var activeHabits: [Habit]
    @Query(HabitQueries.archived) private var archivedHabits: [Habit]

    @Environment(HabitStore.self) private var store

    @State private var editingMode: HabitFormViewModel.Mode?

    /// Necesario porque las propiedades almacenadas son privadas: el
    /// inicializador sintetizado sería privado y exigiría los dos `@Query`.
    init() {}

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Hábitos"))
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbarContent }
                .sheet(item: $editingMode) { mode in
                    HabitFormView(
                        viewModel: HabitFormViewModel(mode: mode, store: store)
                    )
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if activeHabits.isEmpty && archivedHabits.isEmpty {
            EmptyStateView.noHabits { editingMode = .create }
        } else {
            List {
                if !activeHabits.isEmpty {
                    ActiveHabitsSection(
                        habits: activeHabits,
                        store: store,
                        onEdit: { editingMode = .edit($0) }
                    )
                }

                if !archivedHabits.isEmpty {
                    ArchivedHabitsSection(habits: archivedHabits, store: store)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Los dos van juntos a la derecha para que el `EditButton` conserve su
        // sitio a la izquierda: sin él no hay modo edición, y sin modo edición no
        // se pueden reordenar los hábitos arrastrando.
        ToolbarItemGroup(placement: .primaryAction) {
            // El historial se abre desde aquí y no desde la barra de pestañas:
            // pertenece a los hábitos, y así queda sitio para tareas y alarmas.
            NavigationLink {
                HistoryView()
            } label: {
                Image(systemName: "chart.bar")
            }
            .accessibilityLabel("Historial")

            Button { editingMode = .create } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Nuevo hábito")
        }

        if !activeHabits.isEmpty {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
    }
}

// MARK: - Secciones

private struct ActiveHabitsSection: View {
    let habits: [Habit]
    let store: HabitStore
    let onEdit: (Habit) -> Void

    var body: some View {
        Section {
            ForEach(habits) { habit in
                row(habit)
            }
            .onMove { source, destination in
                store.move(habits, from: source, to: destination)
            }
        } header: {
            // Cabecera explícita en lugar de `Section("Activos")`: la forma
            // corta obliga al inferidor a elegir entre las sobrecargas de
            // `LocalizedStringKey` y `StringProtocol`.
            Text("Activos")
        }
    }

    private func row(_ habit: Habit) -> some View {
        ActiveHabitRow(habit: habit, onEdit: { onEdit(habit) })
            .swipeActions(edge: .trailing) {
                Button {
                    store.archive(habit)
                } label: {
                    Label(text: "Archivar", systemImage: "archivebox")
                }
                .tint(.orange)
            }
    }
}

private struct ActiveHabitRow: View {
    let habit: Habit
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 14) {
                Circle()
                    .fill(habit.color.color)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .foregroundStyle(.primary)
                    Text(habit.schedule.displayDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(habit.name), \(habit.schedule.displayDescription)")
        .accessibilityHint("Toca para editar")
        .accessibilityAddTraits(.isButton)
    }
}

private struct ArchivedHabitsSection: View {
    let habits: [Habit]
    let store: HabitStore

    var body: some View {
        Section {
            ForEach(habits) { habit in
                row(habit)
            }
        } header: {
            Text("Archivados")
        } footer: {
            Text("Conservan su historial. Desliza para reactivarlos o eliminarlos.")
        }
    }

    /// Extraída de la `Section` a propósito: dos botones con etiqueta dentro de
    /// `swipeActions`, y todo ello anidado en un `Section` genérico de tres
    /// cierres, era demasiado para el inferidor de tipos.
    private func row(_ habit: Habit) -> some View {
        ArchivedHabitRow(habit: habit)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    store.delete(habit)
                } label: {
                    Label(text: "Eliminar", systemImage: "trash")
                }

                Button {
                    store.unarchive(habit)
                } label: {
                    Label(text: "Reactivar", systemImage: "arrow.uturn.backward")
                }
                .tint(.blue)
            }
    }
}

private struct ArchivedHabitRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(habit.color.color.opacity(0.5))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .foregroundStyle(.secondary)

                if let archivedAt = habit.archivedAt {
                    Text("Archivado el \(archivedAt.formatted(.dateTime.day().month(.wide)))")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Presentación del formulario

/// Permite presentar el formulario con `.sheet(item:)`, que exige identidad.
extension HabitFormViewModel.Mode: Identifiable {
    var id: String {
        switch self {
        case .create: "create"
        case let .edit(habit): habit.uuid.uuidString
        }
    }
}

#Preview("Con hábitos") {
    let container = PreviewData.container()

    HabitListView()
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
}

#Preview("Sin hábitos") {
    let container = PreviewData.emptyContainer()

    HabitListView()
        .modelContainer(container)
        .environment(PreviewData.store(for: container))
}
