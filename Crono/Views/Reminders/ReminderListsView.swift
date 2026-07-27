import SwiftData
import SwiftUI

/// Raíz de la pestaña Tareas: las listas.
struct ReminderListsView: View {
    @Query(ReminderQueries.lists) private var lists: [ReminderList]
    @Query(ReminderQueries.pending) private var pending: [Reminder]

    @Environment(ReminderStore.self) private var store

    @State private var newListName = ""
    @State private var showingNewList = false

    init() {}

    var body: some View {
        NavigationStack {
            List {
                smartSection
                listsSection
            }
            .navigationTitle(Text("Tareas"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .alert("Nueva lista", isPresented: $showingNewList) {
                TextField("Nombre", text: $newListName)
                Button("Crear") { createList() }
                Button("Cancelar", role: .cancel) { newListName = "" }
            } message: {
                Text("El color y el icono se pueden cambiar después.")
            }
        }
    }

    // MARK: - Secciones

    /// Vistas que agrupan tareas de todas las listas, como en Recordatorios.
    private var smartSection: some View {
        Section {
            NavigationLink {
                SmartReminderListView(kind: .today)
            } label: {
                SmartListRow(kind: .today, count: todayCount)
            }

            NavigationLink {
                SmartReminderListView(kind: .flagged)
            } label: {
                SmartListRow(kind: .flagged, count: flaggedCount)
            }
        }
    }

    @ViewBuilder
    private var listsSection: some View {
        Section {
            ForEach(lists) { list in
                NavigationLink {
                    ReminderListDetailView(list: list)
                } label: {
                    ReminderListRow(list: list)
                }
            }
            .onDelete { offsets in
                delete(at: offsets)
            }
            .onMove { source, destination in
                store.moveLists(lists, from: source, to: destination)
            }
        } header: {
            Text("Mis listas")
        } footer: {
            if lists.isEmpty {
                Text("Crea una lista para empezar a organizar tus tareas.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingNewList = true } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Nueva lista")
        }

        if !lists.isEmpty {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
    }

    // MARK: - Cuentas

    private var todayCount: Int {
        pending.topLevel.dueThrough(Date.now.dayKey).count
    }

    private var flaggedCount: Int {
        var count = 0
        for reminder in pending where reminder.isFlagged {
            count += 1
        }
        return count
    }

    // MARK: - Acciones

    private func createList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        newListName = ""
        guard !name.isEmpty else { return }
        store.createList(name: name)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets where lists.indices.contains(index) {
            store.delete(lists[index])
        }
    }
}

// MARK: - Filas

private struct ReminderListRow: View {
    let list: ReminderList

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: list.symbolName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(list.color.color, in: Circle())

            Text(list.name)

            Spacer(minLength: 8)

            Text("\(list.pendingCount)")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(list.name), \(list.pendingCount) pendientes")
    }
}

private struct SmartListRow: View {
    let kind: SmartReminderListView.Kind
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbolName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(kind.tint, in: Circle())

            Text(kind.title)

            Spacer(minLength: 8)

            Text("\(count)")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title), \(count) pendientes")
    }
}

#Preview("Listas") {
    let container = PreviewData.container()

    ReminderListsView()
        .modelContainer(container)
        .environment(PreviewData.reminderStore(for: container))
}
