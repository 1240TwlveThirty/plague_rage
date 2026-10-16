# Ночная задача: полосы, настройки, клавиши, локализация, звук

Отчёт ведётся по ходу работы; если контекст сожмётся — продолжать отсюда.

## Этап 0. Подготовка

- Сделано до начала (по git log и коду): полноэкранного режима, настроек, локализации, переназначения клавиш, звука нет.
  Есть меню паузы по Esc (scripts/esc_menu.gd), окно 1920x1080, stretch canvas_items (aspect не задан).
- Рабочая копия НЕ была чистой: незакоммиченная подгонка слоя замка (scripts/main.gd: F3/F4 в debug-сборке, чтение
  data/layer_tuning.json; копии bench/main_v39_*.gd; bench/view_v47.gd; bench/check_v48.gd; строка v48 в run_all.ps1;
  art/castle_lay_two.png.import mipmaps=true). Решение: это работа, к которой относится п. 5 этапа 1 (layer_tuning.json),
  поэтому она идёт в коммит этапа 1. В коммит этапа 0 — только таймаут run_all.ps1.
- Эталон регрессии: bench/ref/REF.txt = 1c8b0b9 (актуален, симуляция с тех пор не менялась).
- Звуки: папка music_sounds/ в корне проекта, все файлы WAV (PCM 16 бит):

| файл | размер, байт | формат | длительность |
|---|---|---|---|
| battle_theme.wav | 15 235 610 | стерео 48 кГц | 79.3 с |
| battle_theme_2.wav | 39 796 240 | стерео 48 кГц | 207.2 с |
| hub.wav | 36 839 440 | стерео 48 кГц | 191.8 с |
| main_menu.wav | 41 263 120 | стерео 48 кГц | 214.8 с |
| respite.wav | 34 420 240 | стерео 48 кГц | 179.2 с |
| click_exit.wav | 10 628 | моно 44.1 кГц | 0.1 с |
| click_play.wav | 17 684 | моно 44.1 кГц | 0.2 с |
| click_settings.wav | 10 628 | моно 44.1 кГц | 0.1 с |
| clicks_in_hub.wav | 10 628 | моно 44.1 кГц | 0.1 с |
| hover.wav | 8 864 | моно 44.1 кГц | 0.1 с |
| pickupCoin.wav | 19 714 | (не используется) | 0.2 с |

  Итого ≈ 167.6 МБ (> 50 МБ) — по заданию в git не добавляются.
- Коммит этапа 0: a33923b — run_all.ps1: таймаут 300 с на шаг (процесс убивается, шаг FAIL, прогон идёт дальше),
  в конце строка «Зависли: …» или «Зависших шагов нет». Исходный прогон до правок: всё PASS, кроме v48 (см. этап 1).

## Этап 1. Полосы сверху/снизу и подгонка замка — СДЕЛАН

- Камера (scripts/main.gd): отдаления камеры при росте армии в коде не было (камера фиксирована в центре поля).
  Добавлены `camera_min_zoom()` = max(высота экрана / FIELD.y, ширина / FIELD.x) = 1080/1056 ≈ 1.0227 и
  `_camera_clamp()` (центр зажат так, чтобы края вида не выходили за поле). Зум камеры = camera_min_zoom(). Если
  когда-нибудь появится отдаление — зум ограничивать снизу этой же функцией.
- `view_rect()` — видимая часть поля в мире; полосы сигнала всплеска и маркеры разведки у краёв экрана теперь берут
  край вида из неё (раньше — константы VIEW_HALF_W/H для зума 1; они остались только для бенчей без дерева).
