//
//  RecordatoriosApp.swift
//  Recordatorios
//
//  Created by Rafael on 11/09/26.
//

import SwiftUI
import UserNotifications

@main
struct RecordatoriosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

/// Solo existe para recibir las notificaciones: sin delegado, macOS se come el
/// aviso cuando la app esta activa (que es justo cuando el popover esta abierto).
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
