import SwiftUI

struct TaskListView: View {
    @ObservedObject var store: TaskStore
    @StateObject private var loginItem = LoginItem()
    @State private var newTitle = ""
    @State private var loginError: String?
    /// Tarea cuyo selector de fecha esta abierto, si hay alguno.
    @State private var editingDateFor: TodoItem.ID?
    @State private var notificationsDenied = false

    /// Con pocas tareas dejamos crecer el popover; a partir de aqui scrollea.
    private let maxVisibleRows = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Nueva tarea…", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Añadir", action: add)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            if store.items.isEmpty {
                Text("Sin tareas")
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

            if notificationsDenied {
                Text("Las notificaciones estan desactivadas para Recordatorios en Ajustes del Sistema.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("\(store.pendingCount) pendientes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Limpiar hechas") { store.clearDone() }
                    .font(.caption)
                Button("Salir") { NSApplication.shared.terminate(nil) }
                    .font(.caption)
                    .keyboardShortcut("q")
            }

            Toggle("Abrir al iniciar sesión", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginError = loginItem.setEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)

            if let loginError {
                Text(loginError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { loginItem.refresh() }
    }

    private var taskRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($store.items) { $item in
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
        store.add(newTitle)
        newTitle = ""
    }
}

/// Una fila de la lista. Vive aparte porque el cuerpo del ForEach se volvio
/// demasiado grande para que el type-checker resolviera el overload de
/// bindings de ForEach.
private struct TaskRow: View {
    @Binding var item: TodoItem
    let isEditingDate: Bool
    let onToggleDateEditor: () -> Void
    let onDueDateChanged: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    item.isDone.toggle()
                } label: {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? Color.secondary : Color.primary)

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
                .help(item.dueDate == nil ? "Poner recordatorio" : "Cambiar recordatorio")

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

                    Button("Quitar") { item.dueDate = nil }
                        .font(.caption)
                }
                .padding(.leading, 24)
            }
        }
    }

    /// El selector necesita una fecha no opcional.
    private var dueDate: Binding<Date> {
        Binding(
            get: { item.dueDate ?? suggestedDueDate() },
            set: {
                item.dueDate = $0
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
