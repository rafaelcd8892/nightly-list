//
//  RecordatoriosApp.swift
//  Recordatorios
//
//  Created by Rafael on 11/09/26.
//

import SwiftUI

@main
struct RecordatoriosApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        MenuBarExtra {
            TaskListView(store: store)
        } label: {
            Label("\(store.pendingCount)", systemImage: "checklist")
        }
        .menuBarExtraStyle(.window)
    }
}
