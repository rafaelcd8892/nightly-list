import SwiftUI

/// Una fila de la lista. Vive aparte porque el cuerpo del ForEach se volvio
/// demasiado grande para que el type-checker resolviera el overload de
/// bindings de ForEach.
struct TaskRow: View {
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
func suggestedDueDate() -> Date {
    let calendar = Calendar.current
    let nextHour = calendar.date(byAdding: .hour, value: 1, to: .now) ?? .now
    return calendar.date(
        bySettingHour: calendar.component(.hour, from: nextHour),
        minute: 0,
        second: 0,
        of: nextHour
    ) ?? nextHour
}

/// La referencia de ticket detectada en el titulo, en pequeño.
///
/// No se quita del titulo: el texto se queda como lo escribio el usuario y
/// esto solo lo señala.
struct TicketChip: View {
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
struct ListDot: View {
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
