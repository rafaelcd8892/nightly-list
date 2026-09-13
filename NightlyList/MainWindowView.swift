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
        case archived
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
                sidebarRow(.archived, "Archive", systemImage: "archivebox")
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
        if scope == .archived {
            archiveList
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

    /// El archivo es solo de lectura: es lo que ya se retiro de la lista, y
    /// esta ahi para consultarlo, no para trastear con ello.
    private var archiveList: some View {
        List {
            ForEach(store.archived.filter(matchesSearch).sorted { archiveOrder($0, $1) }) { item in
                HStack(spacing: 8) {
                    ListDot(listIdentifier: item.listIdentifier, listTitle: item.listTitle)

                    if let reference = item.ticketReference {
                        TicketChip(reference: reference)
                    }

                    Text(item.title)
                        .strikethrough()
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let archivedAt = item.archivedAt {
                        Text(archivedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search the archive")
        .overlay {
            if store.archived.filter(matchesSearch).isEmpty {
                ContentUnavailableView("The archive is empty", systemImage: "archivebox")
            }
        }
        .navigationTitle("Archive")
        .navigationSubtitle("\(store.archived.count) tasks")
    }

    private func archiveOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        (lhs.archivedAt ?? lhs.createdAt) > (rhs.archivedAt ?? rhs.createdAt)
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
        case .archived:
            return false
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
        if case .archived = scope { return store.archived.count }
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
        case .archived: return "Archive"
        case .all: return "All tasks"
        case let .list(identifier):
            return sync.lists.first { $0.id == identifier }?.title ?? "List"
        }
    }
}

/// Abrir la ventana desde una app sin Dock ni menu tiene truco: hay que
/// activar la app a mano o aparece detras de todo.
enum MainWindow {
    static let id = "main"

    static func open(with openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}
