import SwiftData
import SwiftUI

/// Pantalla de gestión: crear, editar, reordenar, archivar y eliminar.
struct HabitListView: View {
    @Query(
        filter: #Predicate<Habit> { $0.archivedAt == nil },
        sort: [SortDescriptor(\Habit.sortIndex), SortDescriptor(\Habit.createdAt)]
    )
    private var activeHabits: [Habit]

    @Query(
        filter: #Predicate<Habit> { $0.archivedAt != nil },
        sort: [SortDescriptor(\Habit.archivedAt, order: .reverse)]
    )
    private var archivedHabits: [Habit]

    @Environment(HabitStore.self) private var store

    @State private var editingMode: HabitFormViewModel.Mode?

    /// Necesario porque las propiedades almacenadas son privadas: el
    /// inicializador sintetizado sería privado y exigiría los dos `@Query`.
    init() {}

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Hábitos")
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
        ToolbarItem(placement: .primaryAction) {
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
        Section("Activos") {
            ForEach(habits) { habit in
                ActiveHabitRow(habit: habit, onEdit: { onEdit(habit) })
                    .swipeActions(edge: .trailing) {
                        Button {
                            store.archive(habit)
                        } label: {
                            Label("Archivar", systemImage: "archivebox")
                        }
                        .tint(.orange)
                    }
            }
            .onMove { source, destination in
                store.move(habits, from: source, to: destination)
            }
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
                ArchivedHabitRow(habit: habit)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(habit)
                        } label: {
                            Label("Eliminar", systemImage: "trash")
                        }

                        Button {
                            store.unarchive(habit)
                        } label: {
                            Label("Reactivar", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                    }
            }
        } header: {
            Text("Archivados")
        } footer: {
            Text("Conservan su historial. Desliza para reactivarlos o eliminarlos.")
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
        case let .edit(habit): habit.id.uuidString
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