- Экран → мир: выбор ЛКМ (клик, рамка), приказы ПКМ (клик, протяжка), предпросмотр строя уже шли через
  make_input_local (холст + камера); подписи над отрядами, полоса HP ворот, рамка рисуются в мире — правок не нужно.
  Жёсткие числа нашлись только в тестах: bench/view_v47.gd (кадрирование скриншотов: теперь через canvas transform),
  bench/check_v40.gd (г) (точное сравнение float после пути мир→экран→мир — сравнивает с точкой, прошедшей тот же путь),
  bench/smoke_v40.gd (л) (точка протяжки x=450 при новом зуме попадала на экране под левую панель отрядов — протяжка
  сдвинута на 550→850, ожидание 700).
- Цвет очистки чёрный (project.godot rendering/environment/defaults/default_clear_color).
- Подгонка замка: в коммит вошла незакоммиченная работа (F3/F4 в debug-сборке, чтение data/layer_tuning.json,
  bench/check_v48.gd, art/castle_lay_two.png.import mipmaps=true) и data/layer_tuning.json (438/507, 0.4586/0.4921).
  check_v48: первая проверка требовала «файл = значения по умолчанию» и падала с новыми значениями; заменена на
  «файл загружается при старте» + проверки камеры (зум, вид внутри поля, экран→мир).
- Фильтры nearest и шейдеры не менялись. Скриншот волны 10 (fx): C:\Users\danil\AppData\Local\Temp\claude\C--Projects-plague-rage\aeb230fc-738f-43f6-8119-7a258801738c\scratchpad\s1\view_fx_full.png
  (и _castle, _gate, _left, _right рядом) — верхние и нижние 12 строк без серого, деревья, вода, факелы на месте.
- Проверки: регрессия против 1c8b0b9 — провалов 0; FPS на волне 10 (view_v47, окно, fx): 979 FPS, медиана кадра
  0.83 мс, 95-й перцентиль 1.21 мс; run_all полный — ИТОГ PASS, провалов 0, 352 с, зависших нет.
- Коммит этапа 1: a7d8b10.

## Этап 2. Настройки и режим окна — СДЕЛАН

- Автозагрузка Settings (scripts/settings.gd, в project.godot перед Game): единственное хранилище настроек,
  user://settings.cfg (ConfigFile), загрузка и применение при старте, сохранение при каждом изменении, сигнал changed.
  Под тестовым SceneTree (`-s bench/...`) файл игрока не читается и не пишется (persist = false), окно не трогается:
  тесты идут на значениях по умолчанию.
- Экран «Настройки» (scripts/settings_menu.gd, CanvasLayer 110 поверх вызвавшего): открывается из главного меню
  (новая кнопка между «Играть» и «Выход») и из меню паузы (кнопка между «Продолжить» и «Выйти в меню»);
  «Назад» и Esc закрывают только его, фокус возвращается на «Настройки». Пока закрыт, его элементы фокус не берут
  (иначе smoke_v39 «у всех Control focus_mode = NONE» падал). Видна только вкладка «Видео».
- «Видео»: переключатель «Полный экран (F11)» — DisplayServer.WINDOW_MODE_FULLSCREEN (безрамочный), display/fullscreen.
  F11 переключает в любой момент (Settings._input, работает и на паузе). Окно по умолчанию 1920x1080, если экран меньше
  — 1280x720, по центру. project.godot: stretch mode canvas_items уже стоял, добавлен aspect = keep (чёрные поля по бокам).
  Отдельных кнопок режима окна в меню паузы не было — просто добавлена кнопка «Настройки».
- Тесты: bench/check_v49.gd (headless: сохранение/загрузка/битый файл, F11, экран из меню и паузы, Esc закрывает только
  настройки), bench/smoke_v49.gd (с окном: F11 реально включает FULLSCREEN и обратно, значение сохранено, скриншоты).
- Скриншоты: C:\Users\danil\AppData\Local\Temp\claude\C--Projects-plague-rage\aeb230fc-738f-43f6-8119-7a258801738c\scratchpad\s2\v49_menu.png,
  v49_settings_fullscreen.png, v49_settings_window.png (там же).
