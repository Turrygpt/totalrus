# Ассеты карты

Сборка использует локальные модели и процедурные постройки. Кандидаты на импорт со Sketchfab указаны для следующего арт-прохода.

| Кандидат | Автор | Лицензия на карточке |
| --- | --- | --- |
| [Lowpoly Medieval Wooden Cart](https://sketchfab.com/3d-models/lowpoly-medieval-wooden-cart-a371f8525f6049eebaab59f227a4d5a9) | AspectStudios | CC BY |
| [Bridge_wooden](https://sketchfab.com/3d-models/bridge-woodenlow-poly-d9bfef8e297146f5a428a45fb246077a) | Arigura | CC BY |
| [Farm & Village Wood Asset Pack](https://sketchfab.com/3d-models/low-poly-farm-villagemedieval-wood-asset-pack-e440b93204c24a8481fb23265673afe7) | Ksatta | CC BY |
| [Low Poly Medieval Well](https://sketchfab.com/3d-models/low-poly-medieval-well-6e61a97c24cf4271a6550cf46bc90648) | Sravan Kumar | CC BY |

Перед использованием подтвердить лицензию загрузки, нормализовать масштаб и записать фактически импортированные файлы и авторов в титры игры.

Листы трёх видов лежат в `art/campaign_concepts`. Проверены шесть команд Tripo 0.7.2 в режиме `--dry-run`. Каждая вызывает `multiview-to-model` на P1 / `P1-20260311` с входами `*_front.png` и `*_left.png`, текстурами и PBR. GLB выводится без платного конвертирования. Ориентир 50 кредитов на модель, 300 на пакет.

| Имя GLB | Предел полигонов |
| --- | ---: |
| princely_hall | 4500 |
| granary | 2500 |
| gate_tower | 4200 |
| corner_tower | 3500 |
| smithy | 3200 |
| covered_market | 3200 |

Подготовленные модели помещаются в этот каталог под указанными именами, в метрах, с основанием в начале координат. Для отсутствующих моделей используются процедурные постройки.

`smithy.glb` (2 938 треугольников) и `fishery.glb` (3 167 треугольников) подготовлены из моделей Tripo, предоставленных пользователем. Масштаб задаётся при размещении на карте. Тактическая версия кузницы находится в `assets/blacksmith_forge_lod1.glb` (6 413 треугольников).


## Растительность карты — 17 ноября 2026

`foliage/branches.png` — оригинальный RGBA-атлас ветвей дуба, берёзы, ели и сосны, созданный встроенным imagegen для этого проекта. Геометрия деревьев, распределение леса, изгороди и поля создаются кодом `campaign_map/woodland.gd` и `campaign_map/countryside.gd`. Скриншоты Rome II используются как визуальный ориентир; игровые ассеты из них не извлекаются.
