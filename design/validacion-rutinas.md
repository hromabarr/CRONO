# Rutinas y registros diarios

## Cambios

- Cada hábito tiene un momento: Mañana, Durante el día o Noche.
- Hoy agrupa los hábitos programados. Las rutinas de mañana y noche muestran
  el próximo paso y se retoman a partir de las marcas guardadas.
- El botón + de Hoy crea un hábito. El menú del calendario ofrece Corregir ayer
  y Ver historial. Tocar un día pasado o el actual abre sus registros.
- Los hábitos archivados aparecen en el historial hasta el día de archivo,
  incluido. Los registros existentes siguen visibles aunque cambien los días
  de programación. No se reconstruyen cambios antiguos de programación ni
  períodos de archivo/reactivación: esos datos no existían en V1.
- Un día sin hábitos ni tareas sigue mostrando la próxima alarma.

## Persistencia

V1 está congelada en CronoSchemaV1.swift. V2 añade únicamente `routineRaw`
opcional a Habit. Los registros anteriores se interpretan como Durante el día.
El plan declara una migración ligera de V1 a V2.

`SchemaVersionTests.migrationPreservesExistingData` crea una base V1 en disco,
la abre con V2 y verifica identidades, registros, relaciones, tareas y alarmas.
Después guarda una rutina y vuelve a abrir la base.

## Validación realizada en Windows

- Análisis sintáctico con Tree-sitter de todos los archivos Swift, normalizando
  saltos de línea y excluyendo la macro #Index, que esa gramática no soporta.
- Comparación de las cinco definiciones congeladas con los modelos originales.
- Revisión de diferencias y comprobación de espacios con `git diff --check`.

No se han compilado los modelos SwiftData ni las vistas SwiftUI. No se han
ejecutado los tests de iOS ni generado capturas nuevas: se necesita macOS/Xcode.
Las capturas existentes en design son anteriores a estos cambios.

## Comprobación pendiente en Xcode

1. Ejecutar `xcodegen generate` y el esquema de tests Crono en un simulador iOS 26.
   El workflow Compilar también ejecuta los tests antes de producir artefactos.
2. Instalar esta versión sobre una instalación V1 con datos, sin desinstalar.
   Comprobar que no aparece el aviso de almacenamiento y que se conserva todo.
3. Crear dos hábitos de mañana, uno de noche y uno durante el día. Reordenarlos
   desde Hábitos → Editar; confirmar ese orden en las rutinas.
4. Empezar una rutina, marcar un paso, cerrar la hoja y la app, y volver a abrir.
   Continuar debe mostrar el siguiente pendiente. Completar y deshacer una marca.
5. Abrir Corregir ayer y un día anterior desde Historial. Cambiar una marca y
   comprobar anillo y racha. No permitir marcar fechas futuras o anteriores al alta.
6. Archivar un hábito con registros: comprobar los registros anteriores y que
   no se exija después de su fecha de archivo. Probar también con todos archivados.
7. Probar Hoy sin hábitos ni tareas, con una alarma activa, y también vacío.
8. Revisar las hojas nuevas en claro, oscuro, texto grande y VoiceOver, con
   títulos largos y listas vacías. Usar las previsualizaciones añadidas.
