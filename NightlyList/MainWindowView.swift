import SwiftUI

/// La ventana principal.
///
/// El popover es para capturar y echar un vistazo; aqui se navega. Con
/// doscientas tareas sincronizadas, un panel de 360 puntos se queda corto para
/// buscar o repasar el historial.
struct MainWindowView: View {
    @ObservedObject var store: TaskStore
    @StateObject private var sync = RemindersSync.shared
    @State private var scope: Scope = .open
    @State private var search = ""
    @State private var editingDateFor: TodoItem.ID?

    enum Scope: Hashable {
        case today
        case open
        case completed
        case all
        case list(String)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 420)
    }

    // MARK: - Barra lateral

    private var sidebar: some View {
        List(selection: $scope) {
            Section("Views") {
                sidebarRow(.today, "Today", systemImage: "sun.max")
                sidebarRow(.open, "Open", systemImage: "circle")
                sidebarRow(.completed, "Completed", systemImage: "checkmark.circle")
                sidebarRow(.all, "All", systemImage: "tray.full")
            }

            if !sync.lists.isEmpty {
                Section("Lists") {
                    ForEach(sync.lists) { list in
                        Label {
                            Text(list.title)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(list.color)
                        }
                        .badge(count(in: .list(list.id)))
                        .tag(Scope.list(list.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private func sidebarRow(_ scope: Scope, _ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .badge(count(in: scope))
            .tag(scope)
    }

    // MARK: - Contenido

    @ViewBuilder
    private var detail: some View {
        if scope == .completed {
            completedList
        } else {
            taskList
        }
    }

    private var taskList: some View {
        List {
            ForEach($store.items) { $item in
                if matches(item) {
                    TaskRow(
                        item: $item,
                        isEditingDate: editingDateFor == item.id,
                        onToggleDateEditor: { toggleDateEditor(for: $item) },
                        onDueDateChanged: {},
                        onDelete: { store.remove(item) }
                    )
                    .padding(.vertical, 2)
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search tasks")
        .overlay {
            if visibleCount == 0 {
                ContentUnavailableView(
                    search.isEmpty ? "Nothing here" : "No matches",
                    systemImage: search.isEmpty ? "checkmark.circle" : "magnifyingglass"
                )
            }
        }
        .navigationTitle(title(for: scope))
        .navigationSubtitle("\(visibleCount) tasks")
    }

    /// Completed junta lo hecho que sigue en la lista activa con lo que ya se
    /// archivo. Para quien mira, archivar es invisible: es mantenimiento de la
    /// lista activa, no una carpeta aparte que haya que recordar.
    private var completedList: some View {
        List {
            ForEach(completedItems) { item in
                HStack(spacing: 8) {
                    Button {
                        store.toggleCompletion(id: item.id)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Mark as open")

                    ListDot(listIdentifier: item.listIdentifier, listTitle: item.listTitle)

                    if let reference = item.ticketReference {
                        TicketChip(reference: reference)
                    }

                    Text(item.title)
                        .strikethrough()
                        .foregroundStyle(.secondary)

                    TaskBadges(item: item)

                    Spacer()

                    if let completedAt = item.completedAt {
                        Text(completedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button("Details…") { TaskDetailsWindowController.shared.show(item.id) }
                    if let url = item.url {
                        Button("Open link") { NSWorkspace.shared.open(url) }
                    }
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search completed")
        .overlay {
            if completedItems.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "Nothing completed yet" : "No matches",
                    systemImage: search.isEmpty ? "checkmark.circle" : "magnifyingglass"
                )
            }
        }
        .navigationTitle("Completed")
        .navigationSubtitle("\(completedItems.count) tasks")
    }

    /// De mas reciente a mas antigua: lo ultimo que se cerro es lo que se
    /// suele venir a mirar.
    private var completedItems: [TodoItem] {
        (store.items + store.archived)
            .filter { $0.isDone && matchesSearch($0) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    // MARK: - Filtrado

    private func matches(_ item: TodoItem) -> Bool {
        matchesScope(item, in: scope) && matchesSearch(item)
    }

    /// El ambito se pasa por parametro y no se lee del estado, para poder
    /// contar cuantas tareas caen en cada entrada de la barra lateral sin
    /// cambiar la seleccion.
    private func matchesScope(_ item: TodoItem, in scope: Scope) -> Bool {
        switch scope {
        case .today:
            let calendar = Calendar.current
            let completedToday = item.completedAt.map { calendar.isDateInToday($0) } ?? false
            return completedToday || calendar.isDateInToday(item.createdAt)
        case .open:
            return !item.isDone
        case .completed:
            return item.isDone
        case .all:
            return true
        case let .list(identifier):
            return item.listIdentifier == identifier
        }
    }

    private func matchesSearch(_ item: TodoItem) -> Bool {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return item.title.localizedStandardContains(needle)
    }

    private func count(in scope: Scope) -> Int {
        if case .completed = scope { return completedItems.count }
        return store.items.count { matchesScope($0, in: scope) }
    }

    private var visibleCount: Int {
        store.items.count(where: matches)
    }

    private func toggleDateEditor(for item: Binding<TodoItem>) {
        if editingDateFor == item.wrappedValue.id {
            editingDateFor = nil
            return
        }
        editingDateFor = item.wrappedValue.id
        if item.wrappedValue.dueDate == nil {
            item.wrappedValue.dueDate = suggestedDueDate()
        }
    }

    private func title(for scope: Scope) -> String {
        switch scope {
        case .today: return "Today"
        case .open: return "Open"
        case .completed: return "Completed"
        case .all: return "All tasks"
        case let .list(identifier):
            return sync.lists.first { $0.id == identifier }?.title ?? "List"
        }
    }
}
