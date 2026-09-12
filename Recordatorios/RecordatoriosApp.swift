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
            Image(nsImage: Self.statusImage(pending: store.pendingCount))
        }
        .menuBarExtraStyle(.window)
    }

    /// MenuBarExtra solo respeta un Text o un Image como label: un HStack se
    /// ignora y un Label o un Text con simbolo interpolado pierden una de las
    /// dos partes. Para ensenar icono y numero juntos hay que rasterizarlos.
    private static func statusImage(pending: Int) -> NSImage {
        let label = HStack(spacing: 3) {
            Image(systemName: "checklist")
            Text("\(pending)")
                .font(.system(size: 12, weight: .semibold))
        }
        .frame(height: 16)

        let renderer = ImageRenderer(content: label)
        renderer.scale = 2

        guard let image = renderer.nsImage else {
            return NSImage(systemSymbolName: "checklist", accessibilityDescription: nil) ?? NSImage()
        }
        // Plantilla: el sistema lo recolorea segun la barra clara u oscura.
        image.isTemplate = true
        return image
    }
}
