# 🚀 Quick Start: EventKit Integration

## ⚡ 3 Steps to Get Running

### Step 1: Add Privacy Permission (REQUIRED)

> **Ya hecho.** Este proyecto genera el Info.plist desde los ajustes
> `INFOPLIST_KEY_*` del target, y la clave ya esta puesta ahi junto con
> `ENABLE_RESOURCE_ACCESS_CALENDARS = YES`. No hay Info.plist que editar.

Open your `Info.plist` and add:

```xml
<key>NSRemindersFullAccessUsageDescription</key>
<string>Sincronizamos tus tareas con la app Recordatorios para que las veas en todos tus dispositivos Apple.</string>
```

**In Xcode:**
1. Select your target
2. Go to the **Info** tab
3. Click **+** to add a new key
4. Choose **Privacy - Reminders Full Access Usage Description**
5. Enter the message: `Sincronizamos tus tareas con la app Recordatorios para que las veas en todos tus dispositivos Apple.`

### Step 2: Build & Run

That's it! The EventKit framework should already be linked automatically.

If you get a build error about missing EventKit:
1. Select your target
2. Go to **General** → **Frameworks, Libraries, and Embedded Content**
3. Click **+** and add **EventKit.framework**

### Step 3: Test It!

1. Run the app
2. Open the menu bar popover
3. Check **"Sincronizar con Recordatorios"**
4. Grant permission when prompted
5. Open the **Reminders** app on your Mac
6. See your tasks appear! 🎉

---

## 🧪 Quick Test

1. **Create a task in your app** → Opens in Reminders
2. **Edit in Reminders app** → Syncs back to your app
3. **Mark as done in Reminders** → Updates in your app
4. **Delete in Reminders** → Removes from your app

---

## 🔍 Visual Verification

Tasks synced with Reminders will show a **blue badge icon** (🔵) next to their title.

At the bottom of the popover you'll see:
```
☑ Sincronizar con Recordatorios
Última sync: hace 5s  🔄
```

---

## 🐛 Troubleshooting

### Permission Denied
→ Go to **System Settings** → **Privacy & Security** → **Reminders**
→ Make sure your app is checked

### Not Syncing
→ Click the 🔄 button to manually trigger sync
→ Check for error messages in orange text

### Tasks Not in Reminders App
→ Open Reminders app
→ Look in the default "Reminders" list
→ Make sure iCloud is enabled for Reminders

---

## 📚 Full Documentation

- **`REMINDERS_SYNC_SETUP.md`** - Complete setup guide
- **`INTEGRATION_SUMMARY.md`** - Full technical summary
- **`RemindersSync.swift`** - Source code with comments

---

## ✅ That's It!

You now have full two-way sync with Apple Reminders! 🎉

Your users can:
- ✅ Manage tasks on Mac, iPhone, iPad, Apple Watch
- ✅ Use Siri: "Hey Siri, add milk to my reminders"
- ✅ See tasks in Reminders widgets
- ✅ Everything stays in sync via iCloud
