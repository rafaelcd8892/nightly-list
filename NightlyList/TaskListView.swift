import SwiftUI

struct TaskListView: View {
    @ObservedObject var store: TaskStore
    @State private var newTitle = ""
    /// Tarea cuyo selector de fecha esta abierto, si hay alguno.
    @State private var editingDateFor: TodoItem.ID?
    @State private var notificationsDenied = false
    // Today primero: lo que se abre a mirar es el dia, no el inventario.
    @State private var mode: Mode = .today
    /// Compartido con la vista de Today: esconder la seccion tiene que poder
    /// deshacerse desde el menu, o seria una puerta de un solo sentido.
    @AppStorage("today.doneHiddenOn") private var doneHiddenOn = ""

    private var doneHiddenToday: Bool {
        doneHiddenOn == DayReportView.dayKey(Date())
    }
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
                // El filtro de lista vale para las dos pestañas: mirar "Work"
                // y que Today siga ensenandolo todo no tiene sentido.
                DayReportView(
                    report: DayReport(
                        items: store.items.filter(matchesList),
                        archived: store.archived.filter(matchesList)
                    ),
                    maxVisibleRows: maxVisibleRows,
                    onToggle: store.toggleCompletion(id:),
                    onRename: store.rename(id:to:),
                    onDelete: store.delete(id:)
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
                moreMenu
            }

        }
        .padding(12)
        // 360 y no 320: con el boton Deshacer visible, el footer truncaba
        // "Limpiar hechas" a "Limpiar h...".
        .frame(width: 360)
        // El popover se abre a menudo; es buen momento para que la lista
        // activa se limpie sola.
        .onAppear { store.archiveOldCompleted() }
    }

    @ViewBuilder
    private var pendingList: some View {
        if visibleCount == 0 {
            Text(store.items.isEmpty ? "No tasks" : "Nothing open here")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else if visibleCount > maxVisibleRows {
            // Altura definida: un ScrollView con solo maxHeight colapsa a 0
            // dentro de un MenuBarExtra(.window), que se autodimensiona.
            ScrollView { taskRows }
                .frame(height: 320)
        } else {
            taskRows
        }
    }

    private var taskRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(activeBuckets) { bucket in
                VStack(alignment: .leading, spacing: 4) {
                    // Con un solo tramo el encabezado no dice nada que no se
                    // vea ya.
                    if activeBuckets.count > 1 {
                        Text(bucket.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bucket == .overdue ? Color.red : Color.secondary)
                    }

                    rows(in: bucket)
                }
            }
        }
    }

    /// Los tramos que tienen alguna tarea, en su orden.
    private var activeBuckets: [DueBucket] {
        DueBucket.allCases.filter { bucket in
            store.items.contains { matches($0) && DueBucket.of($0) == bucket }
        }
    }

    private func rows(in bucket: DueBucket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($store.items) { $item in
                if matches(item), DueBucket.of(item) == bucket {
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

    /// Lo que no se usa a diario vive aqui, para que el pie del popover no
    /// sea una hilera de botones.
    private var moreMenu: some View {
        Menu {
            Button("Main Window…") { MainWindowController.shared.show() }

            Button("Settings…") { SettingsWindowController.shared.show() }

            if doneHiddenToday {
                Button("Show today's completed") { doneHiddenOn = "" }
                Divider()
            }

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .font(.caption)
        .help("More")
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
                        Image(nsImage: list.dotImage)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let listFilter {
                    Circle()
                        .fill(listFilter.color)
                        .frame(width: 7, height: 7)
                }
                Text(listFilter?.title ?? "All lists")
            }
            .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Open ensena solo lo que queda por hacer. Lo completado de hoy esta en
    /// Today y lo anterior es historial: una pestaña llamada Open llena de
    /// tareas tachadas no se sostiene, y con doscientas no se puede usar.
    private func matches(_ item: TodoItem) -> Bool {
        !item.isDone && matchesList(item)
    }

    private func matchesList(_ item: TodoItem) -> Bool {
        guard let listFilter else { return true }
        return item.listIdentifier == listFilter.id
    }

    /// Cuantas filas se van a pintar de verdad. El recuento total ya no sirve
    /// para decidir ni el vacio ni el scroll.
    private var visibleCount: Int {
        store.items.count(where: matches)
    }

    private var doneCount: Int {
        store.items.count { $0.isDone }
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



/// El dia de un vistazo, y el boton que lo saca en Markdown.
private struct DayReportView: View {
    let report: DayReport
    /// El mismo umbral que la lista Open, para que el popover no cambie de
    /// tamaño al saltar de pestaña.
    let maxVisibleRows: Int
    let onToggle: (TodoItem.ID) -> Void
    let onRename: (TodoItem.ID, String) -> Void
    let onDelete: (TodoItem.ID) -> Void

    @ObservedObject private var session = PopoverSession.shared
    @State private var copied = false
    @State private var renamingID: TodoItem.ID?
    @State private var draftTitle = ""
    @FocusState private var renameFocused: Bool

    /// Plegada por defecto: el popover se abre para ver lo que queda, y el
    /// numero del encabezado ya dice lo que se hizo.
    @AppStorage("today.doneCollapsed") private var doneCollapsed = true

    /// El dia en el que se pidio esconder la seccion. Al cambiar de dia vuelve
    /// sola, para que esconderla no sea una puerta de un solo sentido.
    @AppStorage("today.doneHiddenOn") private var doneHiddenOn = ""

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
        // Un clic en cualquier hueco de la vista sale del renombrado: pinchar
        // en un texto no le quita el foco al campo, porque un Text no es
        // enfocable, asi que el foco por si solo no basta.
        .contentShape(Rectangle())
        .onTapGesture { commitRename() }
        // Y al cerrarse el popover tambien. onDisappear no sirve: el popover
        // no se destruye, se esconde.
        .onChange(of: session.closeCount) { _, _ in commitRename() }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !report.completed.isEmpty && !isDoneHidden {
                VStack(alignment: .leading, spacing: 4) {
                    doneHeader

                    if !doneCollapsed {
                        ForEach(report.completed) { item in
                            row(item, time: item.completedAt, done: true)
                        }
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

    private var isDoneHidden: Bool {
        doneHiddenOn == Self.dayKey(report.day)
    }

    private var doneHeader: some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { doneCollapsed.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .rotationEffect(.degrees(doneCollapsed ? 0 : 90))
                Text("Done · \(report.completed.count)")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(doneCollapsed ? "Show what you finished today" : "Fold it away")
        .contextMenu {
            Button("Hide for today") { doneHiddenOn = Self.dayKey(report.day) }
        }
    }

    /// Clave por dia, para que esconder la seccion caduque al dia siguiente.
    static func dayKey(_ date: Date) -> String {
        let partes = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(partes.year ?? 0)-\(partes.month ?? 0)-\(partes.day ?? 0)"
    }

    private func startRename(_ item: TodoItem) {
        draftTitle = item.title
        renamingID = item.id
        renameFocused = true
    }

    private func commitRename() {
        guard let renamingID else { return }
        onRename(renamingID, draftTitle)
        self.renamingID = nil
        renameFocused = false
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

            if renamingID == item.id {
                TextField("", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($renameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { renamingID = nil }
                    // Clic fuera: se guarda y se sale, como en Finder. Sin
                    // esto el modo renombrar solo se cerraba con Enter, y se
                    // quedaba puesto aunque la fila desapareciera.
                    .onChange(of: renameFocused) { _, enfocado in
                        if !enfocado { commitRename() }
                    }
            } else {
                Text(item.title)
                    .strikethrough(done)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .onTapGesture(count: 2) { startRename(item) }
            }

            Spacer()

            if let time, renamingID != item.id {
                Text(time, style: .time)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            Button("Rename") { startRename(item) }
            Button(done ? "Mark as open" : "Mark as done") { onToggle(item.id) }
            Divider()
            Button("Delete", role: .destructive) { onDelete(item.id) }
        }
    }
}
