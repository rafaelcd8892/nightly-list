//
//  NightlyListApp.swift
//  Nightly List
//
//  Created by Rafael on 11/09/26.
//

import SwiftUI
import UserNotifications

@main
struct NightlyListApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Una App tiene que declarar al menos una escena, pero esta app no usa
    /// ninguna: el icono de la barra, la ventana principal y la de Ajustes se
    /// gestionan con AppKit desde el delegado. MenuBarExtra no distingue el
    /// boton del raton, y la escena Settings no se deja abrir desde fuera de
    /// una vista. Queda declarada y vacia a proposito.
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Solo existe para recibir las notificaciones: sin delegado, macOS se come el
/// aviso cuando la app esta activa (que es justo cuando el popover esta abierto).
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let quickAdd = QuickAddPanel()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        DiagnosticLog.shared.log(.app, "Launched")

        statusItem = StatusItemController(store: .shared)

        QuickCaptureHotKey.shared.start { [quickAdd] in
            quickAdd.toggle()
        }
    }

    /// Cerrar la ventana principal no puede cerrar la app: lo normal en una
    /// app de barra de menus es que siga ahi.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
