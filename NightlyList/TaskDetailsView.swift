import SwiftUI

/// Notas, prioridad y URL de una tarea, los campos que Recordatorios guarda y
/// esta app tiraba en silencio.
///
/// Trabaja por id contra el almacen en vez de con un Binding: la ventana
/// sobrevive a que la tarea se archive o se recargue desde Recordatorios, y
/// con un binding a un indice eso acaba escribiendo en la tarea equivocada.
struct TaskDetailsView: View {
    let id: TodoItem.ID

    @ObservedObject private var store = TaskStore.shared

    init(id: TodoItem.ID) {
        self.id = id
    }

    private var item: TodoItem? { store.item(id: id) }

    var body: some View {
        if let item {
            content(item)
        } else {
            Text("This task no longer exists.")
                .foregroundStyle(.secondary)
                .frame(width: 360, height: 120)
        }
    }

    private func content(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Title") {
                TextField("", text: title)
                    .textFieldStyle(.roundedBorder)
            }

            field("Priority") {
                Picker("", selection: priority) {
                    ForEach(TaskPriority.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            field("Notes") {
                TextEditor(text: notes)
                    .font(.body)
                    .frame(height: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.quaternary)
                    )
            }

            field("URL") {
                HStack(spacing: 6) {
                    TextField("https://", text: urlText)
                        .textFieldStyle(.roundedBorder)

                    Button("Open") {
                        if let url = item.url { NSWorkspace.shared.open(url) }
                    }
                    .disabled(item.url == nil)
                }
            }

            if let repetition = item.recurrenceSummary {
                // Solo lectura a proposito: EventKit borra la regla entera si
                // le escribes una lista vacia, y media regla mal escrita se
                // lleva por delante una repeticion que el usuario monto en
                // Recordatorios. Se enseña, no se toca.
                HStack(spacing: 6) {
                    Image(systemName: "repeat")
                    Text(repetition)
                    Spacer()
                    Text("Edit in Reminders")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(item.isSyncedWithReminders
                 ? "Synced with Reminders."
                 : "Local only: this task is not in Reminders yet.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 380)
    }

    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Bindings

    private var title: Binding<String> {
        Binding(
            get: { item?.title ?? "" },
            // Un titulo en blanco no se guarda, igual que al renombrar en la
            // lista: la tarea conserva el que tenia.
            set: { nuevo in
                let limpio = nuevo.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !limpio.isEmpty else { return }
                store.update(id: id) { $0.title = limpio }
            }
        )
    }

    private var priority: Binding<TaskPriority> {
        Binding(
            get: { item?.priority ?? .none },
            set: { store.setPriority($0, id: id) }
        )
    }

    /// Escribe siempre una cadena, nunca nil: editar las notas es tener una
    /// opinion sobre ellas, y vaciarlas tiene que llegar a Recordatorios.
    private var notes: Binding<String> {
        Binding(
            get: { item?.notes ?? "" },
            set: { nuevo in store.update(id: id) { $0.notes = nuevo } }
        )
    }

    private var urlText: Binding<String> {
        Binding(
            get: { item?.urlString ?? "" },
            set: { nuevo in store.update(id: id) { $0.urlString = nuevo } }
        )
    }
}
