# EventKit (Reminders) Integration Setup

## Configuración Necesaria

### 1. Agregar el Uso de Recordatorios en Info.plist

> **Ya hecho.** Este proyecto genera el Info.plist desde los ajustes
> `INFOPLIST_KEY_*` del target, y la clave ya esta puesta ahi junto con
> `ENABLE_RESOURCE_ACCESS_CALENDARS = YES`. No hay Info.plist que editar.

Abre tu archivo `Info.plist` y agrega la siguiente clave para solicitar permiso al usuario:

```xml
<key>NSRemindersFullAccessUsageDescription</key>
<string>Sincronizamos tus tareas con la app Recordatorios para que las veas en todos tus dispositivos Apple.</string>
```

O en Xcode:
1. Ve a tu target → Info tab
2. Agrega una nueva fila con el tipo **Privacy - Reminders Full Access Usage Description**
3. Pon el mensaje: "Sincronizamos tus tareas con la app Recordatorios para que las veas en todos tus dispositivos Apple."

### 2. Agregar el Framework EventKit

Asegúrate de que EventKit está enlazado:

1. Selecciona tu proyecto en Xcode
2. Ve a tu target → General → Frameworks, Libraries, and Embedded Content
3. Haz clic en **+**
4. Busca y agrega **EventKit.framework**

## Cómo Funciona

### Sincronización Bidireccional

El sistema sincroniza tareas en ambas direcciones:

- **De tu app → Recordatorios**: Cuando creas, editas o marcas una tarea como hecha
- **De Recordatorios → tu app**: Cuando cambias algo en la app Recordatorios de Apple

### Resolución de Conflictos

Si una tarea se modifica en ambos lados, gana la más reciente según el timestamp `lastModified`.

### Sincronización Automática

- **Al cambiar items localmente**: Se dispara automáticamente
- **Al cambiar en Recordatorios**: El sistema detecta cambios externos vía `NotificationCenter`
- **Manual**: El usuario puede presionar el botón de sincronización

### Indicadores Visuales

- **Icono azul**: Aparece junto a las tareas sincronizadas con Recordatorios
- **Última sync**: Muestra cuándo fue la última sincronización exitosa
- **Errores**: Se muestran en naranja si hay problemas

## Uso

### Activar la Sincronización

1. Abre el popover de la app
2. Marca el checkbox **"Sincronizar con Recordatorios"**
3. Acepta el permiso cuando el sistema lo pida
4. ¡Listo! Tus tareas se sincronizarán automáticamente

### Verificar en Recordatorios

1. Abre la app **Recordatorios** de macOS
2. Busca el calendario "Recordatorios" (o el nombre por defecto de tu sistema)
3. Verás todas tus tareas sincronizadas allí

### Editar desde Recordatorios

Cualquier cambio que hagas en la app Recordatorios se sincronizará automáticamente:
- Cambiar el título
- Marcar como hecha/pendiente
- Cambiar la fecha de vencimiento
- Borrar la tarea

## Arquitectura Técnica

### Archivos Clave

- **`RemindersSync.swift`**: Gestiona toda la lógica de sincronización con EventKit
- **`TodoItem.swift`**: Extendido con `reminderIdentifier` y `lastModified`
- **`TaskStore.swift`**: Integrado con RemindersSync para disparar sincronizaciones
- **`TaskListView.swift`**: UI para activar/desactivar sync y ver estado

### Flujo de Sincronización

```
1. Usuario activa "Sincronizar con Recordatorios"
   ↓
2. Se pide permiso (NSRemindersFullAccessUsageDescription)
   ↓
3. Si se acepta, se ejecuta performFullSync()
   ↓
4. Se obtienen todos los recordatorios de EventKit
   ↓
5. Se comparan con las tareas locales
   ↓
6. Se resuelven conflictos por timestamp
   ↓
7. Se crean/actualizan en ambas direcciones
   ↓
8. Se actualiza lastSyncDate
```

### Estados de Autorización

- **`.notDetermined`**: No se ha pedido permiso aún
- **`.fullAccess`**: Permiso concedido, todo funciona
- **`.denied`**: Usuario rechazó el permiso
- **`.restricted`**: Permisos bloqueados por MDM/políticas

## Preguntas Frecuentes

### ¿Qué pasa si borro una tarea en Recordatorios?

La próxima sincronización la eliminará también de tu app.

### ¿Qué pasa si borro una tarea en tu app?

Se eliminará también de Recordatorios.

### ¿Puedo desactivar la sincronización?

Sí, desmarca el checkbox **"Sincronizar con Recordatorios"**. Las tareas que ya estén sincronizadas permanecerán en Recordatorios hasta que las borres manualmente.

### ¿Se sincronizan las notificaciones?

Sí, si una tarea tiene fecha de vencimiento, se crea una alarma en el recordatorio de EventKit.

### ¿Funciona con iCloud?

Sí, si tienes Recordatorios configurado para sincronizar con iCloud, verás tus tareas en todos tus dispositivos Apple (iPhone, iPad, Mac).

### ¿Qué pasa si hay un conflicto?

El sistema usa el timestamp `lastModified` para determinar qué versión es más reciente y esa gana.

## Troubleshooting

### "Permisos denegados"

1. Ve a **Ajustes del Sistema → Privacidad y Seguridad → Recordatorios**
2. Asegúrate de que tu app está en la lista y marcada
3. Si no aparece, intenta desactivar y reactivar la sincronización

### "Error en sincronización"

- Verifica que tienes acceso a internet (si usas iCloud)
- Comprueba que la app Recordatorios funciona correctamente
- Intenta presionar el botón de sincronización manual
- Reinicia la app

### Las tareas no aparecen en todos los dispositivos

- Verifica que iCloud está activado en **Ajustes del Sistema → Apple ID → iCloud → Recordatorios**
- Espera unos minutos, la sincronización de iCloud puede tardar

## Próximos Pasos

Posibles mejoras:

- [ ] Sincronización selectiva (elegir qué lista de Recordatorios usar)
- [ ] Soporte para listas múltiples/categorías
- [ ] Sincronización de subtareas
- [ ] Sincronización de notas/adjuntos
- [ ] Modo de conflicto manual (dejar que el usuario elija)
