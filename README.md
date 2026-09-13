# Nightly List

A macOS menu bar app that records what you actually got done, backed by Apple
Reminders.

Most task apps are good at collecting work and bad at remembering it. This one
keeps the *when*: every task stores the moment it was created and the moment it
was completed, so at the end of the day you can export what happened and hand it
to a model, a standup, or an invoice.

## What it does

- **Quick capture** with ⌥Space from anywhere. `⌘⏎` records something you have
  already finished, for the things you do before you think to write them down.
- **Today** shows what you completed and what you added, and exports the day as
  Markdown with your own summary prompt appended.
- **Ticket detection** picks up references like `ABC-123` in a task title and
  groups the exported day by them.
- **Apple Reminders sync** in both directions, so your tasks reach your iPhone
  and iPad through iCloud without this app running a server.
- Reminders with notifications, rename in place, undo, and an archive: clearing
  completed tasks files them away instead of destroying the record.

## Requirements

macOS 26.5 or later, Xcode 26.

## Build and test

```sh
xcodebuild -project NightlyList.xcodeproj -scheme NightlyList -destination 'platform=macOS' build
xcodebuild test -project NightlyList.xcodeproj -scheme NightlyList -destination 'platform=macOS'
```

The app icon is generated rather than drawn by hand:

```sh
swift scripts/makeicon.swift NightlyList/Assets.xcassets/AppIcon.appiconset
```

## Project configuration

There is **no `Info.plist` file**. Xcode generates it from the target's
`INFOPLIST_KEY_*` build settings, so adding one by hand breaks the build. The
keys that matter live in `project.pbxproj`, in both Debug and Release:

| Setting | Why |
|---|---|
| `INFOPLIST_KEY_CFBundleDisplayName` | The name users see. |
| `INFOPLIST_KEY_LSUIElement = YES` | Menu bar agent: no Dock icon, no app menu. |
| `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` | Required by `requestFullAccessToReminders()`. The older `NSRemindersUsageDescription` is not enough — the request fails with *Mach error 4099*. |
| `ENABLE_RESOURCE_ACCESS_CALENDARS = YES` | Generates the `com.apple.security.personal-information.calendars` entitlement. On macOS, Reminders access goes through the calendars entitlement; there is no separate one. |

## Where the data lives

Tasks are a versioned JSON file inside the app's sandbox container, at
`Application Support/NightlyList/tasks.json`. `Diagnostics` in Settings shows the
log next to it, which is the thing to send when a sync goes wrong.
