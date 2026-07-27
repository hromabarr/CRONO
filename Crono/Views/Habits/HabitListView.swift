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

    var body: some View {
        NavigationStack {
            Group {
                if activeHabits.isEmpty && archivedHabits.isEmpty {
                    EmptyStateView.noHabits { editingMode = .create }
                } else {
                    list
                }
            }
            .navigationTitle("Hábitos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
            .sheet(item: $editingMode) { mode in
                HabitFormView(viewModel: HabitFormViewModel(mode: mode, store: store))
            }
        }
    }

    private var list: some View {
        List {
            if !activeHabits.isEmpty {
                Section("Activos") {
                    ForEach(activeHabits) { habit in
                        habitRow(habit)
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
                        store.move(activeHabits, from: source, to: destination)
                    }
                }
            }

            if !archivedHabits.isEmpty {
                Section {
                    ForEach(archivedHabits) { habit in
                        archivedRow(habit)
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
    }

    private func habitRow(_ habit: Habit) -> some View {
        Button {
            editingMode = .edit(habit)
        } label: {
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

    private func archivedRow(_ habit: Habit) -> some View {
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