- Проверки: регрессия — провалов 0; FPS волна 10: 993 (медиана 0.82 мс, p95 1.21 мс); run_all полный — ИТОГ PASS,
  провалов 0, 341 с (первый прогон: smoke_v39 упал на focus_mode экрана настроек — исправлено, см. выше).
- Коммит этапа 2: 3646dbd.

## Этап 3. Переназначение клавиш — СДЕЛАН

- Клавиатура обрабатывалась в main.gd (_unhandled_input: match по keycode), hub.gd и esc_menu.gd (Esc), settings.gd (F11),
  settings_menu.gd (Esc), main.gd _tune_key (подгонка замка, только debug-сборка).
- Действия InputMap (секция [input] в project.godot, события по keycode, клавиши прежние — для игрока ничего не поменялось):
  - переназначаемые (вкладка «Управление»): squad_select_1..8 (1–8; Shift — добавить), squad_new (N), squad_split (G),
    squad_merge (M), split_side (K), wave_start (Space; в бою — пауза, как раньше), buy_1..buy_4 (Z, X, C, V);
  - фиксированные (тоже действия, но в списке их нет и занять их клавиши нельзя): order_attack (Q), order_hold (W),
    order_retreat (E), about_face (F), banner_toggle (H), auto_width (T), pause (P), post_left/top/right/back (стрелки),
    select_all (Ctrl+A), to_hub (Enter, Num Enter, R; на экране итога ещё и клавиша wave_start), debug_restart (Ctrl+R).
  - Остались по keycode (не переназначаются по заданию): Esc, F1–F5, F11, мышь; клавиши подгонки замка (F3-режим
    debug-сборки) — отладочные, тоже по keycode.
- Settings: REBINDABLE / FIXED_ACTIONS / RESERVED_KEYS; rebind(action, key): занята другим переназначаемым — обмен и
  сообщение; занята фиксированным, Esc, F1–F12 или модификатор — отказ с сообщением. reset_keys() —
  InputMap.load_from_project_settings(). Хранение: секция [input] в settings.cfg (имя клавиши, например squad_new="J"),
  применение при старте; неподходящие значения из файла игнорируются с предупреждением.
- Одна функция Settings.key_label(action) (static, работает и в бенчах без автозагрузки) — во всех подсказках: «+ Отряд (N)»,
  «Разделить (G)», «Слить (M)», «Уходят: … (K)», «Поставь паузу (Space)», «Space — волна N», «Space — начать волну 1»,
  «Enter — в хаб», клавиши в строках магазина и строк отрядов. После переназначения подписи боя обновляются сразу
  (сигнал Settings.changed).
- Вкладка «Управление»: список «действие — клавиша», клик по клавише → «Нажмите клавишу… (Esc — отмена)», сообщение об
  обмене/отказе, «Сбросить по умолчанию».
- Тест bench/check_v50.gd: клавиши по умолчанию, N/1/Shift+2/Ctrl+A работают через InputMap, N→J (N больше не создаёт,
  J создаёт, подпись «+ Отряд (J)»), обмен, отказы (Q, Esc, F5, Enter), подписи магазина и «Поставь паузу (L)», файл,
  «перезапуск», сброс, вкладка: ожидание, Esc-отмена, обмен через push_input, кнопка сброса. Смоуки v39–v42, которые шлют
  нажатия через окно (push_input), проходят на InputMap.
- Проверки: регрессия — провалов 0; FPS волна 10: 1059 (медиана 0.80 мс, p95 1.17 мс); run_all полный — ИТОГ PASS,
  провалов 0, 344 с.
- Коммит этапа 3: c2f0441.

## Этап 4. Локализация ru/en — СДЕЛАН

- Встроенная система Godot: data/translations.csv (keys, ru, en; 160 ключей) импортируется в
  data/translations.ru.translation и data/translations.en.translation (импорт: `godot --headless --path . --import`;
  .csv.import и оба .translation в git), project.godot [internationalization] locale/translations. Язык —
  TranslationServer.set_locale. При правке CSV нужен переимпорт (открыть редактор или `--import`), иначе
  check_translations скажет «переимпортируй».
