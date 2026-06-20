# Configuración de Firebase para DataStock

## Paso 1: Crear proyecto en Firebase Console

1. Ve a https://console.firebase.google.com
2. Haz clic en "Crear proyecto"
3. Completa los detalles del proyecto
4. Habilita Google Analytics (opcional)

## Paso 2: Agregar aplicaciones

### Para Android:
1. Ve a Configuración del proyecto > Aplicaciones
2. Selecciona Android
3. Registra tu app (paquete: `com.example.datastock_mobile`)
4. Descarga el archivo `google-services.json`
5. Colócalo en: `android/app/google-services.json`

### Para iOS:
1. Ve a Configuración del proyecto > Aplicaciones
2. Selecciona iOS
3. Registra tu app (Bundle ID: `com.example.datastockMobile`)
4. Descarga el archivo `GoogleService-Info.plist`
5. Agrégalo al proyecto Xcode en: `ios/Runner/GoogleService-Info.plist`

## Paso 3: Habilitar servicios

En Firebase Console:
- Ve a "Realtime Database"
- Haz clic en "Crear base de datos"
- Selecciona "Estados Unidos" como ubicación
- Elige "Comenzar en modo de prueba" (para desarrollo)

- Ve a "Authentication"
- Habilita "Email/Contraseña" como método de autenticación

## Paso 4: Actualizar firebase_options.dart

Copia los valores de Firebase Console a `lib/firebase_options.dart`:
- `apiKey`
- `appId`
- `messagingSenderId`
- `projectId`
- `databaseURL`

## Paso 5: Instalar dependencias

```bash
flutter pub get
```

## Paso 6: Ejecutar la app

```bash
flutter run
```

## Estructura de datos en Realtime Database

```
productos/
├── {id1}
│   ├── nombre: "Producto 1"
│   ├── categoria: "Electrónica"
│   ├── cantidad: 50
│   ├── precio: 99.99
│   ├── descripcion: "Descripción..."
│   └── fechaCreacion: "2026-06-06T10:30:00Z"
```

## Seguridad (Reglas de la base de datos)

Para desarrollo (modo prueba):
```json
{
  "rules": {
    ".read": true,
    ".write": true
  }
}
```

Para producción (recomendado):
```json
{
  "rules": {
    "usuarios": {
      "$uid": {
        ".read": "$uid === auth.uid",
        ".write": "$uid === auth.uid"
      }
    },
    "productos": {
      ".read": "auth != null",
      ".write": "auth != null"
    }
  }
}
```
