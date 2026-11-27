# Городские постройки

Город начинает с двора и хозяйства. Улучшение двора увеличивает число участков с 3 до 5 и затем до 6. Одна цепочка построек занимает один участок. На строительство влияют осада, оккупация и городская очередь. Повреждённое здание временно теряет эффекты.

## Общие постройки

| I | II | III | Назначение |
| --- | --- | --- | --- |
| Двор | Двор наместника | Княжеский терем | Доход, порядок, прирост населения и новые участки |
| Хозяйство | Скотный двор | Животноводческая усадьба | Продовольствие, серебро и прирост населения |
| Хозяйство | Рыболовный промысел | Рыбная пристань | Больше еды, торговля рыбой. Доступно у подходящего водоёма |
| Хозяйство или Изба охотника | Изба охотника | Пушной двор | Больше серебра, меньше еды. Доступно в городах с мехами |
| Торг | Торговые ряды | Гостиный двор | Продажа местных товаров, серебро и еда |
| Товарный амбар | Зернохранилище | Запасной двор | Серебро и еда. Для работы нужен действующий торг |
| Кузница | Оружейная мастерская | Оружейный двор | Снаряжение для копейщиков и тяжёлой конницы |
| Казармы | Дружинный стан | Дружинный двор | Опыт при найме, гарнизон и прирост населения |
| Стрельбище | Лучный двор | Лучная школа | Наём лучников и снижение его стоимости |
| Конюшни | Конный двор | Конный завод | Наём конницы и снижение его стоимости |
| Укрепления | Деревянная крепость | Каменный детинец | Больше ополчения. При исправных стенах для взятия города нужна осада |
| Святилище | Капище | Храмовый двор | Порядок и культурная интеграция города |

Для III уровня гражданских зданий, кроме двора, нужно «Пашенное хозяйство», для III уровня большинства военных — «Дружинный строй». Улучшения кузницы требуют «Железное дело».

## Местные промыслы

В каждом поселении доступен один тип промысла, соответствующий ресурсу. Промысел занимает обычный участок и имеет один уровень. Для начала стройки нужны действующие двор II и указанная в таблице постройка. Доход указан за ход до податей.

| Ресурс | Постройка | Где доступна | Требуется | Серебро / ходы | Эффект |
| --- | --- | --- | --- | --- | --- |
| Меха | Меховой склад | Новгород, Ладога, Северный погост | Торг | 110 / 2 | +8 серебра и +5 за уровень действующего торга |
| Соль | Солеварня | Старая Русса | Торг | 130 / 3 | +7 серебра, +12 еды |
| Лес | Лесной двор | Холм, Верхний волок, Березинский погост, Искоростень | Хозяйство | 105 / 2 | +8 серебра, −10% к стоимости строительства и улучшений |
| Мёд и воск | Бортный двор | Полоцк, Любеч, Торопец, Западный погост | Хозяйство | 90 / 2 | +9 серебра, +4 еды, +2 порядка |
| Лён | Льняная мастерская | Витебск, Орша, Псков, Деснинский погост | Хозяйство | 110 / 2 | +15 серебра, +1 порядка |
| Железо | Сыродутный двор | Смоленск | Кузница | 125 / 3 | +9 серебра, −8 серебра к цене найма копейщиков и тяжёлой конницы |
| Керамика | Гончарный двор | Могилёв | Торг | 115 / 2 | +19 серебра |
| Зерно | Гумно | Чернигов, Киев, Переяславль, Посульский погост | Хозяйство | 105 / 2 | +3 серебра, +16 еды |
| Камень | Каменный двор | Изборск | Укрепления | 115 / 2 | +7 серебра, −25% к цене улучшения укреплений с учётом скидки военного города |

## Иллюстрации

Встроенный ImageGen создал пять атласов в стиле «Береста». Ячейки имеют размер 418 × 418. Иллюстрации видны на нижнем пульте, в каталоге, в сведениях о здании и в списке вариантов улучшения. Изба охотника использует одну иллюстрацию на I и II уровнях. Двор IV из старых кампаний показывает иллюстрацию княжеского терема. Местные промыслы на карте используют существующие модели хозяйства, склада и кузницы.

### Запросы ImageGen

Общий текст каждого запроса с приложенным референсом `buildings.png`