- Ключи ГРУППА_ПОДГРУППА_ИМЯ: UI_* (меню, пауза, настройки), HUD_* (бой), MSG_* (сообщения), HUB_*, GIFT_*, SHOP_*,
  UNIT_*, ORDER_*, SIDE_*, SPLIT_MODE_*, END_*, STORY_*, SIEGE_NAME, ACTION_* (названия действий), DEBUG_FPS_*.
  Числа и клавиши — подстановкой (`tr("HUD_STATUS") % [...]`), куски не склеиваются (кроме перечислений через запятую:
  «Всплеск: сверху, слева», «убито: крестьяне 90, бегуны 20» — элементы списка отдельными ключами).
- Постоянные Label/Button получают ключ в text и переводятся сами (автоперевод по умолчанию включён: auto_translate_mode
  INHERIT от корня ALWAYS). Собранные в коде строки — через tr() и пересобираются по NOTIFICATION_TRANSLATION_CHANGED:
  хаб (осада, итог, рекорды, магазин, открытый дневник), экран настроек, бой (HUD, панели отрядов и деления, магазин и
  баннер — баннер хранит функцию-сборщик _set_banner, при смене языка вызывает её снова; скрытый по H остаётся скрытым).
- Данные: gifts.json — name/desc заменены на name_key/desc_key (desc — формат эффекта с %s, effect_text подставляет
  число; таблицы STAT_TEXT/TARGET_TEXT в hub.gd удалены); story.json — intro_key/text_key (тексты дневника в таблице,
  {wave} в концовках подставляется как раньше). unit_types.json и shop.json: РЕШЕНИЕ — поле осталось называться label,
  но в нём теперь ключ (UNIT_INFANTRY, SHOP_INF_PACK). Причина: старые копии main в bench (эталон регрессии
  bench/ref/main_ref.gd, main_v39_before*, main_v40_before) читают эти же файлы и требуют строковое поле label;
  переименование сломало бы регрессию. Числа в названиях товаров подставляются из параметров (amount, dmg_mult,
  gate_max_gain), а не зашиты в текст.
- Game: WARN_*/BLOCK_* — ключи; buy_block отдаёт ключ (для «Откроется после осады %s» — уже переведённую строку с номером);
  siege_name через tr. Логи (push_error/push_warning) остались на русском — это не текст игрока.
- Не переводятся (помечены `# tr-skip` или это логи): подсказка режима подгонки замка (F3, только debug-сборка),
  названия фаз профиля (PROFILE), контекст сообщений об ошибках данных.
- Язык: вкладка «Язык» (Русский / English), переключение сразу, general/language в settings.cfg; по умолчанию ru, если
  язык системы русский, иначе en. Под тестовым SceneTree язык всегда ru (тесты сверяют русские строки).
- Шрифт по умолчанию (встроенный) показывает кириллицу и латиницу; на английском тексты помещаются (smoke_v51 проверяет,
  что все видимые Label/Button меню, хаба, паузы, настроек и боя целиком на экране и текст кнопок не шире кнопки).
