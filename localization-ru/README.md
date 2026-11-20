# Русская локализация JetBox iOS — отложена

С 21.11.2026 приложение выходит только на английском (US): решение по релизу
в США (Алексей, #140–#141). Русский не удалён — он лежит здесь и в истории git.

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