```text
Use case: historical-scene. Produce ONE square 3 by 3 texture atlas for the campaign city-building cards of an early medieval Rus historical strategy game. Image 1 is a style reference for ink, matte tempera washes, naturalistic architecture, subtle paper grain, warm pale birch parchment, low saturation earth palette, faded greens and ochre; use its medium and early medieval timber construction vocabulary. Critical production grid: exactly three equally sized rows, exactly three equally sized columns, one independent vignette centered in each mathematically equal square with wide empty parchment gutters. Each vignette fully fits within the central 80% of its own square including ground and props, generous uniform margin all four sides. No graphic divisions, frames, captions, text, symbols, horizon, shared landscape, bleed, or cross-cell interactions. Show full buildings at consistent slightly elevated three-quarter angle, grounded materials, very clear compact distinct silhouettes at 100px. Only sparse paper-fading turf and contextual props. No modern or fantasy architecture. Exact contents in row-major order (top left, top middle, top right, middle left, center, middle right, bottom left, bottom middle, bottom right):
```

К общему тексту добавлялось соответствующее описание ячеек.

#### `civic.webp`

```text
Single modest log elder's hall with carved porch | Governor's residence, taller two-wing log manor with fenced entry | Princely terem, monumental two-storey timber residence with ornate steep gables and raised gallery | Grain smallholding, thatched log hut and wheat patch | Cattle yard, low barn with fenced pen and two cows | Stockbreeding estate, paired big barns around a substantial cattle enclosure | Tiny fishing station, reed hut with drying net and moored dugout at a small isolated patch of water | Fish landing, wide plank jetty lined with drying racks, two boats and smokehouse | Hunter's cabin, tiny woodland log hut with drying hides and plain gear
```

#### `commerce.webp`

```text
Fur yard, broad log storehouse with hide-drying frames and packed pelts | Village market, two red-ochre and cream canvas stalls with baskets and crockery | Trading rows, connected row of three permanent timber booths with open counters | Merchant court, enclosed log trading compound with gallery around central yard | Raised goods barn, open loading door, ramp, sacks and casks | Granary, large tall raised timber building with closed double doors and grain bins | Reserve yard, several substantial raised storehouses clustered around an enclosed yard | Blacksmith's smithy, single lean-to forge with stone chimney, visible hearth and anvil | Armourer's workshop, broad timber workshop with anvil, coal hearth and wall of workpieces
```

#### `military.webp`

```text
Armourer's yard, multiple black-roof log workshops with a sheltered row of three glowing forges | Barracks, long low log quarters with round shields beside entrance | Retinue camp, two long timber dwellings around a compact training yard with standards | Retinue compound, enclosed timber garrison with large hall, long bunkhouse and drills yard | Archery ground, two straw targets and small shelter | Archery yard, longer marked lane with three big straw targets, plank backstop and timber shelter | Archery school, roofed firing line overlooking orderly rows of straw targets with timber store | Stable, low log building with one brown horse in small pen | Horse yard, two stable wings around an ample paddock, two horses
```

#### `defense.webp`

```text
Stud farm, multiple long stables surrounding broad paddock with several small horses | Basic palisade, sharpened logs across earthen bank with simple single timber gateway | Wooden fortress, paired timber defensive towers connected by a high log wall and gate | Stone citadel, squat earthen and fieldstone defensive ring with prominent timber-roofed stone gateway, early medieval | Shrine, single carved wooden idol on stones under birch | Open cult enclosure, circular low timber fence around three wooden idols and firepit | Temple precinct, large rus timber sanctuary, raised porch, wooden idols and votive bowls before building | Fur sorting house, specifically a long low trader’s shed with bundled hare and fox pelts laid out to grade on benches, ropes and bale scales | Saltworks, timber boiling house with several large white brine pans and stout chimney
```

#### `resources.webp`

```text
Timber yard, open-sided saw shed beside stacked long pine logs and squared beams | Apiary, tiny log honey house amid an orderly row of upright hollow-log beehives and pale wax bundles | Linen yard, small timber spinning and weaving shed with pale blue flax and long cream cloth airing on rails | Bloomery, narrow clay shaft furnace in a low lean-to, scattered iron ore and charcoal baskets, dark circular furnace opening | Potter’s yard, clearly visible rounded clay kiln and racks full of terracotta pots | Grain threshing yard, threshing roof, tied standing wheat sheaves and a great straw stack | Stone yard, low cutting shed beside sorted blocks and pale hewn stone slabs | EMPTY plain ivory paper | EMPTY plain ivory paper
```