- Тесты: bench/check_translations.gd (оба языка заполнены, нет повторов, вид ключей, импорт совпадает с таблицей, все
  ключи из scripts/*.gd и data/*.json есть в таблице, в коде нет русских строк мимо tr, в сценах нет русских текстов);
  bench/smoke_v51.gd (скриншоты и смена языка, в том числе прямо в бою, сохранение языка). В старых тестах сравнения
  `.text == "…"` обёрнуты в tr() (метки теперь хранят ключ), фикстуры даров и дневника переведены на *_key,
  bench/ref/story_ref.json — поля переименованы (make_ref.py делает это сам).
- Скриншоты (C:\Users\danil\AppData\Local\Temp\claude\C--Projects-plague-rage\aeb230fc-738f-43f6-8119-7a258801738c\scratchpad\s4\):
  v51_menu_ru.png, v51_menu_en.png, v51_hub_ru.png, v51_hub_en.png, v51_hub_gifts_ru.png, v51_hub_gifts_en.png,
  v51_pause_ru.png, v51_pause_en.png, v51_battle_ru.png, v51_battle_en.png, v51_settings_0_ru.png … v51_settings_2_en.png
  (0 — Видео, 1 — Управление, 2 — Язык).

### 20 строк перевода на проверку

| ключ | ru | en |
|---|---|---|
| STORY_INTRO | Король говорил со мной сегодня… Он верит, что снизу идёт тот, кто всё закончит… | The King spoke to me today… He believes someone is coming from below who will put an end to all of this… («снизу» понял буквально — проверь смысл) |
| STORY_S1W5 | …в глубине убили одного из шестерых, тех, что стояли рядом с королём… | …deep in the land, one of the Six who stood beside the King has been killed… |
| STORY_S1W6 | Чума стала злее. Совпадение. | The plague has grown fiercer. A coincidence. |
| STORY_S3W6 | Она не злая. Это самое страшное… | She isn't cruel. That is the most frightening part… |
| STORY_END_0 | День {wave}. Ворота пали раньше, чем я дописал вчерашнее. Мира, если ты это чита... | Day {wave}. The gate fell before I finished yesterday's entry. Mira, if you're reading th... |
| STORY_VICTORY_1 | …Это не конец: Благодать умеет возвращаться. | …This isn't the end: Grace knows how to return. («Благодать» → Grace) |
| STORY_VICTORY_3 | Ворота стоят, но я больше не держу их. Благодать вошла не как захватчик… | The gate still stands, but I no longer hold it. Grace came in not as a conqueror… |
| GIFT_MINE_DESC | +%s% от дохода прошлой волны в начале каждой волны | Each wave starts with +%s% of the last wave's income |
| GIFT_SPOILS_NAME / GIFT_RESERVE_NAME | Трофеи / Резерв | Spoils of War / Reserves |
| MSG_WAVE_CLEARED | Волна %d пройдена: убито %d, +%d золота. %s — волна %d | Wave %d cleared: %d killed, +%d gold. %s: wave %d |
| END_DEFEAT_HINT | Лучшая волна осады %s: %d. %s — в хаб | Best wave in Siege %s: %d. %s: back to hub |
| HUD_SPLIT_SIDE + SPLIT_MODE_* | Уходят: правые / левые / задние / передние (K) | Leaving: right flank / left flank / rear ranks / front ranks (K) |
| SIDE_TOP/LEFT/RIGHT (в «Всплеск: %s») | сверху / слева / справа | north / west / east («Surge: west, north») |
| HUD_MOUSE_HINT | ЛКМ выбор · ПКМ приказ · Shift добавить | LMB select · RMB order · Shift add |
| ORDER_* | атака / держать / отход | attack / hold / fall back |
| UNIT_PEASANT vs MSG_KILLS_PEASANTS | Зомби / крестьяне %d | Zombies / peasants %d |
| MSG_SQUAD_TOO_SMALL | В отряде меньше 2 юнитов: делить нечего | Fewer than 2 units: nothing to split |
| MSG_KEY_SWAPPED | %s была у «%s»: клавиши поменялись местами | %s was bound to "%s": keys swapped |
| MSG_SAVE_CORRUPT | Сохранение повреждено, начато заново | Your save was damaged, so a new one was started |
| HUB_LAST_WIN | Последний забег: победа на %d-й волне | Last run: victory on wave %d |

- Проверки: регрессия — провалов 0; FPS волна 10: 1128 (медиана 0.75 мс, p95 1.10 мс); run_all полный — ИТОГ PASS,
  провалов 0, 337 с (26 шагов, добавлены check_translations и smoke_v51).
- Найдено и исправлено по ходу: баннер боя после первой смены языка терял свой сборщик и на второй смене не
  обновлялся (smoke_v51 поймал).
