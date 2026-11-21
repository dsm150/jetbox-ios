# Русская локализация JetBox iOS — архив

21.11.2026 (утро) приложение стало только английским (Алексей, #140–#141); вечером того же дня
по слову владельца русский вернули второй локализацией: язык берётся из языка устройства,
английский — язык разработки (запасной). Рабочие каталоги снова содержат ru; эти файлы —
архив русских текстов на момент отключения.

- `JetBox-Localizable.xcstrings` — каталог экранов JetBox (ru + прежний en)
  на коммите `8c7bcee`; рабочий — `NetBird/Source/App/JetBox/Localizable.xcstrings`.
- `Widget-Localizable.xcstrings` — каталог виджета, Пункта управления и
  Команд (исходный язык был ru); рабочий — `NetBirdWidgetExtension/Localizable.xcstrings`.

Папка вне таргетов: в сборку не попадает.

## Как вернуть русский

1. Перенести из этих файлов локализации `"ru"` в рабочие каталоги
   (английские значения в рабочих каталогах новее — их оставить).
2. В `NetBird.xcodeproj/project.pbxproj` вернуть `ru` в `knownRegions`
   (и при желании `developmentRegion = ru`).
3. Фразы Команд в `NetBirdWidgetExtension/Intents/NetBirdShortcuts.swift`
   до `8c7bcee` были русскими — вернуть или перевести через AppShortcuts.xcstrings.
