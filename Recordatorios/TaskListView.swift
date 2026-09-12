import SwiftUI

struct TaskListView: View {
    @ObservedObject var store: TaskStore
    @State private var newTitle = ""

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
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach($store.items) { $item in
                            HStack(spacing: 8) {
                                Button {
                                    item.isDone.toggle()
                                } label: {
                                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isDone ? .green : .secondary)
                                }
                                .buttonStyle(.plain)

                                Text(item.title)
                                    .strikethrough(item.isDone)
                                    .foregroundStyle(item.isDone ? .secondary : .primary)

                                Spacer()

                                Button {
                                    store.remove(item)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
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
        }
        .padding(12)
        .frame(width: 320)
    }
}

private extension TaskListView {
    func add() {
        store.add(newTitle)
        newTitle = ""
    }
}
