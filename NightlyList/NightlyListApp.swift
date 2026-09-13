//
//  NightlyListApp.swift
//  Nightly List
//
//  Created by Rafael on 11/09/26.
//

import SwiftUI
import Carbon.HIToolbox
import UserNotifications

@main
struct NightlyListApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// La unica escena de SwiftUI. El icono de la barra y la ventana principal
    /// se gestionan con AppKit desde el delegado, porque MenuBarExtra no
    /// distingue el boton del raton y no deja poner menu contextual.
    var body: some Scene {
        Settings {
            SettingsView()
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

        // Option+Espacio abre la captura rapida.
        HotKeyCenter.shared.register(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey)
        ) { [quickAdd] in
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
