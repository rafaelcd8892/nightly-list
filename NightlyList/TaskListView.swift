import SwiftUI

struct TaskListView: View {
    @ObservedObject var store: TaskStore
    @State private var newTitle = ""
    /// Tarea cuyo selector de fecha esta abierto, si hay alguno.
    @State private var editingDateFor: TodoItem.ID?
    @State private var notificationsDenied = false
    @State private var mode: Mode = .pending
    /// Lista por la que se filtra, o nil para todas.
    @State private var listFilter: TaskList?
    @StateObject private var sync = RemindersSync.shared

    /// Con pocas tareas dejamos crecer el popover; a partir de aqui scrollea.
    private let maxVisibleRows = 8

    enum Mode: String, CaseIterable, Identifiable {
        case pending = "Open"
        case today = "Today"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("New task…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack(spacing: 8) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if !sync.lists.isEmpty {
                    listFilterMenu
                }
            }

            switch mode {
            case .pending:
                pendingList
            case .today:
                DayReportView(
                    report: DayReport(items: store.items, archived: store.archived),
                    maxVisibleRows: maxVisibleRows,
                    onToggle: store.toggleCompletion(id:)
                )
            }

            if notificationsDenied {
                Text("Notifications are turned off for this app in System Settings.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let storageError = store.storageError {
                Text(storageError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("\(store.pendingCount) open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.canUndo {
                    Button("Undo") { store.undoRemoval() }
                        .font(.caption)
                        .keyboardShortcut("z")
                }
                Button("Archive done") { store.clearDone() }
                    .font(.caption)
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .help("Settings")
                // Una app LSUIElement no se pone delante sola: sin esto la
                // ventana de Ajustes se abre detras de todo.
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                })

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .font(.caption)
                    .keyboardShortcut("q")
            }

        }
        .padding(12)
        // 360 y no 320: con el boton Deshacer visible, el footer truncaba
        // "Limpiar hechas" a "Limpiar h...".
        .frame(width: 360)
    }

    @ViewBuilder
    private var pendingList: some View {
        if store.items.isEmpty {
            Text("No tasks")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else if store.items.count > maxVisibleRows {
            // Altura definida: un ScrollView con solo maxHeight colapsa a 0
            // dentro de un MenuBarExtra(.window), que se autodimensiona.
            ScrollView { taskRows }
                .frame(height: 320)
        } else {
            taskRows
        }
    }

    private var taskRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($store.items) { $item in
                if matches(item) {
                    TaskRow(
                        item: $item,
                        isEditingDate: editingDateFor == item.id,
                        onToggleDateEditor: { toggleDateEditor(for: $item) },
                        onDueDateChanged: askForNotificationPermission,
                        onDelete: { store.remove(item) }
                    )
                }
            }
        }
    }

    private var listFilterMenu: some View {
        Menu {
            Button("All lists") { listFilter = nil }
            Divider()
            ForEach(sync.lists) { list in
                Button {
                    listFilter = list
                } label: {
                    Label {
                        Text(list.title)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(list.color)
                    }
                }
            }
        } label: {
            Text(listFilter?.title ?? "All lists")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func matches(_ item: TodoItem) -> Bool {
        guard let listFilter else { return true }
        return item.listIdentifier == listFilter.id
    }

    private func toggleDateEditor(for item: Binding<TodoItem>) {
        if editingDateFor == item.wrappedValue.id {
            editingDateFor = nil
            return
        }
        editingDateFor = item.wrappedValue.id
        // Al abrir el selector sobre una tarea sin fecha le ponemos ya la
        // propuesta, para que el boton sirva de algo sin tocar el selector.
        if item.wrappedValue.dueDate == nil {
            item.wrappedValue.dueDate = suggestedDueDate()
            askForNotificationPermission()
        }
    }

    private func askForNotificationPermission() {
        Task {
            let granted = await ReminderScheduler.shared.ensureAuthorized()
            notificationsDenied = !granted
        }
    }
}

private extension TaskListView {
    func add() {
        store.add(newTitle, to: listFilter)
        newTitle = ""
    }
}

/// Una fila de la lista. Vive aparte porque el cuerpo del ForEach se volvio
/// demasiado grande para que el type-checker resolviera el overload de
/// bindings de ForEach.
private struct TaskRow: View {
    @Binding var item: TodoItem
    @State private var draftTitle: String?
    @FocusState private var titleFocused: Bool
    let isEditingDate: Bool
    let onToggleDateEditor: () -> Void
    let onDueDateChanged: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    item.isDone.toggle()
                    item.lastModified = Date()
                } label: {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ListDot(listIdentifier: item.listIdentifier, listTitle: item.listTitle)

                if let reference = item.ticketReference {
                    TicketChip(reference: reference)
                }

                VStack(alignment: .leading, spacing: 1) {
                    if let draftTitle {
                        TextField("", text: Binding(
                            get: { draftTitle },
                            set: { self.draftTitle = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .focused($titleFocused)
                        .onSubmit(commitTitle)
                        .onExitCommand { self.draftTitle = nil }
                        .onChange(of: titleFocused) { _, focused in
                            // Clic fuera: se guarda, como en Finder.
                            if !focused { commitTitle() }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text(item.title)
                                .strikethrough(item.isDone)
                                .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                                .onTapGesture(count: 2) { startEditingTitle() }
                                .help("Double-click to rename")
                            
                            if item.isSyncedWithReminders {
                                Image(systemName: "checkmark.circle.badge.questionmark.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .help("Synced with Apple Reminders")
                            }
                        }
                    }

                    if let dueDate = item.dueDate {
                        Text(dueDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                    }
                }

                Spacer()

                Button(action: onToggleDateEditor) {
                    Image(systemName: item.dueDate == nil ? "bell" : "bell.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.dueDate == nil ? Color.secondary : Color.accentColor)
                .help(item.dueDate == nil ? "Set reminder" : "Change reminder")

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
            }

            if isEditingDate {
                HStack(spacing: 6) {
                    DatePicker("", selection: dueDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()

                    Button("Clear") { 
                        item.dueDate = nil 
                        item.lastModified = Date()
                    }
                        .font(.caption)
                }
                .padding(.leading, 24)
            }
        }
        .contextMenu {
            Button("Rename") { startEditingTitle() }

            Button(item.isDone ? "Mark as open" : "Mark as done") {
                item.isDone.toggle()
                item.lastModified = Date()
            }

            Divider()

            Button(item.dueDate == nil ? "Add reminder…" : "Change reminder…") {
                onToggleDateEditor()
            }

            if item.dueDate != nil {
                Button("Remove reminder") {
                    item.dueDate = nil
                    item.lastModified = Date()
                }
            }

            if !RemindersSync.shared.lists.isEmpty {
                Menu("Move to") {
                    ForEach(RemindersSync.shared.lists) { list in
                        Button(list.title) {
                            let moved = item
                            Task { await RemindersSync.shared.move(moved, to: list) }
                        }
                        .disabled(list.id == item.listIdentifier)
                    }
                }
            }

            Divider()

            Button("Copy title") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.title, forType: .string)
            }

            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func startEditingTitle() {
        draftTitle = item.title
        titleFocused = true
    }

    /// Un titulo en blanco no se guarda: se descarta la edicion y la tarea
    /// conserva el nombre que tenia.
    private func commitTitle() {
        guard let draftTitle else { return }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            item.title = trimmed
            item.lastModified = Date()
        }
        self.draftTitle = nil
    }

    /// El selector necesita una fecha no opcional.
    private var dueDate: Binding<Date> {
        Binding(
            get: { item.dueDate ?? suggestedDueDate() },
            set: {
                item.dueDate = $0
                item.lastModified = Date()
                onDueDateChanged()
            }
        )
    }
}

/// La hora en punto siguiente.
private func suggestedDueDate() -> Date {
    let calendar = Calendar.current
    let nextHour = calendar.date(byAdding: .hour, value: 1, to: .now) ?? .now
    return calendar.date(
        bySettingHour: calendar.component(.hour, from: nextHour),
        minute: 0,
        second: 0,
        of: nextHour
    ) ?? nextHour
}

/// El dia de un vistazo, y el boton que lo saca en Markdown.
private struct DayReportView: View {
    let report: DayReport
    /// El mismo umbral que la lista Open, para que el popover no cambie de
    /// tamaño al saltar de pestaña.
    let maxVisibleRows: Int
    let onToggle: (TodoItem.ID) -> Void
    @State private var copied = false

    private var rowCount: Int { report.completed.count + report.created.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if report.isEmpty {
                Text("Nothing yet today.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else if rowCount > maxVisibleRows {
                // Altura definida y no maxHeight: dentro de un
                // MenuBarExtra(.window) un ScrollView sin altura fija colapsa
                // a cero. Mismo umbral y misma altura que la lista Open, para
                // que el popover no baile al cambiar de pestaña.
                ScrollView { sections }
                    .frame(height: 320)
            } else {
                sections
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report.markdown(), forType: .string)
                copied = true
            } label: {
                Label(
                    copied ? "Copied" : "Copy day as Markdown",
                    systemImage: copied ? "checkmark" : "doc.on.clipboard"
                )
                .font(.caption)
            }
            .disabled(report.isEmpty)
            // Vuelve a su sitio si cambia el dia mientras el popover sigue
            // abierto, para no dejar el "Copiado" pegado para siempre.
            .onChange(of: report.day) { _, _ in copied = false }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !report.completed.isEmpty {
                section("Done", count: report.completed.count) {
                    ForEach(report.completed) { item in
                        row(item, time: item.completedAt, done: true)
                    }
                }
            }

            if !report.created.isEmpty {
                section("Added", count: report.created.count) {
                    ForEach(report.created) { item in
                        row(item, time: nil, done: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) · \(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ item: TodoItem, time: Date?, done: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                onToggle(item.id)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.green : Color.secondary)
                    // Sin contentShape el area sensible es solo el trazo del
                    // simbolo, que son cuatro pixeles y no se acierta.
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(done ? "Mark as open" : "Mark as done")

            ListDot(listIdentifier: item.listIdentifier, listTitle: item.listTitle)

            if let reference = item.ticketReference {
                TicketChip(reference: reference)
            }

            Text(item.title)
                .strikethrough(done)
                .foregroundStyle(done ? Color.secondary : Color.primary)

            Spacer()

            if let time {
                Text(time, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// La referencia de ticket detectada en el titulo, en pequeño.
///
/// No se quita del titulo: el texto se queda como lo escribio el usuario y
/// esto solo lo señala.
private struct TicketChip: View {
    let reference: String

    var body: some View {
        Text(reference)
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.secondary)
            .help("Detected project reference")
    }
}

/// El color de la lista a la que pertenece la tarea.
///
/// Resuelve el color contra las listas que trae la sincronizacion en vez de
/// recibirlo por parametro, para no tener que hilarlo por media interfaz. Si
/// la lista ya no existe pero la tarea recuerda su nombre, se pinta en gris.
private struct ListDot: View {
    let listIdentifier: String?
    let listTitle: String?
    @ObservedObject private var sync = RemindersSync.shared

    var body: some View {
        if let listIdentifier,
           let list = sync.lists.first(where: { $0.id == listIdentifier }) {
            dot(list.color, name: list.title)
        } else if let listTitle {
            dot(.secondary, name: listTitle)
        }
    }

    private func dot(_ color: Color, name: String) -> some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .help(name)
    }
}
