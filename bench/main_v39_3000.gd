extends Node2D

const INFANTRY_COUNT := 300   # отряд 0: пехота игрока
const ARCHER_COUNT := 100     # отряд 1: лучники игрока
const UNIT_COUNT := 3000       # стартовый состав без волн: остальные (UNIT_COUNT - INFANTRY_COUNT - ARCHER_COUNT) — зомби
const MAX_UNITS := 4000       # ёмкость всех массивов юнитов (выделяются один раз)
const WAVES_ENABLED := true   # false: как bak21 (300 зомби на старте, без волн) — для старых бенчей
const WAVES_PATH := "res://data/waves.json"
const SHOP_PATH := "res://data/shop.json"
const SHOP_ITEMS := ["inf_pack", "archer_pack", "weapons", "gate", "spear_pack"]   # товары магазина передышки
const SHOP_LINE_TITLE_COST := "%s — %s"   # товар — цена (первая строка кнопки набора)   # tr-skip: разделитель
const SHOP_LINE_COST_DELTA := "%s · %s"   # цена · до → после (вторая строка кнопки улучшения, задача 26)   # tr-skip: разделитель
const SHOP_LINE_COST_TARGET := "%s  %s"   # цена и отряд во второй строке, если первая не помещается   # tr-skip: разделитель
const SHOP_ACTIONS := ["buy_1", "buy_2", "buy_3", "buy_4", "buy_spear"]   # действие покупки товара k (по умолчанию Z X C V B)
const SHOP_COST_STATS := ["unit_cost", "unit_cost", "weapon_cost", "repair_cost", "unit_cost"]   # стат цены товара для Mods.value, порядок SHOP_ITEMS
const SHOP_COST_TARGET := ["", "archer", "", "", "spearman"]   # дополнительная цель стата цены (unit_cost / archer, unit_cost / spearman)
const WAR_CRY_GLOW := Color(1.0, 0.82, 0.3, 0.3)   # подсветка краёв экрана, пока действует Клич Благодати
const WAR_CRY_GLOW_PX := 10.0
const SPLIT_NAMES := {"infantry": "UI_SPLIT_INFANTRY", "archer": "UI_SPLIT_ARCHER"}   # «Жертва ради победы»: кому выпало
const COND_KEYS := {"hold": "COND_HOLD", "retreat": "COND_RETREAT", "gate_low": "COND_GATE_LOW", "squad_low": "COND_SQUAD_LOW",
	"wave_time": "COND_WAVE_TIME", "gold_high": "COND_GOLD_HIGH", "lost_steps": "COND_LOST_STEPS", "hero_low": "COND_HERO_LOW", "hero_near": "COND_HERO_NEAR"}
const SHOP_EDGE := 16.0      # отступ магазина и его кнопки от правого края экрана
const SHOP_TAB_GAP := 8.0    # зазор между магазином и кнопкой сворачивания
const SHOP_HEAD_COLOR := Color("#181425")   # заголовки блоков магазина на светлой панели (Endesga 32, контраст — check_v74_ui)
const CARD_ON := Color(1.0, 0.82, 0.3)          # строка карточки: условие выполнено
const CARD_IDLE := Color(1.0, 1.0, 1.0, 0.55)   # условная карточка, условие не выполнено
const BLOCK_CAP := 0.95   # общий шанс блока не выше
const COND_EVERY := 15   # условия карточек пересчитываются раз в столько тиков симуляции
const CD_CARRY := 2.0 / 30.0   # перенос остатка перезарядки: не больше одного шага решения юнита (2 тика при 30 Гц)
const FONTS := preload("res://scripts/fonts.gd")   # кегли и контуры текста под вариант шрифта (задача 20)
const SETTINGS := preload("res://scripts/settings.gd")   # key_label(действие): клавиша для подсказок
# Действия клавиатуры в порядке проверки (_key_action): с модификаторами раньше, чтобы Ctrl+A не ушло в действие на A
const ACTION_TEXTS := ["HUD_SQUAD_NEW", "HUD_SQUAD_SPLIT", "HUD_SQUAD_MERGE"]   # кнопки под панелью отрядов (ключи, %s — клавиша)
const ACTION_KEYS := ["squad_new", "squad_split", "squad_merge"]
const KEY_ACTIONS := ["select_all", "debug_restart", "squad_select_1", "squad_select_2", "squad_select_3", "squad_select_4",
	"squad_select_5", "squad_select_6", "squad_select_7", "squad_select_8", "squad_new", "squad_split", "squad_merge", "split_side",
	"wave_start", "buy_1", "buy_2", "buy_3", "buy_4", "order_attack", "order_hold", "order_retreat", "about_face", "banner_toggle",
	"auto_width", "pause", "post_left", "post_top", "post_right", "post_back", "war_cry", "buy_spear", "hero_attack", "shop_toggle",
	"squad_panel_toggle", "camera_zoom_reset"]
const ROWS_MAX := 20       # строй не глубже: при большом отряде растёт ширина
const WIDTH_MAX := 100     # и не шире
const WAVE_DMG_TO_UNITS := true   # урон зомби по юнитам растёт с волной (team_dmg_mult[1])
const PROFILE := false     # true: время фаз тика (среднее за 60 тиков) в отладочной строке
const TEMP_SLOT_BASE := 1 << 24   # временные slot_idx новых юнитов (уникальные, больше любых настоящих)
# Залп: true — стреляет только лучник, чья точка падения не дальше range_far от него самого;
# false — стреляют все лучники отряда, дальность считается от центра отряда.
const ARCHER_OWN_RANGE := false
const SCOUT_SHOWN := false        # true: в передышке видны маркеры разведки и строка HUD «Дальше: ...»
const BURSTS_ENABLED := true      # false: прежние подволны (subwave_*) со всех сторон сразу
const BURSTS_LAYERED := true      # всплески по слою: стороны по весам, группы, темп и сигнал из waves.json layers; false — как раньше
const DEBUG_LAYER := 1            # номер слоя 1-3, когда синглтона Game нет (бенчи); в игре слой = Game.siege
const RUN_LIMIT_ENABLED := true   # забег из waves_per_run волн с победой (нужен синглтон Game); false — бесконечные волны
const SIGNAL_TEXT_SHOWN := false  # надпись «Всплеск: ...» при сигнале (при BURSTS_LAYERED)
const SIGNAL_ICONS_SHOWN := false # треугольники у стороны при сигнале (при BURSTS_LAYERED)
const SIGNAL_SOUND_PATH := "res://audio/horn.ogg"   # звук сигнала всплеска; файла нет — без звука
const ARCHERS_FOLLOW := false     # true: лучники идут за пехотой (как раньше) — для бенчей и регрессии
# Приказы отряда
const ORDER_ATTACK := 0   # как раньше: юниты идут на врага в VIEW_RANGE
const ORDER_HOLD := 1     # держать: к врагу не идут, бьют только в дальности атаки
const ORDER_RETREAT := 2  # отход: врага не ищут, не бьют, лучники не стреляют; скорость x1.5 до прихода
const RETREAT_SPEED_MULT := 1.5
const GATE_SPOTS := [0, -1, 1, -2, 2, -3, 3, 0]   # точка у ворот по номеру отряда, в шагах GATE_SPOT_DX от центра ворот
const GATE_SPOT_DX := 110.0
const ORDER_NAMES := ["ORDER_ATTACK", "ORDER_HOLD", "ORDER_RETREAT"]   # ключи перевода
const UNIT_TYPES_PATH := "res://data/unit_types.json"
const HERO_PATH := "res://data/hero.json"   # герой (задача 10, эксперимент): параметры и enabled
const HIT_FX_PATH := "res://data/fx.json"   # эффекты попаданий героя (задача 12): кровь, искры, пятна, тряска экрана
const CASTLE_PATH := "res://data/castle.json"
const RECORD_PATH := "user://record.json"   # прежний рекорд best_wave: в игре не читается и не пишется (рекорды в Game)
const RUN_PATH := "res://data/run.json"     # забег: waves_per_run, siege_count
const GAME_SCRIPT := preload("res://scripts/game.gd")   # общий загрузчик run.json
const STORY_PATH := "res://data/story.json"   # дневник: тексты баннеров (на механику не влияет)
const GIFTS_PATH := "res://data/gifts.json"   # дары: модификаторы забега
const MODS := preload("res://scripts/mods.gd")
const CARDS := preload("res://scripts/cards.gd")
const UNITS := preload("res://scripts/units.gd")   # расстояния для игрока в шагах (задача 26)
const HINTS := preload("res://scripts/hints.gd")   # подсказки первой минуты (задача 26, data/hints.json)
const CARD_PICK := preload("res://scripts/card_pick.gd")
const ICONS := preload("res://scripts/icons.gd")   # иконки карточек (список в HUD)   # экран выбора карточки
const CARD_RULES_PATH := "res://data/cards_rules.json"
const PORTRAITS := preload("res://scripts/portraits.gd")   # иллюстрации отрядов в кнопках магазина и панели отрядов (data/unit_portraits.json)
const UI_LAYOUT_PATH := "res://data/ui_layout.json"   # размеры кнопок магазина, отрядов, действий и Клича (задача 16)
const FIT_MIN_FONT := 11   # текст кнопки фиксированного размера ужимается до этого кегля (дальше — перенос по словам)
const SHOP_PORTRAIT := {"inf_pack": "infantry", "archer_pack": "archer", "spear_pack": "spearman"}   # товар -> тип юнита для иллюстрации
const UI := preload("res://scripts/ui.gd")   # универсальные рамки кнопки и панели (тема проекта, задача 18)
const TOP_HUD := preload("res://scripts/top_hud.gd")   # верхняя панель боя из окошек и окошко Сияния (задача 19, data/ui_layout.json)
const HUD_SLOT := preload("res://scripts/hud_slot.gd")
const ESC_MENU := preload("res://scripts/esc_menu.gd")   # меню паузы по Esc: «Продолжить», «Выйти в меню», «Выход из игры»
const ESC_NOTE := "UI_PAUSE_NOTE_LOSS"   # ключ перевода
const BANNER_WIDTH := 700.0                   # ширина баннера, px: длинный текст переносится по словам
const STORY_COLOR := Color(1.0, 0.88, 0.6)    # цвет текста дневника в баннере
const RADIANCE_COLOR := Color(0.6, 0.9, 1.0)  # цвет строки «+N Сияния» на экране итога
const SQUAD_MAX := 8                          # ёмкость всех массивов отрядов (выделяются один раз)
const START_SQUADS := 2                       # отряды 0 (пехота) и 1 (лучники) есть всегда и не освобождаются
const ROTATE_STEP := PI / 12.0                # Shift + колесо: поворот отряда на месте, 15°
const BANNER_BG_ALPHA := 0.55                 # непрозрачность панели баннера и «Командир пал»: строй под ними виден (текст непрозрачный)
const INFO_WIDTH := 560.0                     # ширина строки разведки и сообщений слева сверху (перенос по словам; баннер не задевает)
const BANNER_TOP := 120.0                     # верхняя граница баннера, px от верха экрана
const OVERLAP_MAX := 0.25                     # расстановка: доля площади меньшего блока, с которой пересечение со своим отрядом запрещено
const DRAG_MIN := 24.0                       # px мира: короче — обычный клик, длиннее — строй по линии; data/ui_layout.json drag_min
const FORM_MARGIN := 12.0                     # строй при расстановке не ниже WALL_Y - FORM_MARGIN
const PAUSE_ENABLED := true                   # активная пауза в бою (Space, P); false — паузы нет, как раньше
const SIDE_POST_T := 0.45                     # стрелки: пост на отрезке ворота -> точка появления стороны, доля пути
const GATE_POST_BACK := 90.0                  # стрелка вниз: пост у ворот, на столько выше стены
const SPLIT_MODE_NAMES := ["SPLIT_MODE_RIGHT", "SPLIT_MODE_LEFT", "SPLIT_MODE_BACK", "SPLIT_MODE_FRONT"]   # ключи перевода
const PICK_RADIUS := 1.5 * SLOT_SPACING       # ЛКМ мимо блоков: выбирается отряд ближайшего юнита игрока не дальше этого
const BOX_SELECT_FRAC := 0.25                 # рамка выбирает отряд, если в ней его центр или не меньше этой доли живых
const SORT_OFFSET := 1 << 20                  # сдвиг ключа сортировки _place_formation: координата * 16 всегда > 0
# Состояние боя
const WS_BATTLE := 0    # идёт бой
const WS_DEFEAT := 1    # ворота пали
const WS_RESPITE := 2   # передышка между волнами
const WS_WIN := 3       # забег пройден: все волны осады пережиты
# --- Масштаб мира: множители к базовым значениям геометрии и скоростей (и к range, range_far, speed из JSON,
# spawn_spacing из waves.json — при загрузке). Результат округляется до 0.01. 1.0 — база (шаг строя 8); сейчас шаг 12.
const SCALE_REL := 1.5           # геометрия: шаг строя, дистанции, клетка сетки, дальности, квадрат юнита
const SPEED_REL := 1.5           # скорости юнитов и стрел
const RENDER_JITTER := 1.0       # px: статичный сдвиг отрисовки юнита (по unit_rand), только на экране
const FLOATS_PER_UNIT := 16   # 8 (трансформ 2D) + 4 (цвет) + 4 (custom: x = ячейка атласа)
# --- Спрайты ---
# Листы задаются в unit_types.json (поле sprite): лицом вправо, кадры 16x16 в ряд по состояниям (стоит, замах, атака);
# кадров может быть меньше — состояние зажимается до последнего кадра.
const SPRITE_PX := 16            # сторона кадра и размер спрайта в мире, px
const SPRITE_FRAMES_MAX := 3     # состояний анимации: 0 стоит, 1 замах, 2 атака
# Зомби (юниты без отряда) рисуются теми же листами и тем же способом. В бою кадры по состоянию, как у пехоты (замах, атака);
# на ходу — шаг по времени отрисовки: кадры ZOMBIE_WALK_SEQ, смена кадра раз в ZOMBIE_WALK_FRAME_T. На бой не влияет.
const ZOMBIE_WALK_FRAME_T := 0.15   # секунд на кадр шага: как кадры «замах» и «атака» пехоты; 0 — на ходу стоит кадр 0
const ZOMBIE_WALK_SEQ: Array[int] = [0, 1, 0, 2]
const RUNNER_ANIM_SPEED := 1.6      # во сколько раз быстрее шаг бегуна
const KNIGHT_SPRITE_SCALE := 1.5    # павший рыцарь на экране крупнее остальных (только спрайт: размеры в бою те же)
const ZOMBIE_TURN_MIN := 1.0        # px за тик: медленнее этого зомби спрайт не поворачивает
const ZOMBIE_TURN_HYST := 1.43      # поворот, когда одна ось движения больше другой во столько раз (tg 55°, как DIR_HYST)
const UNIT_QUAD := roundf(5.33 * SCALE_REL * 100.0) / 100.0   # сторона цветного квадрата юнита, px
const WINDUP_T := 0.15           # кадр «замах» столько секунд до удара
const UPDATE_TICKS := 2          # юнит принимает решение (и бьёт) раз в столько физических тиков
const ATTACK_ANIM_T := 0.15      # кадр «атака» столько секунд после удара
const DIR_HYST := 55.0 * PI / 180.0   # направление спрайта меняется, когда угол отряда ушёл от центра сектора дальше этого
const DIR_VEC: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]   # взгляд по unit_dir (для отдачи)
# Базис спрайта по направлению (0 вправо, 1 вниз, 2 влево, 3 вверх), по 4 числа: x.x, y.x, x.y, y.y.
# Вправо как есть, влево зеркало по x, вниз поворот +90°, вверх -90°.
const DIR_BASIS: Array[float] = [16.0, 0.0, 0.0, 16.0,   0.0, -16.0, 16.0, 0.0,   -16.0, 0.0, 0.0, 16.0,   0.0, 16.0, -16.0, 0.0]
const FIELD := Vector2(2208.0, 1056.0)   # поле в px (не масштабируется), юниты не выходят за край
const CELL_SIZE := roundf(16.0 * SCALE_REL * 100.0) / 100.0   # клетка мелкой сетки
const GRID_W := ceili(FIELD.x / CELL_SIZE)   # сетка считается от поля и клетки
const GRID_H := ceili(FIELD.y / CELL_SIZE)
const CELL_COUNT := GRID_W * GRID_H   # клеток мелкой сетки
const MIN_DIST := roundf(6.67 * SCALE_REL * 100.0) / 100.0   # ближе этого юниты отталкиваются
const PUSH_K := 0.5          # доля перекрытия, которую снимаем за тик
const VIEW_RANGE := CELL_SIZE   # равен CELL_SIZE: окно 3x3 его гарантированно покрывает
# --- Карта замка (вертикальная, 1920x1080; игрок внизу, зомби сверху) ---
const BG_PATH := "res://art/castle_map.png"   # 1831x859, пиксель-арт
const TREES_LAYER_PATH := "res://art/trees_lay.png"        # слой леса: кроны по краям поля, прозрачный PNG 1823x863
const CASTLE_LAYER_PATH := "res://art/castle_lay_two.png"  # слой замка: стены, башни с факелами, крыши; двор и вода прозрачные, 1831x859
const BG_SCALE := 1056.0 / 859.0   # фон по высоте ровно на поле (1056 px), как прежний castle_bg.jpg 1500x704 с масштабом 1.5
const BG_OFFSET := Vector2(-21, 0)
# Слои в текселях фона: тексель слоя (u, v) ложится на тексель фона *_TX_OFFSET + *_TX_SCALE * (u, v). Найдено перебором
# масштаба и сдвига по цвету фона, где лес и прежний замок уже нарисованы (bench/align_layers.py).
const TREES_TX_OFFSET := Vector2(-2, 5)
const TREES_TX_SCALE := 1.004
# Замок — значения по умолчанию: при старте их заменяет data/layer_tuning.json (castle_offset, castle_scale_x, castle_scale_y),
# если файл есть; подгонка вручную — F3 в debug-сборке (_tune_key), F4 сохраняет файл.
const CASTLE_TX_OFFSET := Vector2(455, 519)
const CASTLE_TX_SCALE := 0.448
const LAYER_TUNING_PATH := "res://data/layer_tuning.json"
const TUNE_STEP := 1.0             # сдвиг замка за нажатие стрелки, текселей фона (с Shift — TUNE_STEP_FINE)
const TUNE_STEP_FINE := 0.25
const TUNE_SCALE_STEP := 0.005     # масштаб замка за нажатие Q/E, Z/X, C/V: x (1 ± шаг) (с Shift — TUNE_SCALE_STEP_FINE)
const TUNE_SCALE_STEP_FINE := 0.001
# Фильтр слоя замка: "nearest" или "linear_mipmap" (mipmaps включены в импорте castle_lay_two.png; с эффектами на экран
# идёт текстура вьюпорта без mip-уровней — тогда фактически linear)
const CASTLE_FILTER := "nearest"
const TREES_ALPHA := 1.0           # прозрачность слоя леса
const CASTLE_ALPHA := 1.0          # прозрачность слоя замка
const FG_Z := 1                    # слои леса и замка (замок поверх леса) выше юнитов, снарядов и полос HP ворот (всё на z 0), ниже интерфейса (CanvasLayer)
# Мягкие пиксельные эффекты: сдвиги только на целый тексель, без интерполяции; всё по времени отрисовки (TIME шейдера,
# delta кадра), без тиков и генераторов боя. false — картинка как без них (этап А).
const FX_ENABLED := true
const FX_RATE := 15.0           # кадров анимации слоёв леса и замка в секунду (деревья, факелы)
# Деревья (слой леса): любой непрозрачный пиксель слоя. Сдвиг по x на 0 или ±1 тексель по знаку низкочастотного шума
# n в [-1, 1]: гладкий по x (TREE_NOISE_SCALE.x текселей на ячейку) и времени (TREE_NOISE_SPEED ячеек в секунду), свой
# в каждой полосе из TREE_NOISE_SCALE.y рядов; |n| <= порога — на месте. Ряды внутри кроны шевелятся вразнобой, соседние
# кроны тоже. Берётся сосед, только если он тоже непрозрачный: силуэт кроны не меняется.
const TREE_NOISE_SCALE := Vector2(40.0, 3.0)   # текселей на ячейку шума по x, рядов в полосе по y
const TREE_NOISE_SPEED := 0.5   # ячеек шума в секунду
const TREE_CALM := 0.6          # порог |n| без ветра: сдвинуто около 18% рядов (0.5 — 28%, 0.4 — 40%)
const TREE_GUST_CALM := 0.25    # порог в порыв: около 61% рядов (0.15 — 76%)
const GUST_EVERY_MIN := 8.0     # с между порывами (в диапазоне по хэшу номера порыва)
const GUST_EVERY_MAX := 15.0
const GUST_LEN_MIN := 1.0       # с, длительность порыва
const GUST_LEN_MAX := 2.0
const GUST_RAMP := 0.3          # с на нарастание и спад
# Факелы (слой замка): оранжево-жёлтые пиксели (r >= FIRE_R_MIN, g >= FIRE_G_MIN, b <= FIRE_B_MAX, r - g >= FIRE_RG_GAP),
# связные области (8 соседей) не меньше FIRE_MIN_PIXELS и не уже FIRE_MIN_SPAN текселей по обеим осям — отдельные
# факелы, у каждого своя фаза. Остальной слой замка не меняется. Яркость пикселя
# (границы FIRE_LUM) задаёт один из трёх оттенков FIRE_SHADES, оттенок идёт по кругу FIRE_CYCLE_SPEED шагов в секунду.
# Верхние FIRE_TOP_ROWS рядов пламени долю FIRE_FLICK_DUTY времени выше на 1 тексель (FIRE_FLICK_RATE циклов в секунду).
const FIRE_R_MIN := 0.85
const FIRE_G_MIN := 0.35
const FIRE_B_MAX := 0.35
const FIRE_RG_GAP := 0.15
const FIRE_MIN_PIXELS := 300    # мельче — не факел (у факела 550-620)
const FIRE_MIN_SPAN := 20       # уже — не факел: золотая отделка крыш — полосы в 3-5 текселей (у факела 32x47)
const FIRE_LUM := Vector2(0.55, 0.75)   # границы тёмного, среднего и светлого оттенка
const FIRE_SHADES: Array[Color] = [Color(0.85, 0.32, 0.08), Color(0.98, 0.58, 0.12), Color(1.0, 0.86, 0.35)]
const FIRE_CYCLE_SPEED := 6.0
const FIRE_TOP_ROWS := 4
const FIRE_FLICK_RATE := 1.3
const FIRE_FLICK_DUTY := 0.25
# Вода (фон): синий канал больше красного и зелёного на WATER_MARGIN. Ряд сдвигается на round(WATER_AMP * sin(y * WATER_FREQ_Y
# + t * WATER_SPEED)) тексель (сосед — тоже вода, берег не тянется); блики — доля WATER_GLINT_DENSITY пикселей воды,
# новые места WATER_GLINT_RATE раз в секунду, светлее на WATER_GLINT_LIGHT.
const WATER_MARGIN := 0.03
const WATER_AMP := 0.7          # не больше 1; меньше 1 — меньше рядов сдвинуто в каждый момент
const WATER_SPEED := 0.6        # рад/с, медленный ритм
const WATER_FREQ_Y := 0.7       # рад на ряд
const WATER_GLINT_DENSITY := 0.0015
const WATER_GLINT_RATE := 3.0
const WATER_GLINT_LIGHT := 0.45
# Отладка масок (F2 в debug-сборке, вместе с раскраской юнитов по ряду): факелы и вода — своими цветами, пиксели цвета
# огня, отсеянные по размеру области, — FX_DEBUG_FIRE_REJECTED; остальное (и лес) затемнено.
const FX_DEBUG_FIRE := Color(1.0, 1.0, 1.0)
const FX_DEBUG_FIRE_REJECTED := Color(1.0, 0.0, 0.0)
const FX_DEBUG_WATER := Color(0.0, 1.0, 1.0)
const FX_DEBUG_DIM := 0.3
# Листва: частицы от левого края поля вправо, выше юнитов и слоёв леса и замка, ниже интерфейса
const LEAF_AMOUNT := 36         # слотов; с разбросом жизни одновременно летит около 30
const LEAF_LIFE_MIN := 10.0     # с
const LEAF_LIFE_MAX := 15.0
const LEAF_SPEED_MIN := 225.0   # px/с: даже самый медленный и короткоживущий успевает вылететь за правый край
const LEAF_SPEED_MAX := 260.0
const LEAF_SPREAD := 4.0        # градусов
const LEAF_PX_MIN := 2.0        # размер, px
const LEAF_PX_MAX := 3.0
const LEAF_ALPHA := 0.7
const LEAF_SWAY_AMP := 2.5      # покачивание по вертикали в размерах листа: шейдер сдвигает вершины до масштаба частицы, на экране 5-7.5 px
const LEAF_SWAY_FREQ := 2.2     # рад/с
const LEAF_COLORS: Array[Color] = [Color(0.36, 0.62, 0.22), Color(0.25, 0.48, 0.16), Color(0.78, 0.66, 0.24), Color(0.6, 0.42, 0.18)]
const LEAF_Z := 2
const HERO_Z := FG_Z - 1           # задача 28: герой (спрайт, кольцо, полоса HP, дуга удара) — под слоями замка и леса, как юниты; над ними — позже в дереве
const HERO_OCC_Z := LEAF_Z + 1     # силуэт героя там, где его закрывают слои (_setup_hero_occlusion)
const FX_NOISE_GLSL := """
float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}
// шум, гладкий по p.x и p.y (время), без интерполяции между полосами band: 4 хэша на пиксель
float vnoise_band(vec2 p, float band) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash3(vec3(i, band)), hash3(vec3(i + vec2(1, 0), band)), f.x),
		mix(hash3(vec3(i + vec2(0, 1), band)), hash3(vec3(i + vec2(1, 1), band)), f.x), f.y);
}
"""
# Слой леса: ряды непрозрачных пикселей сдвигаются на 0 или ±1 тексель.
const TREES_SHADER := """shader_type canvas_item;
uniform vec2 tree_noise_scale;
uniform float tree_noise_speed;
uniform float tree_calm;
uniform bool debug_masks = false;
uniform float debug_dim;
varying vec4 vcol;
NOISE
void vertex() {
	vcol = COLOR;
}
void fragment() {
	vec2 tp = TEXTURE_PIXEL_SIZE;
	vec2 px = floor(UV / tp);
	vec4 c = texture(TEXTURE, UV);
	vec4 res = c;
	if (debug_masks) {
		res = vec4(c.rgb * debug_dim, c.a);
	} else if (c.a > 0.5) {
		float n = vnoise_band(vec2(px.x / tree_noise_scale.x, TIME * tree_noise_speed), floor(px.y / tree_noise_scale.y)) * 2.0 - 1.0;
		float off = abs(n) > tree_calm ? sign(n) : 0.0;
		if (off != 0.0) {
			vec4 s = texture(TEXTURE, UV + vec2(off * tp.x, 0.0));
			res = s.a > 0.5 ? s : c;
		}
	}
	COLOR = vcol * res;
}
"""
# Слой замка: факелы. fire_map (по текселю): r — факел, g — верхние ряды пламени, b — фаза факела.
const CASTLE_SHADER := """shader_type canvas_item;
uniform sampler2D fire_map : filter_nearest;
uniform vec4 fire_test;    // r_min, g_min, b_max, rg_gap
uniform vec2 fire_lum;
uniform vec4 fire_shade0 : source_color;
uniform vec4 fire_shade1 : source_color;
uniform vec4 fire_shade2 : source_color;
uniform float fire_cycle_speed;
uniform float fire_flick_rate;
uniform float fire_flick_duty;
uniform bool debug_masks = false;
uniform vec4 debug_fire : source_color;
uniform vec4 debug_fire_rejected : source_color;
uniform float debug_dim;
varying vec4 vcol;
bool is_fire_color(vec4 c) {
	return c.a > 0.5 && c.r >= fire_test.x && c.g >= fire_test.y && c.b <= fire_test.z && c.r - c.g >= fire_test.w;
}
vec4 fire_shade(vec4 c, float phase) {
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	float i = lum < fire_lum.x ? 0.0 : (lum < fire_lum.y ? 1.0 : 2.0);
	float k = mod(i + floor(TIME * fire_cycle_speed + phase * 3.0), 3.0);
	vec4 s = k < 0.5 ? fire_shade0 : (k < 1.5 ? fire_shade1 : fire_shade2);
	return vec4(s.rgb, c.a);
}
void vertex() {
	vcol = COLOR;
}
void fragment() {
	vec2 tp = TEXTURE_PIXEL_SIZE;
	vec4 c = texture(TEXTURE, UV);
	vec4 res = c;
	if (debug_masks) {
		vec4 m = texture(fire_map, UV);
		res = m.r > 0.5 ? debug_fire : (is_fire_color(c) ? debug_fire_rejected : vec4(c.rgb * debug_dim, c.a));
	} else {
		vec4 below = texture(fire_map, UV + vec2(0.0, tp.y));
		if (below.g > 0.5 && fract(TIME * fire_flick_rate + below.b * 7.13) < fire_flick_duty) {
			res = fire_shade(texture(TEXTURE, UV + vec2(0.0, tp.y)), below.b);   // верх пламени на тексель выше
		} else if (c.a > 0.5) {
			vec4 m = texture(fire_map, UV);   // факелы только среди непрозрачных пикселей
			if (m.r > 0.5) {
				res = fire_shade(c, m.b);
			}
		}
	}
	COLOR = vcol * res;
}
"""
# Фон: вода — сдвиг рядов и блики.
const BG_SHADER := """shader_type canvas_item;
uniform float water_margin;
uniform float water_amp;
uniform float water_speed;
uniform float water_freq_y;
uniform float glint_density;
uniform float glint_rate;
uniform float glint_light;
uniform bool debug_masks = false;
uniform vec4 debug_water : source_color;
uniform float debug_dim;
varying vec4 vcol;
NOISE
bool is_water(vec4 c) {
	return c.b > max(c.r, c.g) + water_margin;
}
void vertex() {
	vcol = COLOR;
}
void fragment() {
	vec2 tp = TEXTURE_PIXEL_SIZE;
	vec2 px = floor(UV / tp);
	vec4 c = texture(TEXTURE, UV);
	vec4 res = c;
	if (debug_masks) {
		res = is_water(c) ? debug_water : vec4(c.rgb * debug_dim, c.a);
	} else if (is_water(c)) {
		float off = round(water_amp * sin(px.y * water_freq_y + TIME * water_speed));
		vec4 s = texture(TEXTURE, UV + vec2(off * tp.x, 0.0));
		res = is_water(s) ? s : c;
		if (hash3(vec3(px, floor(TIME * glint_rate))) < glint_density) {
			res.rgb = mix(res.rgb, vec3(1.0), glint_light);
		}
	}
	COLOR = vcol * res;
}
"""
const LEAF_SHADER := """shader_type canvas_item;
uniform float amp;
uniform float freq;
void vertex() {
	VERTEX.y += amp * sin(TIME * freq + float(INSTANCE_ID) * 2.4);
}
"""
const ROAD_X := 970.0                  # ось дороги, по которой идёт орда
const GATE_POS := Vector2(1010, 745)   # ворота замка
const WALL_Y := 745.0                  # временный пол: ниже не заходит ни один юнит, пока нет стен
# Центр строя пехоты на старте (лучники встают позади). y считается от стены: задний ряд стартовых лучников стоит
# на WALL_Y - FORM_MARGIN - ARCHER_ROWS_RESERVE рядов (место под ряды отряда лучников при покупках до предела магазина),
# выше него — ряды лучников, ARCHER_GAP и половины глубин обоих строёв (глубина = ряды * шаг).
const START_WIDTH_INF := 20      # ширина стартового строя пехоты
const START_WIDTH_ARCH := 25     # и лучников (шире и мельче)
const ARCHER_ROWS_RESERVE := 3
const PLAYER_START := Vector2(1010, WALL_Y - FORM_MARGIN - ARCHER_GAP
	- (ceili(INFANTRY_COUNT / float(START_WIDTH_INF)) * 0.5 + ceili(ARCHER_COUNT / float(START_WIDTH_ARCH)) - 0.5 + ARCHER_ROWS_RESERVE) * SLOT_SPACING)
const PLAYER_ANGLE := -PI / 2.0            # «вперёд» отряда игрока — вверх, к зомби
const ZOMBIE_FRONT_Y := 130.0              # передний край блока зомби на старте; ряды уходят вверх
# Юнит обновляется раз в 2 тика. Два обновления по PUSH_K оставляют 25% перекрытия,
# поэтому за одно обновление снимаем 1 - 0.5^2 = 75%.
const PUSH_K_2 := 1.0 - (1.0 - PUSH_K) * (1.0 - PUSH_K)
const SLOT_GAIN := 5.0        # сила притяжения к слоту (1/с)
const SLOT_SPACING := roundf(8.0 * SCALE_REL * 100.0) / 100.0   # шаг строя
const SLOT_NEAR_SQ := SLOT_SPACING * SLOT_SPACING * 0.25   # дальше полуслота от своего места (в квадрате) — «возвращается»
const GATE_SIDE_MARGIN := roundf(8.0 * SCALE_REL * 100.0) / 100.0   # запас по x у ворот: один слот
const GOAL_STOP := roundf(5.33 * SCALE_REL * 100.0) / 100.0          # орда не идёт к цели ближе этого
const SPAWN_JITTER := roundf(1.33 * SCALE_REL * 100.0) / 100.0       # разброс точки появления зомби, ±px
const TURN_SPEED := 1.5          # рад/с, поворот на месте
const ABOUT_FACE_ANGLE := 2.1    # около 120°: если угол больше, разворот «кругом»
const MOVE_ANGLE := 0.7          # около 40°: пока угол больше, отряд стоит и поворачивается
const HORDE_GOAL := GATE_POS           # орда идёт к воротам замка
const HORDE_SPEED_SPREAD := 0.1        # разброс скорости зомби: ±10%
const HORDE_CHAOS := 0.4               # доля бокового качания зомби при подходе к врагу
const BLOCK_COS := 0.5                 # передний сектор щита: ±60° от фронта отряда
const SHIELD_DOWN_TIME := 0.25         # щит опущен столько секунд после собственного удара
# --- Лучники ---
const ARCHER_GAP := roundf(13.33 * SCALE_REL * 100.0) / 100.0   # зазор между строем ведущего отряда и строем лучников (сверх половин глубин)
const COARSE_CELLS := 4                # грубая клетка = 4x4 мелких — для прицеливания по зомби
const COARSE_SIZE := CELL_SIZE * COARSE_CELLS
const COARSE_W := (GRID_W + COARSE_CELLS - 1) / COARSE_CELLS   # ceil: покрывает всё поле
const COARSE_H := (GRID_H + COARSE_CELLS - 1) / COARSE_CELLS
const COARSE_COUNT := COARSE_W * COARSE_H
const COARSE_EVERY := 4                # пересчёт грубой сетки раз в столько тиков
const NEAR_RANGE := roundf(40.0 * SCALE_REL * 100.0) / 100.0   # зомби ближе — одиночный огонь
const MODE_HYST := roundf(13.33 * SCALE_REL * 100.0) / 100.0   # дальше NEAR_RANGE + MODE_HYST — залп; между порогами режим не меняется
const MODE_VOLLEY := 0
const MODE_SINGLE := 1
const SINGLE_SCAN_T := 0.3             # одиночный огонь: лучник ищет цель раз в столько секунд
const VOLLEY_JITTER := 0.15            # залп: индивидуальная задержка выстрела ±столько секунд
const ARROW_SPEED := roundf(266.67 * SPEED_REL * 100.0) / 100.0   # px/с, задаёт задержку падения стрелы
const ARROW_HIT_R := roundf(10.67 * SCALE_REL * 100.0) / 100.0   # стрела попадает в ближайшего зомби в этом радиусе от точки падения
const ARROW_CAP := 2048                # ёмкость очереди стрел (с запасом)
const DEBUG_COLORS := true            # F2, Shift+F3 (F3 в release-сборке), F4: отладочная раскраска; false в релизе (остаётся только F1)
# Состояние юнита для раскраски F3 (пишется там, где принимается решение)
const ST_IDLE := 0     # стоит в слоте / идёт с ордой
const ST_CHASE := 1    # идёт на врага
const ST_RETURN := 2   # возвращается к слоту
const ST_ATTACK := 3   # враг в дальности атаки: стоит и бьёт

# --- Данные юнитов: параллельные массивы. Юнит = индекс i ---
var pos := PackedVector2Array()   # позиции
var prev_pos := PackedVector2Array()   # позиции в начале физического тика (для интерполяции при рендере)
var vel := PackedVector2Array()   # желаемая скорость, px/с (решается раз в 2 тика, применяется каждый тик)
var team := PackedByteArray()     # 0 = игрок (внизу), 1 = зомби (сверху)
var buf := PackedFloat32Array()
var cell_of := PackedInt32Array()
var cell_start := PackedInt32Array()
var cursor := PackedInt32Array()
var sorted_units := PackedInt32Array()
var hp := PackedFloat32Array()
var cooldown := PackedFloat32Array()
var tick_parity := false
var update_odd := false   # какая половина обновляется в этом тике: false = чётные индексы
var count := UNIT_COUNT        # живых юнитов сейчас
var tick_counter := 0          # физических тиков с начала боя
var spawn_seed := 1            # seed генератора unit_rand
var unit_rand := PackedFloat32Array()   # 0..1 на юнита, выдаётся при спавне
var squad_pos := PackedVector2Array()
var squad_target := PackedVector2Array()
var squad_angle := PackedFloat32Array()
var squad_used := PackedByteArray()     # 1 = индекс отряда занят (0 и 1 заняты всегда)
var squad_n := PackedInt32Array()       # живых юнитов в отряде
var squad_team := PackedByteArray()
var squad_stop_dist := PackedFloat32Array()   # отряд стоит, когда до цели не больше этого
var unit_squad := PackedInt32Array()    # -1 = без отряда
var unit_slot := PackedVector2Array()
var unit_slot_idx := PackedInt32Array()   # k = ряд * ширина + колонка
var squad_width := PackedInt32Array()
var squad_rows := PackedInt32Array()      # число рядов сетки (при старте и после _reflow_squad)
var squad_dirty := PackedByteArray()      # 1 = в отряде кто-то погиб, нужна перестройка
var slot_owner := PackedInt32Array()      # scratch для _compact_squad: юнит в слоте k или -1
var col_map := PackedInt32Array()         # scratch для _compact_squad: старая колонка -> номер занятой или -1
var squad_compact_t := 0.0
var squad_speed := PackedFloat32Array()   # 0.75 * минимальная скорость юнитов отряда: строй успевает
# Якорь отряда (squad_pos) = центр живых слотов. unit_slot = _slot_vector(k, width) - squad_center_off[s],
# где squad_center_off — смещение центра живых слотов в координатах сетки (обновляет _reanchor).
var squad_center_off := PackedVector2Array()
var squad_reflow_n := PackedInt32Array()      # живых при прошлой перестройке (_reflow_squad)
var reflow_order := PackedInt32Array()        # scratch для _reflow_squad: юниты в порядке старых слотов
var slot_idx_prev := PackedInt32Array()       # scratch: slot_idx до перестройки (для unit_slot_changed_t)
var unit_state := PackedByteArray()           # ST_* (для раскраски F3 и кадра «замах»)
var unit_anim_t := PackedFloat32Array()       # сколько секунд ещё показывать кадр «атака» (только отрисовка)
var unit_dir := PackedByteArray()             # направление спрайта: 0 вправо, 1 вниз, 2 влево, 3 вверх (только отрисовка)
var squad_dir_angle := PackedFloat32Array()   # угол отряда, по которому в последний раз считались unit_dir; NAN = пересчитать
var unit_render_off := PackedVector2Array()   # сдвиг отрисовки юнита (_render_offset), считается при появлении (только отрисовка)
var unit_shot_t := PackedFloat32Array()       # лучник в залпе: сколько секунд до его собственного выпуска стрелы; 0 = не ждёт (только отрисовка)
var sprites_on := true                        # F5: спрайты (в F1); false — все юниты квадратами
var type_sprite := PackedStringArray()        # путь листа спрайта типа; "" = цветной квадрат
var type_recoil := PackedFloat32Array()       # отдача при «атаке», px (только отрисовка)
var type_sprite_frames := PackedInt32Array()  # кадров в листе типа; 0 = рисуется квадратом (нет листа или он не подошёл)
var type_sprite_base := PackedInt32Array()    # первая ячейка типа в атласе
var type_sprite_scale := PackedFloat32Array() # множитель размера спрайта типа на экране (1, у рыцаря KNIGHT_SPRITE_SCALE)
var type_walk_rate := PackedFloat32Array()    # кадров шага в секунду у типа-зомби; 0 — шага нет (рыцарь: его лист — замах и удар мечом)
var anim_clock := 0.0                         # секунды отрисовки для шага зомби: идёт в _process, на паузе стоит
var cell_white := 0                           # ячейка атласа после всех кадров: белая, для цветных квадратов
var atlas_cells := 1                          # всего ячеек в атласе
var windup_cd := 0.0                          # порог cooldown для кадра «замах», см. _unit_frame
var unit_slot_changed_t := PackedFloat32Array()   # время (с) последней смены slot_idx (для F4)
var color_mode := 0                           # 0 = F1 по типу, 1 = F2 по ряду, 2 = Shift+F3 по состоянию, 3 = F4 смена слота
var squad_front_row := PackedInt32Array()     # scratch для F2: передний занятый ряд отряда

# --- Типы юнитов (data/unit_types.json): плоские массивы по номеру типа ---
var unit_type := PackedByteArray()
var type_hp := PackedFloat32Array()
var type_damage := PackedFloat32Array()
var type_range_sq := PackedFloat32Array()   # квадрат дальности атаки
var type_cooldown := PackedFloat32Array()
var type_speed := PackedFloat32Array()
var type_block_mult := PackedFloat32Array()
var type_block_chance := PackedFloat32Array()   # доля ударов, которые щит отражает по своему правилу (данные: block_chance; пехота ~0.6)
var type_enabled := PackedByteArray()          # тип в игре (данные: enabled, по умолчанию да); копейщики в v1 выключены — их пакет не продаётся
var type_hold_block := PackedFloat32Array()     # навык «Стена щитов»: прибавка к шансу блока отряда на приказе «держать» (данные: hold_block_bonus)
var type_block_bonus := PackedFloat32Array()    # стат block (дары, карточки M) на тип, долей; пересчёт в _apply_wave_data   # множитель урона при блоке щитом; 1.0 = без щита
# Мягкая привязь к слоту: до leash_start юнит гонится за врагом, к leash_end — только к слоту.
var type_leash_start := PackedFloat32Array()
var type_leash_start_sq := PackedFloat32Array()
var type_leash_end := PackedFloat32Array()
var type_color := PackedColorArray()
var type_range_far := PackedFloat32Array()      # дальность стрельбы; 0 = не стреляет
var type_volley_period := PackedFloat32Array()  # период цикла залпа, с
var type_draw_time := PackedFloat32Array()      # натяжение перед залпом, с
var type_spread := PackedFloat32Array()         # разброс: радиус = spread * дистанция
var wave_spread := PackedFloat32Array()         # разброс на эту волну: type_spread через Mods.value (стат spread), _read_wave_mods
var type_arrow_dmg := PackedFloat32Array()
var type_bounty_mult := PackedFloat32Array()   # золото за убитого = gold_per_kill * это
var type_chase := PackedByteArray()            # орда: 1 = идёт к врагу в VIEW_RANGE; 0 = идёт мимо, бьёт только в дальности атаки

# --- Лучники: отряды, грубая сетка зомби, стрелы-события ---
var squad_follow := PackedInt32Array()      # номер ведущего отряда или -1
var squad_ranged := PackedByteArray()       # 1 = отряд стреляет
var squad_type := PackedInt32Array()        # тип юнитов отряда (для параметров залпа)
var squad_volley_mode := PackedByteArray()  # MODE_VOLLEY / MODE_SINGLE
var squad_volley_t := PackedFloat32Array()  # время с начала цикла залпа
var squad_volley_fired := PackedByteArray() # 1 = в этом цикле уже выстрелили (идёт перезарядка)
var squad_arrows_fired := PackedInt32Array()   # статистика по отряду: выпущено стрел
var squad_mode_switches := PackedInt32Array()  # статистика по отряду: смены режима стрельбы
var coarse_zcount := PackedInt32Array()      # зомби в грубой клетке
var coarse_sum := PackedVector2Array()      # сумма их позиций (центр масс = сумма / число)
var coarse_start := PackedInt32Array()
var coarse_cursor := PackedInt32Array()
var coarse_units := PackedInt32Array()      # индексы зомби по клеткам (могут устареть до пересчёта)
var coarse_cell_of := PackedInt32Array()
var arrow_land := PackedVector2Array()      # точка падения
var arrow_tick := PackedInt32Array()        # тик падения
var arrow_dmg := PackedFloat32Array()
var arrow_count := 0
# Только отрисовка (задача 29, scripts/arrow_fx.gd): откуда летит, тик выпуска на экране (дробный), номер выстрела. Пишутся рядом с
# очередью и переставляются вместе с ней; симуляция их не читает.
var arrow_from := PackedVector2Array()
var arrow_t0 := PackedFloat64Array()
var arrow_vid := PackedInt32Array()
var arrow_fx: Node2D = null     # видимые стрелы (scripts/arrow_fx.gd); null — без отрисовки (бенчи без дерева, нет data/arrows_fx.json)
var arrow_fx_on := false        # отрисовка стрел включена (настройка «Показывать стрелы»): только тогда _fire_arrow и _process_arrows отдают события
var arrow_rng := RandomNumberGenerator.new()
var arrows_fired := 0   # статистика
var arrows_hit := 0     # статистика
var arrows_out_of_range := 0   # статистика: выстрелы залпа, отменённые по дальности от позиции лучника (за волну)
var archer_own_range := ARCHER_OWN_RANGE   # бенчи переопределяют
var arrows_dropped := 0 # статистика: не влезли в ARROW_CAP
# Статистика за волну (для отчётов и бенчей, в отладочную строку не выводится): контакт = первый урон по юниту игрока
var contact_tick := -1             # тик первого урона по юниту игрока; -1 — контакта ещё не было
var volleys_before_contact := 0    # залпов до контакта
var arrows_before_contact := 0     # стрел, выпущенных до контакта
var kills_by_arrows := 0           # убито стрелами
var mode_switches := 0  # статистика: смены режима стрельбы
var squad_depth := PackedFloat32Array()     # глубина строя = занятых рядов * SLOT_SPACING (кеш, см. _update_squad_extent)
var squad_front_x := PackedFloat32Array()   # локальная x переднего ряда относительно якоря (кеш)
var first_death_tick := -1   # статистика: тик первой смерти (начало контакта)
var reach_sum := 0.0         # статистика: сумма reach = range_far - расстояние до переднего ряда ведущего
var reach_dist_sum := 0.0    # статистика: сумма расстояний центр лучников -> передний ряд ведущего
var reach_n := 0             # тиков в сумме (первые 10 с до контакта)
var blocked_hits := 0   # статистика: удары, ослабленные щитом
var total_hits := 0     # статистика: удары по юнитам со щитом (block_mult < 1.0)
var leash_ticks := 0    # статистика: юнито-тики, где привязь перевешивает (w > 0.5)
var type_id := {}   # имя -> номер
var portraits = PORTRAITS.new()   # иллюстрации в кнопках (только интерфейс)
# data/ui_layout.json: фиксированные размеры кнопок (минимум и он же ширина — текст ужимается, кнопка не растягивается).
var ui_layout := {"shop_button_size": Vector2(464, 64), "squad_button_size": Vector2(352, 48), "action_button_size": Vector2(184, 48), "war_cry_size": Vector2(352, 48),
	"debug_fps": false, "shop_slide_time": 0.2, "panel_toggle_size": Vector2(232, 48), "squad_compact_size": Vector2(112, 48),
	"info_flash_time": 2.0, "info_width": 320.0, "drag_min": DRAG_MIN}
var type_label := PackedStringArray()   # название типа для интерфейса
# Характеристики выбранного отряда (задача 26): поля и время подсветки — data/ui_layout.json squad_info_fields, info_flash_time
const INFO_FIELDS_DEFAULT := ["alive", "hp", "damage", "range", "attack_rate", "speed"]
const INFO_FIELD_KEYS := {"alive": "HUD_INFO_ALIVE", "hp": "HUD_INFO_HP", "damage": "HUD_INFO_DAMAGE", "range": "HUD_INFO_RANGE",
	"attack_rate": "HUD_INFO_ATTACK_RATE", "speed": "HUD_INFO_SPEED"}
const INFO_FLASH_COLOR := Color("#feae34")   # подсветка числа после покупки (Endesga 32, как выбранный отряд)
var info_fields: Array = INFO_FIELDS_DEFAULT.duplicate()
var squad_info: PanelContainer            # панель характеристик под панелью отрядов
var hints: PanelContainer                 # подсказка первой минуты внизу по центру (scripts/hints.gd) или null (бенчи)
var sel_touched := false                  # игрок уже выбирал отряды (условие подсказки squad_selected)
var squad_info_title: Label
var squad_info_labels := {}               # поле -> Label
var info_shown := {}                      # поле -> показанное значение (число) у отряда info_for
var info_for := -1                        # отряд, чьи характеристики показаны
var info_flash := {}                      # поле -> до какого Time.get_ticks_msec подсвечено
var hud_flash := {}                       # id окошка верхней панели -> до какого мс подсвечено

# --- Ворота и поражение (data/castle.json) ---
var wave_state := WS_BATTLE
var wave_number := 0
var best_wave := 0
var record_path := RECORD_PATH   # тесты подменяют, чтобы не трогать настоящий рекорд
var run_path := RUN_PATH         # тесты подменяют
var game: Node = null            # синглтон Game или null (бенчи, headless-скрипты)
var run_limit := false           # RUN_LIMIT_ENABLED и синглтон есть: забег кончается победой на волне waves_per_run
var waves_per_run := 0
var run_kills := 0               # убито зомби за забег
var hub_button: Button           # «В хаб» в баннере на экране конца забега
var gate_hp := 0.0
var gate_hp_max := 0.0
var gate_half := 0.0             # полуширина ворот по x
var gate_dmg_mult := 0.0
var team_dmg_mult := PackedFloat32Array([1.0, 1.0])   # множитель урона команды (team 1 растёт с волнами)
var gate_hits := 0               # статистика
var gate_damage_total := 0.0     # статистика
var banner: PanelContainer             # полупрозрачный фон, внутри — колонка из четырёх подписей
var banner_any := false                # в баннере есть текст
var banner_hidden := false             # скрыт клавишей H (до следующего текста)
var banner_labels: Array[Label] = []   # заголовок, текст, дневник, подсказка
var banner_build := Callable()        # собирает текущий баннер заново при смене языка (_set_banner) или пусто
var banner_parts := PackedStringArray(["", "", "", ""])   # что сейчас в баннере (тесты читают и без интерфейса)
var esc_menu: CanvasLayer = null       # меню паузы по Esc; null без интерфейса (бенчи)
var radiance_label: Label              # «+N Сияния» на экране итога, между дневником и подсказкой
var banner_radiance := ""              # её текст или "" (тесты читают и без интерфейса)
var squad_user_width := PackedInt32Array()   # ширина строя, заданная перетаскиванием; 0 = авто (squad_aspect)
var drag_active := false               # идёт протяжка ПКМ по карте (приказ: клик — цель, протяжка — строй)
var drag_start := Vector2.ZERO         # мировые координаты нажатия
var drag_cur := Vector2.ZERO           # и курсора сейчас
var drag_flip := false                 # F во время протяжки: лицо строя наоборот
var story_path := STORY_PATH           # тесты подменяют
var gifts_path := GIFTS_PATH           # тесты подменяют
var active_gifts := {}                 # активные дары забега, id -> уровень: с синглтоном берутся из Game.active_gifts, бенчи задают до _setup_data
var gift_defs := {}                    # дары из gifts_path (MODS.load_gifts)
var cards_path := "res://data/cards.json"   # бенчи и тесты подменяют
var card_defs := {}                    # карточки из cards_path (CARDS.load_cards)
var active_cards: Array = []           # карточки забега без синглтона (бенчи): записи {id[, result]}; с Game — Game.run_cards
# Условия карточек (тип C) и особые (K): пересчёт по отрядам раз в COND_EVERY тиков (_update_card_conditions), горячий цикл умножает на готовое.
# Без карточек все множители ровно 1.0.
var squad_dmg_mult := PackedFloat32Array()     # множитель урона отряда (удар и стрелы)
var squad_taken_mult := PackedFloat32Array()   # множитель получаемого отрядом урона
var squad_speed_mult := PackedFloat32Array()   # множитель скорости отряда (строй и юниты)
var squad_fallen := PackedInt32Array()         # своих павших отряда за волну (стат recover)
var squad_recover_carry := PackedFloat64Array()   # дробный остаток возврата павших отряда (переносится на следующие волны забега)
var squad_start_n := PackedInt32Array()        # численность отряда на начало волны (squad_low, lost_steps); 0 — отряд создан в бою, берётся при первой проверке
var wave_recovered := 0                        # своих юнитов вернулось после последней волны (стат recover), всего за забег — run_recovered
var run_recovered := 0
var wave_fallen := 0                           # своих юнитов пало за волну (карточка 24, vengeance)
var cond_cards: Array = []                     # условные карточки забега на эту волну: [{cond, when, mods [{stat, target, value}]}]
var vengeance := {}                            # карточка 24: {per_unit_pct, max_pct} или {}
var squad_block_bonus := PackedFloat32Array()   # бонус шанса блока отряда по условиям (карточка №9, навык «Стена щитов»); без них 0.0
var squad_skill_on := PackedByteArray()          # 1 — навык «Стена щитов» отряда сейчас действует (для HUD)
var squad_atk_speed_mult := PackedFloat32Array()   # множитель скорости ударов и стрельбы отряда: Клич Благодати x скорость боя по условиям карточек; без них ровно 1.0
var squad_rate_mult := PackedFloat32Array()   # множитель скорости боя отряда по условиям карточек (стат attack_rate); без них ровно 1.0
# Клич Благодати (дар war_cry, способность): состояние в тиках симуляции — пауза и ускорение работают сами.
# Активация — команда с меткой тика: request_war_cry ставит запрос, он исполняется в начале следующего тика (_tick_war_cry);
# war_cry_log — тики активаций, war_cry_plan — тики, на которых активировать (воспроизведение записанного прогона, бенчи).
var war_cry_level := 0          # уровень купленного дара; 0 — способности нет
var war_cry_mult := 1.0         # 1 + бонус / 100
var war_cry_dur := 0            # длительность, тиков
var war_cry_cd := 0             # перезарядка от активации, тиков
var war_cry_until := -1         # действует на тиках [активация, war_cry_until); -1 — не действует
var war_cry_ready := 0          # с этого тика можно активировать
var war_cry_request := false
var war_cry_log: Array = []
var war_cry_plan: Array = []
var war_cry_uses := 0           # активаций за забег (статистика бенчей)
var war_cry_active_ticks := 0   # тиков с действующим бонусом за забег
var war_cry_box: VBoxContainer = null   # кнопка в HUD (только с интерфейсом)
var war_cry_button: Button = null
var war_cry_bar: ProgressBar = null
var war_cry_glow: Array = []    # золотистая подсветка краёв экрана, пока клич действует
# Выбор карточек: в начале передышки после волн card_rules.pick_after_waves — тройка (pending_offer). С Game — правила и генератор забега Game;
# без Game выбора нет, если бенч не задал card_pick_auto ("random": бенч выбирает сам через choose_card) и bench_card_rng.
var card_rules := {}
var pending_offer: Array = []          # тройка, ждущая выбора; пока не пуста, волну не начать
var card_pick_auto := ""               # бенчи: "random" — выбор без экрана
var bench_card_rng: RandomNumberGenerator = null
var card_screen: CanvasLayer = null    # экран выбора (только с интерфейсом)
var cards_label: Label = null          # заголовок списка выбранных карточек в HUD («Карточки:»)
var cards_box: VBoxContainer = null    # список: строка на карточку (подсветка условия, подсказка при наведении)
var cards_rows: Array = []             # Label на каждую выбранную карточку, порядок _cards()
# Индикаторы карточек для HUD: id -> {on: условие выполнено хотя бы в одном отряде, pct: текущий бонус урона %} — пишет
# _update_card_conditions (раз в COND_EVERY тиков), HUD только читает; в передышке все выключены.
var card_state := {}
var mods: RefCounted = null            # MODS: собирается при старте забега и в начале каждой волны (_prepare_wave), тик его не вызывает
var income_pct := 0.0                  # стат income: эта доля дохода волны начисляется в конце волны (до магазина передышки)
var income_flat := 0.0                 # стат income_flat: столько золота начисляется в конце волны вместе с доходом
# База данных типов (из unit_types.json, castle.json) — от неё в начале каждой волны считаются эффективные массивы type_* (_apply_wave_data)
var base_type_hp := PackedFloat32Array()
var base_type_damage := PackedFloat32Array()
var base_type_arrow_dmg := PackedFloat32Array()
var base_type_bounty := PackedFloat32Array()
var base_type_speed := PackedFloat32Array()
var base_type_cooldown := PackedFloat32Array()
var base_type_volley := PackedFloat32Array()
var base_type_range_far := PackedFloat32Array()
var base_gate_hp_max := 0.0
var gate_mult := 1.0                   # множитель gate_hp, с которым посчитан gate_hp_max
var type_cd_floor := PackedFloat32Array()   # нижний предел cooldown: 0, с модификатором скорости удара -CD_CARRY (остаток переносится на следующий удар)
var wave_income := 0.0                 # доход прошлой волны: золото за убитых и бонус волны
var gold_wave_start := 0.0             # золото в начале волны (после начисления дара): от него считается доход волны
var story_intro := ""
var story_entries := {}                # Vector2i(осада, волна) -> {id, text}
var story_victories := {}              # осада -> текст победы
var siege_count := 0                   # из run.json: для каждой осады нужен текст победы
var story_end_wave := PackedInt32Array()    # концовки: min_wave
var story_end_text := PackedStringArray()   # и текст с {wave}
var drawn_gate_hp := -1.0        # последнее нарисованное HP ворот (перерисовка полосы только при изменении)

# --- Волны и экономика (data/waves.json, data/shop.json) ---
var waves_enabled := WAVES_ENABLED   # бенчи переопределяют до _setup_data
var wave_cfg := {}                   # числа из waves.json
var wave_remaining := 0              # зомби этой волны, ещё не появившихся
var subwave_timer := 0.0
var wave_hp_mult := 1.0
var wave_kills := 0
var wave_spawned := 0                  # зомби создано за волну: номер следующего — для разброса HP (hp_spread)
var zombie_alive := 0
var gold := 0.0
var unit_rng := RandomNumberGenerator.new()   # unit_rand, джиттер спавна, точки выхода из ворот
var infantry_type := -1
var archer_type := -1
var spearman_type := -1   # копейщики: свой товар (spear_pack) и свои отряды, создаются при первой покупке
var zombie_type := -1
var runner_type := -1
var knight_type := -1
# Герой (задача 10, эксперимент): одна сущность в общих массивах юнитов — тип hero (добавляется последним к типам из unit_types.json,
# только когда герой включён), команда игрока, без отряда. Зомби видят и бьют его через общую сетку; сам он решает отдельно (_update_hero).
var hero_path := HERO_PATH   # тесты подменяют
var hero_mode := 0           # 0 — по данным (enabled) и только в игровом режиме (с синглтоном Game); 1 — включён (тесты, бот B9); -1 — выключен
var hero_cfg := {}           # data/hero.json как есть (проверен _load_hero)
var hero_on := false         # герой в этом бою; без него ни одна ветка героя не выполняется — эталон бит в бит
var hero_type := -1
var hero_idx := -1           # индекс героя в массивах юнитов; -1 — нет (выключен или пал); переносится в _remove_dead
var hero_move := Vector2.ZERO   # ввод движения этого тика (длина не больше 1), читается раз в тик в _physics_process
var hero_attack_in := false     # ввод удара этого тика (J нажата с прошлого тика или удерживается при hold_repeat)
var hero_face_in := NAN         # взгляд из ввода этого тика (hero_feed "face", рад); NAN — по движению
# Тесты и бот: func(тик) вместо клавиатуры (записанная последовательность ввода). Возвращает Vector2 (только движение) или
# Dictionary {"move": Vector2, "attack": bool, "face": угол в рад — необязательно, без него взгляд по движению}.
var hero_feed := Callable()
var hero_face := 1.0            # взгляд спрайта по x: 1 — вправо, -1 — влево (только отрисовка, по hero_face_ang)
var hero_face_ang := -PI / 2.0  # направление взгляда героя (рад, состояние симуляции): удар — сектор вокруг него; старт — вверх, к зомби
var hero_attack_latch := false  # J нажата между тиками (событие): попадёт во ввод ближайшего тика, короткое нажатие не теряется
var hero_swing_n := 0           # всех ударов героя, и мимо (эффекты по кадрам замечают новый удар)
var hero_swing_ang := 0.0       # направление последнего удара (рад)
var hero_hit_idx := PackedInt32Array()     # зомби, задетые последним ударом (их индексы и позиции на тот тик): мигание белым
var hero_hit_pos := PackedVector2Array()
var hero_hit_dead := PackedByteArray()     # 1 — этот удар его добил (крупный всплеск крови)
var hero_hit_type := PackedInt32Array()    # тип и unit_dir задетых на тот тик (куски тела добитых)
var hero_hit_dir := PackedByteArray()
var hero_swing_from := Vector2.ZERO        # где стоял герой при ударе (направление всплеска)
const HERO_SPAWN := Vector2(1010.0, 680.0)   # у ворот над стеной (GATE_POS.x, WALL_Y - 65; ниже — на зубцах стены): появление и возрождение
var hero_dead := false   # герой пал в этой волне: приказы заблокированы до её конца, в начале передышки — возрождение
var hero_near_r := CARDS.HERO_NEAR_DEFAULT   # радиус условия hero_near (hero.json hero_near_radius, px); читает _load_hero
var hero_taken_mult := 1.0   # множитель урона по герою по условию hero_low (карточка 44, damage_taken); пишет _update_card_conditions, без карточки ровно 1.0
var hero_fallen_label: Label   # «Командир пал» в HUD
var hero_fallen_panel: PanelContainer   # её подложка (универсальная панель), видна вместе с ней
var hero_view: Node2D          # герой на экране: кольцо-маркер и полоса HP (_draw_hero_marker), спрайт — дочерний; null в бенчах без дерева
var hero_sprite: Sprite2D
# Спрайтшит героя (задача 15; hero.json sprite_path, frame_w, frame_h, frames, animations, pivot, orient; только отрисовка):
# анимации idle, walk (герой сдвинулся за тик), attack (кадры растянуты на вспышку удара arc_fx_time). Один кадр или неверная
# сетка — прежнее поведение: вся картинка, отражение по движению и выпад.
var hero_anims := {}            # имя -> {"frames": PackedInt32Array, "fps": float}; пусто — без анимации
var hero_rotate := false        # orient "rotate": кадр смотрит вправо и поворачивается по взгляду; "flip" — отражение по x
var hero_anim := ""             # текущая анимация (idle / walk / attack)
var hero_anim_t := 0.0          # с от начала текущей анимации (время кадра)
var hero_drawn := Vector2(-1.0, -1.0)   # HP и зум, с которыми маркер нарисован (перерисовка только при смене)
const HERO_RING_PX := 20.0     # радиус кольца на экране, px — постоянный при любом зуме камеры
# Обратная связь на удар (задача 11; только отрисовка, время кадра — не тики и не ГСЧ симуляции): дуга-вспышка (hero.json arc_fx_color,
# arc_fx_time), выпад героя вперёд, звук hero_swing, мигание белым задетых зомби.
const HERO_LUNGE_PX := 2.0      # выпад героя по взгляду в начале вспышки, px мира (к её концу — 0)
const HERO_FX_GROW_PX := 2.5    # кромка дуги расширяется наружу за вспышку, px мира
const HERO_FX_GLOW_PX := 3.0    # свечение — шире основного сектора на столько px и на HERO_FX_GLOW_ANG по краям
const HERO_FX_GLOW_ANG := 0.08
const HIT_FLASH_FRAMES := 2     # задетые зомби белые столько кадров (custom.y инстанса, шейдер MultiMesh)
var hero_occ: Sprite2D = null  # задача 28: силуэт героя над слоями (только где слой его закрывает); null — выключен в hero.json или нет слоёв
var hero_occ_mat: ShaderMaterial = null
var hero_fx: Node2D             # дуга-вспышка (_draw_hero_fx): над юнитами, под спрайтом героя; null в бенчах без дерева
var hero_fx_seen := 0           # hero_swing_n, вспышка которого уже начата
var hero_fx_age := -1.0         # с от начала вспышки (сумма delta кадров); < 0 — вспышки нет
var hero_fx_ang := 0.0
var hero_flash_left := 0        # кадров мигания задетых осталось
var hero_flash_slots := PackedInt32Array()   # ячейки буфера, где мигание включено (в следующем кадре сбрасываются)
# Эффекты попаданий героя (задача 12, data/fx.json; только отрисовка): частицы крови и искры — плоские массивы и один MultiMesh
# (не больше max_particles живых, лишние не создаются), пятна на земле — кольцевой буфер max_stains и свой MultiMesh под юнитами,
# тряска экрана — смещение камеры. ГСЧ — свой (hit_rng), время — delta кадра; на паузе новые не создаются и старые стоят.
const HIT_FPI := 12             # float на частицу или пятно в буфере MultiMesh: 8 (трансформ 2D) + 4 (цвет)
var hit_cfg := {}               # data/fx.json; пусто — эффектов нет
var hit_rng := RandomNumberGenerator.new()
var hit_mm: MultiMesh           # частицы
var hit_buf := PackedFloat32Array()
var hit_n := 0                  # живых частиц
var hit_pos := PackedVector2Array()
var hit_vel := PackedVector2Array()
var hit_life := PackedFloat32Array()     # осталось, с
var hit_life0 := PackedFloat32Array()    # всего, с
var hit_size := PackedFloat32Array()
var hit_col := PackedColorArray()
var hit_drag := PackedFloat32Array()     # затухание скорости, 1/с (искры стоят)
var hit_dropped := 0            # частиц не создано из-за лимита (статистика, тесты)
# Слой крови на земле (задача 23): пятна впечатываются в одну текстуру поля — SubViewport без очистки, каждый кадр в него рисуются
# только новые пятна (MultiMesh очереди кадра), поэтому цена не растёт с числом пятен; слой показывает Sprite2D под юнитами.
var stain_vp: SubViewport       # null — пятен нет
var stain_layer: Sprite2D
var stain_stamp_mm: MultiMesh   # пятна этого кадра
var stain_stamp_buf := PackedFloat32Array()
var stain_stamp_n := 0          # в очереди кадра (не больше stains_per_frame)
var stain_fade: ColorRect       # шаг подсыхания: умножение слоя на stain_dry_mult (CanvasItemMaterial BLEND_MODE_MUL)
var stain_fade_on := false      # шаг подсыхания ждёт отрисовки слоя
var stain_pending := false      # очередь пятен отдана слою — очистится, когда кадр движка сменится (значит, слой нарисован)
var stain_pending_frame := 0    # Engine.get_process_frames() в момент отдачи очереди
var stain_dry_left := 0         # осталось шагов подсыхания после волны
var stain_dry_t := 0.0
var stain_total := 0            # впечатано пятен с начала забега (тесты, отчёт)
var stain_skipped := 0          # пятен сверх stains_per_frame (не впечатаны)
var stain_redraws := 0          # кадров, когда слой перерисовывался
var shake_amp := 0.0            # амплитуда тряски текущего удара, px экрана (shake_base_px + за попавших, x уровень настройки)
var shake_cap := 0.0            # потолок смещения, px экрана (shake_max_px x уровень)
var shake_hit_t := 0.0          # осталось тряски, с
var shake_hit_count := 0        # трясок (ударов с попаданием при включённой тряске; тесты)
var shake_last_amp := 0.0       # амплитуда последней тряски (тесты)
# События смертей для эффектов (задача 23): _remove_dead записывает (только чтение состояния симуляции, ГСЧ не трогается),
# _hit_fx_frame разбирает раз в кадр. Пусто — эффекты выключены.
var death_pos := PackedVector2Array()
var death_team := PackedByteArray()
var death_type := PackedInt32Array()
var death_dir := PackedByteArray()
var death_n := 0
var death_over := 0             # смертей сверх death_buffer за кадр (не записаны)
var mass_shown := 0             # смертей с брызгами (в видимой области, после выборки; статистика, тесты)
var mass_sampled_out := 0       # видимых смертей, пропущенных выборкой (больше mass_deaths_per_frame за кадр)
var mass_frame_max := 0         # наибольшее число смертей с брызгами за кадр (тесты)
# Брызги смертей (задача 23): один квад на смерть, капли считает шейдер scripts/splash.gdshader — CPU пишет инстанс один раз
# (кольцевой буфер mass_splash_max), покадрово — только время now. Без покадрового цикла по частицам: резня не грузит кадр.
const SPLASH_FPI := 16          # float на брызги: 8 (трансформ 2D) + 4 (цвет) + 4 (custom: появление, зерно, жизнь, 0)
var splash_mm: MultiMesh        # null — брызг смертей нет
var splash_mat: ShaderMaterial
var splash_buf := PackedFloat32Array()
var splash_head := 0            # следующая ячейка кольца
var splash_used := 0            # занятых ячеек (до mass_splash_max)
var splash_time := 0.0          # время эффектов, с (стоит на паузе)
var splash_dirty := false       # буфер изменился — отдать MultiMesh
var gib_mass := 0               # пар кусков у смертей не от героя
var hero_kill_pos := PackedVector2Array()   # добитые героем в этом кадре: их смерть уже показана ударом
var hit_bursts := 0             # всплесков (ударов героя с попаданием, замеченных кадром не на паузе; тесты)
var hit_streak := 0             # добитых героем подряд (между добиваниями не больше big_drop_window с): крупные капли
var hit_streak_t := 0.0         # с с последнего добивания (время кадра)
# Куски тела (задача 13, data/fx.json gib_*): добитый героем зомби распадается на верх и низ (две картинки); пары в плоских массивах
# (k — пара, 2k — верх, 2k + 1 — низ) и два MultiMesh (по текстуре), над пятнами и юнитами, ниже героя. Без вращения.
var gib_top_mm: MultiMesh       # null — куски выключены
var gib_bot_mm: MultiMesh
var gib_top_buf := PackedFloat32Array()
var gib_bot_buf := PackedFloat32Array()
var gib_n := 0                  # живых пар
var gib_pos := PackedVector2Array()
var gib_vel := PackedVector2Array()
var gib_age := PackedFloat32Array()      # с с появления пары
var gib_dir := PackedByteArray()         # unit_dir зомби в момент смерти (ориентация обеих половин)
var gib_scale := PackedFloat32Array()    # масштаб спрайта типа (рыцарь крупнее)
var gib_tex_k: Array[Vector2] = [Vector2.ONE, Vector2.ONE]   # размер картинки верха и низа / SPRITE_PX (DIR_BASIS — под 16 px)
var gib_col := PackedColorArray()        # перекраска по цвету типа (gib_type_tint)
var gib_dropped := 0            # пар не создано из-за лимита max_gibs (статистика, тесты)
var hero_swings := 0   # статистика героя за забег: ударов (с хоть одной целью), попаданий, добитых им зомби, смертей
var hero_hits := 0
var hero_kills := 0
var hero_deaths := 0
var gold_spent := 0.0   # потрачено золота в магазине за забег (журнал забегов, задача 26; на симуляцию не влияет)
const SIDE_TOP := 0     # стороны появления орды
const SIDE_LEFT := 1
const SIDE_RIGHT := 2
const SIDE_ARROWS := ["↑", "←", "→"]
const VIEW_HALF_H := 540.0   # и половина высоты
const SIDE_WORDS := ["SIDE_TOP", "SIDE_LEFT", "SIDE_RIGHT"]   # ключи перевода
const VIEW_HALF_W := 960.0   # половина ширины экрана в px мира без камеры (бенчи без дерева); с камерой край вида — view_rect()
var wave_plan: Array = []              # состав следующей (в бою — текущей) волны: записи {type, side, count}
var wave_plan_for := 0                 # для какой волны построен wave_plan
var wave_left := PackedInt32Array()    # сколько ещё не появилось по каждой записи плана
var wave_kills_by_type := PackedInt32Array()   # убито за волну по типу юнита
var scout_shown := SCOUT_SHOWN         # тесты переопределяют
var bursts_enabled := BURSTS_ENABLED   # бенчи переопределяют до старта волны
var bursts_layered := BURSTS_LAYERED   # бенчи переопределяют до _setup_data
var debug_layer := DEBUG_LAYER         # и слой тоже
var burst_pending := 0                 # слои: ещё не появившиеся юниты уже начавшихся всплесков
var burst_live := 0                    # слои: сколько всплесков сейчас появляется
var signal_redraw_until := 0.0         # до какого wave_t полоса сигнала меняется (перерисовка каждый кадр)
var wave_signal_lead := 0.0            # окно сигнала всплеска на эту волну, с: signal_lead слоя (или burst_signal_lead) через Mods.value, _read_wave_mods
const ARRIVALS_WINDOW := 300           # тиков в окне arrivals_10s_max (10 с)
var arrivals_ring := PackedInt32Array()   # PROFILE: сколько зомби появилось в каждом из последних тиков
var arrivals_sum := 0
var arrivals_now := 0                  # появилось в текущем тике
var arrivals_10s_max := 0              # PROFILE: максимум появившихся за любые 10 с волны
var wave_bursts: Array = []            # всплески волны wave_plan_for: {t_start, side, records [{type, count}]}
var wave_t := 0.0                      # секунд с начала волны (Space)
var burst_idx := 0                     # следующий всплеск, который ещё не начал появляться
var burst_signal_n := 0                # скольким всплескам уже дан сигнал
var burst_active := false              # всплеск burst_idx появляется кусками
var burst_rec := 0                     # запись всплеска, из которой идёт очередной кусок
var burst_rec_left := 0                # сколько осталось в этой записи
var burst_placed := 0                  # сколько юнитов всплеска уже появилось (место в сетке блока)
var burst_chunk_t := 0.0               # до следующего куска, с
var burst_msg := ""                    # надпись «Всплеск: ...»
var burst_msg_until := 0.0             # до какого wave_t она видна
var burst_label: Label
var signal_player: AudioStreamPlayer   # null, если звукового файла нет
static var hero_legacy_warned := false   # задача 28: предупреждение о прежней картинке героя (блок legacy) — один раз за запуск
var hero_sheet_legacy := false          # сетка героя из блока legacy hero.json (картинка ещё прежняя)
static var signal_warned := false      # предупреждение об отсутствии звука — один раз за запуск игры (R сцену пересоздаёт)
var sort_keys := PackedInt64Array()           # scratch для _reflow_squad
var squad_aspect := PackedVector2Array()      # пропорция строя (ширина, глубина): пехота 20/15, лучники 25/4
var shop_label := PackedStringArray()
var shop_base := PackedFloat64Array()   # float64: цены вида 100·1.2 без хвостов float32
var shop_growth := PackedFloat64Array()
var shop_param := PackedFloat64Array()        # amount / dmg_mult / gate_max_gain
var shop_bought := PackedInt32Array()
var weapon_stat := "damage"                # что усиливает «Оружие» (shop.json weapons.stat): damage — урон, attack_rate — скорость боя; x dmg_mult за покупку
var shop_cap := PackedInt32Array()          # inf_pack / archer_pack: максимум живых юнитов этого типа
var shop_enabled := PackedByteArray()      # товар в игре (shop.json enabled, по умолчанию да; пакет выключенного типа — нет): иначе скрыт, клавиша не покупает
var top_hud: TOP_HUD                           # верхняя панель боя: Волна, Зомби, Войска, Ворота, Золото (scripts/top_hud.gd)
var info_label: Label                         # разведка и сообщения (отказ команды) — бывшие 2-я и 3-я строки HUD, левый верхний угол
var info_plan := false                        # что сейчас в info_label: строка разведки показана, для какой волны, какое сообщение —
var info_plan_for := -1                       # текст пересобирается, только когда что-то из этого поменялось
var info_msg := ""
var radiance_slot: HUD_SLOT                    # окошко «Сияние» на экране итога (баланс), под ним — заработанное за забег
var radiance_earned_label: Label
var war_cry_sig := -1                         # состояние и число в подписи Клича: подпись пересобирается, только когда они сменились
var shop_panel: PanelContainer           # выдвижной магазин справа (задача 24): блоки «Войска» и «Улучшения»
var shop_tab: Button                      # кнопка «свернуть / развернуть» под магазином (и клавиша shop_toggle)
var shop_open := true                     # магазин развёрнут (цель анимации); в начале волны — false, в передышке — true
var shop_slide := 1.0                     # доля выезда 0..1 (анимация shop_slide_time из ui_layout.json)
var shop_state_seen := -1                 # wave_state, при котором последний раз выставлен shop_open
var shop_blocks: Array[Label] = []        # заголовки блоков магазина
var squad_toggle: Button                  # «свернуть / развернуть» панель отрядов (и клавиша squad_panel_toggle)
var squad_compact: Array[Button] = []     # свёрнутая панель: строка отряда — квадратик и число живых
var squad_expanded := true                # панель отрядов развёрнута (Settings.squad_panel_expanded)
var shop_buttons: Array[Button] = []
var ui_t := 0.0                               # таймер обновления HUD (10 Гц)

# --- Управление отрядами ---
var archers_follow := ARCHERS_FOLLOW          # бенчи переопределяют до _setup_data
var squad_order := PackedByteArray()          # ORDER_* на отряд
var sel_mask := 1                             # выбранные отряды: бит s = отряд s выбран
var sel_primary := 0                          # главный выбранный (последний выбранный, в него идёт покупка) или -1
var box_active := false                       # идёт рамка выбора (ЛКМ)
var box_start := Vector2.ZERO                 # мировые координаты нажатия
var box_cur := Vector2.ZERO                   # и курсора сейчас
var box_dbl := false                          # нажатие было двойным кликом
var mod_shift := false                        # Shift по последнему событию мыши или клавиатуры (клик по строке панели)
var sel_sig := 0.0                            # отпечаток выбранных отрядов (место, угол, состав): изменился — перерисовка контуров
var sel_boxes := []                           # границы живых слотов отрядов для контуров (_squad_boxes), пока строи те же
var sel_boxes_key := 0.0
var hint_label: Label
var fx_enabled := FX_ENABLED                  # бенчи переопределяют до _ready
var fx_bg_mat: ShaderMaterial = null          # материалы эффектов; null при fx_enabled = false
var fx_trees_mat: ShaderMaterial = null
var fx_castle_mat: ShaderMaterial = null
var fx_vps: Array[SubViewport] = []          # вьюпорты слоёв леса и замка с эффектами
var camera: Camera2D = null                   # камера поля (_setup_camera); null в бенчах без дерева
const CAMERA_CFG := "res://data/camera.json"  # зум игрока (задача 27): пределы, шаг колеса, сглаживание
const CAMERA_DEFAULTS := {"zoom_user_min": 1.0, "zoom_user_max": 2.5, "zoom_step": 1.15, "zoom_smooth": 14.0, "pan_sensitivity": 1.0}
var shake_raw := Vector2.ZERO                # задача 28: смещение тряски до урезания краем поля (camera.offset — после), px мира
const CAMERA_ZOOM_FLOOR := 1.0               # задача 28: множитель не меньше — при 1.0 поле закрывает экран целиком
var cam_cfg: Dictionary = CAMERA_DEFAULTS     # data/camera.json (нет файла — значения выше с предупреждением)
var zoom_user := 1.0                          # множитель зума игрока поверх базового (camera_min_zoom), сглаженный
var zoom_user_target := 1.0                   # куда идёт zoom_user (колесо, сброс); хранится в Game.camera_zoom_user
var zoom_anchor_screen := Vector2.ZERO        # точка экрана, под которой при зуме остаётся zoom_anchor_world
var zoom_anchor_world := Vector2.ZERO
var pan_active := false                      # задача 28: зажата средняя кнопка — камера идёт за курсором (pan_begin / pan_to / pan_end)
var pan_sp0 := Vector2.ZERO                  # точка экрана и центр камеры, от которых считается перетаскивание (у края поля
var pan_cam0 := Vector2.ZERO                 # и после шага зума — заново, чтобы обратное движение сдвигало вид сразу)
var unit_node: MultiMeshInstance2D = null      # юниты на экране (пятна крови вставляются в дерево перед ним — под юнитами)
var castle_filter := CASTLE_FILTER            # бенчи переопределяют до _ready
var layer_tuning_path := LAYER_TUNING_PATH    # и путь подгонки замка тоже
var trees_sprite: Sprite2D = null             # спрайт слоя леса на экране (задача 28: маска силуэта героя)
var castle_sprite: Sprite2D = null            # спрайт слоя замка на экране (с эффектами — спрайт текстуры вьюпорта)
var castle_offset := CASTLE_TX_OFFSET         # положение и масштаб замка в текселях фона (data/layer_tuning.json)
var castle_scale := Vector2(CASTLE_TX_SCALE, CASTLE_TX_SCALE)
var tune_on := false                          # режим подгонки замка (F3, debug-сборка)
var tune_label: Label = null
var tune_msg := ""                            # итог последнего сохранения
var fx_bake_t := 0.0                          # с до следующей перерисовки вьюпорта
static var fx_fire_map: ImageTexture = null   # карта факелов, строится один раз за запуск
static var fx_torches := 0                    # найдено факелов
var fx_gust_n := 0                            # номер порыва: интервал и длительность — хэш от номера (без генераторов)
var fx_gust_wait := 0.0                       # с до порыва
var fx_gust_left := 0.0                       # с до конца порыва
var fx_gust := 0.0                            # сила порыва 0..1
var paused := false                           # активная пауза: _physics_process не выполняется, команды только меняют данные
var split_frac := 0.5                         # деление: доля уходящих в новый отряд
var split_mode := 0                           # кто уходит: 0 правые, 1 левые, 2 задние ряды, 3 передние ряды
var pause_label: Label
var pause_dim: ColorRect
var split_box: VBoxContainer              # ползунок доли и кнопка режима деления (передышка и пауза в бою)
var split_label: Label
var split_slider: HSlider
var split_mode_button: Button
var action_buttons: Array[Button] = []
var squad_panel: VBoxContainer
var squad_buttons: Array[Button] = []
var squad_rows_ui: Array[HBoxContainer] = []   # строки панели, по одной на индекс отряда
var squad_swatches: Array[ColorRect] = []
var squad_actions: HBoxContainer          # кнопки «+ Отряд», «Разделить», «Слить» (только в передышке)
var squad_panel_sig := -1                 # какие строки панели видны (перевёрстка только при изменении)
var squad_text_sig := PackedInt64Array()    # по отряду: число, приказ, навык, тип, номер среди одного типа — подпись строки только при их смене
var hud_msg := ""                         # сообщение в HUD (отказ команды), гаснет через hud_msg_t секунд
var hud_msg_t := 0.0
var panel_t := 0.0                            # таймер обновления левой панели (4 Гц)

# --- Отрисовка ---
var multimesh: MultiMesh
var fps_label: Label                      # отладочная строка FPS; null, если выключена (debug_fps_on)
var debug_fps_force := false              # тесты: как debug_fps в ui_layout.json (до _ready)
var grid_ms := 0.0
var sim_avg := 0.0
var sim_peak := 0.0
var sim_max := 0.0        


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_setup_data()
	if type_id.is_empty():
		return   # типы не загрузились: ошибка уже выведена, симуляция остановлена
	_setup_background()
	_setup_rendering()
	_setup_camera()
	_setup_fps_label()
	var st := get_node_or_null("/root/Settings")
	if st != null:
		st.changed.connect(_on_settings_changed)   # переназначили клавишу — обновить подписи
	queue_redraw()   # отладочные маркеры ворот и дороги (_draw)
	# Звук сигнала всплеска: если файла нет — тихо, одно предупреждение за запуск.
	if ResourceLoader.exists(SIGNAL_SOUND_PATH):
		signal_player = AudioStreamPlayer.new()
		signal_player.stream = load(SIGNAL_SOUND_PATH)
		add_child(signal_player)
	elif not signal_warned:
		signal_warned = true
		push_warning("Нет звука сигнала %s: всплески без звука" % SIGNAL_SOUND_PATH)


# Фон: карта замка. Если файла нет — без фона, с предупреждением.
func _setup_background() -> void:
	if not ResourceLoader.exists(BG_PATH):
		push_warning("Нет фона %s: поле рисуется без фона" % BG_PATH)
		return
	var bg := _map_sprite(BG_PATH)
	bg.z_index = -1   # ниже MultiMeshInstance2D юнитов (z 0)
	if fx_enabled:
		fx_bg_mat = _fx_material(BG_SHADER, {"water_margin": WATER_MARGIN, "water_amp": minf(WATER_AMP, 1.0),
			"water_speed": WATER_SPEED, "water_freq_y": WATER_FREQ_Y, "glint_density": WATER_GLINT_DENSITY,
			"glint_rate": WATER_GLINT_RATE, "glint_light": WATER_GLINT_LIGHT, "debug_water": FX_DEBUG_WATER, "debug_dim": FX_DEBUG_DIM})
		bg.material = fx_bg_mat
	add_child(bg)
	# Слои леса и замка поверх юнитов; замок добавлен позже — поверх леса
	var trees := _layer_sprite(TREES_LAYER_PATH, TREES_TX_OFFSET, Vector2.ONE * TREES_TX_SCALE, TREES_ALPHA)
	if trees != null:
		if fx_enabled:
			fx_trees_mat = _fx_material(TREES_SHADER, {"tree_noise_scale": TREE_NOISE_SCALE,
				"tree_noise_speed": TREE_NOISE_SPEED, "tree_calm": TREE_CALM, "debug_dim": FX_DEBUG_DIM})
			trees.material = fx_trees_mat
			trees = _fx_bake(trees)
			fx_gust_wait = lerpf(GUST_EVERY_MIN, GUST_EVERY_MAX, _fx_hash(0))
		add_child(trees)
		trees_sprite = trees
	_load_layer_tuning()
	var castle := _layer_sprite(CASTLE_LAYER_PATH, castle_offset, castle_scale, CASTLE_ALPHA)
	if castle != null:
		if castle_filter == "linear_mipmap":
			castle.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		elif castle_filter != "nearest":
			push_warning("CASTLE_FILTER: неизвестный фильтр %s, оставлен nearest" % castle_filter)
		if fx_enabled:
			if fx_fire_map == null:
				fx_fire_map = _build_fire_map(castle.texture.get_image())
			fx_castle_mat = _fx_material(CASTLE_SHADER, {"fire_map": fx_fire_map,
				"fire_test": Vector4(FIRE_R_MIN, FIRE_G_MIN, FIRE_B_MAX, FIRE_RG_GAP), "fire_lum": FIRE_LUM,
				"fire_shade0": FIRE_SHADES[0], "fire_shade1": FIRE_SHADES[1], "fire_shade2": FIRE_SHADES[2],
				"fire_cycle_speed": FIRE_CYCLE_SPEED, "fire_flick_rate": FIRE_FLICK_RATE, "fire_flick_duty": FIRE_FLICK_DUTY,
				"debug_fire": FX_DEBUG_FIRE, "debug_fire_rejected": FX_DEBUG_FIRE_REJECTED, "debug_dim": FX_DEBUG_DIM})
			castle.material = fx_castle_mat
			castle = _fx_bake(castle)
		add_child(castle)
		castle_sprite = castle
	if fx_enabled:
		_setup_leaves()
		_sync_fx_debug()


func _fx_material(code: String, params: Dictionary) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code.replace("NOISE", FX_NOISE_GLSL)
	var mat := ShaderMaterial.new()
	mat.shader = sh
	for k in params:
		mat.set_shader_parameter(k, params[k])
	return mat


# Слой с эффектами рисуется в SubViewport размера текстуры раз в 1 / FX_RATE с (_update_fx), на экран — готовая
# текстура спрайтом с теми же позицией, масштабом и z: шейдер не считается каждый кадр. Вьюпорт хранит цвет, умноженный
# на альфу, поэтому смешивание premultiplied (и прозрачность слоя — во всех каналах modulate).
func _fx_bake(inner: Sprite2D) -> Sprite2D:
	var out := Sprite2D.new()
	out.centered = false
	out.position = inner.position
	out.scale = inner.scale
	out.z_index = inner.z_index
	var a := inner.modulate.a
	out.modulate = Color(a, a, a, a)
	out.texture_filter = inner.texture_filter
	var vp := SubViewport.new()
	vp.size = Vector2i(inner.texture.get_size())
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	inner.position = Vector2.ZERO
	inner.scale = Vector2.ONE
	inner.z_index = 0
	inner.modulate = Color.WHITE
	inner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # во вьюпорт — тексель в тексель
	vp.add_child(inner)
	add_child(vp)
	fx_vps.append(vp)
	out.texture = vp.get_texture()
	var cm := CanvasItemMaterial.new()
	cm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	out.material = cm
	return out


# Карта факелов по текселям слоя замка: связные области цвета огня от FIRE_MIN_PIXELS и FIRE_MIN_SPAN. r — факел, g — верхние
# FIRE_TOP_ROWS рядов области, b — фаза (золотое сечение от номера факела). Один раз за запуск игры (статическое поле).
func _build_fire_map(img: Image) -> ImageTexture:
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var src := img.get_data()
	var r_min := int(FIRE_R_MIN * 255.0)
	var g_min := int(FIRE_G_MIN * 255.0)
	var b_max := int(FIRE_B_MAX * 255.0)
	var gap := int(FIRE_RG_GAP * 255.0)
	var fire := PackedByteArray()
	fire.resize(w * h)
	for i in w * h:
		var o := i * 4
		var r := src[o]
		if r >= r_min and src[o + 3] > 127 and src[o + 1] >= g_min and src[o + 2] <= b_max and r - src[o + 1] >= gap:
			fire[i] = 1
	var out := PackedByteArray()
	out.resize(w * h * 4)
	var torches := 0
	for i in w * h:
		if fire[i] != 1:
			continue
		var area := PackedInt32Array([i])
		fire[i] = 2
		var k := 0
		while k < area.size():
			var q := area[k]
			k += 1
			var qx := q % w
			var qy := q / w
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var x: int = qx + dx
					var y: int = qy + dy
					if x >= 0 and y >= 0 and x < w and y < h and fire[y * w + x] == 1:
						fire[y * w + x] = 2
						area.append(y * w + x)
		if area.size() < FIRE_MIN_PIXELS:
			continue
		var top := h
		var bottom := 0
		var left := w
		var right := 0
		for q in area:
			top = mini(top, q / w)
			bottom = maxi(bottom, q / w)
			left = mini(left, q % w)
			right = maxi(right, q % w)
		if mini(bottom - top, right - left) + 1 < FIRE_MIN_SPAN:
			continue
		var phase := int(fposmod(torches * 0.618034, 1.0) * 255.0)
		torches += 1
		for q in area:
			out[q * 4] = 255
			out[q * 4 + 1] = 255 if q / w < top + FIRE_TOP_ROWS else 0
			out[q * 4 + 2] = phase
			out[q * 4 + 3] = 255
	fx_torches = torches
	return ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out))


# Порывы ветра по времени кадра: порог шума деревьев плавно опускается за GUST_RAMP с и обратно.
func _update_fx(delta: float) -> void:
	if fx_vps.is_empty():
		return
	fx_bake_t -= delta
	if fx_bake_t <= 0.0:
		fx_bake_t = maxf(fx_bake_t + 1.0 / FX_RATE, 0.0)
		for vp in fx_vps:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if fx_trees_mat == null:
		return
	if fx_gust_left > 0.0:
		fx_gust_left -= delta
		if fx_gust_left <= 0.0:
			fx_gust_n += 1
			fx_gust_wait = lerpf(GUST_EVERY_MIN, GUST_EVERY_MAX, _fx_hash(fx_gust_n * 2))
	else:
		fx_gust_wait -= delta
		if fx_gust_wait <= 0.0:
			fx_gust_left = lerpf(GUST_LEN_MIN, GUST_LEN_MAX, _fx_hash(fx_gust_n * 2 + 1))
	var g := move_toward(fx_gust, 1.0 if fx_gust_left > 0.0 else 0.0, delta / GUST_RAMP)
	if g != fx_gust:
		fx_gust = g
		fx_trees_mat.set_shader_parameter("tree_calm", lerpf(TREE_CALM, TREE_GUST_CALM, g))


# Псевдослучайное 0..1 от целого (для порывов ветра).
func _fx_hash(k: int) -> float:
	return fposmod(sin(k * 12.9898 + 1.0) * 43758.5453, 1.0)


# Отладка масок эффектов: F2 (раскраска по ряду) в debug-сборке.
func _sync_fx_debug() -> void:
	var on := OS.is_debug_build() and color_mode == 1
	for mat in [fx_bg_mat, fx_trees_mat, fx_castle_mat]:
		if mat != null:
			mat.set_shader_parameter("debug_masks", on)
	fx_bake_t = 0.0   # слои перерисуются в ближайшем кадре


# Листва: CPUParticles2D со своим генератором; движение — по времени кадра, покачивание — в шейдере по TIME.
func _setup_leaves() -> void:
	var p := CPUParticles2D.new()
	p.amount = LEAF_AMOUNT
	p.lifetime = LEAF_LIFE_MAX
	p.lifetime_randomness = 1.0 - LEAF_LIFE_MIN / LEAF_LIFE_MAX
	p.preprocess = LEAF_LIFE_MAX   # поле с листьями с первого кадра
	p.position = Vector2(0.0, FIELD.y * 0.5)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1.0, FIELD.y * 0.5)
	p.direction = Vector2.RIGHT
	p.spread = LEAF_SPREAD
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = LEAF_SPEED_MIN
	p.initial_velocity_max = LEAF_SPEED_MAX
	p.scale_amount_min = LEAF_PX_MIN   # без текстуры частица — квадрат 1x1 px
	p.scale_amount_max = LEAF_PX_MAX
	var ramp := Gradient.new()   # случайная точка рампы на частицу; ступенчатая рампа — один из цветов LEAF_COLORS
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.offsets = PackedFloat32Array(range(LEAF_COLORS.size()).map(func(k: int) -> float: return float(k) / LEAF_COLORS.size()))
	ramp.colors = PackedColorArray(LEAF_COLORS)
	p.color_initial_ramp = ramp
	p.modulate.a = LEAF_ALPHA
	p.z_index = LEAF_Z
	var sh := Shader.new()
	sh.code = LEAF_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("amp", LEAF_SWAY_AMP)
	mat.set_shader_parameter("freq", LEAF_SWAY_FREQ)
	p.material = mat
	add_child(p)


# Спрайт карты: тексель (u, v) — тексель фона tx_offset + tx_scale * (u, v); фон — с нулевым сдвигом и масштабом 1.
func _map_sprite(path: String, tx_offset := Vector2.ZERO, tx_scale := Vector2.ONE) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = load(path)
	sp.centered = false
	_place_map_sprite(sp, tx_offset, tx_scale)
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sp


func _place_map_sprite(sp: Sprite2D, tx_offset: Vector2, tx_scale: Vector2) -> void:
	sp.scale = Vector2(BG_SCALE, BG_SCALE) * tx_scale
	sp.position = BG_OFFSET + tx_offset * BG_SCALE


# Положение и масштаб замка из data/layer_tuning.json; нет файла — значения по умолчанию, битый — они же с предупреждением.
func _load_layer_tuning() -> void:
	if not FileAccess.file_exists(layer_tuning_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(layer_tuning_path))
	var off = d.get("castle_offset") if d is Dictionary else null
	if not (off is Array and off.size() == 2 and (off[0] is float or off[0] is int) and (off[1] is float or off[1] is int)
			and _require_numbers(d, ["castle_scale_x", "castle_scale_y"], layer_tuning_path)):
		push_warning("%s: нужны castle_offset [x, y], castle_scale_x, castle_scale_y — взяты значения по умолчанию" % layer_tuning_path)
		return
	castle_offset = Vector2(off[0], off[1])
	castle_scale = Vector2(d["castle_scale_x"], d["castle_scale_y"])


func _save_layer_tuning() -> void:
	var f := FileAccess.open(layer_tuning_path, FileAccess.WRITE)
	if f == null:
		tune_msg = "не сохранено: %s (%s)" % [layer_tuning_path, error_string(FileAccess.get_open_error())]   # tr-skip: отладка или контекст лога
		return
	f.store_string(JSON.stringify({"castle_offset": [castle_offset.x, castle_offset.y],
		"castle_scale_x": castle_scale.x, "castle_scale_y": castle_scale.y}, "\t", false) + "\n")
	f.close()
	tune_msg = "сохранено в %s" % layer_tuning_path   # tr-skip: отладка или контекст лога


# Подгонка замка (только debug-сборка): F3 включает и выключает; во включённом режиме стрелки — сдвиг на TUNE_STEP
# текселя фона, Q/E — масштаб по обеим осям, Z/X — по x, C/V — по y (меньше/больше в 1 ± TUNE_SCALE_STEP раз), с Shift
# мельче; масштаб — от левого верхнего угла слоя; F4 — сохранить. Съеденная клавиша в игру не идёт; выключенный режим
# не забирает ничего, кроме F3 без Shift (раскраска по состоянию — Shift+F3). Симуляцию не трогает: только спрайт.
func _tune_key(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and OS.is_debug_build() and castle_sprite != null):
		return false
	var k: Key = event.keycode
	if k == KEY_F3 and not event.shift_pressed:
		if not event.echo:
			tune_on = not tune_on
			tune_msg = ""
			_tune_show()
		return true
	if not tune_on:
		return false
	var step := TUNE_STEP_FINE if event.shift_pressed else TUNE_STEP
	var ds := TUNE_SCALE_STEP_FINE if event.shift_pressed else TUNE_SCALE_STEP
	match k:
		KEY_LEFT:
			castle_offset.x -= step
		KEY_RIGHT:
			castle_offset.x += step
		KEY_UP:
			castle_offset.y -= step
		KEY_DOWN:
			castle_offset.y += step
		KEY_Q:
			castle_scale *= 1.0 - ds
		KEY_E:
			castle_scale *= 1.0 + ds
		KEY_Z:
			castle_scale.x *= 1.0 - ds
		KEY_X:
			castle_scale.x *= 1.0 + ds
		KEY_C:
			castle_scale.y *= 1.0 - ds
		KEY_V:
			castle_scale.y *= 1.0 + ds
		KEY_F4:
			if not event.echo:
				_save_layer_tuning()
		_:
			return false
	_place_map_sprite(castle_sprite, castle_offset, castle_scale)
	_tune_show()
	return true


func _tune_show() -> void:
	if tune_label == null:
		var layer := CanvasLayer.new()
		tune_label = Label.new()
		tune_label.position = Vector2(16, 40)
		tune_label.add_theme_constant_override("outline_size", FONTS.outline(6))
		tune_label.add_theme_color_override("font_outline_color", Color.BLACK)
		tune_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(tune_label)
		add_child(layer)
	tune_label.visible = tune_on
	tune_label.text = ("Подгонка замка (F3): смещение (%.2f, %.2f) текселей фона, масштаб x %.4f, y %.4f\n"   # tr-skip: отладка или контекст лога
		+ "стрелки — сдвиг 1 (Shift 0.25) · Q/E — масштаб -/+0.5%% (Shift 0.1%%) · Z/X — по x · C/V — по y · F4 — сохранить%s") % [   # tr-skip: отладка или контекст лога
		castle_offset.x, castle_offset.y, castle_scale.x, castle_scale.y, ("\n" + tune_msg) if tune_msg != "" else ""]


# Слой поверх юнитов (z FG_Z) с прозрачностью alpha; нет файла — null с предупреждением.
func _layer_sprite(path: String, tx_offset: Vector2, tx_scale: Vector2, alpha: float) -> Sprite2D:
	if not ResourceLoader.exists(path):
		push_warning("Нет слоя %s: рисуется без него" % path)
		return null
	var sp := _map_sprite(path, tx_offset, tx_scale)
	sp.z_index = FG_Z
	sp.modulate.a = alpha
	return sp


# Камера на центре поля, без отдаления при росте армии. Базовый зум camera_min_zoom(): поле закрывает весь экран
# (при 1920x1080 и поле 2208x1056 — по высоте, 1080/1056), центр зажат так, чтобы края вида не выходили за поле.
# Задача 27: зум = базовый × множитель игрока zoom_user (колесо, data/camera.json); множитель забега — из Game.
func _setup_camera() -> void:
	cam_cfg = _load_camera_cfg()
	var g := _game()
	zoom_user = clampf(float(g.camera_zoom_user) if g != null else 1.0, float(cam_cfg.zoom_user_min), float(cam_cfg.zoom_user_max))
	zoom_user_target = zoom_user
	camera = Camera2D.new()
	camera.zoom = Vector2.ONE * camera_min_zoom() * zoom_user
	camera.position = _camera_clamp(FIELD * 0.5, camera.zoom.x)
	add_child(camera)
	camera.make_current()


static func _load_camera_cfg(path := CAMERA_CFG) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var out := CAMERA_DEFAULTS.duplicate()
	if not d is Dictionary:
		push_warning("%s не читается: зум камеры по умолчанию" % path)
		return out
	for k in out:
		if d.get(k) is float or d.get(k) is int:
			out[k] = float(d[k])
		else:
			push_warning("%s: нет числа %s — %s" % [path, k, str(out[k])])
	if out.zoom_user_min > out.zoom_user_max or out.zoom_user_min <= 0.0 or out.zoom_step <= 1.0 or out.pan_sensitivity <= 0.0:
		push_warning("%s: пределы или шаг зума неверны — по умолчанию" % path)
		out = CAMERA_DEFAULTS.duplicate()
	if out.zoom_user_min < CAMERA_ZOOM_FLOOR:   # задача 28: дальше базового — чёрные поля за краем карты
		push_warning("%s: zoom_user_min %s меньше %s — взят %s" % [path, str(out.zoom_user_min), str(CAMERA_ZOOM_FLOOR), str(CAMERA_ZOOM_FLOOR)])
		out.zoom_user_min = CAMERA_ZOOM_FLOOR
		out.zoom_user_max = maxf(out.zoom_user_max, CAMERA_ZOOM_FLOOR)
	return out


# Точка мира под точкой экрана sp (px интерфейса, как event.position) без тряски (смещение камеры не учитывается).
func screen_to_world(sp: Vector2) -> Vector2:
	if camera == null:
		return sp
	return camera.position + (sp - _screen_size() * 0.5) / camera.zoom.x


# Колесо: steps щелчков (больше 0 — ближе) к точке экрана sp. Цель множителя — в пределах data; точка мира под sp
# остаётся под sp, пока идёт сглаживание (если центр не упрётся в край поля).
func zoom_by(steps: float, sp: Vector2) -> void:
	if camera == null:
		return
	zoom_user_target = clampf(zoom_user_target * pow(float(cam_cfg.zoom_step), steps), float(cam_cfg.zoom_user_min), float(cam_cfg.zoom_user_max))
	zoom_anchor_screen = sp
	zoom_anchor_world = screen_to_world(sp)
	_store_zoom()
	_hint_event("camera")


# Клавиша camera_zoom_reset: множитель 1, центр поля.
func zoom_reset() -> void:
	if camera == null:
		return
	pan_end()   # перетаскивание считалось от прежнего вида
	zoom_user_target = 1.0
	zoom_anchor_screen = _screen_size() * 0.5
	zoom_anchor_world = FIELD * 0.5
	_store_zoom()


func _store_zoom() -> void:
	var g := _game()
	if g != null:
		g.camera_zoom_user = zoom_user_target


# Кадр камеры: множитель сглаженно (в логарифме, скорость zoom_smooth) идёт к цели, центр — чтобы точка-якорь стояла под
# своей точкой экрана, зажат в поле. Базовый зум пересчитывается (окно могло смениться). Только отрисовка.
func _camera_frame(delta: float) -> void:
	if camera == null:
		return
	var base := camera_min_zoom()
	var moving := zoom_user != zoom_user_target
	if moving:
		var sm := float(cam_cfg.zoom_smooth)
		var a := 1.0 if sm <= 0.0 else 1.0 - exp(-sm * delta)
		zoom_user = exp(lerpf(log(zoom_user), log(zoom_user_target), a))
		if absf(zoom_user / zoom_user_target - 1.0) < 0.002:
			zoom_user = zoom_user_target
	var z := base * zoom_user
	if moving:
		camera.zoom = Vector2.ONE * z
		camera.position = _camera_clamp(zoom_anchor_world - (zoom_anchor_screen - _screen_size() * 0.5) / z, z)
		if pan_active:   # зум во время перетаскивания: дальше — от нового вида (якорь зума — курсор)
			pan_sp0 = zoom_anchor_screen
			pan_cam0 = camera.position
		queue_redraw()   # полосы сигнала, маркеры и подписи у курсора — в px экрана
	elif camera.zoom.x != z:
		camera.zoom = Vector2.ONE * z
		camera.position = _camera_clamp(camera.position, z)


# Задача 28: перетаскивание камеры зажатой средней кнопкой («берёшь карту рукой»). Нажатие над полем (не над панелью) —
# pan_begin; движение и отпускание ловит _input (до интерфейса: курсор над панелью или отпускание над ней перетаскивание
# не обрывают). Сдвиг 1:1, без сглаживания: точка мира под курсором остаётся под ним (pan_sensitivity 1.0), центр зажат в
# поле; упёрся в край — отсчёт заново, обратное движение сдвигает вид сразу. Работает при любом зуме и на паузе. Только отрисовка.
func pan_begin(sp: Vector2) -> void:
	if camera == null:
		return
	pan_active = true
	pan_sp0 = sp
	pan_cam0 = camera.position
	_hint_event("camera")


func pan_to(sp: Vector2) -> void:
	if not pan_active or camera == null:
		return
	var z := camera.zoom.x
	var want := pan_cam0 - (sp - pan_sp0) / z * float(cam_cfg.pan_sensitivity)
	camera.position = _camera_clamp(want, z)
	if camera.position != want:
		pan_sp0 = sp
		pan_cam0 = camera.position
	zoom_anchor_screen = sp   # идёт сглаживание зума — оно продолжается вокруг курсора
	zoom_anchor_world = screen_to_world(sp)
	queue_redraw()   # полосы сигнала и маркеры у края вида


func pan_end() -> void:
	pan_active = false


# Px экрана в px мира поверх базового зума: элементы интерфейса, нарисованные в мире (полосы у края, маркеры, подписи
# у курсора), делятся на множитель игрока — на экране того же размера при любом зуме.
func ui_k() -> float:
	return 1.0 / zoom_user


# Наименьший зум, при котором поле перекрывает экран целиком по обеим осям.
func camera_min_zoom() -> float:
	var vs := _screen_size()
	return maxf(vs.y / FIELD.y, vs.x / FIELD.x)


# Размер экрана в px интерфейса (база окна при stretch canvas_items); вне дерева — размер окна из настроек проекта.
func _screen_size() -> Vector2:
	if is_inside_tree():
		return get_viewport_rect().size
	return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))


# Центр камеры при зуме z: половина вида в мире не выходит за край поля (вид больше поля по оси — центр поля).
func _camera_clamp(c: Vector2, z: float) -> Vector2:
	var half := _screen_size() * 0.5 / z
	var out := c
	for a in 2:
		out[a] = FIELD[a] * 0.5 if half[a] * 2.0 >= FIELD[a] else clampf(c[a], half[a], FIELD[a] - half[a])
	return out


# Видимая часть поля в мировых координатах (для полос сигнала и маркеров у края экрана). Без камеры (бенчи без дерева) —
# экран VIEW_HALF_W x VIEW_HALF_H вокруг центра поля, как раньше.
func view_rect() -> Rect2:
	if camera == null:
		return Rect2(FIELD * 0.5 - Vector2(VIEW_HALF_W, VIEW_HALF_H), Vector2(VIEW_HALF_W, VIEW_HALF_H) * 2.0)
	var half := _screen_size() * 0.5 / camera.zoom
	return Rect2(camera.position - half, half * 2.0)


# Полоса HP ворот (всегда) и отладочные маркеры ворот и дороги (только при DEBUG_COLORS).
func _draw() -> void:
	if gate_hp_max > 0.0:
		var f := clampf(gate_hp / gate_hp_max, 0.0, 1.0)
		var bar := Rect2(GATE_POS + Vector2(-gate_half, -22.0), Vector2(gate_half * 2.0, 6.0))
		draw_rect(bar, Color(0.0, 0.0, 0.0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color.RED.lerp(Color.LIME_GREEN, f))
	drawn_gate_hp = gate_hp
	# Цели отрядов игрока: кружок цвета типа, у выбранного крупнее (и в релизе)
	for s in SQUAD_MAX:
		if squad_used[s] == 1 and squad_n[s] > 0 and squad_team[s] == 0:
			var r := 9.0 if _is_sel(s) else 5.0
			draw_arc(squad_target[s], r, 0.0, TAU, 24, type_color[squad_type[s]], 2.0)
	# Лицо отрядов игрока: шеврон у середины переднего ряда (у невыбранных полупрозрачный)
	for s in SQUAD_MAX:
		if squad_used[s] == 1 and squad_n[s] > 0 and squad_team[s] == 0:
			var f_dir := Vector2.from_angle(squad_angle[s])
			var f_lat := Vector2(-f_dir.y, f_dir.x)
			var fc := _front_centre(s) + f_dir * 6.0
			draw_colored_polygon(PackedVector2Array([fc + f_dir * 10.0, fc + f_lat * 5.0, fc - f_lat * 5.0]),
				Color(type_color[squad_type[s]], 1.0 if _is_sel(s) else 0.4))
	# Выбранные отряды: тонкий контур блока живых слотов цветом типа (у главного толще) и дальность стрельбы стрелков
	if sel_mask != 0:
		# границы слотов меняются только с составом и строем: проход по юнитам — когда изменился отпечаток строёв
		var key := 0.0
		for s in SQUAD_MAX:
			key += (squad_n[s] * 13.0 + squad_width[s] * 7.0 + squad_center_off[s].x * 1.3 + squad_center_off[s].y * 2.7
				+ squad_depth[s] * 0.37 + squad_front_x[s] * 0.11) * (s + 1)
		if key != sel_boxes_key or sel_boxes.is_empty():
			sel_boxes_key = key
			sel_boxes = _squad_boxes()
		for s in SQUAD_MAX:
			if not _is_sel(s) or squad_n[s] == 0:
				continue
			var sel_col := type_color[squad_type[s]]
			var outline := _live_block(s, sel_boxes, squad_pos[s])
			if outline.size() > 0:
				outline.append(outline[0])
				draw_polyline(outline, sel_col, 3.0 if s == sel_primary else 1.0)
			var ring := _range_ring_radius(s)
			if ring > 0.0:
				draw_arc(squad_pos[s], ring, 0.0, TAU, 96, Color(sel_col, 0.35), 1.0)
	# Рамка выбора (ЛКМ)
	if box_active and box_start.distance_to(box_cur) >= ui_layout.drag_min:
		var box_rect := Rect2(box_start, box_cur - box_start).abs()
		draw_rect(box_rect, Color(0.2, 1.0, 0.3, 0.12))
		draw_rect(box_rect, Color(0.2, 1.0, 0.3, 0.9), false, 1.0)
	# Предпросмотр расстановки (ПКМ): контур блока (красный, если блок не помещается и будет сдвинут или слишком
	# пересекается с другим своим отрядом и поставлен не будет), яркий передний ряд, стрелка лица, подпись.
	# Несколько выбранных: блок каждого отряда цветом типа, подпись — число отрядов и длина линии.
	if drag_active and drag_start.distance_to(drag_cur) < ui_layout.drag_min:
		_draw_ghosts()   # задача 26: ПКМ зажата, протяжки нет — копия блока там, куда отряд пойдёт по клику
	if drag_active and drag_start.distance_to(drag_cur) >= ui_layout.drag_min:
		var list := _order_list()
		if list.size() == 1:
			var g := _formation_geometry(list[0], drag_start, drag_cur, drag_flip)
			if g.n > 0:
				_draw_block_preview(type_color[squad_type[list[0]]], g.centre, g.front, g.angle, g.width, g.rows, g.adjusted or g.overlap >= 0)
				_draw_cursor_text(tr("HUD_PREVIEW_ONE") % [g.width, g.rows, g.n], Color.WHITE)
		elif list.size() > 1:
			var mg := _multi_geometry(list, drag_start, drag_cur, drag_flip)
			for it in mg.items:
				_draw_block_preview(type_color[squad_type[it.s]], it.centre, it.front, mg.angle, it.width, it.rows, mg.adjusted or not mg.fits or mg.overlap >= 0)
			_draw_cursor_text(tr("HUD_PREVIEW_MANY") % [list.size(), UNITS.dist_text(mg.length)], Color.WHITE)
	# Сигнал всплеска: пульсирующая золотая полоса вдоль края экрана и мигающий (2 Гц) треугольник 48 px у своей стороны
	var vr := view_rect()
	var view_lo := vr.position
	var view_size := vr.size
	var k := ui_k()   # задача 27: полосы и треугольники — в px экрана при любом зуме
	# Слои: мягкая красная полоса у края экрана своей стороны — 0.30 у края, плавно до 0 на 100 px вглубь (10 ступеней)
	for side in 3:
		var sa := _signal_alpha(side)
		if sa <= 0.0:
			continue
		for q in 10:
			var band := Rect2(view_lo + Vector2(0.0, q * 10.0 * k), Vector2(view_size.x, 10.0 * k))
			if side == SIDE_LEFT:
				band = Rect2(view_lo + Vector2(q * 10.0 * k, 0.0), Vector2(10.0 * k, view_size.y))
			elif side == SIDE_RIGHT:
				band = Rect2(view_lo + Vector2(view_size.x - (q + 1) * 10.0 * k, 0.0), Vector2(10.0 * k, view_size.y))
			draw_rect(band, Color(0.85, 0.12, 0.12, sa * (1.0 - q / 10.0)))
		if SIGNAL_ICONS_SHOWN and fmod(wave_t * 2.0, 1.0) < 0.5:
			var tri_at := _edge_point(side, vr)
			var tri_dir := Vector2.DOWN
			if side == SIDE_LEFT:
				tri_dir = Vector2.RIGHT
			elif side == SIDE_RIGHT:
				tri_dir = Vector2.LEFT
			var tri_lat := Vector2(-tri_dir.y, tri_dir.x) * 24.0 * k
			var tri_d := tri_dir * 24.0 * k
			draw_colored_polygon(PackedVector2Array([tri_at + tri_d, tri_at - tri_d + tri_lat, tri_at - tri_d - tri_lat]), Color(0.85, 0.12, 0.12, 0.95))
	for side in _burst_signals():
		var pulse := 0.5 + 0.5 * sin(wave_t * 2.0 * TAU)
		var strip := Rect2(view_lo, Vector2(view_size.x, 24.0 * k))
		var icon_at := _edge_point(side, vr)
		var icon_dir := Vector2.DOWN
		if side == SIDE_LEFT:
			strip = Rect2(view_lo, Vector2(24.0 * k, view_size.y))
			icon_dir = Vector2.RIGHT
		elif side == SIDE_RIGHT:
			strip = Rect2(view_lo + Vector2(view_size.x - 24.0 * k, 0.0), Vector2(24.0 * k, view_size.y))
			icon_dir = Vector2.LEFT
		draw_rect(strip, Color(1.0, 0.8, 0.2, 0.35 * pulse))
		if fmod(wave_t * 2.0, 1.0) < 0.5:
			var icon_lat := Vector2(-icon_dir.y, icon_dir.x) * 24.0 * k
			var icon_d := icon_dir * 24.0 * k
			draw_colored_polygon(PackedVector2Array([icon_at + icon_d, icon_at - icon_d + icon_lat, icon_at - icon_d - icon_lat]), Color(1.0, 0.8, 0.2, 0.95))
	# Разведка в передышке: у каждой активной стороны треугольник внутрь поля и состав (цвет типа, число)
	for mk in _recon_markers():
		var d: Vector2 = mk.dir
		var side_lat := Vector2(-d.y, d.x)
		draw_set_transform(mk.pos, 0.0, Vector2.ONE * k)   # маркер и состав — в px экрана от точки маркера (задача 27)
		draw_colored_polygon(PackedVector2Array([d * 16.0, -d * 8.0 + side_lat * 12.0, -d * 8.0 - side_lat * 12.0]), Color(1.0, 0.35, 0.25, 0.9))
		var items: Array = mk.items
		var x0 := -22.0 - items.size() * 78.0 if mk.side == SIDE_RIGHT else 22.0   # справа список идёт влево от маркера
		for q in items.size():
			var cell := Vector2(x0 + q * 78.0, -7.0)
			draw_rect(Rect2(cell, Vector2(14, 14)), type_color[items[q][0]])
			draw_string(ThemeDB.fallback_font, cell + Vector2(18.0, 13.0), "×%d" % items[q][1], HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONTS.px(18), Color.WHITE)
		draw_set_transform(Vector2.ZERO)
	if not DEBUG_COLORS:
		return
	draw_circle(GATE_POS, 8.0, Color(1.0, 0.85, 0.2, 0.8))
	var y := 0.0
	while y <= WALL_Y:
		draw_circle(Vector2(ROAD_X, y), 3.0, Color(1.0, 1.0, 1.0, 0.5))
		y += 60.0


const GHOST_BAD_COLOR := Color(1.0, 0.2, 0.2)   # призрак блока, если приказ не пройдёт (как красный контур предпросмотра строя)
var ghost_frame := -1   # кадр, в котором призрак последний раз нарисован (тесты)


# Блок предпросмотра: заливка и контур (bad — красный), яркий передний ряд, стрелка лица.
func _draw_block_preview(col: Color, c: Vector2, front: Vector2, angle: float, width: int, rows: int, bad: bool) -> void:
	var face := Vector2.from_angle(angle)
	var lat := Vector2(-face.y, face.x)
	var hw := (width - 1) * SLOT_SPACING * 0.5 + SLOT_SPACING * 0.5
	var hd := (rows - 1) * SLOT_SPACING * 0.5 + SLOT_SPACING * 0.5
	var box := PackedVector2Array([c - lat * hw + face * hd, c + lat * hw + face * hd, c + lat * hw - face * hd, c - lat * hw - face * hd])
	draw_colored_polygon(box, Color(col, 0.25))
	box.append(box[0])
	draw_polyline(box, Color(1.0, 0.2, 0.2, 0.9) if bad else Color(col, 0.7), 2.0)
	draw_line(front - lat * hw, front + lat * hw, col.lightened(0.5), 3.0)
	var tip := front + face * 30.0   # стрелка лица
	draw_line(front, tip, Color.WHITE, 2.0)
	draw_line(tip, tip - face * 8.0 + lat * 5.0, Color.WHITE, 2.0)
	draw_line(tip, tip - face * 8.0 - lat * 5.0, Color.WHITE, 2.0)


# Середина переднего ряда отряда в мире (по сетке слотов).
func _front_centre(s: int) -> Vector2:
	return squad_pos[s] + Vector2(squad_front_x[s], -squad_center_off[s].y).rotated(squad_angle[s])


# Радиус кольца дальности для отряда s: range_far, если это занятый непустой стреляющий отряд, иначе 0.
func _range_ring_radius(s: int) -> float:
	if squad_used[s] == 0 or squad_n[s] == 0:
		return 0.0
	return type_range_far[squad_type[s]]


# Общий загрузчик data/*.json: файл есть и JSON читается. При ошибке push_error и null.
func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Нет файла данных: %s" % path)
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		push_error("%s: битый JSON" % path)
	return data


# Все ключи есть и это числа. Значений по умолчанию нет: чего нет — ошибка.
func _require_numbers(d: Dictionary, keys: Array, where: String) -> bool:
	for key in keys:
		if not (d.get(key) is float or d.get(key) is int):
			push_error("%s: нет числового поля %s" % [where, key])
			return false
	return true


func _load_castle() -> bool:
	var d = _load_json(CASTLE_PATH)
	if d == null:
		return false
	if not d is Dictionary:
		push_error("%s: ожидается JSON-объект" % CASTLE_PATH)
		return false
	if not _require_numbers(d, ["gate_hp", "gate_half_width", "gate_damage_mult"], CASTLE_PATH):
		return false
	gate_hp_max = d.gate_hp
	gate_hp = gate_hp_max
	gate_half = d.gate_half_width
	gate_dmg_mult = d.gate_damage_mult
	return true


func _load_waves() -> bool:
	var d = _load_json(WAVES_PATH)
	if d == null:
		return false
	if not d is Dictionary:
		push_error("%s: ожидается JSON-объект" % WAVES_PATH)
		return false
	if not _require_numbers(d, ["count_base", "count_step", "count_cap", "hp_growth", "dmg_growth", "subwave_size",
			"subwave_interval", "max_alive", "spawn_center_x", "spawn_front_y", "spawn_columns", "spawn_spacing",
			"wave_bonus_gold", "gold_per_kill", "start_gold", "runner_from_wave", "runner_share_early", "runner_share", "sides_from_wave",
			"side_prob", "knight_from_wave", "knight_per_wave", "knight_cap", "spawn_left_x", "spawn_left_y", "spawn_right_x", "spawn_right_y",
			"burst_target_size", "burst_gap", "burst_gap_jitter", "burst_signal_lead", "burst_chunk", "burst_chunk_interval", "heal_base"], WAVES_PATH):
		return false
	if d.heal_base < 0.0 or d.heal_base > 1.0:
		push_error("%s: heal_base — доля потерянного HP от 0 до 1" % WAVES_PATH)
		return false
	var spread = d.get("hp_spread", 0.0)   # нет поля — разброса нет
	if not (spread is float or spread is int) or spread < 0.0 or spread >= 1.0:
		push_error("%s: hp_spread — число от 0 до 1 (не включая 1)" % WAVES_PATH)
		return false
	d.hp_spread = float(spread)
	if not d.get("layers") is Array or d.layers.size() != 3:
		push_error("%s: нет массива layers из трёх слоёв" % WAVES_PATH)
		return false
	for q in 3:
		var layer = d.layers[q]
		if not layer is Dictionary or not _require_numbers(layer, ["gap", "gap_jitter", "signal_lead", "pair_prob", "group_max", "side_weight_top", "side_weight_left",
				"side_weight_right", "sides_from_wave", "burst_target_size", "burst_count_min", "burst_count_max"], "%s, слой %d" % [WAVES_PATH, q + 1]):   # tr-skip: отладка или контекст лога
			if not layer is Dictionary:
				push_error("%s: слой %d не объект" % [WAVES_PATH, q + 1])
			return false
		if layer.side_weight_top < 0.0 or layer.side_weight_left < 0.0 or layer.side_weight_right < 0.0 \
				or layer.side_weight_top + layer.side_weight_left + layer.side_weight_right <= 0.0:
			push_error("%s, слой %d: веса сторон должны быть >= 0, а их сумма > 0" % [WAVES_PATH, q + 1])
			return false
	d.spawn_spacing = _scaled(d.spawn_spacing, SCALE_REL)
	wave_cfg = d
	return true


func _load_shop() -> bool:
	var d = _load_json(SHOP_PATH)
	if d == null:
		return false
	if not d is Dictionary:
		push_error("%s: ожидается JSON-объект" % SHOP_PATH)
		return false
	var param_key := {"inf_pack": "amount", "archer_pack": "amount", "weapons": "dmg_mult", "gate": "gate_max_gain", "spear_pack": "amount"}
	var n := SHOP_ITEMS.size()
	shop_label.resize(n)
	shop_base.resize(n)
	shop_growth.resize(n)
	shop_param.resize(n)
	shop_bought.resize(n)
	shop_bought.fill(0)
	shop_cap.resize(n)
	shop_enabled.resize(n)
	for k in n:
		var id: String = SHOP_ITEMS[k]
		var e = d.get(id)
		if not e is Dictionary:
			push_error("%s: нет товара %s" % [SHOP_PATH, id])
			return false
		var keys := ["base", "growth", param_key[id]]
		if id in ["inf_pack", "archer_pack", "spear_pack"]:
			keys.append("cap")
		if not _require_numbers(e, keys, "%s, товар %s" % [SHOP_PATH, id]):   # tr-skip: отладка или контекст лога
			return false
		if not e.get("label") is String:
			push_error("%s: у товара %s нет строкового поля label" % [SHOP_PATH, id])
			return false
		shop_label[k] = e.label
		shop_base[k] = e.base
		shop_growth[k] = e.growth
		shop_param[k] = e[param_key[id]]
		shop_cap[k] = e.get("cap", 0)   # только у отрядов; у остальных не используется
		shop_enabled[k] = 1 if e.get("enabled", true) else 0
		if id == "weapons":
			weapon_stat = String(e.get("stat", "damage"))
			if not weapon_stat in ["damage", "attack_rate"]:
				push_error("%s: товар weapons, stat %s — нужен damage или attack_rate" % [SHOP_PATH, weapon_stat])
				return false
	return true


# Название товара на текущем языке: ключ из shop.json с числом из его параметра (оружие — в процентах).
func _shop_title(k: int) -> String:
	var v := shop_param[k]
	return tr(shop_label[k]) % (roundi((v - 1.0) * 100.0) if SHOP_ITEMS[k] == "weapons" else roundi(v))


# Синглтон Game (каркас забега) или null: в бенчах и headless-скриптах автозагрузки нет.
func _game() -> Node:
	return get_node_or_null("/root/Game") if is_inside_tree() else null


# run.json: проверки те же, что в Game (общий загрузчик). Без синглтона слой остаётся debug_layer, забег без предела.
func _load_run() -> bool:
	var cfg: Dictionary = GAME_SCRIPT.load_run_cfg(run_path)
	if cfg.is_empty():
		return false
	waves_per_run = cfg.waves_per_run
	siege_count = cfg.siege_count
	game = _game()
	run_limit = RUN_LIMIT_ENABLED and game != null
	if game != null:
		debug_layer = game.siege
	return true


# Прежний рекорд в файле: в игре не вызывается (рекорды ведёт Game), оставлен для старых бенчей.
func _load_record() -> void:
	best_wave = 0
	if not FileAccess.file_exists(record_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(record_path))
	if d is Dictionary and (d.get("best_wave") is float or d.get("best_wave") is int):
		best_wave = int(d.best_wave)
	else:
		push_warning("%s испорчен, рекорд сброшен в 0" % record_path)


func _save_record() -> void:
	var f := FileAccess.open(record_path, FileAccess.WRITE)
	if f == null:
		push_warning("Не удалось записать рекорд в %s" % record_path)
		return
	f.store_string(JSON.stringify({"best_wave": best_wave}))
	f.close()


# --- Волны --------------------------------------------------------------------

# Дары: gifts.json и активный набор (Game.active_gifts или active_gifts бенча). Ошибка в файле или в наборе — остановка.
func _load_mods() -> bool:
	gift_defs = MODS.load_gifts(gifts_path)
	if gift_defs.is_empty():
		return false
	card_defs = CARDS.load_cards(cards_path)
	if card_defs.is_empty():
		return false
	card_rules = game.card_rules if game != null else (CARDS.load_rules(CARD_RULES_PATH) if card_pick_auto != "" else {})
	if game != null:
		active_gifts = game.active_gifts.duplicate()
	mods = MODS.new(gift_defs)
	_setup_war_cry()
	return _load_mods_sources()


# Клич Благодати: уровень из набора даров забега (Game.active_gifts или active_gifts бенча), параметры уровня из gifts.json.
func _setup_war_cry() -> void:
	war_cry_level = 0
	var d: Dictionary = gift_defs.get("war_cry", {})
	var lvl := int(active_gifts.get("war_cry", 0))
	if d.is_empty() or d.get("type", "") != "ability" or d.get("hidden", false) or lvl < 1 or lvl > d.levels.size():
		return
	var lv: Dictionary = d.levels[lvl - 1]
	var tps := Engine.physics_ticks_per_second
	war_cry_level = lvl
	war_cry_mult = 1.0 + lv.bonus_pct / 100.0
	war_cry_dur = roundi(lv.duration_s * tps)
	war_cry_cd = roundi(lv.cooldown_s * tps)


# Можно ли активировать клич сейчас: дар куплен, идёт бой, перезарядка прошла (исполнится на следующем тике).
func war_cry_can() -> bool:
	return war_cry_level > 0 and wave_state == WS_BATTLE and not paused and tick_counter + 1 >= war_cry_ready and not _orders_locked()


# Команда игрока или бота: активировать клич на ближайшем тике симуляции. Нельзя — false, ничего не меняется.
func request_war_cry() -> bool:
	if _orders_locked():
		return false   # командир пал: приказы до конца волны недоступны
	if not war_cry_can():
		return false
	war_cry_request = true
	return true


# Начало тика: план (воспроизведение), запрос, окончание действия. Активация на тике T: бонус на тиках T..T+dur-1, готов снова с T+cd.
func _tick_war_cry() -> void:
	while not war_cry_plan.is_empty() and war_cry_plan[0] <= tick_counter:
		war_cry_plan.pop_front()
		war_cry_request = true
	if war_cry_request:
		war_cry_request = false
		if wave_state == WS_BATTLE and tick_counter >= war_cry_ready:
			war_cry_until = tick_counter + war_cry_dur
			war_cry_ready = tick_counter + war_cry_cd
			war_cry_log.append(tick_counter)
			war_cry_uses += 1
			_sync_atk_mult()
	if war_cry_until >= 0:
		if tick_counter >= war_cry_until:
			_end_war_cry()
		else:
			war_cry_active_ticks += 1


func _end_war_cry() -> void:
	war_cry_until = -1
	_sync_atk_mult()


# Множитель скорости ударов и стрельбы отряда = скорость боя по условиям карточек x Клич Благодати (пока действует).
func _sync_atk_mult() -> void:
	var cry := war_cry_mult if war_cry_until >= 0 else 1.0
	for sq in SQUAD_MAX:
		squad_atk_speed_mult[sq] = squad_rate_mult[sq] * cry


# Новая волна: клич готов сразу (перезарядка между волнами сбрасывается).
func _reset_war_cry() -> void:
	_end_war_cry()
	war_cry_request = false
	war_cry_ready = 0


# Собрать модификаторы из списка источников — как Game.mod_sources, но с defs из gifts_path сцены.
func _load_mods_sources() -> bool:
	return mods.build_sources(_mod_sources())


func _mod_sources() -> Array:
	return [MODS.gifts_source(gift_defs, active_gifts), CARDS.source(card_defs, _cards())]


# Выбранные карточки забега: Game.run_cards или active_cards бенча.
func _cards() -> Array:
	return game.run_cards if game != null else active_cards


# Старт забега, до создания юнитов: запомнить базу типов и ворот, посчитать эффективные данные (_apply_wave_data), ворота полные.
func _apply_mods() -> void:
	base_type_hp = type_hp.duplicate()
	base_type_damage = type_damage.duplicate()
	base_type_arrow_dmg = type_arrow_dmg.duplicate()
	base_type_bounty = type_bounty_mult.duplicate()
	base_type_speed = type_speed.duplicate()
	base_type_cooldown = type_cooldown.duplicate()
	base_type_volley = type_volley_period.duplicate()
	base_type_range_far = type_range_far.duplicate()
	base_gate_hp_max = gate_hp_max
	gate_mult = 1.0
	type_cd_floor.resize(type_hp.size())
	type_cd_floor.fill(0.0)
	_apply_wave_data()
	gate_hp = gate_hp_max


# Эффективные данные волны = база + все активные модификаторы (дары и карточки), каждый раз от базы, не поверх прошлых:
# урон и стрелы (с покупками оружия в том же порядке, что _buy), HP, скорость, перезарядка и скорость удара, дальность лучников,
# HP зомби (enemy_hp), награда (общая и за рыцаря), ворота (с прибавками ремонта), доход. Тип игрока получает множители цели
# all_units и своей (infantry, archer). Изменился максимум HP типа — у живых юнитов этого типа HP сохраняет долю от максимума;
# изменилась скорость — скорость строя отряда этого типа меняется в той же пропорции. Без модификаторов все множители ровно 1.0
# и числа те же бит в бит. Вызывается при старте забега и в начале каждой волны (_prepare_wave).
# Числа считает _wave_data (без побочных эффектов) — ею же магазин показывает «до → после» покупки (задача 26).
func _apply_wave_data() -> void:
	var wd := _wave_data(shop_bought)
	var hp_new: PackedFloat32Array = wd.hp
	var speed_new: PackedFloat32Array = wd.speed
	type_cd_floor = wd.cd_floor
	for t in hp_new.size():
		if hp_new[t] != type_hp[t] and type_hp[t] > 0.0:
			var k: float = hp_new[t] / type_hp[t]
			for i in mini(count, unit_type.size()):   # при старте забега массивов юнитов ещё нет
				if unit_type[i] == t:
					hp[i] *= k
		if speed_new[t] != type_speed[t] and type_speed[t] > 0.0:
			for sq in SQUAD_MAX:
				if squad_used.size() > sq and squad_used[sq] == 1 and squad_type[sq] == t:
					squad_speed[sq] *= speed_new[t] / type_speed[t]
	type_hp = hp_new
	type_damage = wd.damage
	type_arrow_dmg = wd.arrow
	type_speed = speed_new
	type_cooldown = wd.cooldown
	type_volley_period = wd.volley
	type_range_far = wd.range_far
	type_bounty_mult = wd.bounty
	type_block_bonus = wd.block_bonus
	if wd.gate_mult != gate_mult:   # ворота — только при смене множителя: от базы с прибавками ремонта, текущее HP сохраняет долю
		var gmax: float = wd.gate_max
		if gate_hp_max > 0.0:
			gate_hp *= gmax / gate_hp_max
		gate_hp_max = gmax
		gate_mult = wd.gate_mult
	income_pct = mods.get_mult("income", "player") - 1.0
	income_flat = mods.value("income_flat", 0.0)


# Эффективные данные типов при покупках bought (shop_bought или его копия с лишней покупкой): база + модификаторы + покупки
# «Оружия» в том же порядке, что _buy. Ничего не меняет. Ключи: hp, damage, arrow, speed, cooldown, cd_floor, volley, range_far,
# bounty, block_bonus — массивы по типам; gate_mult, gate_max — множитель ворот и максимум от базы с прибавками ремонта.
func _wave_data(bought: PackedInt32Array) -> Dictionary:
	var names := {infantry_type: "infantry", archer_type: "archer", spearman_type: "spearman"}
	if hero_type >= 0:
		names[hero_type] = "hero"   # герой — юнит игрока: множители цели all_units и своей цели hero (карточки героя, задача 14)
	var hp_new := base_type_hp.duplicate()
	var dmg_new := base_type_damage.duplicate()
	var arrow_new := base_type_arrow_dmg.duplicate()
	var speed_new := base_type_speed.duplicate()
	var cd_new := base_type_cooldown.duplicate()
	var volley_new := base_type_volley.duplicate()
	var range_new := base_type_range_far.duplicate()
	var bounty_new := base_type_bounty.duplicate()
	for t in names:
		var dmg: float = mods.get_mult("damage", "all_units") * mods.get_mult("damage", names[t])
		dmg_new[t] *= dmg
		arrow_new[t] *= dmg
		hp_new[t] *= mods.get_mult("hp", "all_units") * mods.get_mult("hp", names[t])
		speed_new[t] *= mods.get_mult("speed", "all_units") * mods.get_mult("speed", names[t])
	var wk := SHOP_ITEMS.find("weapons")
	var wrate := 1.0   # «Оружие» на скорости боя: x dmg_mult за покупку пехоте, копейщикам и лучникам
	if weapon_stat == "attack_rate":
		for n in bought[wk]:
			wrate *= shop_param[wk]
	for n in (bought[wk] if weapon_stat == "damage" else 0):   # покупки оружия — после модификаторов, как в _buy
		dmg_new[infantry_type] *= shop_param[wk]
		dmg_new[spearman_type] *= shop_param[wk]
		arrow_new[archer_type] *= shop_param[wk]
	var enemy: float = mods.get_mult("enemy_hp", "enemy")
	for t in hp_new.size():
		if not names.has(t):
			hp_new[t] *= enemy
	# Скорость боя: проценты складываются — пехота: attack_speed + attack_rate (все, пехота); копейщики: attack_rate (все, пехота);
	# лучники: reload + attack_rate (все, лучники). Интервал удара = фактический / множитель, остаток переносится (type_cd_floor).
	var ar_all: bool = mods.has_key("attack_rate", "all_units")
	var rate_all: float = mods.get_mult("attack_rate", "all_units") - 1.0
	var w_on := wrate != 1.0
	var inf_on: bool = mods.has_key("attack_speed", "infantry") or ar_all or mods.has_key("attack_rate", "infantry") or w_on
	var inf_rate: float = (mods.get_mult("attack_speed", "infantry") + rate_all + (mods.get_mult("attack_rate", "infantry") - 1.0)) * wrate
	var spear_on: bool = ar_all or mods.has_key("attack_rate", "infantry") or w_on
	var spear_rate: float = (1.0 + rate_all + (mods.get_mult("attack_rate", "infantry") - 1.0)) * wrate
	var arch_on: bool = mods.has_key("reload", "archer") or ar_all or mods.has_key("attack_rate", "archer") or w_on
	var reload: float = (mods.get_mult("reload", "archer") + rate_all + (mods.get_mult("attack_rate", "archer") - 1.0)) * wrate
	var floor_new := type_cd_floor.duplicate()
	if inf_on:
		cd_new[infantry_type] = _cd_actual(base_type_cooldown[infantry_type]) / inf_rate
	if spear_on:
		cd_new[spearman_type] = _cd_actual(base_type_cooldown[spearman_type]) / spear_rate
	if arch_on:
		cd_new[archer_type] = _cd_actual(base_type_cooldown[archer_type]) / reload
	volley_new[archer_type] /= reload
	range_new[archer_type] *= mods.get_mult("range", "archer")
	floor_new[infantry_type] = -CD_CARRY if inf_on else 0.0
	floor_new[spearman_type] = -CD_CARRY if spear_on else 0.0
	floor_new[archer_type] = -CD_CARRY if arch_on else 0.0
	if hero_type >= 0:   # герой: attack_rate all_units и своей цели (карточка 42), «Оружие»; решает каждый тик — интервал без округления до 2 тиков, перенос до 1 тика
		var hero_on_rate: bool = ar_all or w_on or mods.has_key("attack_rate", "hero")
		var hero_rate: float = (1.0 + rate_all + (mods.get_mult("attack_rate", "hero") - 1.0)) * wrate
		cd_new[hero_type] = base_type_cooldown[hero_type] / hero_rate if hero_on_rate else base_type_cooldown[hero_type]
		floor_new[hero_type] = -1.0 / 30.0 if hero_on_rate else 0.0
	var bounty: float = mods.get_mult("bounty", "player")
	for t in bounty_new.size():
		bounty_new[t] *= bounty
	bounty_new[knight_type] *= mods.get_mult("bounty", "knight")
	var block_new := PackedFloat32Array()
	block_new.resize(hp_new.size())
	block_new.fill(0.0)
	for t in names:   # стат block: «все» и своя цель (пехота, копейщики)
		block_new[t] = mods.get_flat("block", "all_units") + mods.get_flat("block", names[t])
	var gm: float = mods.get_mult("gate_hp", "gate")
	var gk := SHOP_ITEMS.find("gate")
	var gmax: float = base_gate_hp_max * gm
	for n in bought[gk]:   # прибавки ремонта — после множителя, как в _buy
		gmax += shop_param[gk]
	return {"hp": hp_new, "damage": dmg_new, "arrow": arrow_new, "speed": speed_new, "cooldown": cd_new, "cd_floor": floor_new,
		"volley": volley_new, "range_far": range_new, "bounty": bounty_new, "block_bonus": block_new, "gate_mult": gm, "gate_max": gmax}


# Фактический интервал удара без модификатора: cooldown убывает шагами решения юнита (CD_CARRY = 2 тика) до 0 без переноса,
# и из-за float32 0.8 с — это 13 шагов (0.867 с), а не 12. С модификатором скорости удара интервал = этот фактический / множитель
# и остаток переносится (type_cd_floor), поэтому +12% к скорости дают в среднем +12% ударов, а не прыжок к ближайшему шагу.
func _cd_actual(cd: float) -> float:
	var c := PackedFloat32Array([cd])
	var steps := 0
	while c[0] > 0.0 and steps < 10000:
		c[0] = maxf(c[0] - CD_CARRY, 0.0)
		steps += 1
	return steps * CD_CARRY


# Множитель HP зомби при разбросе s: 1 + s * (2u − 1), u в [0, 1) — из целочисленного хэша (seed, волна, номер зомби в волне).
# Детерминирован и не трогает потоки ГСЧ симуляции; одинаковые аргументы — один и тот же множитель.
static func hp_spread_factor(s: float, seed: int, w: int, n: int) -> float:
	var h := (seed * 73856093) ^ (w * 19349663) ^ (n * 83492791)
	for k in 3:   # перемешивание в 32 битах
		h = (h ^ (h >> 16)) & 0xFFFFFFFF
		h = (h * 0x45D9F3B) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	var u := float(h & 0xFFFFFF) / 16777216.0
	return 1.0 + s * (2.0 * u - 1.0)


# Начало волны: модификаторы заново (карточки могли смениться в передышке), данные волны от базы, статы на лету,
# бесплатные юниты (grant_units_free) в первый отряд пехоты — до начала боя, с уже пересчитанным HP.
func _prepare_wave() -> void:
	_load_mods_sources()
	_apply_wave_data()
	_read_wave_mods()
	var free := int(mods.value("grant_units_free", 0.0))
	if free > 0:
		_squad_add_units(_first_squad_of(infantry_type), infantry_type, free)
	_prepare_cards()


# Условные (C) и особые (K vengeance) карточки на волну: список условий, численность отрядов на начало волны, павшие — с нуля.
func _prepare_cards() -> void:
	cond_cards = []
	vengeance = {}
	for r in _cards():
		var d: Dictionary = card_defs.get(r.id, {})
		if d.is_empty() or d.get("disabled", false):
			continue
		if d.kind == "C":
			cond_cards.append({"id": r.id, "cond": d.when.cond, "when": d.when, "mods": d.mods.filter(func(e): return not e.get("cost", false))})
		elif d.get("special", "") == "vengeance":
			vengeance = {"id": r.id, "per_unit_pct": float(d.per_unit_pct), "max_pct": float(d.max_pct)}
	for sq in SQUAD_MAX:
		squad_start_n[sq] = squad_n[sq] if squad_used[sq] == 1 else 0
	wave_fallen = 0
	squad_fallen.fill(0)
	_cards_off()
	squad_dmg_mult.fill(1.0)
	squad_taken_mult.fill(1.0)
	squad_speed_mult.fill(1.0)
	squad_rate_mult.fill(1.0)
	hero_taken_mult = 1.0
	_sync_atk_mult()


# Индикаторы карточек: условия и особые — выключены, бонус 0 (начало пересчёта, начало волны, передышка).
func _cards_off() -> void:
	card_state = {}
	for c in cond_cards:
		card_state[c.id] = {"on": false, "pct": 0.0}
	if not vengeance.is_empty():
		card_state[vengeance.id] = {"on": false, "pct": 0.0}


# Множители отрядов по условиям карточек (раз в COND_EVERY тиков боя и в начале волны; по тикам и состоянию симуляции, без ГСЧ).
# Проценты условий складываются; урон — 1 + сумма / 100 (и vengeance: +per_unit_pct за павшего, не больше max_pct), скорость — так же.
# Бонус к HP по условию — снижение получаемого урона 1 / (1 + x): HP юнитов на лету не переписывается.
func _update_card_conditions() -> void:
	if cond_cards.is_empty() and vengeance.is_empty() and not _any_hold_skill():
		return
	_cards_off()
	for sq in SQUAD_MAX:
		var d := 0.0
		var h := 0.0
		var sp := 0.0
		var bl := 0.0
		var ar := 0.0
		var skill := 0
		if squad_used[sq] == 1 and squad_n[sq] > 0 and squad_team[sq] == 0:
			if squad_start_n[sq] == 0:
				squad_start_n[sq] = squad_n[sq]
			var tname: String = {infantry_type: "infantry", archer_type: "archer", spearman_type: "spearman"}.get(squad_type[sq], "")
			if squad_order[sq] == ORDER_HOLD and type_hold_block[squad_type[sq]] > 0.0:   # навык «Стена щитов»
				bl += type_hold_block[squad_type[sq]]
				skill = 1
			for c in cond_cards:
				if c.cond == "hero_low":
					continue   # условие героя — ниже, не по отрядам
				var k := cond_factor(c.cond, c.when, sq)
				if k == 0.0:
					continue
				var st: Dictionary = card_state[c.id]
				st.on = true
				for e in c.mods:   # индикатор: бонус урона или скорости боя этой карточки в отряде (для ступеней — с их числом), наибольший по отрядам
					if (e.stat == "damage" and (e.target == "all_units" or e.target == tname)) or (e.stat == "attack_rate" and _rate_hits(e.target, tname)):
						st.pct = maxf(st.pct, e.value * k)
				for e in c.mods:
					if e.stat == "attack_rate":
						if _rate_hits(e.target, tname):
							ar += e.value * k
					elif e.target == "all_units" or e.target == tname:
						match e.stat:
							"damage":
								d += e.value * k
							"hp":
								h += e.value * k
							"speed":
								sp += e.value * k
							"block":
								bl += e.value * k
			if not vengeance.is_empty():
				var vp := minf(vengeance.per_unit_pct * wave_fallen, vengeance.max_pct)
				d += vp
				card_state[vengeance.id] = {"on": vp > 0.0, "pct": vp}
		squad_dmg_mult[sq] = 1.0 + d / 100.0
		squad_taken_mult[sq] = 1.0 / (1.0 + h / 100.0)
		squad_speed_mult[sq] = 1.0 + sp / 100.0
		squad_block_bonus[sq] = bl
		squad_skill_on[sq] = skill
		squad_rate_mult[sq] = 1.0 + ar / 100.0
	# Условие героя (hero_low, карточка 44): не по отрядам — множитель урона по герою; проценты damage_taken складываются.
	var ht := 0.0
	for c in cond_cards:
		if c.cond == "hero_low" and hero_idx >= 0 and hp[hero_idx] > 0.0 and hp[hero_idx] < c.when.frac * type_hp[hero_type]:
			card_state[c.id].on = true
			for e in c.mods:
				ht += e.value
	hero_taken_mult = maxf(1.0 + ht / 100.0, 0.0)
	_sync_atk_mult()


# Цель стата attack_rate для отряда типа tname: all_units — все; infantry — пехота и копейщики (удар ближнего боя); archer — лучники.
static func _rate_hits(target: String, tname: String) -> bool:
	return target == "all_units" or target == tname or (target == "infantry" and tname == "spearman")


# Есть ли отряд, у типа которого навык на «держать» (копейщики, «Стена щитов»): тогда условия считаются и без карточек.
func _any_hold_skill() -> bool:
	for sq in SQUAD_MAX:
		if squad_used[sq] == 1 and squad_n[sq] > 0 and type_hold_block[squad_type[sq]] > 0.0:
			return true
	return false


# Детерминированное «выпадение» дополнительного блока в [0, 1): хэш (тик, атакующий, цель), без ГСЧ симуляции.
static func block_roll(tick: int, i: int, j: int) -> float:
	var h := (tick * 73856093) ^ (i * 19349663) ^ (j * 83492791)
	for k in 3:
		h = (h ^ (h >> 16)) & 0xFFFFFFFF
		h = (h * 0x45D9F3B) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h & 0xFFFFFF) / 16777216.0


# Условие карточки для отряда sq: 0 — не выполнено, 1 — выполнено; lost_steps — число ступеней (0..max_steps).
func cond_factor(cond: String, w: Dictionary, sq: int) -> float:
	match cond:
		"hold":
			return 1.0 if squad_order[sq] == ORDER_HOLD else 0.0
		"retreat":
			return 1.0 if squad_order[sq] == ORDER_RETREAT else 0.0
		"gate_low":
			return 1.0 if gate_hp < w.frac * gate_hp_max else 0.0
		"squad_low":
			return 1.0 if squad_n[sq] < w.frac * squad_start_n[sq] else 0.0
		"wave_time":
			return 1.0 if wave_state == WS_BATTLE and wave_t < w.seconds else 0.0
		"gold_high":
			return 1.0 if gold_wave_start >= w.gold else 0.0
		"lost_steps":
			if squad_start_n[sq] <= 0:
				return 0.0
			var lost_pct := (squad_start_n[sq] - squad_n[sq]) * 100.0 / squad_start_n[sq]
			return float(clampi(floori(lost_pct / w.step_pct + 1e-9), 0, int(w.max_steps)))
		"hero_near":   # центр отряда (якорь — центр живых слотов) ближе hero_near_radius px (hero.json) к живому герою
			return 1.0 if hero_idx >= 0 and hp[hero_idx] > 0.0 and squad_pos[sq].distance_squared_to(pos[hero_idx]) < hero_near_r * hero_near_r else 0.0
	return 0.0


# Доля потерянного HP, которую свои юниты восстанавливают между волнами: heal_base из waves.json плюс стат heal (дары, карточки)
# процентными пунктами (+10 — это +0.10 доли, а не умножение базы), не больше 1.0 и не меньше 0.
func heal_fraction() -> float:
	return clampf(wave_cfg.heal_base + (mods.get_mult("heal", "player") - 1.0), 0.0, 1.0)


# Доля павших за волну, что возвращаются после неё: стат recover (+10 — 0.10), не меньше 0.
func recover_fraction() -> float:
	return maxf(mods.get_mult("recover", "player") - 1.0, 0.0)


# Конец побеждённой волны (до магазина): каждый свой отряд получает назад floor(павшие x доля + остаток) юнитов своего типа
# бесплатно с полным HP (выходят из ворот); дробный остаток копится в отряде на следующие волны. Отряд не больше, чем в начале
# волны. Отряд, погибший целиком (0 юнитов), не получает никого: созданный удаляется в начале передышки, его остаток пропадает.
func _recover_fallen() -> void:
	var frac := recover_fraction()
	if frac <= 0.0:
		return
	for s in SQUAD_MAX:
		if squad_used[s] == 0 or squad_team[s] != 0 or squad_fallen[s] == 0:
			continue
		if squad_n[s] == 0:
			squad_recover_carry[s] = 0.0
			continue
		squad_recover_carry[s] += squad_fallen[s] * frac
		var back := floori(squad_recover_carry[s] + 1e-9)   # 1e-9: 0.3 x 10 не должно дать 2
		squad_recover_carry[s] = maxf(squad_recover_carry[s] - back, 0.0)
		back = mini(back, squad_start_n[s] - squad_n[s])
		if back > 0:
			_squad_add_units(s, squad_type[s], back)
			wave_recovered += back


# Начало передышки после волны из pick_after_waves: тройка карточек (генератор забега), с интерфейсом — экран выбора.
func _offer_cards() -> void:
	if card_rules.is_empty() or not wave_number in card_rules.pick_after_waves:
		return
	var rng: RandomNumberGenerator = game.run_rng if game != null else bench_card_rng
	if rng == null:
		return
	pending_offer = CARDS.offer(card_defs, _cards(), card_rules, rng, hero_on)
	if card_screen != null and not pending_offer.is_empty():
		card_screen.open(pending_offer, card_defs, _cards().map(func(r): return card_defs[r.id].name_key))


# Выбрать карточку из тройки: запись (Game.pick_card или запись бенча), разовый эффект, экран закрыт. Не из тройки — false.
func choose_card(id: String) -> bool:
	if not id in pending_offer:
		return false
	var r: Dictionary
	if game != null:
		r = game.pick_card(id)
	else:
		r = CARDS.make_record(card_defs[id], bench_card_rng)
		active_cards.append(r)
	pending_offer = []
	if card_screen != null:
		if not card_screen.anim_on:   # задача 25: с анимацией экран закроется сам (closed -> _on_cards_closed)
			card_screen.visible = false
		banner.visible = banner_any and not banner_hidden and not _picking()
	if not r.is_empty():
		apply_on_pick(r)
		if r.has("result"):   # «Жертва ради победы»: что выпало — сразу строкой в HUD
			_say(tr("MSG_CARD_SPLIT") % [tr(card_defs[r.id].name_key), card_split_text(r)], 8.0)
	ui_t = 0.0
	return true


# Экран выбора закрылся (анимация закончилась или пропущена): баннер итога волны снова виден, HUD обновляется.
func _on_cards_closed() -> void:
	if banner != null:
		banner.visible = banner_any and not banner_hidden and not _picking()
	ui_t = 0.0


# Число для подписей карточек: 25, а не 25.0; 1.5 и 0.85 как есть.
static func num_text(v: float) -> String:
	return str(int(v)) if v == floorf(v) else String.num(v)


# Результат случайного эффекта карточки (random_split): «пехота ×1.5, лучники ×0.85».
func card_split_text(r: Dictionary) -> String:
	var sp: Dictionary = card_defs[r.id].on_pick.random_split
	return "%s ×%s, %s ×%s" % [tr(SPLIT_NAMES[r.result.good]), num_text(sp.good), tr(SPLIT_NAMES[r.result.bad]), num_text(sp.bad)]


# Строка карточки в HUD: название; результат случайного эффекта; бонус по ступеням или павшим (+15%), пока он есть.
func card_row_text(r: Dictionary) -> String:
	var t := tr(card_defs[r.id].name_key)
	if r.has("result"):
		t += " (%s)" % card_split_text(r)
	var st: Dictionary = card_state.get(r.id, {})
	var d: Dictionary = card_defs[r.id]
	if st.get("on", false) and (d.get("special", "") == "vengeance" or (d.has("when") and d.when.cond == "lost_steps")):
		t += " +%s%%" % num_text(snappedf(st.pct, 0.1))
	return t


# Подсказка к строке карточки: название, описание (без издержки), издержка, условие.
func card_tooltip(r: Dictionary) -> String:
	var d: Dictionary = card_defs[r.id]
	var desc := CARDS.fill_desc(tr(d.desc_key))
	var lines := [tr(d.name_key)]
	var at := desc.find(";")
	lines.append(desc if at < 0 else desc.left(at))
	if at >= 0:
		lines.append(tr("UI_CARD_TIP_COST") % desc.substr(at + 1).strip_edges())
	if d.has("when"):
		lines.append(tr("UI_CARD_TIP_COND") % cond_text(d.when))
	elif d.get("special", "") == "vengeance":
		lines.append(tr("UI_CARD_TIP_COND") % tr("COND_VENGEANCE"))
	if r.has("result"):
		lines.append(tr("UI_CARD_TIP_RESULT") % card_split_text(r))
	return "\n".join(lines)


func cond_text(w: Dictionary) -> String:
	match w.cond:
		"gate_low", "squad_low":
			return tr(COND_KEYS[w.cond]) % num_text(w.frac * 100.0)
		"wave_time":
			return tr(COND_KEYS[w.cond]) % num_text(w.seconds)
		"gold_high":
			return tr(COND_KEYS[w.cond]) % num_text(w.gold)
		"lost_steps":
			return tr(COND_KEYS[w.cond]) % num_text(w.step_pct)
		"hero_low":
			return tr(COND_KEYS[w.cond]) % num_text(w.frac * 100.0)
		"hero_near":
			return tr(COND_KEYS[w.cond]) % UNITS.dist_text(hero_near_r)
	return tr(COND_KEYS[w.cond])


# Список карточек в HUD: строки создаются при смене набора; текст, цвет и подсказка — по card_state (его пишет симуляция).
func _update_cards_ui() -> void:
	var recs := _cards()
	if cards_rows.size() != recs.size():
		for l in cards_rows:
			l.get_parent().queue_free()
		cards_rows.clear()
		for r in recs:
			var row := HBoxContainer.new()   # иконка карточки и название
			row.alignment = BoxContainer.ALIGNMENT_END
			row.add_theme_constant_override("separation", 6)
			var icon := ICONS.make(ICONS.of_card(r.id), 1)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(icon)
			var l := Label.new()
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.mouse_filter = Control.MOUSE_FILTER_STOP   # подсказка при наведении
			l.add_theme_font_size_override("font_size", FONTS.px(18))
			l.add_theme_color_override("font_outline_color", Color.BLACK)
			l.add_theme_constant_override("outline_size", FONTS.outline(5))
			row.add_child(l)
			cards_box.add_child(row)
			cards_rows.append(l)
	cards_label.visible = not recs.is_empty()
	for k in recs.size():
		var r: Dictionary = recs[k]
		var l: Label = cards_rows[k]
		var cond: bool = card_state.has(r.id)
		var on: bool = card_state.get(r.id, {}).get("on", false)
		l.text = ("● " if on else "") + card_row_text(r)
		l.add_theme_color_override("font_color", CARD_ON if on else (CARD_IDLE if cond or card_defs[r.id].has("when") else Color.WHITE))
		l.tooltip_text = card_tooltip(r)


# Разовый эффект выбранной карточки (on_pick): grant_units — столько пехоты в первый отряд пехоты сразу.
func apply_on_pick(r: Dictionary) -> void:
	var d: Dictionary = card_defs.get(r.id, {})
	if d.has("on_pick") and d.on_pick.has("grant_units"):
		_squad_add_units(_first_squad_of(infantry_type), infantry_type, int(d.on_pick.grant_units))


# Первый занятый отряд типа type (пехота — всегда есть отряд 0).
func _first_squad_of(type: int) -> int:
	for s in SQUAD_MAX:
		if squad_used[s] == 1 and squad_type[s] == type:
			return s
	return 0


# Статы волны «на лету» (Mods.value): разброс стрел и окно сигнала всплеска. Читаются при старте забега и в начале каждой волны,
# тик берёт готовые wave_spread и wave_signal_lead. Без модификаторов — те же числа, что в данных.
func _read_wave_mods() -> void:
	wave_spread = type_spread.duplicate()
	wave_spread[archer_type] = mods.value("spread", type_spread[archer_type])
	wave_signal_lead = mods.value("signal_window", _layer().signal_lead if bursts_layered else wave_cfg.burst_signal_lead)


# Дар на стартовые юниты: прибавка каждому стартовому отряду (процент от его числа — вниз, не меньше +1), юниты выходят из ворот, как купленные.
func _add_start_units() -> void:
	for s in START_SQUADS:
		var n: int = mods.get_count("start_units", "player", squad_n[s])
		if n > 0:
			_squad_add_units(s, squad_type[s], n)


func _wave_count(w: int) -> int:
	return mini(int(wave_cfg.count_cap), roundi(wave_cfg.count_base + wave_cfg.count_step * (w - 1)))


# Состав волны w: записи {type, side, count}, сумма count = _wave_count(w).
# Бегуны: доля runner_share_early на волнах [runner_from_wave, sides_from_wave), runner_share дальше.
# Рыцари с knight_from_wave: (w - knight_from_wave + 1) * knight_per_wave * 2, не больше knight_cap. Остальные — крестьяне.
# Стороны: верх всегда; с sides_from_wave левая и правая включаются с вероятностью side_prob каждая
# (свой генератор, seed = spawn_seed + w; обе выключены — включается случайная из двух).
# Бегуны идут на боковые стороны поровну (боковых нет — сверху); крестьяне и рыцари — по весам: верх 2, боковая 1.
func _plan_wave(w: int) -> Array:
	var total := _wave_count(w)
	var share := 0.0
	if w >= int(wave_cfg.sides_from_wave):
		share = wave_cfg.runner_share
	elif w >= int(wave_cfg.runner_from_wave):
		share = wave_cfg.runner_share_early
	var runners := mini(roundi(total * share), total)
	var knights := 0
	if w >= int(wave_cfg.knight_from_wave):
		knights = mini(mini(roundi((w - int(wave_cfg.knight_from_wave) + 1) * wave_cfg.knight_per_wave * 2.0), int(wave_cfg.knight_cap)), total - runners)
	var peasants := total - runners - knights
	var sides: Array[int] = []   # активные боковые стороны
	if w >= int(wave_cfg.sides_from_wave):
		var rng := RandomNumberGenerator.new()
		rng.seed = spawn_seed + w
		var left: bool = rng.randf() < wave_cfg.side_prob
		var right: bool = rng.randf() < wave_cfg.side_prob
		if not left and not right:
			if rng.randi() % 2 == 0:
				left = true
			else:
				right = true
		if left:
			sides.append(SIDE_LEFT)
		if right:
			sides.append(SIDE_RIGHT)
	var plan := []
	# крестьяне и рыцари: боковой стороне 1 часть из (2 + число боковых), верху — остальное
	for part in [[zombie_type, peasants], [knight_type, knights]]:
		var n: int = part[1]
		var each := roundi(n / float(2 + sides.size())) if not sides.is_empty() else 0
		_plan_add(plan, part[0], SIDE_TOP, n - each * sides.size())
		for side in sides:
			_plan_add(plan, part[0], side, each)
	# бегуны: поровну на боковые (лишний — первой), без боковых — сверху
	if sides.is_empty():
		_plan_add(plan, runner_type, SIDE_TOP, runners)
	else:
		var each_r := runners / sides.size()
		for q in sides.size():
			_plan_add(plan, runner_type, sides[q], each_r + (runners - each_r * sides.size() if q == 0 else 0))
	return plan


func _plan_add(plan: Array, type: int, side: int, n: int) -> void:
	if n > 0:
		plan.append({"type": type, "side": side, "count": n})


# Строка разведки для HUD: «Дальше: волна N · ↑ 150 · ← 60 · → 40 (бегуны 20, рыцари 4)».
func _plan_text() -> String:
	var by_side := [0, 0, 0]
	var runners := 0
	var knights := 0
	for r in wave_plan:
		by_side[r.side] += r.count
		if r.type == runner_type:
			runners += r.count
		elif r.type == knight_type:
			knights += r.count
	var text := tr("HUD_PLAN") % wave_plan_for
	for side in 3:
		if by_side[side] > 0:
			text += " · %s %d" % [SIDE_ARROWS[side], by_side[side]]
	var extra := PackedStringArray()
	if runners > 0:
		extra.append(tr("HUD_PLAN_RUNNERS") % runners)
	if knights > 0:
		extra.append(tr("HUD_PLAN_KNIGHTS") % knights)
	return text if extra.is_empty() else text + " (%s)" % ", ".join(extra)


# Точка значка стороны у края вида vr (сигнал всплеска, разведка). Без зума игрока (множитель 1) — как до задачи 27: верх —
# (spawn_center_x, 150), левая и правая — в 120 px от края экрана на высоте своей точки появления. С зумом отступы в px экрана
# (ui_k), точка не выходит за вид: верх — не выше 150 мира и не выше края вида, x и y зажаты в вид.
func _edge_point(side: int, vr: Rect2) -> Vector2:
	var k := ui_k()
	var p := Vector2(wave_cfg.spawn_center_x, 150.0)
	if side == SIDE_LEFT:
		p = Vector2(vr.position.x + 120.0 * k, wave_cfg.spawn_left_y)
	elif side == SIDE_RIGHT:
		p = Vector2(vr.end.x - 120.0 * k, wave_cfg.spawn_right_y)
	if zoom_user == 1.0:
		return p
	var m := 120.0 * k
	if side == SIDE_TOP:
		p.y = maxf(150.0, vr.position.y + 150.0 * k)
	p.x = clampf(p.x, vr.position.x + m, maxf(vr.end.x - m, vr.position.x + m))
	p.y = clampf(p.y, vr.position.y + m, maxf(vr.end.y - m, vr.position.y + m))
	return p


# Маркеры разведки (только в передышке): на сторону — точка у края, направление внутрь поля и состав [тип, число].
# Места — _edge_point.
func _recon_markers() -> Array:
	var out := []
	if not scout_shown or not waves_enabled or wave_state != WS_RESPITE:
		return out
	var vr := view_rect()
	var at := [_edge_point(SIDE_TOP, vr), _edge_point(SIDE_LEFT, vr), _edge_point(SIDE_RIGHT, vr)]
	var dirs := [Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT]
	for side in 3:
		var items := []
		for r in wave_plan:
			if r.side == side:
				items.append([r.type, r.count])
		if not items.is_empty():
			out.append({"side": side, "pos": at[side], "dir": dirs[side], "items": items})
	return out


# Всплески волны w по её плану: каждая сторона делит свои записи на ceil(всего на стороне / burst_target_size)
# порций поровну (остаток — первым порциям). Порции всех сторон перемешиваются (свой генератор,
# seed = spawn_seed + w * 7919); порция k начинается в burst_signal_lead + k * burst_gap ± burst_gap_jitter
# (первая — без разброса), но не раньше чем через 6 с после предыдущей.
# Результат: [{t_start, side, records [{type, count}]}]; сумма по всплескам равна плану по каждой паре (сторона, тип).
func _plan_bursts(w: int, plan: Array) -> Array:
	if bursts_layered:
		return _plan_bursts_layered(w, plan)
	var portions := []
	for side in 3:
		var total := 0
		for r in plan:
			if r.side == side:
				total += r.count
		if total == 0:
			continue
		var n_side := maxi(ceili(total / float(wave_cfg.burst_target_size)), 1)
		for q in n_side:
			var records := []
			for r in plan:
				if r.side == side:
					var part: int = r.count / n_side + (1 if q < r.count % n_side else 0)
					if part > 0:
						records.append({"type": r.type, "count": part})
			if not records.is_empty():
				portions.append({"t_start": 0.0, "side": side, "records": records})
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed + w * 7919
	for k in range(portions.size() - 1, 0, -1):   # перемешивание Фишера — Йетса
		var j := rng.randi_range(0, k)
		var tmp = portions[k]
		portions[k] = portions[j]
		portions[j] = tmp
	var prev := 0.0
	for k in portions.size():
		var t: float = wave_cfg.burst_signal_lead
		if k > 0:
			t = maxf(t + k * wave_cfg.burst_gap + rng.randf_range(-wave_cfg.burst_gap_jitter, wave_cfg.burst_gap_jitter), prev + 6.0)
		portions[k].t_start = t
		prev = t
	return portions


# Слой темпа: gap, сигнал, группы, веса сторон, размер и число всплесков (waves.json layers, номер debug_layer).
func _layer() -> Dictionary:
	return wave_cfg.layers[clampi(debug_layer, 1, 3) - 1]


# Всплески волны w по слою. Число N = clamp(ceil(всего / burst_target_size), burst_count_min, burst_count_max).
# Сторона каждого всплеска — взвешенный случайный выбор (свой генератор, seed = spawn_seed + w * 7919):
# верх допустим всегда, левая и правая — с волны sides_from_wave слоя. Крестьяне и рыцари делятся поровну между
# всеми всплесками (остаток — первым), бегуны — только между боковыми (боковых нет — между всеми).
# Группы: следующий всплеск присоединяется к текущей группе с вероятностью pair_prob, если его стороны в группе
# ещё нет и группа меньше group_max. Группа g стартует в signal_lead + g * gap ± gap_jitter (первая — без разброса),
# не раньше чем через max(2, 0.6 * gap) после предыдущей; всплески группы из нескольких — с разбросом ±0.3 с.
# Результат в порядке t_start: [{t_start, t_group, group, order (как выпал), side, records [{type, count}]}].
func _plan_bursts_layered(w: int, plan: Array) -> Array:
	var layer := _layer()
	var by_type := {}
	var total := 0
	for r in plan:
		by_type[r.type] = by_type.get(r.type, 0) + r.count
		total += r.count
	if total == 0:
		return []
	var n := clampi(ceili(total / float(layer.burst_target_size)), int(layer.burst_count_min), int(layer.burst_count_max))
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed + w * 7919
	var lateral_ok := w >= int(layer.sides_from_wave)
	var weights := [float(layer.side_weight_top), float(layer.side_weight_left) if lateral_ok else 0.0, float(layer.side_weight_right) if lateral_ok else 0.0]
	if weights[0] + weights[1] + weights[2] <= 0.0:
		weights[0] = 1.0   # все допустимые веса нулевые: остаётся верх
	var sides := PackedInt32Array()
	var lateral := 0
	for k in n:
		var x: float = rng.randf() * (weights[0] + weights[1] + weights[2])
		var side := SIDE_TOP
		if x >= weights[0]:
			side = SIDE_LEFT if x < weights[0] + weights[1] else SIDE_RIGHT
		sides.append(side)
		if side != SIDE_TOP:
			lateral += 1
	var bursts := []
	var lat_k := 0   # номер среди боковых всплесков
	for k in n:
		var records := []
		for type in [zombie_type, knight_type, runner_type]:
			var c: int = by_type.get(type, 0)
			var part := c / n + (1 if k < c % n else 0)
			if type == runner_type and lateral > 0:
				part = 0
				if sides[k] != SIDE_TOP:
					part = c / lateral + (1 if lat_k < c % lateral else 0)
			if part > 0:
				records.append({"type": type, "count": part})
		if sides[k] != SIDE_TOP:
			lat_k += 1
		if not records.is_empty():
			bursts.append({"t_start": 0.0, "t_group": 0.0, "group": 0, "order": bursts.size(), "side": sides[k], "records": records})
	# группы и время
	var group := 0
	var group_sides := []
	var group_first := 0
	var t_group: float = layer.signal_lead
	var min_step := maxf(2.0, 0.6 * layer.gap)
	for k in bursts.size():
		if k > 0:
			var join: bool = rng.randf() < layer.pair_prob
			if join and not group_sides.has(bursts[k].side) and group_sides.size() < int(layer.group_max):
				pass
			else:
				_spread_group(bursts, group_first, k, rng)
				group += 1
				group_sides = []
				group_first = k
				t_group = maxf(layer.signal_lead + group * layer.gap + rng.randf_range(-layer.gap_jitter, layer.gap_jitter), t_group + min_step)
		group_sides.append(bursts[k].side)
		bursts[k].group = group
		bursts[k].t_group = t_group
		bursts[k].t_start = t_group
	_spread_group(bursts, group_first, bursts.size(), rng)
	bursts.sort_custom(func(a, b): return a.t_start < b.t_start if a.t_start != b.t_start else a.group < b.group)
	return bursts


# Всплески одной группы [first, last) из нескольких сторон стартуют с разбросом ±0.3 с вокруг времени группы.
func _spread_group(bursts: Array, first: int, last: int, rng: RandomNumberGenerator) -> void:
	if last - first < 2:
		return
	for k in range(first, last):
		bursts[k].t_start = bursts[k].t_group + rng.randf_range(-0.3, 0.3)


# Ход волны по слою. Сигнал группы — за signal_lead до её времени (звук один раз на группу). Всплески стартуют
# по порядку t_start, когда пришло время и есть место по max_alive с учётом уже идущих; несколько всплесков могут
# появляться одновременно, каждый своей сеткой блока. Куски — по burst_chunk раз в burst_chunk_interval.
func _update_bursts_layered(delta: float) -> void:
	wave_t += delta
	var lead := wave_signal_lead
	while burst_signal_n < wave_bursts.size() and wave_t >= wave_bursts[burst_signal_n].t_group - lead:
		var g: int = wave_bursts[burst_signal_n].group
		var words := PackedStringArray()
		while burst_signal_n < wave_bursts.size() and wave_bursts[burst_signal_n].group == g:
			words.append(tr(SIDE_WORDS[wave_bursts[burst_signal_n].side]))
			burst_signal_n += 1
		if SIGNAL_TEXT_SHOWN:
			burst_msg = tr("HUD_BURST") % ", ".join(words)
			burst_msg_until = wave_t + 3.0
			ui_t = 0.0
		if signal_player != null:
			signal_player.play()
		queue_redraw()   # полоса появляется сразу
	while burst_idx < wave_bursts.size() and wave_t >= wave_bursts[burst_idx].t_start:
		var b: Dictionary = wave_bursts[burst_idx]
		var size := _burst_size(b)
		if zombie_alive + burst_pending + size > int(wave_cfg.max_alive) or count + burst_pending + size > MAX_UNITS:
			break   # нет места: ждёт, следующие — за ним
		b.state = 1
		b.started = wave_t
		b.rec = 0
		b.left = b.records[0].count
		b.placed = 0
		b.chunk_t = 0.0
		burst_pending += size
		burst_live += 1
		burst_idx += 1
		signal_redraw_until = wave_t + 0.7   # полоса держится 0.4 с после старта и гаснет за 0.2 с
	if burst_live == 0:
		return
	for k in burst_idx:
		var b: Dictionary = wave_bursts[k]
		if b.state != 1:
			continue
		b.chunk_t -= delta
		if b.chunk_t > 0.0:
			continue
		var room := int(wave_cfg.burst_chunk)
		while room > 0 and b.rec < b.records.size():
			var n := mini(room, b.left)
			_spawn_block(n, b.records[b.rec].type, b.side, b.placed)
			b.placed += n
			b.left -= n
			wave_remaining -= n
			burst_pending -= n
			room -= n
			if b.left == 0:
				b.rec += 1
				if b.rec < b.records.size():
					b.left = b.records[b.rec].count
		b.chunk_t = wave_cfg.burst_chunk_interval
		if b.rec >= b.records.size():
			b.state = 2
			burst_live -= 1


# Сила красной полосы сигнала у стороны side (0..0.30): горит с сигнала группы до 0.4 с после старта своего
# всплеска, затем гаснет за 0.2 с. Вне боя и без слоёв — 0.
func _signal_alpha(side: int) -> float:
	if not waves_enabled or not bursts_enabled or not bursts_layered or wave_state != WS_BATTLE:
		return 0.0
	var a := 0.0
	for k in burst_signal_n:
		var b: Dictionary = wave_bursts[k]
		if b.side != side:
			continue
		if b.state == 0:
			return 0.30
		var dt: float = wave_t - b.started
		if dt <= 0.4:
			return 0.30
		if dt < 0.6:
			a = maxf(a, 0.30 * (1.0 - (dt - 0.4) / 0.2))
	return a


func _burst_size(b: Dictionary) -> int:
	var n := 0
	for r in b.records:
		n += r.count
	return n


# Стороны, по которым сейчас дан сигнал: всплеск объявлен, но ещё не начал появляться. В передышке пусто.
func _burst_signals() -> Array:
	var out := []
	if not waves_enabled or not bursts_enabled or bursts_layered or wave_state != WS_BATTLE:
		return out
	for k in range(burst_idx + (1 if burst_active else 0), burst_signal_n):
		if not out.has(wave_bursts[k].side):
			out.append(wave_bursts[k].side)
	return out


# Ход волны всплесками. Сигнал — за burst_signal_lead секунд до t_start. Всплеск начинается, когда пришло его время
# и после него живых зомби будет не больше max_alive (нет места — ждёт, сигнал уже дан). Порция выходит кусками
# по burst_chunk юнитов раз в burst_chunk_interval; куски продолжают одну сетку блока своей стороны.
func _update_bursts(delta: float) -> void:
	wave_t += delta
	while burst_signal_n < wave_bursts.size() and wave_t >= wave_bursts[burst_signal_n].t_start - wave_signal_lead:
		burst_msg = tr("HUD_BURST") % tr(SIDE_WORDS[wave_bursts[burst_signal_n].side])
		burst_msg_until = wave_t + 3.0
		burst_signal_n += 1
		ui_t = 0.0   # надпись и иконка сразу
		if signal_player != null:
			signal_player.play()
	if not burst_active and burst_idx < wave_bursts.size() and wave_t >= wave_bursts[burst_idx].t_start:
		var size := _burst_size(wave_bursts[burst_idx])
		if zombie_alive + size <= int(wave_cfg.max_alive) and count + size <= MAX_UNITS:
			burst_active = true
			burst_rec = 0
			burst_rec_left = wave_bursts[burst_idx].records[0].count
			burst_placed = 0
			burst_chunk_t = 0.0
	if not burst_active:
		return
	burst_chunk_t -= delta
	if burst_chunk_t > 0.0:
		return
	var b: Dictionary = wave_bursts[burst_idx]
	var room := int(wave_cfg.burst_chunk)
	while room > 0 and burst_rec < b.records.size():
		var n := mini(room, burst_rec_left)
		_spawn_block(n, b.records[burst_rec].type, b.side, burst_placed)
		burst_placed += n
		burst_rec_left -= n
		wave_remaining -= n
		room -= n
		if burst_rec_left == 0:
			burst_rec += 1
			if burst_rec < b.records.size():
				burst_rec_left = b.records[burst_rec].count
	burst_chunk_t = wave_cfg.burst_chunk_interval
	if burst_rec >= b.records.size():
		burst_active = false
		burst_idx += 1
		queue_redraw()   # иконка этого всплеска гаснет


# Space в передышке: следующая волна. Сила зомби растёт с номером волны.
func _start_wave() -> void:
	if not waves_enabled or wave_state != WS_RESPITE or not pending_offer.is_empty():
		return   # пока карточка не выбрана, волна не начинается
	wave_number += 1
	wave_state = WS_BATTLE
	_set_paused(false)
	gold_wave_start = gold
	if wave_plan_for != wave_number:   # план строится в начале передышки; сюда — если номер волны сменили в обход
		wave_plan = _plan_wave(wave_number)
		wave_plan_for = wave_number
		wave_bursts = _plan_bursts(wave_number, wave_plan)
	wave_left.resize(wave_plan.size())
	wave_remaining = 0
	for k in wave_plan.size():
		wave_left[k] = wave_plan[k].count
		wave_remaining += wave_left[k]
	wave_hp_mult = 1.0 + wave_cfg.hp_growth * (wave_number - 1)
	team_dmg_mult[1] = 1.0 + wave_cfg.dmg_growth * (wave_number - 1)
	wave_kills = 0
	wave_kills_by_type.fill(0)
	wave_spawned = 0
	_prepare_wave()
	arrows_fired = 0   # в отладочной строке — за текущую волну
	arrows_hit = 0
	arrows_out_of_range = 0
	contact_tick = -1
	volleys_before_contact = 0
	arrows_before_contact = 0
	kills_by_arrows = 0
	subwave_timer = 0.0
	wave_t = 0.0
	_update_card_conditions()   # условия карточек — с первого тика волны
	_reset_war_cry()
	burst_idx = 0
	burst_signal_n = 0
	burst_active = false
	burst_pending = 0
	burst_live = 0
	signal_redraw_until = 0.0
	for b in wave_bursts:   # слои: состояние всплеска хранится в его записи
		b.state = 0
		b.started = -1.0
	arrivals_ring.resize(ARRIVALS_WINDOW)
	arrivals_ring.fill(0)
	arrivals_sum = 0
	arrivals_now = 0
	arrivals_10s_max = 0
	burst_msg = ""
	burst_msg_until = 0.0
	_show_banner("")
	queue_redraw()   # маркеры разведки скрываются


# Подволны: раз в subwave_interval по каждой записи плана появляется subwave_size * (count записи / вся волна)
# юнитов (не меньше 1, пока запись не исчерпана), если живых зомби после этого не больше max_alive.
# Волна пройдена: все появились и все убиты -> бонус, лечение армии, передышка.
func _update_waves(delta: float) -> void:
	if not waves_enabled or wave_state != WS_BATTLE:
		return
	if bursts_enabled:
		if bursts_layered:
			_update_bursts_layered(delta)
		else:
			_update_bursts(delta)
		if profile:   # отладка: максимум появившихся за любые 10 с
			var slot := tick_counter % ARRIVALS_WINDOW
			arrivals_sum += arrivals_now - arrivals_ring[slot]
			arrivals_ring[slot] = arrivals_now
			arrivals_now = 0
			arrivals_10s_max = maxi(arrivals_10s_max, arrivals_sum)
		if wave_remaining == 0 and zombie_alive == 0:
			_wave_cleared()
		return
	subwave_timer -= delta
	if wave_remaining > 0 and subwave_timer <= 0.0:
		var total := 0
		for r in wave_plan:
			total += r.count
		var batch := 0
		for k in wave_plan.size():
			batch += mini(maxi(roundi(wave_cfg.subwave_size * wave_plan[k].count / float(total)), 1), wave_left[k])
		if zombie_alive + batch <= int(wave_cfg.max_alive) and count + batch <= MAX_UNITS:
			var placed := [0, 0, 0]   # сколько уже поставлено на сторону в этой подволне: блоки записей идут друг за другом
			for k in wave_plan.size():
				var n := mini(maxi(roundi(wave_cfg.subwave_size * wave_plan[k].count / float(total)), 1), wave_left[k])
				if n > 0:
					var side: int = wave_plan[k].side
					_spawn_block(n, wave_plan[k].type, side, placed[side])
					placed[side] += n
					wave_left[k] -= n
			wave_remaining -= batch
			subwave_timer = wave_cfg.subwave_interval
	if wave_remaining == 0 and zombie_alive == 0:
		_wave_cleared()


# Блок появления: spawn_columns в ширину, ряды назад от переднего края. Сверху — как раньше (лицом вниз);
# слева и справа — тот же блок с центром переднего ряда в (spawn_left/right_x, y), лицом к HORDE_GOAL.
# first — с какого места блока начинать (если на этой стороне в подволне уже кто-то появился).
func _spawn_block(n: int, type: int, side: int, first: int) -> void:
	var cols := int(wave_cfg.spawn_columns)
	var sp: float = wave_cfg.spawn_spacing
	var lim := Vector2(FIELD.x, WALL_Y - 20.0)   # новые зомби в поле и не ниже WALL_Y - 20
	var centre := Vector2.ZERO
	var face := Vector2.DOWN
	if side != SIDE_TOP:
		centre = Vector2(wave_cfg.spawn_left_x, wave_cfg.spawn_left_y) if side == SIDE_LEFT else Vector2(wave_cfg.spawn_right_x, wave_cfg.spawn_right_y)
		face = (HORDE_GOAL - centre).normalized()
	var lat := Vector2(-face.y, face.x)
	for q in range(first, first + n):
		var col := q % cols
		var row := q / cols
		var p: Vector2
		if side == SIDE_TOP:
			p = Vector2(wave_cfg.spawn_center_x + (col - (cols - 1) * 0.5) * sp, wave_cfg.spawn_front_y - row * sp)
		else:
			p = centre + lat * ((col - (cols - 1) * 0.5) * sp) - face * (row * sp)
		p += Vector2(unit_rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER), unit_rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER))
		_spawn_zombie(p.clamp(Vector2.ZERO, lim), type)


# Новый юнит орды типа type в индекс count; cooldown рассинхронизирован по unit_rand.
func _spawn_zombie(p: Vector2, type: int) -> void:
	var i := count
	count += 1
	pos[i] = p
	prev_pos[i] = p
	vel[i] = Vector2.ZERO
	team[i] = 1
	unit_type[i] = type
	unit_squad[i] = -1
	unit_slot_idx[i] = -1
	unit_slot[i] = Vector2.ZERO
	unit_rand[i] = unit_rng.randf()
	unit_render_off[i] = _render_offset(i)
	hp[i] = type_hp[type] * wave_hp_mult
	if wave_cfg.hp_spread > 0.0:   # разброс HP: свой хэш (волна, номер зомби в волне, seed), не ГСЧ симуляции
		hp[i] *= hp_spread_factor(wave_cfg.hp_spread, spawn_seed, wave_number, wave_spawned)
	wave_spawned += 1
	arrivals_now += 1
	cooldown[i] = unit_rand[i] * type_cooldown[type]
	unit_state[i] = ST_IDLE
	unit_slot_changed_t[i] = -1000.0
	unit_anim_t[i] = 0.0
	unit_shot_t[i] = 0.0
	unit_dir[i] = 0
	zombie_alive += 1


# Состав убитых за волну: «убито: крестьяне 90, бегуны 20, рыцари 4» (типы без убитых не показываются).
func _kills_text() -> String:
	var parts := PackedStringArray()
	var names := ["MSG_KILLS_PEASANTS", "MSG_KILLS_RUNNERS", "MSG_KILLS_KNIGHTS"]
	var types := [zombie_type, runner_type, knight_type]
	for q in 3:
		if wave_kills_by_type[types[q]] > 0:
			parts.append(tr(names[q]) % wave_kills_by_type[types[q]])
	return "" if parts.is_empty() else tr("MSG_KILLS") % ", ".join(parts)


func _wave_cleared() -> void:
	_end_war_cry()   # в передышке клич не действует
	_cards_off()     # в передышке условия карточек не горят
	_stain_dry_start()   # кровь на земле подсыхает к следующей волне (только отрисовка)
	if run_limit and wave_number == waves_per_run:
		_on_win()   # последняя волна забега: передышки не будет
		return
	gold += wave_cfg.wave_bonus_gold
	wave_income = gold - gold_wave_start
	if income_pct != 0.0:
		gold += wave_income * income_pct   # доход (стат income) — в конце волны, до магазина передышки
	if income_flat != 0.0:
		gold += income_flat
	var heal := heal_fraction()
	for i in count:
		if team[i] == 0:
			if heal >= 1.0:
				hp[i] = type_hp[unit_type[i]]   # полное лечение
			else:
				hp[i] += (type_hp[unit_type[i]] - hp[i]) * heal   # возвращается доля heal потерянного HP
	if hero_dead:   # начало передышки: герой возрождается у ворот, управление возвращается
		hero_dead = false
		_spawn_hero(hero_cfg.revive_hp_fraction)
	wave_recovered = 0
	_recover_fallen()
	run_recovered += wave_recovered
	wave_state = WS_RESPITE
	_set_paused(false)
	_free_empty_squads()
	wave_plan = _plan_wave(wave_number + 1)   # состав и всплески следующей волны известны с начала передышки
	wave_plan_for = wave_number + 1
	wave_bursts = _plan_bursts(wave_plan_for, wave_plan)
	_offer_cards()
	_set_banner(_banner_wave_cleared.bind(_entry_text(wave_number), wave_number, wave_kills, int(wave_cfg.wave_bonus_gold)))
	queue_redraw()   # маркеры разведки

# --- Магазин ------------------------------------------------------------------

# Цена товара k: база с ростом за купленные, затем Mods.value по стату товара (SHOP_COST_STATS); без модификаторов — как есть.
func _price(k: int) -> float:
	return mods.value(SHOP_COST_STATS[k], shop_base[k] * (1.0 + shop_growth[k] * shop_bought[k]), SHOP_COST_TARGET[k])


# Отряд упёрся в cap: живых этого типа плюс покупка больше предела.
func _at_cap(k: int) -> bool:
	var type := -1
	match SHOP_ITEMS[k]:
		"inf_pack":
			type = infantry_type
		"archer_pack":
			type = archer_type
		"spear_pack":
			type = spearman_type
	if type < 0:
		return false
	var alive := 0
	for i in count:
		if unit_type[i] == type:
			alive += 1
	return alive + int(shop_param[k]) > shop_cap[k]


# Покупка только включённого товара (shop_enabled), в передышке, при достаточном золоте и не сверх cap. Возвращает, состоялась ли.
func _buy(k: int) -> bool:
	if shop_enabled[k] == 0:   # товар выключен в данных (копейщики в v1): клавиша не действует, отряд не создаётся
		return false
	if wave_state != WS_RESPITE or gold < _price(k) or _at_cap(k):
		return false
	var spear_sq := -1
	if SHOP_ITEMS[k] == "spear_pack":   # отряд копейщиков: выбранный или первый; нет — новый у ворот; нет свободного индекса — отказ
		spear_sq = _buy_target(spearman_type)
		if squad_type[spear_sq] != spearman_type or squad_used[spear_sq] == 0:
			spear_sq = _squad_create(0, spearman_type)
			if spear_sq < 0:
				_say(tr("MSG_NO_SQUAD_FOR_SPEARMEN"))
				return false
	var before := _flash_snapshot()   # задача 26: что изменится — подсветить
	gold_spent += _price(k)   # журнал забегов (только учёт)
	gold -= _price(k)
	shop_bought[k] += 1
	match SHOP_ITEMS[k]:
		"inf_pack":
			_squad_add_units(_buy_target(infantry_type), infantry_type, int(shop_param[k]))
		"archer_pack":
			_squad_add_units(_buy_target(archer_type), archer_type, int(shop_param[k]))
		"spear_pack":
			_squad_add_units(spear_sq, spearman_type, int(shop_param[k]))
		"weapons":
			if weapon_stat == "attack_rate":
				_apply_wave_data()   # скорость боя: интервалы удара и стрельбы заново от базы (с этой покупкой)
			else:
				type_damage[infantry_type] *= shop_param[k]
				type_damage[spearman_type] *= shop_param[k]   # оружие и копейщикам (удар ближнего боя)
				type_arrow_dmg[archer_type] *= shop_param[k]
		"gate":
			gate_hp_max = _gate_after_buy(gate_hp_max)   # фиксированная прибавка gate_max_gain
			gate_hp = gate_hp_max
	ui_t = 0.0   # обновить HUD и магазин сразу
	_flash_changes(before)
	_hint_event("buy")
	return true


# Куда идёт покупка юнитов типа type: в главный выбранный отряд, если он этого типа, иначе в первый занятый отряд типа
# (он есть всегда: 0 — пехота, 1 — лучники).
func _buy_target(type: int) -> int:
	if sel_primary >= 0 and squad_used[sel_primary] == 1 and squad_type[sel_primary] == type:
		return sel_primary
	for s in SQUAD_MAX:
		if squad_used[s] == 1 and squad_type[s] == type:
			return s
	return 0


# Новые юниты отряда выходят из ворот: временные уникальные slot_idx, затем одна перестройка.
# Пустой созданный отряд (индекс >= START_SQUADS) при первой покупке встаёт у ворот лицом вверх.
func _squad_add_units(s: int, type: int, n: int) -> void:
	var at_gate := s >= START_SQUADS and squad_n[s] == 0
	if at_gate:
		squad_center_off[s] = Vector2.ZERO
		squad_angle[s] = PLAYER_ANGLE
	for k in n:
		if count >= MAX_UNITS:
			break
		var i := count
		count += 1
		squad_n[s] += 1
		var p := Vector2(GATE_POS.x + unit_rng.randf_range(-20.0, 20.0), WALL_Y - 6.0)
		pos[i] = p
		prev_pos[i] = p
		vel[i] = Vector2.ZERO
		team[i] = squad_team[s]
		unit_type[i] = type
		unit_squad[i] = s
		unit_slot_idx[i] = TEMP_SLOT_BASE + k
		unit_slot[i] = Vector2.ZERO
		unit_rand[i] = unit_rng.randf()
		unit_render_off[i] = _render_offset(i)
		hp[i] = type_hp[type]
		cooldown[i] = 0.0
		unit_state[i] = ST_IDLE
		unit_slot_changed_t[i] = -1000.0
		unit_anim_t[i] = 0.0
		unit_shot_t[i] = 0.0
		unit_dir[i] = _nearest_dir(squad_angle[s])
	squad_dir_angle[s] = NAN
	_reflow_squad(s)
	if at_gate:
		squad_pos[s] = gate_spot(s)
		squad_target[s] = squad_pos[s]


# --- Отряды: создание, разделение, слияние (только в передышке) ---------------------

# Индекс отряда в исходное состояние: свободен, 0 юнитов, все поля по умолчанию.
func _squad_reset(s: int) -> void:
	squad_used[s] = 0
	squad_n[s] = 0
	squad_pos[s] = Vector2.ZERO
	squad_target[s] = Vector2.ZERO
	squad_angle[s] = PLAYER_ANGLE
	squad_team[s] = 0
	squad_stop_dist[s] = 0.0
	squad_width[s] = 1
	squad_rows[s] = 0
	squad_dirty[s] = 0
	squad_speed[s] = 0.0
	squad_center_off[s] = Vector2.ZERO
	squad_reflow_n[s] = 0
	squad_front_row[s] = 0
	squad_follow[s] = -1
	squad_ranged[s] = 0
	squad_type[s] = 0
	squad_volley_mode[s] = MODE_VOLLEY
	squad_volley_t[s] = 0.0
	squad_volley_fired[s] = 0
	squad_arrows_fired[s] = 0
	squad_mode_switches[s] = 0
	squad_depth[s] = 0.0
	squad_front_x[s] = 0.0
	squad_user_width[s] = 0
	squad_aspect[s] = Vector2.ONE
	squad_order[s] = ORDER_ATTACK
	squad_dir_angle[s] = NAN
	squad_fallen[s] = 0
	squad_recover_carry[s] = 0.0


# Новый пустой отряд по образцу отряда src (тип, команда, пропорция строя) в первом свободном индексе
# >= START_SQUADS; type >= 0 — другой тип юнитов (копейщики по образцу пехоты). Стоит у своей точки у ворот (gate_spot) лицом вверх,
# приказ «атака». Возвращает индекс или -1, если все заняты.
func _squad_create(src: int, type := -1) -> int:
	for s in range(START_SQUADS, SQUAD_MAX):
		if squad_used[s] == 1:
			continue
		_squad_reset(s)
		squad_used[s] = 1
		squad_type[s] = squad_type[src]
		squad_team[s] = squad_team[src]
		squad_ranged[s] = squad_ranged[src]
		squad_aspect[s] = squad_aspect[src]
		if type >= 0:
			squad_type[s] = type
		squad_speed[s] = 0.75 * type_speed[squad_type[s]]
		squad_width[s] = maxi(int(squad_aspect[src].x), 1)
		squad_pos[s] = gate_spot(s)
		squad_target[s] = squad_pos[s]
		return s
	return -1


func _say(text: String, secs := 3.0) -> void:
	hud_msg = text
	hud_msg_t = secs
	ui_t = 0.0   # показать сразу


# Освободить индекс отряда (не 0 и не 1; юнитов в нём уже нет). Из выбора он уходит.
func _squad_free(s: int) -> void:
	if s < START_SQUADS:
		return
	_squad_reset(s)
	_prune_sel()


# В начале передышки: созданные отряды без живых юнитов освобождаются.
func _free_empty_squads() -> void:
	for s in range(START_SQUADS, SQUAD_MAX):
		if squad_used[s] == 1 and squad_n[s] == 0:
			_squad_free(s)
	_update_squad_panel()


# N: новый пустой отряд того же типа, что главный выбранный; выбор переходит на него.
func _cmd_new_squad() -> bool:
	if _orders_locked():
		return false   # командир пал: приказы до конца волны недоступны
	if wave_state != WS_RESPITE:
		return false
	if sel_primary < 0:
		_say(tr("MSG_PICK_SQUAD"))
		return false
	var s := _squad_create(sel_primary)
	if s < 0:
		_say(tr("MSG_NO_FREE_SQUADS") % [SQUAD_MAX, SQUAD_MAX])
		return false
	_select_only(s)
	return true


# G: часть выбранного отряда уходит в новый отряд с той же командой, целью, углом, приказом и шириной строя;
# оба перестраиваются, выбор переходит на новый. Уходит k = clamp(floor(n * split_frac), 1, n - 1) юнитов:
# split_mode 0 и 1 — с наибольшей / наименьшей local.y (правые / левые), 2 и 3 — с наименьшей / наибольшей
# local.x (задние / передние ряды). В бою — только на паузе. Позиции юнитов не меняются. Выбран должен быть ровно один отряд.
func _cmd_split() -> bool:
	if _orders_locked():
		return false   # командир пал: приказы до конца волны недоступны
	if _run_over():
		return false
	if wave_state == WS_BATTLE and not paused:
		if PAUSE_ENABLED:
			_say(tr("MSG_PAUSE_FIRST") % SETTINGS.key_label("wave_start"))
		return false
	if sel_mask == 0 or sel_mask & (sel_mask - 1) != 0:
		_say(tr("MSG_PICK_ONE_SQUAD"))
		return false
	var s := sel_primary
	var n := squad_n[s]
	if squad_used[s] == 0 or n < 2:
		_say(tr("MSG_SQUAD_TOO_SMALL"))
		return false
	var t := _squad_create(s)
	if t < 0:
		_say(tr("MSG_NO_FREE_SQUADS") % [SQUAD_MAX, SQUAD_MAX])
		return false
	squad_order[t] = squad_order[s]
	squad_pos[t] = squad_pos[s]
	squad_angle[t] = squad_angle[s]
	squad_target[t] = squad_target[s]
	squad_user_width[t] = squad_user_width[s]
	squad_stop_dist[t] = squad_stop_dist[s]
	squad_width[t] = squad_width[s]   # старые slot_idx уходящих читаются в сетке исходного отряда
	squad_center_off[t] = squad_center_off[s]
	sort_keys.fill(0x7FFFFFFFFFFFFFFF)
	var m := 0
	for i in count:
		if unit_squad[i] == s:
			var local := (pos[i] - squad_pos[s]).rotated(-squad_angle[s])
			var v := local.y if split_mode < 2 else local.x
			sort_keys[m] = ((int(v * 16.0) + SORT_OFFSET) << 32) | i
			m += 1
	sort_keys.sort()
	var k := _split_count(n)
	# по возрастанию ключа: наибольшие в конце (режимы 0 и 3), наименьшие в начале (1 и 2)
	var first := n - k if split_mode == 0 or split_mode == 3 else 0
	for q in range(first, first + k):
		unit_squad[int(sort_keys[q] & 0xFFFFFFFF)] = t
	squad_n[s] = n - k
	squad_n[t] = k
	squad_dir_angle[t] = NAN
	_reflow_squad(s)
	_reflow_squad(t)
	_select_only(t)
	return true


# Сколько юнитов уходит при делении отряда из n: доля в целых процентах (шаг ползунка 5%), не меньше 1 и не больше n - 1.
func _split_count(n: int) -> int:
	return clampi(n * roundi(split_frac * 100.0) / 100, 1, n - 1)


func _set_split_frac(v: float) -> void:
	split_frac = clampf(v, 10.0, 90.0) / 100.0
	_update_split_ui()


# K и кнопка режима: кто уходит при делении.
func _next_split_mode() -> void:
	split_mode = (split_mode + 1) % SPLIT_MODE_NAMES.size()
	_update_split_ui()


func _update_split_ui() -> void:
	if split_label == null:
		return
	split_label.text = tr("HUD_SPLIT_SHARE") % roundi(split_frac * 100.0)
	split_mode_button.text = tr("HUD_SPLIT_SIDE") % [tr(SPLIT_MODE_NAMES[split_mode]), SETTINGS.key_label("split_side")]


# Пауза только в бою. При включении prev_pos = pos: после снятия юниты не отскакивают на долю тика назад.
func _set_paused(v: bool) -> void:
	v = v and PAUSE_ENABLED and wave_state == WS_BATTLE
	if v == paused:
		return
	paused = v
	hero_attack_latch = false   # нажатие J до паузы не исполняется после неё
	if paused:
		prev_pos = pos.duplicate()
	if pause_label != null:
		pause_label.visible = paused
		pause_dim.visible = paused
	_update_squad_panel()
	queue_redraw()


# Стрелки: выбранные отряды встают на пост у стороны side (SIDE_*; -1 — у ворот) лицом к ней. Один отряд — строем
# нынешней ширины; несколько — в одну линию длиной в сумму их ширин (_place_formation_multi).
# Приказ не меняется; проверки пересечения и границ поля — как при расстановке протяжкой.
func _cmd_side_post(side: int) -> bool:
	if _orders_locked():
		return false   # командир пал: приказы до конца волны недоступны
	var list := _order_list()
	if list.is_empty():
		return false
	var post := _side_post(side)
	var p: Vector2 = post[0]
	var v: Vector2 = post[1]
	var length := 0.0
	for s in list:
		length += maxf((squad_width[s] - 1) * SLOT_SPACING, SLOT_SPACING)
	var d := Vector2(-v.y, v.x) * length
	return _place_formation_multi(list, p - d * 0.5, p + d * 0.5)


# Пост у стороны: [точка, лицо]. Точка — на отрезке от ворот к точке появления стороны (доля SIDE_POST_T),
# лицо — к точке появления; для ворот (-1) — над воротами, лицом вверх.
func _side_post(side: int) -> Array:
	if side < 0:
		return [Vector2(GATE_POS.x, WALL_Y - GATE_POST_BACK), Vector2.UP]
	var sp := Vector2(wave_cfg.spawn_center_x, wave_cfg.spawn_front_y)
	if side == SIDE_LEFT:
		sp = Vector2(wave_cfg.spawn_left_x, wave_cfg.spawn_left_y)
	elif side == SIDE_RIGHT:
		sp = Vector2(wave_cfg.spawn_right_x, wave_cfg.spawn_right_y)
	var p := GATE_POS.lerp(sp, SIDE_POST_T)
	return [p, (sp - p).normalized()]


# M: выбранный отряд вливается в первый другой занятый отряд того же типа; его индекс освобождается,
# выбор переходит на целевой. Отряды 0 и 1 не освобождаются: если выбран один из них, другой вливается в него.
# Выбрано несколько отрядов одного типа: все вливаются в отряд с наименьшим индексом.
func _cmd_merge() -> bool:
	if _orders_locked():
		return false   # командир пал: приказы до конца волны недоступны
	if wave_state != WS_RESPITE:
		return false
	var srcs := _sel_list()
	if srcs.is_empty():
		return false
	var dst := -1
	if srcs.size() == 1:
		var src := srcs[0]
		for s in SQUAD_MAX:
			if s != src and squad_used[s] == 1 and squad_type[s] == squad_type[src]:
				dst = s
				break
		if dst < 0:
			_say(tr("MSG_NO_MERGE_PARTNER"))
			return false
		if src < START_SQUADS:
			srcs[0] = dst
			dst = src
	else:
		dst = srcs[0]
		for s in srcs:
			if squad_type[s] != squad_type[dst]:
				_say(tr("MSG_MERGE_SAME_TYPE"))
				return false
		srcs.remove_at(0)
	var k := 0
	for i in count:
		if unit_squad[i] != dst and unit_squad[i] in srcs:
			unit_squad[i] = dst
			unit_slot_idx[i] = TEMP_SLOT_BASE + k   # уникальные временные индексы: новые в конец
			k += 1
	for src in srcs:
		squad_n[dst] += squad_n[src]
		squad_n[src] = 0
		_squad_free(src)
	squad_dir_angle[dst] = NAN
	_reflow_squad(dst)
	_select_only(dst)
	return true


# Ворота пали: бой останавливается, итог уходит в Game, Enter — в хаб. Без синглтона (бенчи) рекордов нет, R — заново.
func _on_defeat() -> void:
	wave_state = WS_DEFEAT
	_set_paused(false)   # при поражении пауза недоступна
	set_physics_process(false)
	best_wave = maxi(best_wave, wave_number)
	if game == null:
		_set_banner(func(): _show_banner("", _ending_text(wave_number), tr("MSG_RESTART") % "R"))
		return
	game.end_run("loss", wave_number, run_kills, _run_stats())
	_set_banner(func():
		_show_banner("", _ending_text(wave_number), tr("END_DEFEAT_HINT") % [
			GAME_SCRIPT.roman(game.siege), game.records[game.siege].best_wave, SETTINGS.key_label("to_hub")])
		_show_radiance(game.last_run.radiance))
	_show_hub_button()


# Последняя волна забега пройдена: бой останавливается (как при поражении), итог уходит в Game, Enter — в хаб.
func _on_win() -> void:
	wave_state = WS_WIN
	_set_paused(false)   # при победе пауза недоступна
	set_physics_process(false)
	best_wave = maxi(best_wave, wave_number)
	game.end_run("win", wave_number, run_kills, _run_stats())
	_set_banner(func():
		_show_banner(tr("END_WIN_TITLE") % [wave_number, waves_per_run], tr(story_victories.get(debug_layer, "")),
			tr("END_TO_HUB_HINT") % SETTINGS.key_label("to_hub"))
		_show_radiance(game.last_run.radiance))
	_show_hub_button()
	queue_redraw()


func _run_over() -> bool:
	return wave_state == WS_DEFEAT or wave_state == WS_WIN


func _show_hub_button() -> void:
	if hub_button != null:
		hub_button.visible = true
		banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
		banner.position.y = BANNER_TOP


# Esc вне протяжки и рамки: меню паузы (дерево сцен встаёт на паузу: бой, окно сигнала и play_time стоят).
# Только с синглтоном Game: в бенчах выходить некуда.
func _open_esc_menu() -> void:
	if esc_menu != null and game != null:
		esc_menu.open("" if _run_over() else ESC_NOTE)


# «Выйти в меню» посреди забега: поражение с начислением Сияния, без экрана итога. В бою — на текущей волне,
# в передышке — на следующей (пройденные волны засчитаны все). Забег уже кончился — итог записан, повторно не пишется.
func _abandon_run() -> void:
	if game == null or _run_over():
		return
	var w := wave_number if wave_state == WS_BATTLE else wave_number + 1
	wave_state = WS_DEFEAT
	set_physics_process(false)
	game.end_run("loss", w, run_kills, _run_stats())


# Экран итога: строка «+N Сияния» между дневником и подсказкой (после _show_banner: он её прячет).
func _show_radiance(n: int) -> void:
	banner_radiance = tr("END_RADIANCE") % n
	if radiance_label == null:
		return
	radiance_label.text = banner_radiance
	radiance_label.visible = true
	if game != null and radiance_slot != null:   # окошко «Сияние» справа сверху: баланс после забега, под ним заработанное
		radiance_slot.visible = true
		radiance_slot.set_value(game.radiance)
		radiance_earned_label.text = banner_radiance
		radiance_earned_label.visible = true
		radiance_earned_label.reset_size()
		var r := radiance_slot.get_rect()
		radiance_earned_label.position = Vector2(r.end.x - radiance_earned_label.size.x, r.end.y + 4.0)
		cards_box.position.y = radiance_earned_label.position.y + radiance_earned_label.size.y + 4.0   # список карточек — ниже
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	banner.position.y = BANNER_TOP


# Экран конца забега: Enter, Space, R и кнопка «В хаб». Без синглтона (бенчи) — прежний перезапуск сцены.
func _to_hub() -> void:
	if not _run_over():
		return
	if game != null:
		game.go_hub()
	elif is_inside_tree():
		get_tree().reload_current_scene()


# Баннер: заголовок, текст, дневник (другим цветом), подсказка. Пустая часть скрыта; всё пусто — баннер скрыт.
func _show_banner(text: String, story := "", hint := "", title := "") -> void:
	banner_build = Callable()   # новый баннер: прежний сборщик больше не нужен (_set_banner ставит свой после вызова)
	banner_parts = PackedStringArray([title, text, story, hint])
	banner_radiance = ""
	if banner == null:
		return
	radiance_label.visible = false
	var any := false
	for k in banner_labels.size():
		banner_labels[k].text = banner_parts[k]
		banner_labels[k].visible = banner_parts[k] != ""
		any = any or banner_parts[k] != ""
	banner_any = any
	banner_hidden = false   # новый текст показывается, даже если прошлый скрыли клавишей H
	banner.visible = any and not _picking()
	# размер по содержимому, по центру сверху: иначе после длинного текста баннер остаётся высоким
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	banner.position.y = BANNER_TOP


# H в передышке: скрыть или показать баннер.
func _toggle_banner() -> void:
	if wave_state != WS_RESPITE:
		return
	banner_hidden = not banner_hidden
	if banner != null:
		banner.visible = banner_any and not banner_hidden and not _picking()


# Открыт экран выбора карточки: баннер итога волны ждёт выбора (не просвечивает сквозь экран).
func _picking() -> bool:
	return card_screen != null and card_screen.visible


# F вне протяжки: каждый выбранный отряд разворачивается «кругом» на месте (слоты в мире не двигаются).
func _cmd_about_face() -> bool:
	if _orders_locked():
		return false   # командир пал: приказы до конца волны недоступны
	var list := _order_list()
	for s in list:
		_about_face(s)
	queue_redraw()
	return not list.is_empty()


# Shift + колесо: каждый выбранный отряд поворачивается на месте на steps * 15° вокруг центра своих живых слотов
# (squad_pos). Цель отряда не меняется; при «отходе» команда игнорируется.
func _cmd_rotate(steps: int) -> bool:
	if _orders_locked():
		return false   # командир пал: приказы до конца волны недоступны
	var any := false
	for s in _order_list():
		if squad_order[s] == ORDER_RETREAT:
			continue
		squad_angle[s] = wrapf(squad_angle[s] + steps * ROTATE_STEP, -PI, PI)
		any = true
	queue_redraw()
	return any


# --- Дневник --------------------------------------------------------------------

# story.json: intro, entries [{id, siege, wave, text}], endings [{min_wave, text}], victories [{siege, text}].
# Проверки те же, что в Game (общий загрузчик); значений по умолчанию нет.
func _load_story() -> bool:
	var d: Dictionary = GAME_SCRIPT.load_story(story_path, siege_count)
	if d.is_empty():
		return false
	story_intro = d.intro
	story_entries = {}
	for e in d.entries:
		story_entries[Vector2i(e.siege, e.wave)] = {"id": e.id, "text": e.text}
	story_end_wave = d.end_wave
	story_end_text = d.end_text
	story_victories = d.victories
	return true


func _is_whole(v: Variant) -> bool:
	return (v is float or v is int) and v == floorf(v)


# Запись дневника после волны w текущей осады или "". С синглтоном запись показывается один раз: её id уходит в
# Game.diary_seen и сохраняется. Без синглтона (бенчи) — каждый раз.
func _entry_text(w: int) -> String:
	var e = story_entries.get(Vector2i(debug_layer, w))
	if e == null:
		return ""
	if game != null:
		if game.diary_read(e.id):
			return ""
		game.mark_diary(e.id)
	return e.text   # ключ перевода записи


# Баннер, собранный функцией build (тексты через tr): при смене языка build вызывается снова, скрытый (H) баннер
# остаётся скрытым.
func _set_banner(build: Callable) -> void:
	build.call()
	banner_build = build


# Итог волны в передышке: entry — ключ записи дневника или "".
func _banner_wave_cleared(entry: String, w: int, kills: int, bonus: int) -> void:
	var summary: String = tr("MSG_WAVE_CLEARED") % [w, kills, bonus, SETTINGS.key_label("wave_start"), w + 1]
	var killed := _kills_text()
	_show_banner(summary if killed == "" else summary + "\n" + killed, tr(entry) if entry != "" else "")


# Смена языка: баннер собрать заново (скрытый клавишей H остаётся скрытым), HUD и панели — сразу, не ждать таймера.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		pan_end()   # отпускание средней кнопки вне окна могло не прийти
	if what != NOTIFICATION_TRANSLATION_CHANGED:
		return
	if banner_build.is_valid():
		var build := banner_build
		var hidden := banner_hidden
		build.call()
		banner_build = build   # _show_banner его сбросил
		if hidden and banner != null:
			banner_hidden = true
			banner.visible = false
	if top_hud != null:
		top_hud.refresh()
		info_plan_for = -1   # строка разведки, подписи Клича и отрядов — заново на новом языке
		war_cry_sig = -1
		squad_text_sig.fill(-1)
		_update_split_ui()
		_update_squad_panel()
		_update_ui()


# Вступление для стартового баннера (ключ перевода): с синглтоном — только пока оно не прочитано. "" — баннер без дневника.
func _intro_text() -> String:
	if game != null:
		if game.diary_read(GAME_SCRIPT.INTRO_ID):
			return ""
		game.mark_diary(GAME_SCRIPT.INTRO_ID)
	return story_intro


# Концовка с наибольшим min_wave <= w; {wave} — день (номер волны).
func _ending_text(w: int) -> String:
	var best := -1
	for k in story_end_wave.size():
		if story_end_wave[k] <= w and (best < 0 or story_end_wave[k] > story_end_wave[best]):
			best = k
	return "" if best < 0 else tr(story_end_text[best]).replace("{wave}", str(w))


func _load_types() -> bool:
	var data = _load_json(UNIT_TYPES_PATH)
	if data == null:
		return false
	if not data is Array or data.is_empty():
		push_error("%s: ожидается непустой JSON-массив типов" % UNIT_TYPES_PATH)
		return false
	if hero_on:
		data.append(_hero_type_entry())   # тип героя — последним: номера типов из файла не сдвигаются
	var n: int = data.size()
	type_hp.resize(n)
	type_damage.resize(n)
	type_range_sq.resize(n)
	type_cooldown.resize(n)
	type_speed.resize(n)
	type_block_mult.resize(n)
	type_block_chance.resize(n)
	type_hold_block.resize(n)
	type_enabled.resize(n)
	type_leash_start.resize(n)
	type_leash_start_sq.resize(n)
	type_leash_end.resize(n)
	type_color.resize(n)
	type_range_far.resize(n)
	type_volley_period.resize(n)
	type_draw_time.resize(n)
	type_spread.resize(n)
	type_arrow_dmg.resize(n)
	type_label.resize(n)
	type_bounty_mult.resize(n)
	type_chase.resize(n)
	type_sprite.resize(n)
	type_recoil.resize(n)
	type_sprite_frames.resize(n)
	type_sprite_frames.fill(0)
	type_sprite_base.resize(n)
	type_sprite_base.fill(0)
	var ids := {}
	for t in n:
		var e = data[t]
		if not e is Dictionary or not e.get("name") is String:
			push_error("%s: тип #%d без поля name" % [UNIT_TYPES_PATH, t])
			return false
		if not _require_numbers(e, ["hp", "damage", "range", "cooldown", "speed", "block_mult", "leash_start", "leash_end",
				"range_far", "volley_period", "draw_time", "spread", "arrow_dmg", "bounty_mult", "chase", "recoil_px"], "%s, тип \"%s\"" % [UNIT_TYPES_PATH, e.name]):   # tr-skip: отладка или контекст лога
			return false
		if not e.get("label") is String:
			push_error("%s: у типа \"%s\" нет строкового поля label" % [UNIT_TYPES_PATH, e.name])
			return false
		if not e.get("sprite") is String:
			push_error("%s: у типа \"%s\" нет строкового поля sprite (\"\" = цветной квадрат)" % [UNIT_TYPES_PATH, e.name])
			return false
		if e.leash_end < e.leash_start:
			push_error("%s: у типа \"%s\" leash_end меньше leash_start" % [UNIT_TYPES_PATH, e.name])
			return false
		if not e.get("color") is String or not Color.html_is_valid(e.color):
			push_error("%s: у типа \"%s\" нет поля color с hex-цветом" % [UNIT_TYPES_PATH, e.name])
			return false
		if ids.has(e.name):
			push_error("%s: тип \"%s\" повторяется" % [UNIT_TYPES_PATH, e.name])
			return false
		ids[e.name] = t
		type_hp[t] = e.hp
		type_damage[t] = e.damage
		var rng_near := _scaled(e.range, SCALE_REL)
		type_range_sq[t] = rng_near * rng_near
		type_cooldown[t] = e.cooldown
		type_speed[t] = _scaled(e.speed, SPEED_REL)
		type_block_mult[t] = e.block_mult
		type_block_chance[t] = clampf(float(e.get("block_chance", 0.0)), 0.0, BLOCK_CAP)
		type_hold_block[t] = maxf(float(e.get("hold_block_bonus", 0.0)), 0.0)
		type_enabled[t] = 1 if e.get("enabled", true) else 0
		type_leash_start[t] = e.leash_start
		type_leash_start_sq[t] = e.leash_start * e.leash_start
		type_leash_end[t] = e.leash_end
		type_color[t] = Color.html(e.color)
		type_range_far[t] = _scaled(e.range_far, SCALE_REL)
		type_volley_period[t] = e.volley_period
		type_draw_time[t] = e.draw_time
		type_spread[t] = e.spread
		type_arrow_dmg[t] = e.arrow_dmg
		type_label[t] = e.label
		type_bounty_mult[t] = e.bounty_mult
		type_chase[t] = 1 if e.chase != 0 else 0
		type_sprite[t] = e.sprite
		type_recoil[t] = e.recoil_px
	type_id = ids   # заполняем только при полном успехе
	return true


# data/hero.json: числа и их пределы; hero_on — включён ли герой в этом бою (hero_mode, enabled, игровой режим).
func _load_hero() -> bool:
	hero_on = false
	var d = _load_json(hero_path)
	if d == null:
		return false
	if not d is Dictionary or not d.get("enabled") is bool or not d.get("auto_attack") is bool or not d.get("hold_repeat") is bool \
			or not d.get("label") is String or not (d.get("sprite_path", d.get("sprite")) is String) or not d.get("marker_color") is String \
			or not Color.html_is_valid(d.marker_color) or not d.get("arc_fx_color") is String or not Color.html_is_valid(d.arc_fx_color):
		push_error("%s: нужен JSON-объект с enabled, auto_attack, hold_repeat (bool), label, sprite_path, marker_color и arc_fx_color (hex)" % hero_path)
		return false
	if not _require_numbers(d, ["hp", "speed", "damage", "attack_interval", "arc_angle", "arc_range", "max_targets", "arc_fx_time",
			"revive_hp_fraction"], hero_path):
		return false
	if d.hp <= 0.0 or d.speed <= 0.0 or d.damage < 0.0 or d.attack_interval <= 0.0 or d.arc_range <= 0.0 or d.arc_angle <= 0.0 or d.arc_angle > 360.0 \
			or d.arc_fx_time <= 0.0 or not _is_whole(d.max_targets) or d.max_targets < 0 or d.revive_hp_fraction <= 0.0 or d.revive_hp_fraction > 1.0:
		push_error("%s: hp, speed, attack_interval, arc_range, arc_fx_time больше 0; arc_angle в (0, 360]; max_targets целое от 0 (0 — без лимита); revive_hp_fraction в (0, 1]" % hero_path)
		return false
	var nr = d.get("hero_near_radius", CARDS.HERO_NEAR_DEFAULT)
	if not (nr is float or nr is int) or nr <= 0.0:
		push_error("%s: hero_near_radius — число больше 0 (радиус условия hero_near карточки 45, px)" % hero_path)
		return false
	hero_near_r = float(nr)
	var rel = d.get("hero_screen_scale_rel", 1.0)
	if not (rel is float or rel is int) or rel <= 0.0:
		push_error("%s: hero_screen_scale_rel — число больше 0 (1.0 — герой на экране ростом с павшего рыцаря)" % hero_path)
		return false
	hero_cfg = d
	hero_on = hero_mode == 1 or (hero_mode == 0 and d.enabled and _game() != null)
	return true


# Запись типа героя в формате unit_types.json. speed (px/с) и arc_range (px) в hero.json — уже мировые: делятся на масштаб,
# чтобы _scaled вернул их как есть. Щита нет (block_mult 1.0), награды нет, ГСЧ и поводка нет.
func _hero_type_entry() -> Dictionary:
	return {"name": "hero", "label": hero_cfg.label, "hp": hero_cfg.hp, "damage": hero_cfg.damage, "range": hero_cfg.arc_range / SCALE_REL,
		"cooldown": hero_cfg.attack_interval, "speed": hero_cfg.speed / SPEED_REL, "block_mult": 1.0, "leash_start": 100000.0, "leash_end": 100000.0,
		"color": hero_cfg.marker_color, "range_far": 0.0, "volley_period": 0.0, "draw_time": 0.0, "spread": 0.0, "arrow_dmg": 0.0, "bounty_mult": 0.0,
		"chase": 1, "sprite": "", "recoil_px": 0.0}


# Герой — последним юнитом у ворот (HERO_SPAWN) с долей frac от HP типа. ГСЧ не трогает: unit_rand фиксирован, порядок
# случайных чисел остальных юнитов тот же.
func _spawn_hero(frac: float) -> void:
	if count >= MAX_UNITS:
		return
	var i := count
	count += 1
	hero_idx = i
	pos[i] = HERO_SPAWN
	prev_pos[i] = HERO_SPAWN
	vel[i] = Vector2.ZERO
	team[i] = 0
	unit_type[i] = hero_type
	unit_squad[i] = -1
	unit_slot_idx[i] = -1
	unit_slot[i] = Vector2.ZERO
	unit_rand[i] = 0.5
	unit_render_off[i] = Vector2.ZERO
	hp[i] = type_hp[hero_type] * frac
	cooldown[i] = 0.0
	unit_state[i] = ST_IDLE
	unit_slot_changed_t[i] = -1000.0
	unit_anim_t[i] = 0.0
	unit_shot_t[i] = 0.0
	unit_dir[i] = 0
	hero_face = 1.0
	hero_face_ang = -PI / 2.0   # вверх, к зомби


# Нода героя: спрайт (hero.json sprite_path; нет файла — квадрат цвета маркера), nearest. Высота кадра на экране — как у павшего
# рыцаря (KNIGHT_SPRITE_SCALE x SPRITE_PX) x hero_screen_scale_rel при любом размере кадра (_hero_sprite_scale).
func _setup_hero_view() -> void:
	hero_fx = Node2D.new()   # дуга удара: тот же слой, что герой (над юнитами, под замком и лесом), раньше в дереве — под спрайтом
	hero_fx.visible = false
	hero_fx.z_index = HERO_Z
	add_child(hero_fx)
	hero_fx.draw.connect(_draw_hero_fx)
	hero_view = Node2D.new()
	hero_view.visible = false
	hero_view.z_index = HERO_Z   # задача 28: под слоями замка и леса, как юниты (раньше LEAF_Z + 1 — над ними); закрытую часть показывает силуэт
	add_child(hero_view)
	hero_sprite = Sprite2D.new()
	var path: String = hero_cfg.get("sprite_path", hero_cfg.get("sprite"))
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if tex == null:
		push_warning("Спрайт героя %s не загрузился: герой рисуется квадратом" % path)
		var img := Image.create(SPRITE_PX, SPRITE_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color(hero_cfg.marker_color))
		tex = ImageTexture.create_from_image(img)
	hero_sprite.texture = tex
	hero_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hero_sprite.scale = _hero_sprite_scale(tex.get_height())
	_setup_hero_sheet(tex)
	hero_view.add_child(hero_sprite)
	hero_view.draw.connect(_draw_hero_marker)
	_setup_hero_occlusion()
	_setup_hit_fx()   # кровь и искры: тот же слой, позже героя — поверх него (попадания в 10–28 px, под спрайтом не видны); пятна — под юнитами


# Задача 28: силуэт героя поверх слоёв — тот же кадр спрайта ребёнком hero_sprite (позиция, поворот, масштаб — его), z HERO_OCC_Z,
# шейдер HERO_OCC_SHADER: однотонный hero_occlusion_color с hero_occlusion_alpha только в точках, где непрозрачен слой замка
# или леса (их текстуры и прямоугольники в мире — в шейдер). Открытый герой силуэта не получает: маска по точкам, не по
# прямоугольнику. Выключатель hero_occlusion_enabled (data/hero.json). Только отрисовка.
const HERO_OCC_DEFAULTS := {"hero_occlusion_enabled": true, "hero_occlusion_color": "#feae34", "hero_occlusion_alpha": 0.6}
const HERO_OCC_SHADER := """
shader_type canvas_item;
uniform vec4 occ_color : source_color;
uniform sampler2D layer0 : filter_nearest;
uniform sampler2D layer1 : filter_nearest;
uniform vec4 layer0_rect;   // xy — левый верхний угол слоя в мире, zw — размер; z = 0 — слоя нет
uniform vec4 layer1_rect;
uniform vec2 xf_x;   // преобразование ноды силуэта в мир (get_global_transform: оси и начало) — задаёт _sync_hero_occ
uniform vec2 xf_y;
uniform vec2 xf_o;
varying vec2 world;
void vertex() {
	world = xf_o + VERTEX.x * xf_x + VERTEX.y * xf_y;
}
float cover(sampler2D t, vec4 r) {
	if (r.z <= 0.0) return 0.0;
	vec2 uv = (world - r.xy) / r.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) return 0.0;
	return texture(t, uv).a;
}
void fragment() {
	float occ = max(cover(layer0, layer0_rect), cover(layer1, layer1_rect));
	COLOR = vec4(occ_color.rgb, occ_color.a * step(0.5, texture(TEXTURE, UV).a) * step(0.5, occ));
}
"""


func hero_occ_cfg() -> Dictionary:
	var out := HERO_OCC_DEFAULTS.duplicate()
	var on = hero_cfg.get("hero_occlusion_enabled", out.hero_occlusion_enabled)
	var col = hero_cfg.get("hero_occlusion_color", out.hero_occlusion_color)
	var a = hero_cfg.get("hero_occlusion_alpha", out.hero_occlusion_alpha)
	if not on is bool or not col is String or not Color.html_is_valid(col) or not (a is float or a is int) or a < 0.0 or a > 1.0:
		push_warning("%s: hero_occlusion_enabled (bool), hero_occlusion_color (hex), hero_occlusion_alpha (0..1) — взяты по умолчанию" % hero_path)
		return out
	return {"hero_occlusion_enabled": on, "hero_occlusion_color": col, "hero_occlusion_alpha": float(a)}


func _setup_hero_occlusion() -> void:
	var c := hero_occ_cfg()
	if not c.hero_occlusion_enabled or (trees_sprite == null and castle_sprite == null):
		return
	hero_occ = Sprite2D.new()
	hero_occ.texture = hero_sprite.texture
	hero_occ.hframes = hero_sprite.hframes
	hero_occ.vframes = hero_sprite.vframes
	hero_occ.offset = hero_sprite.offset
	hero_occ.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hero_occ.z_as_relative = false
	hero_occ.z_index = HERO_OCC_Z
	var sh := Shader.new()
	sh.code = HERO_OCC_SHADER
	hero_occ_mat = ShaderMaterial.new()
	hero_occ_mat.shader = sh
	var col := Color(c.hero_occlusion_color)
	col.a = c.hero_occlusion_alpha
	hero_occ_mat.set_shader_parameter("occ_color", col)
	var k := 0
	for sp in [trees_sprite, castle_sprite]:
		if sp != null:
			hero_occ_mat.set_shader_parameter("layer%d" % k, sp.texture)
		k += 1
	hero_occ.material = hero_occ_mat
	hero_sprite.add_child(hero_occ)
	_sync_hero_occ()


# Кадр силуэта — кадр спрайта; прямоугольники слоёв в мире (замок двигает подгонка F3).
func _sync_hero_occ() -> void:
	if hero_occ == null:
		return
	hero_occ.frame = hero_sprite.frame
	hero_occ.flip_h = hero_sprite.flip_h
	var xf := hero_occ.get_global_transform()
	hero_occ_mat.set_shader_parameter("xf_x", xf.x)
	hero_occ_mat.set_shader_parameter("xf_y", xf.y)
	hero_occ_mat.set_shader_parameter("xf_o", xf.origin)
	var k := 0
	for sp in [trees_sprite, castle_sprite]:
		var r := Vector4.ZERO
		if sp != null and sp.texture != null:
			var sz: Vector2 = sp.texture.get_size() * sp.scale
			r = Vector4(sp.position.x, sp.position.y, sz.x, sz.y)
		hero_occ_mat.set_shader_parameter("layer%d_rect" % k, r)
		k += 1


# Масштаб спрайта героя: кадр высотой frame_h px — на экране ростом с павшего рыцаря (KNIGHT_SPRITE_SCALE x SPRITE_PX px мира),
# умноженным на hero_screen_scale_rel (по умолчанию 1.0).
func _hero_sprite_scale(frame_h: float) -> Vector2:
	return Vector2.ONE * KNIGHT_SPRITE_SCALE * SPRITE_PX * float(hero_cfg.get("hero_screen_scale_rel", 1.0)) / frame_h


# Сетка и анимации спрайтшита из hero.json. Ошибка в данных — предупреждение и прежнее поведение (вся картинка, отражение).
func _setup_hero_sheet(tex: Texture2D) -> void:
	hero_anims = {}
	hero_rotate = false
	hero_anim = ""
	var nf = hero_cfg.get("frames", 1)
	if not (nf is float or nf is int) or nf <= 1:
		return
	var fw = hero_cfg.get("frame_w")
	var fh = hero_cfg.get("frame_h")
	var pv0 = hero_cfg.get("pivot")
	# Задача 28: кадр героя 24x24 (frame_w, frame_h, pivot). Картинка другого размера (не frames x frame_w по ширине или не
	# frame_h по высоте: прежний файл 104x26) — сетка из блока legacy, одно предупреждение за запуск.
	hero_sheet_legacy = false
	var leg = hero_cfg.get("legacy")
	if _is_whole(fw) and _is_whole(fh) and _is_whole(nf) and (tex.get_width() != int(nf) * int(fw) or tex.get_height() != int(fh)) and leg is Dictionary:
		fw = leg.get("frame_w")
		fh = leg.get("frame_h")
		pv0 = leg.get("pivot")
		hero_sheet_legacy = true
		if not hero_legacy_warned:
			hero_legacy_warned = true
			push_warning("%s: картинка героя %dx%d — не %d кадров %sx%s, взята прежняя сетка legacy (кадр %sx%s)" % [hero_path, tex.get_width(), tex.get_height(),
				int(nf), str(hero_cfg.frame_w), str(hero_cfg.frame_h), str(fw), str(fh)])
	var anims = hero_cfg.get("animations")
	var ok: bool = _is_whole(fw) and _is_whole(fh) and _is_whole(nf) and fw > 0 and fh > 0 and tex.get_width() % int(fw) == 0 \
		and tex.get_height() % int(fh) == 0 and int(nf) <= (tex.get_width() / int(fw)) * (tex.get_height() / int(fh)) \
		and anims is Dictionary and anims.get("idle") is Dictionary
	var parsed := {}
	if ok:
		for name in anims:
			var a = anims[name]
			var fr = a.get("frames") if a is Dictionary else null
			var fps = a.get("fps", 0.0) if a is Dictionary else null
			if not fr is Array or fr.is_empty() or not (fps is float or fps is int) or fps < 0.0 \
					or not fr.all(func(x): return _is_whole(x) and x >= 0 and x < nf):
				ok = false
				break
			parsed[name] = {"frames": PackedInt32Array(fr.map(func(x): return int(x))), "fps": float(fps)}
	var pv = (pv0 if pv0 != null else [fw / 2.0, fh / 2.0]) if ok else null
	ok = ok and pv is Array and pv.size() == 2 and pv.all(func(x): return x is float or x is int) and hero_cfg.get("orient", "flip") in ["flip", "rotate"]
	if not ok:
		push_warning("%s: сетка спрайтшита героя неверна (frame_w и frame_h делят картинку, frames не больше кадров, есть animations.idle, " % hero_path
			+ "кадры анимаций от 0 до frames - 1, fps от 0, pivot [x, y], orient flip или rotate): вся картинка, как раньше")
		return
	hero_sprite.hframes = tex.get_width() / int(fw)
	hero_sprite.vframes = tex.get_height() / int(fh)
	hero_sprite.offset = Vector2(fw / 2.0 - pv[0], fh / 2.0 - pv[1])   # точка pivot кадра — в позиции героя (кольцо, поворот)
	hero_sprite.scale = _hero_sprite_scale(fh)
	hero_rotate = hero_cfg.get("orient") == "rotate"
	hero_anims = parsed
	_hero_play("idle")


# Кадр анимации name через t с её начала: attack — все кадры на одну вспышку удара (доля t от arc_fx_time), остальные — fps по кругу.
func _hero_frame(name: String, t: float) -> int:
	var a: Dictionary = hero_anims[name]
	var fr: PackedInt32Array = a.frames
	var k := 0
	if name == "attack":
		k = mini(int(t / float(hero_cfg.arc_fx_time) * fr.size()), fr.size() - 1)
	elif a.fps > 0.0:
		k = int(t * a.fps) % fr.size()
	return fr[k]


# Анимация name (нет в данных — idle) с текущим кадром; смена анимации — с её первого кадра.
func _hero_play(name: String) -> void:
	if not hero_anims.has(name):
		name = "idle"
	if name != hero_anim:
		hero_anim = name
		hero_anim_t = 0.0
	hero_sprite.frame = _hero_frame(hero_anim, hero_anim_t)


# Задача 28: радиус кольца в px мира — HERO_RING_PX экрана при базовом зуме, умноженный на hero_screen_scale_rel: растёт с героем
# (размер кадра на него не влияет — рост героя на экране задаёт hero_screen_scale_rel) и с зумом игрока, как спрайт.
func hero_ring_radius() -> float:
	var base := camera_min_zoom() if camera != null else 1.0
	return HERO_RING_PX * float(hero_cfg.get("hero_screen_scale_rel", 1.0)) / base


# Кольцо цвета маркера (Endesga 32, hero.json marker_color) с тёмной обводкой и полоса HP под ним; толщина и радиус
# делятся на зум — на экране одного размера при любом зуме (радиус — hero_ring_radius, с героем). Рисуется под спрайтом (своя отрисовка ноды раньше дочерних).
func _draw_hero_marker() -> void:
	var z := camera.zoom.x if camera != null else 1.0
	var r := hero_ring_radius()
	var dark := Color("#181425")
	hero_view.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, dark, 5.0 / z)
	hero_view.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(hero_cfg.marker_color), 3.0 / z)
	if hero_idx < 0:
		return
	var f := clampf(hp[hero_idx] / type_hp[hero_type], 0.0, 1.0)
	var top := Vector2(-r, r + 4.0 / z)
	var size := Vector2(2.0 * r, 4.0 / z)
	hero_view.draw_rect(Rect2(top - Vector2.ONE / z, size + Vector2.ONE * 2.0 / z), dark)
	hero_view.draw_rect(Rect2(top, Vector2(size.x * f, size.y)), Color("#63c74d") if f > 0.35 else Color("#e43b44"))


# Каждый кадр: позиция между тиками (как у юнитов), взгляд по последнему движению; пал — нода скрыта. Спрайтшит: удар — пока
# идёт вспышка, иначе ходьба, если герой сдвинулся за тик, иначе покой; orient rotate — поворот по взгляду (во время удара — по удару).
# delta — время кадра (на паузе 0: анимация стоит).
func _update_hero_view(frac: float, have_prev: bool, delta := 0.0) -> void:
	hero_view.visible = hero_idx >= 0
	if hero_idx < 0:
		return
	var h := hero_idx
	hero_view.position = prev_pos[h].lerp(pos[h], frac) if have_prev else pos[h]
	hero_fx.position = hero_view.position
	if hero_fx_age >= 0.0:   # выпад: вперёд по направлению удара, к концу вспышки — на место
		hero_view.position += Vector2.from_angle(hero_fx_ang) * HERO_LUNGE_PX * (1.0 - hero_fx_age / float(hero_cfg.arc_fx_time))
	if hero_anims.is_empty():
		hero_sprite.flip_h = hero_face < 0.0
	else:
		hero_anim_t += delta
		var moving := have_prev and prev_pos[h].distance_squared_to(pos[h]) > 0.01
		_hero_play("attack" if hero_fx_age >= 0.0 else ("walk" if moving else "idle"))
		if hero_rotate:
			hero_sprite.rotation = hero_fx_ang if hero_fx_age >= 0.0 else hero_face_ang
		else:
			hero_sprite.flip_h = hero_face < 0.0
	_sync_hero_occ()
	var key := Vector2(hp[h], camera.zoom.x if camera != null else 1.0)
	if key != hero_drawn:
		hero_drawn = key
		hero_view.queue_redraw()


# Кадр эффектов удара (до записи буфера MultiMesh): новый удар (hero_swing_n) — вспышка, звук, мигание задетых; вспышка живёт
# arc_fx_time по времени кадра. Мигание — custom.y ячеек задетых зомби (в тот же индекс и рядом с позицией удара: после _remove_dead
# на индекс мог встать другой юнит), через HIT_FLASH_FRAMES кадров сбрасывается. Горячий цикл отрисовки не меняется.
func _hero_fx_frame(delta: float) -> void:
	for j in hero_flash_slots:
		buf[j * FLOATS_PER_UNIT + 13] = 0.0
	hero_flash_slots.clear()
	if hero_swing_n != hero_fx_seen:
		hero_fx_seen = hero_swing_n
		hero_fx_age = 0.0
		hero_fx_ang = hero_swing_ang
		hero_flash_left = HIT_FLASH_FRAMES
		var au := get_node_or_null("/root/Audio")
		if au != null:
			au.play_sfx("hero_swing")
		if not paused:
			_hit_fx_spawn()
	elif hero_fx_age >= 0.0:
		hero_fx_age += delta
		if hero_fx_age >= hero_cfg.arc_fx_time:
			hero_fx_age = -1.0
	if hero_flash_left > 0:
		hero_flash_left -= 1
		for n in hero_hit_idx.size():
			var j := hero_hit_idx[n]
			if j < count and team[j] == 1 and pos[j].distance_squared_to(hero_hit_pos[n]) < 64.0:
				buf[j * FLOATS_PER_UNIT + 13] = 1.0
				hero_flash_slots.append(j)
	hero_fx.visible = hero_fx_age >= 0.0
	if hero_fx.visible:
		hero_fx.queue_redraw()


# data/fx.json (эффекты: удар героя, резня, слой крови, тряска). Не читается или неверный — эффектов нет, игра идёт (это только отрисовка).
func _load_hit_fx() -> Dictionary:
	if not FileAccess.file_exists(HIT_FX_PATH):
		push_warning("Нет %s: эффекты выключены" % HIT_FX_PATH)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(HIT_FX_PATH))
	var nums := ["max_particles", "blood_drag", "blood_spread_deg", "spark_count", "spark_life", "spark_size",
		"big_drop_streak", "big_drop_window", "big_drop_size", "big_drop_drag", "hero_blood_mult", "hero_drop_speed_mult", "hero_drop_spread_deg",
		"shake_base_px", "shake_extra_px", "shake_extra_per", "shake_max_px", "shake_time",
		"stain_layer_scale", "stains_per_frame", "stain_alpha", "stain_dry_steps", "stain_dry_step_time",
		"mass_deaths_per_frame", "mass_splash_max", "mass_splash_px", "mass_splash_density", "mass_stains", "gib_chance_mass", "death_buffer",
		"max_gibs", "gib_life", "gib_fade", "gib_drag", "gib_type_tint"]
	var pairs := ["blood_hit", "blood_kill", "blood_life", "blood_speed", "blood_size", "big_drop_count", "big_drop_life", "big_drop_speed",
		"stain_size", "mass_splash_life", "dust_count", "gib_top_fwd", "gib_top_side", "gib_bottom_side", "gib_bottom_back"]
	var lists := ["blood_colors", "big_drop_colors", "spark_colors", "stain_colors", "dust_colors", "stain_colors_no_gore"]
	var flags := ["screen_shake_enabled", "stains_enabled", "gibs_enabled", "mass_enabled", "hero_big_drop_every_kill"]
	var ok: bool = d is Dictionary and d.get("gib_top_path") is String and d.get("gib_bottom_path") is String
	for k in flags:
		ok = ok and d.get(k) is bool
	for k in nums:
		ok = ok and d.get(k) is float and d[k] >= 0.0
	for k in pairs:
		ok = ok and d.get(k) is Array and d[k].size() == 2 and d[k][0] is float and d[k][1] is float and d[k][0] <= d[k][1]
	for k in lists:
		ok = ok and d.get(k) is Array and not d[k].is_empty() and d[k].all(func(c): return c is String and Color.html_is_valid(c))
	for k in ["gib_tint_human", "gib_tint_zombie"]:
		ok = ok and d.get(k) is String and Color.html_is_valid(d[k])
	ok = ok and d.get("shake_levels") is Array and not d.shake_levels.is_empty() and d.shake_levels.all(func(x): return x is float and x >= 0.0)
	ok = ok and d.get("stain_dry_mult") is Array and d.stain_dry_mult.size() == 4 and d.stain_dry_mult.all(func(x): return x is float and x >= 0.0)
	ok = ok and d.stain_layer_scale > 0.0 and d.shake_extra_per >= 1.0
	if not ok:
		push_error("%s: нужны числа >= 0 (%s), пары [от, до] (%s), списки цветов hex (%s), цвета gib_tint_human и gib_tint_zombie, bool (%s), shake_levels (числа), stain_dry_mult (4 числа), stain_layer_scale > 0, shake_extra_per >= 1, gib_top_path и gib_bottom_path — эффекты выключены" % [
			HIT_FX_PATH, ", ".join(nums), ", ".join(pairs), ", ".join(lists), ", ".join(flags)])
		return {}
	for k in lists:
		d[k] = d[k].map(func(c): return Color(c))
	d.gib_tint_human = Color(d.gib_tint_human)
	d.gib_tint_zombie = Color(d.gib_tint_zombie)
	return d


# Единичный квадрат (центр в 0) для MultiMesh эффектов: размер и цвет — у инстанса.
func _fx_quad_mm(n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])   # для кусков тела (текстура)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var quad := ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mm.mesh = quad
	mm.instance_count = maxi(n, 1)
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-FIELD.x, -FIELD.y, 0.0), Vector3(FIELD.x * 3.0, FIELD.y * 3.0, 0.0))
	return mm


func _setup_hit_fx() -> void:
	if not hit_cfg.is_empty() or hit_mm != null:
		return   # уже (герой и бой без героя зовут одну установку)
	hit_cfg = _load_hit_fx()
	if hit_cfg.is_empty():
		return
	hit_rng.seed = 1201   # свой генератор визуала: ГСЧ симуляции не трогается
	var n := int(hit_cfg.max_particles)
	hit_pos.resize(n)   # Packed-массивы — значения: resize каждого явно
	hit_vel.resize(n)
	hit_life.resize(n)
	hit_life0.resize(n)
	hit_size.resize(n)
	hit_drag.resize(n)
	hit_col.resize(n)
	hit_buf.resize(maxi(n, 1) * HIT_FPI)
	hit_mm = _fx_quad_mm(n)
	var pn := MultiMeshInstance2D.new()
	pn.multimesh = hit_mm
	pn.z_index = LEAF_Z + 1   # как герой: над юнитами и замком, ниже интерфейса; добавлена после героя — поверх спрайта
	add_child(pn)
	_setup_gibs()
	if hit_cfg.mass_enabled or hit_cfg.stains_enabled:
		var dn := int(hit_cfg.death_buffer)
		death_pos.resize(dn)
		death_team.resize(dn)
		death_type.resize(dn)
		death_dir.resize(dn)
	if hit_cfg.stains_enabled and int(hit_cfg.stains_per_frame) > 0:
		_setup_stain_layer()
	if hit_cfg.mass_enabled and int(hit_cfg.mass_splash_max) > 0:
		_setup_splash()


# Брызги смертей: MultiMesh квадов (цвет и custom) с шейдером scripts/splash.gdshader над юнитами (как частицы), ближайший сосед.
func _setup_splash() -> void:
	var n := int(hit_cfg.mass_splash_max)
	splash_mm = MultiMesh.new()
	splash_mm.transform_format = MultiMesh.TRANSFORM_2D
	splash_mm.use_colors = true
	splash_mm.use_custom_data = true
	splash_mm.mesh = _fx_quad_mm(1).mesh
	splash_mm.instance_count = n
	splash_mm.visible_instance_count = 0
	splash_mm.custom_aabb = AABB(Vector3(-FIELD.x, -FIELD.y, 0.0), Vector3(FIELD.x * 3.0, FIELD.y * 3.0, 0.0))
	splash_buf.resize(n * SPLASH_FPI)
	splash_mat = ShaderMaterial.new()
	splash_mat.shader = load("res://scripts/splash.gdshader")
	splash_mat.set_shader_parameter("cells", float(hit_cfg.mass_splash_px))
	splash_mat.set_shader_parameter("density", float(hit_cfg.mass_splash_density))
	var sn := MultiMeshInstance2D.new()
	sn.multimesh = splash_mm
	sn.material = splash_mat
	sn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sn.z_index = LEAF_Z + 1   # над юнитами и замком, как кровь удара героя
	add_child(sn)


# Брызги смерти в точке p цветом col: ячейка кольца (самые старые заменяются), время появления — сейчас.
func _splash(p: Vector2, col: Color) -> void:
	var o := splash_head * SPLASH_FPI
	splash_head = (splash_head + 1) % (splash_buf.size() / SPLASH_FPI)
	splash_used = mini(splash_used + 1, splash_buf.size() / SPLASH_FPI)
	var sz := float(hit_cfg.mass_splash_px)
	splash_buf[o + 0] = sz
	splash_buf[o + 1] = 0.0
	splash_buf[o + 3] = roundf(p.x)
	splash_buf[o + 4] = 0.0
	splash_buf[o + 5] = sz
	splash_buf[o + 7] = roundf(p.y)
	splash_buf[o + 8] = col.r
	splash_buf[o + 9] = col.g
	splash_buf[o + 10] = col.b
	splash_buf[o + 11] = 1.0
	splash_buf[o + 12] = splash_time
	splash_buf[o + 13] = hit_rng.randf()
	splash_buf[o + 14] = hit_rng.randf_range(hit_cfg.mass_splash_life[0], hit_cfg.mass_splash_life[1])
	splash_buf[o + 15] = 0.0
	splash_dirty = true


# Слой крови: SubViewport размером с поле x stain_layer_scale, прозрачный, без очистки (пятна копятся), перерисовывается только
# в кадры с новыми пятнами или шагом подсыхания (UPDATE_ONCE); внутри — шаг подсыхания (умножение, первым) и пятна кадра.
# Показ — Sprite2D в мире под юнитами (над фоном), ближайший сосед (пиксельно), смешивание premultiplied: слой хранит цвет x альфа.
func _setup_stain_layer() -> void:
	var sc := float(hit_cfg.stain_layer_scale)
	stain_vp = SubViewport.new()
	stain_vp.size = Vector2i(ceili(FIELD.x * sc), ceili(FIELD.y * sc))
	stain_vp.transparent_bg = true
	stain_vp.disable_3d = true
	stain_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	stain_vp.process_mode = Node.PROCESS_MODE_ALWAYS   # перерисовка слоя не зависит от паузы и от выключенной обработки сцены (тесты, снимки)
	add_child(stain_vp)
	stain_fade = ColorRect.new()
	stain_fade.size = Vector2(stain_vp.size)
	var mul := CanvasItemMaterial.new()
	mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	stain_fade.material = mul
	stain_fade.visible = false
	stain_vp.add_child(stain_fade)
	var cap := int(hit_cfg.stains_per_frame)
	stain_stamp_mm = _fx_quad_mm(cap)
	stain_stamp_buf.resize(cap * HIT_FPI)
	var sn := MultiMeshInstance2D.new()
	sn.multimesh = stain_stamp_mm
	sn.scale = Vector2.ONE * sc
	stain_vp.add_child(sn)
	stain_layer = Sprite2D.new()
	stain_layer.texture = stain_vp.get_texture()
	stain_layer.centered = false
	stain_layer.scale = Vector2.ONE / sc
	stain_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	stain_layer.material = pm
	add_child(stain_layer)
	if unit_node != null:
		move_child(stain_layer, unit_node.get_index())   # тот же z, раньше в дереве — под юнитами, над фоном (z -1)
	reset_stain_layer()


# Новый кадр движка после отдачи очереди: слой уже нарисован (отрисовка — в конце кадра), впечатанные пятна и шаг подсыхания
# в нём — очередь пуста, шаг спрятан. В пределах одного кадра очередь копится, сколько бы раз ни звали _process (тесты, снимки).
func _stain_drawn_check() -> void:
	if not stain_pending or Engine.get_process_frames() == stain_pending_frame:
		return
	stain_pending = false
	stain_stamp_n = 0
	if stain_fade_on:
		stain_fade.visible = false
		stain_fade_on = false


# Новый забег (новая сцена) или явный сброс: слой очищается на ближайшем кадре, подсыхание и счётчики — с нуля.
func reset_stain_layer() -> void:
	stain_stamp_n = 0
	stain_pending = false
	stain_total = 0
	stain_skipped = 0
	stain_dry_left = 0
	if stain_vp != null:
		stain_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		stain_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


# Конец волны: кровь подсыхает (stain_dry_steps шагов через stain_dry_step_time с), остаётся тёмным следом.
func _stain_dry_start() -> void:
	if stain_vp != null:
		stain_dry_left = int(hit_cfg.stain_dry_steps)
		stain_dry_t = float(hit_cfg.stain_dry_step_time)


# Новая частица; лимит — новые не создаются (hit_dropped).
func _hit_particle(p: Vector2, v: Vector2, life: float, size: float, col: Color, drag: float) -> void:
	if hit_n >= hit_pos.size():
		hit_dropped += 1
		return
	var i := hit_n
	hit_n += 1
	hit_pos[i] = p
	hit_vel[i] = v
	hit_life[i] = life
	hit_life0[i] = life
	hit_size[i] = size
	hit_col[i] = col
	hit_drag[i] = drag


# Видимые стрелы (задача 29): полёт над слоями (z частиц ударов), тени и воткнутые — на земле, под юнитами.
func _setup_arrow_fx() -> void:
	if arrow_fx != null:
		return
	var fx: Node2D = preload("res://scripts/arrow_fx.gd").new()
	fx.name = "ArrowFx"
	add_child(fx)
	if not fx.setup(self, LEAF_Z + 1, unit_node):
		fx.queue_free()
		return
	arrow_fx = fx


# «Показывать стрелы» (настройка): нет узла настроек (бенчи) — показывать.
func _arrows_shown() -> bool:
	var st := get_node_or_null("/root/Settings")
	return st == null or bool(st.show_arrows)


# Кадр стрел: время картинки — как у юнитов (lerp(prev_pos, pos, frac): тик tick_counter - 1 + frac; на паузе — pos, доля 1).
func _arrow_fx_frame(frac: float, dt: float) -> void:
	arrow_fx_on = _arrows_shown()
	arrow_fx.on = arrow_fx_on
	arrow_fx.frame(tick_counter - 1 + frac, dt, camera.zoom.x if camera != null else 1.0)


# «Жестокость» (настройка, задача 23): false — без крови и кусков (искры, пыль, серые пятна).
func _fx_gore() -> bool:
	var st := get_node_or_null("/root/Settings")
	return st == null or int(st.gore) > 0


# Пятно в очередь кадра (впечатается в слой); сверх stains_per_frame — не впечатывается (stain_skipped). Размер — целые px мира.
func _hit_stain(p: Vector2, gore := true) -> void:
	if stain_vp == null:
		return
	_stain_drawn_check()
	if stain_stamp_n * HIT_FPI >= stain_stamp_buf.size():
		stain_skipped += 1
		return
	var o := stain_stamp_n * HIT_FPI
	stain_stamp_n += 1
	stain_total += 1
	var sz := float(hit_rng.randi_range(int(hit_cfg.stain_size[0]), int(hit_cfg.stain_size[1])))
	var cols: Array = hit_cfg.stain_colors if gore else hit_cfg.stain_colors_no_gore
	var col: Color = cols[hit_rng.randi() % cols.size()]
	stain_stamp_buf[o + 0] = sz
	stain_stamp_buf[o + 1] = 0.0
	stain_stamp_buf[o + 3] = roundf(p.x)
	stain_stamp_buf[o + 4] = 0.0
	stain_stamp_buf[o + 5] = sz
	stain_stamp_buf[o + 7] = roundf(p.y)
	stain_stamp_buf[o + 8] = col.r
	stain_stamp_buf[o + 9] = col.g
	stain_stamp_buf[o + 10] = col.b
	stain_stamp_buf[o + 11] = float(hit_cfg.stain_alpha)


# Картинка половины зомби (fx.json gib_top_path / gib_bottom_path): импортированный ресурс, иначе PNG с диска (файл подложен без
# импорта); нет файла — половина первого кадра спрайта крестьянина, нарезанная в памяти (top: верх при взгляде вправо).
func _gib_texture(path: String, top: bool) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	push_warning("Нет картинки куска тела %s: половина спрайта зомби" % path)
	var sp := type_sprite[zombie_type] if zombie_type >= 0 else ""
	var src: Texture2D = load(sp) as Texture2D if sp != "" and ResourceLoader.exists(sp) else null
	var half := Image.create(SPRITE_PX, SPRITE_PX, false, Image.FORMAT_RGBA8)
	if src != null:
		var sheet := src.get_image()
		if sheet.is_compressed():
			sheet.decompress()
		sheet.convert(Image.FORMAT_RGBA8)
		var y0 := 0 if top else SPRITE_PX / 2
		half.blit_rect(sheet, Rect2i(0, y0, SPRITE_PX, SPRITE_PX / 2), Vector2i(0, y0))
	else:
		half.fill_rect(Rect2i(4, 4 if top else 8, 8, 4), Color(hit_cfg.blood_colors[0]))
	return ImageTexture.create_from_image(half)


# Куски тела: две ноды MultiMesh (верх и низ) сразу после юнитов в дереве — над пятнами и юнитами, ниже героя (z героя выше).
func _setup_gibs() -> void:
	var pairs := int(hit_cfg.max_gibs) / 2
	if not hit_cfg.gibs_enabled or pairs <= 0:
		return
	gib_pos.resize(pairs * 2)
	gib_vel.resize(pairs * 2)
	gib_age.resize(pairs)
	gib_dir.resize(pairs)
	gib_scale.resize(pairs)
	gib_col.resize(pairs)
	gib_top_buf.resize(pairs * HIT_FPI)
	gib_bot_buf.resize(pairs * HIT_FPI)
	gib_top_mm = _fx_quad_mm(pairs)
	gib_bot_mm = _fx_quad_mm(pairs)
	var at := unit_node.get_index() + 1 if unit_node != null else -1
	for k in 2:
		var gn := MultiMeshInstance2D.new()
		gn.multimesh = gib_top_mm if k == 0 else gib_bot_mm
		gn.texture = _gib_texture(hit_cfg.gib_top_path if k == 0 else hit_cfg.gib_bottom_path, k == 0)
		gib_tex_k[k] = gn.texture.get_size() / SPRITE_PX
		gn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(gn)
		if at >= 0:
			move_child(gn, at + k)


# Пара кусков в точке p: верх летит по удару (dir) и немного вбок, низ — в другую сторону вбок и чуть назад; тонировка по стороне
# (side_team 0 — люди, gib_tint_human; 1 — зомби, gib_tint_zombie).
func _hit_gib(p: Vector2, dir: Vector2, ut: int, udir: int, side_team := 1) -> void:
	if gib_top_mm == null:
		return
	if gib_n >= gib_age.size():
		gib_dropped += 1
		return
	var c := hit_cfg
	var k := gib_n
	gib_n += 1
	var side := dir.orthogonal() * (1.0 if hit_rng.randf() < 0.5 else -1.0)
	gib_pos[2 * k] = p
	gib_pos[2 * k + 1] = p
	gib_vel[2 * k] = dir * hit_rng.randf_range(c.gib_top_fwd[0], c.gib_top_fwd[1]) + side * hit_rng.randf_range(c.gib_top_side[0], c.gib_top_side[1])
	gib_vel[2 * k + 1] = -side * hit_rng.randf_range(c.gib_bottom_side[0], c.gib_bottom_side[1]) - dir * hit_rng.randf_range(c.gib_bottom_back[0], c.gib_bottom_back[1])
	gib_age[k] = 0.0
	gib_dir[k] = udir
	gib_scale[k] = type_sprite_scale[ut] if ut < type_sprite_scale.size() else 1.0
	gib_col[k] = Color.WHITE.lerp(c.gib_tint_human if side_team == 0 else c.gib_tint_zombie, clampf(c.gib_type_tint, 0.0, 1.0))   # люди красные, зомби тёмные


# Удар героя по кому-то (задачи 12–13, 23): в точке каждого задетого — искры (spark_*), всплеск крови от героя по направлению удара
# с разбросом (добитый — больше; x hero_blood_mult), пятна в слой; добитый — пара кусков тела (всегда), крупные капли (на каждом добитом
# при hero_big_drop_every_kill, иначе с big_drop_streak-го подряд) — быстрее (hero_drop_speed_mult) и уже (hero_drop_spread_deg) по удару.
# «Жестокость: выкл» — без крови и кусков: искры и пыль (dust_*), пятна серые. Тряска (fx.json screen_shake_enabled и настройка
# «Тряска экрана»): shake_base_px + shake_extra_px за каждые shake_extra_per попавших, не больше shake_max_px, x уровень настройки.
func _hit_fx_spawn() -> void:
	if hit_cfg.is_empty() or hero_hit_idx.is_empty():
		return
	var c := hit_cfg
	var gore := _fx_gore()
	hit_bursts += 1
	if hit_streak_t > float(c.big_drop_window):
		hit_streak = 0
	var spread := deg_to_rad(float(c.blood_spread_deg))
	var dspread := deg_to_rad(float(c.hero_drop_spread_deg))
	var bmult := float(c.hero_blood_mult)
	var bcols: Array = c.blood_colors if gore else c.dust_colors
	var dcols: Array = c.big_drop_colors
	var scols: Array = c.spark_colors
	var kills := 0
	for n in hero_hit_pos.size():
		var p := hero_hit_pos[n]
		var dead := hero_hit_dead[n] == 1
		var d := p - hero_swing_from
		var base := d.angle() if d.length_squared() > 0.01 else hero_swing_ang
		for k in int(c.spark_count):
			_hit_particle(p, Vector2.ZERO, c.spark_life, c.spark_size, scols[hit_rng.randi() % scols.size()], 0.0)
		var rng_n: Array = (c.blood_kill if dead else c.blood_hit) if gore else c.dust_count
		var nb := hit_rng.randi_range(int(rng_n[0]), int(rng_n[1]))
		if gore:
			nb = roundi(nb * bmult)
		for k in nb:
			var v := Vector2.from_angle(base + hit_rng.randf_range(-spread, spread)) * hit_rng.randf_range(c.blood_speed[0], c.blood_speed[1])
			_hit_particle(p, v, hit_rng.randf_range(c.blood_life[0], c.blood_life[1]), float(hit_rng.randi_range(int(c.blood_size[0]), int(c.blood_size[1]))),
				bcols[hit_rng.randi() % bcols.size()], c.blood_drag)
		for k in (3 if dead else 1):
			_hit_stain(p + Vector2.from_angle(base + hit_rng.randf_range(-spread, spread)) * hit_rng.randf_range(1.0, 9.0), gore)
		if not dead:
			continue
		kills += 1
		hit_streak += 1
		hero_kill_pos.append(p)
		if not gore:
			continue
		_hit_gib(p, Vector2.from_angle(base), hero_hit_type[n], hero_hit_dir[n], 1)
		if c.hero_big_drop_every_kill or hit_streak >= int(c.big_drop_streak):
			for k in hit_rng.randi_range(int(c.big_drop_count[0]), int(c.big_drop_count[1])):
				var v := Vector2.from_angle(base + hit_rng.randf_range(-dspread, dspread)) \
					* hit_rng.randf_range(c.big_drop_speed[0], c.big_drop_speed[1]) * float(c.hero_drop_speed_mult)
				_hit_particle(p, v, hit_rng.randf_range(c.big_drop_life[0], c.big_drop_life[1]), c.big_drop_size, dcols[hit_rng.randi() % dcols.size()], c.big_drop_drag)
	if kills > 0:
		hit_streak_t = 0.0
	var lvl := _shake_level_mult()
	if lvl > 0.0 and camera != null and float(c.shake_time) > 0.0:
		var hits := hero_hit_pos.size()
		var amp := minf(float(c.shake_base_px) + float(c.shake_extra_px) * floorf(hits / float(c.shake_extra_per)), float(c.shake_max_px))
		if amp > 0.0:
			shake_amp = amp * lvl
			shake_cap = float(c.shake_max_px) * lvl
			shake_last_amp = shake_amp
			shake_hit_t = float(c.shake_time)   # заводится заново, не копится
			shake_hit_count += 1


# Множитель тряски: 0 — выключена (fx.json screen_shake_enabled или настройка «Тряска экрана: выкл»), иначе shake_levels[уровень].
func _shake_level_mult() -> float:
	if not hit_cfg.screen_shake_enabled:
		return 0.0
	var levels: Array = hit_cfg.shake_levels
	var st := get_node_or_null("/root/Settings")
	var lvl: int = st.screen_shake_level if st != null else 2
	return float(levels[clampi(lvl, 0, levels.size() - 1)])


# Смерти тиков с прошлого кадра (задача 23): пятна в слой — от всех (сначала видимые; не больше stains_per_frame за кадр); брызги
# и куски — только в видимой области камеры и не больше mass_deaths_per_frame смертей (лишние — случайная выборка, hit_rng); брызги —
# квад с шейдером на смерть (_splash); кусок — с шансом gib_chance_mass, тонировка по стороне. Добитые героем пропускаются — их уже
# показал удар. «Жестокость: выкл» — пыль вместо крови, без кусков, пятна серые.
func _mass_fx() -> void:
	var c := hit_cfg
	var gore := _fx_gore()
	var vr := view_rect().grow(8.0)
	var seen := PackedInt32Array()
	var off := PackedInt32Array()
	for k in death_n:
		var p := death_pos[k]
		var by_hero := false
		for q in hero_kill_pos:
			if q.distance_squared_to(p) < 64.0:
				by_hero = true
				break
		if by_hero:
			continue
		if vr.has_point(p):
			seen.append(k)
		else:
			off.append(k)
	var ns := int(c.mass_stains)
	for k in seen:
		for q in ns:
			_hit_stain(death_pos[k] + Vector2(hit_rng.randf_range(-4.0, 4.0), hit_rng.randf_range(-4.0, 4.0)), gore)
	for k in off:
		for q in ns:
			_hit_stain(death_pos[k] + Vector2(hit_rng.randf_range(-4.0, 4.0), hit_rng.randf_range(-4.0, 4.0)), gore)
	if not c.mass_enabled:
		return
	var limit := int(c.mass_deaths_per_frame)
	if seen.size() > limit:   # выборка: первые limit после частичного перемешивания
		for q in limit:
			var r := hit_rng.randi_range(q, seen.size() - 1)
			var t := seen[q]
			seen[q] = seen[r]
			seen[r] = t
		mass_sampled_out += seen.size() - limit
		seen.resize(limit)
	var cols: Array = c.blood_colors if gore else c.dust_colors
	for k in seen:
		var p := death_pos[k]
		mass_shown += 1
		if splash_mm != null:
			_splash(p, cols[hit_rng.randi() % cols.size()])   # брызги во все стороны — шейдер
		if gore and hit_rng.randf() < float(c.gib_chance_mass):
			gib_mass += 1
			_hit_gib(p, Vector2.from_angle(hit_rng.randf() * TAU), death_type[k], death_dir[k], death_team[k])
	mass_frame_max = maxi(mass_frame_max, seen.size())


# Кадр эффектов (dt 0 — пауза: всё стоит): смерти тиков — резня и пятна; частицы летят с затуханием скорости и гаснут, погасшие
# удаляются (последняя на место); пятна кадра впечатываются в слой, шаги подсыхания после волны; тряска — случайное смещение камеры,
# убывающее к концу.
func _hit_fx_frame(dt: float) -> void:
	_stain_drawn_check()
	if death_n > 0 and dt > 0.0:
		_mass_fx()
		death_n = 0
	hero_kill_pos.clear()
	var i := 0
	while i < hit_n:
		hit_life[i] -= dt
		if hit_life[i] <= 0.0:
			hit_n -= 1
			hit_pos[i] = hit_pos[hit_n]
			hit_vel[i] = hit_vel[hit_n]
			hit_life[i] = hit_life[hit_n]
			hit_life0[i] = hit_life0[hit_n]
			hit_size[i] = hit_size[hit_n]
			hit_col[i] = hit_col[hit_n]
			hit_drag[i] = hit_drag[hit_n]
			continue
		if hit_drag[i] > 0.0:
			hit_vel[i] *= exp(-hit_drag[i] * dt)
		hit_pos[i] += hit_vel[i] * dt
		var o := i * HIT_FPI
		var sz := hit_size[i]
		hit_buf[o + 0] = sz
		hit_buf[o + 1] = 0.0
		hit_buf[o + 3] = roundf(hit_pos[i].x)   # по целым px: «пиксельная» кровь
		hit_buf[o + 4] = 0.0
		hit_buf[o + 5] = sz
		hit_buf[o + 7] = roundf(hit_pos[i].y)
		var col := hit_col[i]
		hit_buf[o + 8] = col.r
		hit_buf[o + 9] = col.g
		hit_buf[o + 10] = col.b
		hit_buf[o + 11] = clampf(hit_life[i] / hit_life0[i] * 1.5, 0.0, 1.0)   # гаснет в последней трети жизни
		i += 1
	if hit_n > 0 or hit_mm.visible_instance_count > 0:
		hit_mm.visible_instance_count = hit_n
		if hit_n > 0:
			hit_mm.buffer = hit_buf
	if stain_vp != null:
		_stain_frame(dt)
	if splash_mm != null:
		splash_time += dt
		splash_mat.set_shader_parameter("now", splash_time)
		if splash_dirty:
			splash_dirty = false
			splash_mm.buffer = splash_buf
			splash_mm.visible_instance_count = splash_used
	if gib_n > 0 or (gib_top_mm != null and gib_top_mm.visible_instance_count > 0):
		_gib_frame(dt)
	hit_streak_t += dt
	if camera != null and (shake_hit_t > 0.0 or camera.offset != Vector2.ZERO):
		shake_hit_t = maxf(shake_hit_t - dt, 0.0)
		if shake_hit_t > 0.0:
			if dt > 0.0 or camera.offset == Vector2.ZERO:   # на паузе смещение стоит
				shake_raw = _shake_offset(shake_amp * shake_hit_t / maxf(float(hit_cfg.shake_time), 0.001))
				camera.offset = _shake_in_field(shake_raw)
		elif dt > 0.0:
			camera.offset = Vector2.ZERO
			shake_raw = Vector2.ZERO


# Слой крови за кадр: шаг подсыхания (если пора) и пятна очереди — одна перерисовка SubViewport; очередь пуста после отрисовки.
func _stain_frame(dt: float) -> void:
	var redraw := stain_stamp_n > 0
	if stain_dry_left > 0 and dt > 0.0 and not stain_fade_on:
		stain_dry_t -= dt
		if stain_dry_t <= 0.0:
			stain_dry_left -= 1
			stain_dry_t = float(hit_cfg.stain_dry_step_time)
			var m: Array = hit_cfg.stain_dry_mult
			stain_fade.color = Color(m[0], m[1], m[2], m[3])
			stain_fade.visible = true
			stain_fade_on = true
			redraw = true
	if not redraw:
		return
	stain_stamp_mm.visible_instance_count = stain_stamp_n
	stain_stamp_mm.buffer = stain_stamp_buf
	stain_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not stain_pending:
		stain_redraws += 1
	stain_pending = true
	stain_pending_frame = Engine.get_process_frames()


# Задача 28: смещение тряски off (px мира) урезано по каждой оси до запаса вида до края поля (целые px экрана) — у края карты
# чёрная полоса не мелькает. При зуме 1.0 вид по высоте равен полю: тряска только по горизонтали. ГСЧ не трогает; смещение
# до урезания — в shake_raw (тесты тряски).
func _shake_in_field(off: Vector2) -> Vector2:
	var z := camera.zoom.x
	var half := _screen_size() * 0.5 / z
	var px := (off * z).round()
	for a in 2:
		var lo := floorf((camera.position[a] - half[a]) * z + 0.001)
		var hi := floorf((FIELD[a] - camera.position[a] - half[a]) * z + 0.001)
		px[a] = clampf(px[a], -maxf(lo, 0.0), maxf(hi, 0.0))
	return px / z


# Смещение камеры тряски силой a px экрана: целые пиксели экрана (иначе пиксель-арт мылится), не меньше 1 px, не больше shake_cap;
# направление случайное (hit_rng). Смещение камеры — в px мира, поэтому делится на зум.
func _shake_offset(a: float) -> Vector2:
	var r := clampf(roundf(a), 1.0, maxf(floorf(shake_cap), 1.0))
	var v := Vector2.from_angle(hit_rng.randf() * TAU) * r
	var px := Vector2(roundf(v.x), roundf(v.y))
	if px.length() > r:   # диагональ после округления длиннее r — только по большей оси
		px = Vector2(px.x, 0.0) if absf(v.x) >= absf(v.y) else Vector2(0.0, px.y)
	return px / camera.zoom


# Кадр кусков тела: полёт с затуханием скорости (gib_drag), жизнь gib_life, последние gib_fade с — плавно гаснут; погасшая пара
# заменяется последней. Ориентация — DIR_BASIS по unit_dir зомби (как у спрайтов юнитов), размер — по картинке и типу; позиция — целые px.
func _gib_frame(dt: float) -> void:
	var life: float = hit_cfg.gib_life
	var fade: float = maxf(float(hit_cfg.gib_fade), 0.001)
	var damp := exp(-float(hit_cfg.gib_drag) * dt)
	var k := 0
	while k < gib_n:
		gib_age[k] += dt
		if gib_age[k] >= life:
			gib_n -= 1
			gib_pos[2 * k] = gib_pos[2 * gib_n]
			gib_pos[2 * k + 1] = gib_pos[2 * gib_n + 1]
			gib_vel[2 * k] = gib_vel[2 * gib_n]
			gib_vel[2 * k + 1] = gib_vel[2 * gib_n + 1]
			gib_age[k] = gib_age[gib_n]
			gib_dir[k] = gib_dir[gib_n]
			gib_scale[k] = gib_scale[gib_n]
			gib_col[k] = gib_col[gib_n]
			continue
		var b := gib_dir[k] * 4
		var al := clampf((life - gib_age[k]) / fade, 0.0, 1.0)
		var col := gib_col[k]
		var o := k * HIT_FPI
		var q := 2 * k
		gib_vel[q] *= damp
		gib_pos[q] += gib_vel[q] * dt
		var sk: Vector2 = gib_tex_k[0] * gib_scale[k]
		gib_top_buf[o + 0] = DIR_BASIS[b] * sk.x
		gib_top_buf[o + 1] = DIR_BASIS[b + 1] * sk.y
		gib_top_buf[o + 3] = roundf(gib_pos[q].x)
		gib_top_buf[o + 4] = DIR_BASIS[b + 2] * sk.x
		gib_top_buf[o + 5] = DIR_BASIS[b + 3] * sk.y
		gib_top_buf[o + 7] = roundf(gib_pos[q].y)
		gib_top_buf[o + 8] = col.r
		gib_top_buf[o + 9] = col.g
		gib_top_buf[o + 10] = col.b
		gib_top_buf[o + 11] = al
		q += 1
		gib_vel[q] *= damp
		gib_pos[q] += gib_vel[q] * dt
		sk = gib_tex_k[1] * gib_scale[k]
		gib_bot_buf[o + 0] = DIR_BASIS[b] * sk.x
		gib_bot_buf[o + 1] = DIR_BASIS[b + 1] * sk.y
		gib_bot_buf[o + 3] = roundf(gib_pos[q].x)
		gib_bot_buf[o + 4] = DIR_BASIS[b + 2] * sk.x
		gib_bot_buf[o + 5] = DIR_BASIS[b + 3] * sk.y
		gib_bot_buf[o + 7] = roundf(gib_pos[q].y)
		gib_bot_buf[o + 8] = col.r
		gib_bot_buf[o + 9] = col.g
		gib_bot_buf[o + 10] = col.b
		gib_bot_buf[o + 11] = al
		k += 1
	gib_top_mm.visible_instance_count = gib_n
	gib_bot_mm.visible_instance_count = gib_n
	if gib_n > 0:
		gib_top_mm.buffer = gib_top_buf
		gib_bot_mm.buffer = gib_bot_buf


# Сектор радиуса r вокруг направления ang, полуугол half (рад): центр и точки дуги; полный круг — без центра.
func _sector(r: float, ang: float, half: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var full := half >= PI - 0.001
	if not full:
		pts.append(Vector2.ZERO)
	var n := 24 if full else 16
	for k in n + (0 if full else 1):
		pts.append(Vector2.from_angle(ang - half + 2.0 * half * k / n) * r)
	return pts


# Дуга-вспышка удара: свечение (шире и прозрачнее) под полупрозрачной заливкой цвета arc_fx_color, поверх — яркая кромка по внешней
# дуге (расширяется на HERO_FX_GROW_PX) и две боковые линии сектора; альфа плавно гаснет за arc_fx_time. Размер — arc_range, arc_angle.
func _draw_hero_fx() -> void:
	if hero_fx_age < 0.0:
		return
	var e := clampf(hero_fx_age / float(hero_cfg.arc_fx_time), 0.0, 1.0)
	var a := 1.0 - e * e * (3.0 - 2.0 * e)
	var col := Color(hero_cfg.arc_fx_color)
	var edge := col.lerp(Color.WHITE, 0.6)
	var r: float = hero_cfg.arc_range * hero_range_mult()
	var half := minf(deg_to_rad(hero_arc_angle()) * 0.5, PI)
	var grow := HERO_FX_GROW_PX * e
	var ang := hero_fx_ang
	var full := half >= PI - 0.001
	hero_fx.draw_colored_polygon(_sector(r + HERO_FX_GLOW_PX + grow, ang, minf(half + HERO_FX_GLOW_ANG, PI)), Color(col, 0.16 * a))
	hero_fx.draw_colored_polygon(_sector(r, ang, half), Color(col, 0.38 * a))
	hero_fx.draw_arc(Vector2.ZERO, r + grow, ang - half, ang + half, 24, Color(edge, 0.3 * a), 4.0)   # ореол кромки
	hero_fx.draw_arc(Vector2.ZERO, r + grow, ang - half, ang + half, 24, Color(edge, 0.95 * a), 1.5)
	if not full:
		for sd in [-1.0, 1.0]:
			hero_fx.draw_line(Vector2.ZERO, Vector2.from_angle(ang + sd * half) * (r + grow), Color(edge, 0.8 * a), 1.0)


# Командир пал в бою: приказы (клавиши, ПКМ, Клич, построения) не принимаются до конца волны; выбор, пауза и камера работают.
func _orders_locked() -> bool:
	return hero_dead and wave_state == WS_BATTLE


# Ввод героя на этот тик (раз в тик симуляции): hero_feed (тесты, бот) или клавиатура — движение move_* (WASD по умолчанию;
# с зажатым Ctrl не читается: Ctrl+A — «выбрать все», а не шаг влево), удар hero_attack (J): нажатие с прошлого тика
# (hero_attack_latch) или удержание при hold_repeat. Диагональ — длина 1.
func _hero_input() -> void:
	var v := Vector2.ZERO
	hero_attack_in = false
	hero_face_in = NAN
	if hero_feed.is_valid():
		var f = hero_feed.call(tick_counter)
		if f is Dictionary:
			v = f.get("move", Vector2.ZERO)
			hero_attack_in = f.get("attack", false)
			hero_face_in = float(f.get("face", NAN))
		else:
			v = f
	elif is_inside_tree() and not _run_over() and InputMap.has_action("move_up"):
		if not (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
			v = Vector2(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
				Input.get_action_strength("move_down") - Input.get_action_strength("move_up"))
		hero_attack_in = hero_attack_latch or (hero_cfg.hold_repeat and InputMap.has_action("hero_attack") and Input.is_action_pressed("hero_attack"))
	hero_attack_latch = false
	hero_move = v.normalized() if v.length_squared() > 1.0 else v


# Тик героя: скорость из ввода (ход и границы — общий _move_units: поле и пол у стены, как у юнитов), взгляд — по вводу "face"
# или по движению (в покое — прежний), удар. Ручной (по умолчанию): ввод удара и перезарядка прошла — удар сектором (_hero_swing),
# и мимо. Автоатака (auto_attack true, задача 10): раз в интервал — ближайшие живые зомби в arc_range по кругу, если они есть.
func _update_hero(delta: float) -> void:
	var h := hero_idx
	vel[h] = hero_move * type_speed[hero_type]
	if not is_nan(hero_face_in):
		hero_face_ang = hero_face_in
	elif hero_move != Vector2.ZERO:
		hero_face_ang = hero_move.angle()
	var fx := cos(hero_face_ang)
	if absf(fx) > 0.01:
		hero_face = signf(fx)   # спрайт: отражение по x; вверх и вниз — прежнее
	unit_state[h] = ST_CHASE if hero_move != Vector2.ZERO else ST_IDLE
	cooldown[h] = maxf(cooldown[h] - delta, type_cd_floor[hero_type])
	if cooldown[h] > 0.0:
		return
	if hero_cfg.auto_attack:
		var tj := _hero_targets(false)
		if not tj.is_empty():
			_hero_swing(tj)
	elif hero_attack_in:
		_hero_swing(_hero_targets(true))


# Цели удара героя: живые зомби в arc_range, в секторе взгляда (угол до зомби не больше arc_angle / 2; arc false — по кругу),
# не больше max_targets ближайших (0 — без лимита), по возрастанию расстояния. Поиск — по мелкой сетке этого тика: окно
# ±ceil(arc_range / CELL_SIZE) клеток (28 px при клетке 24 — 5x5).
func _hero_targets(arc: bool) -> PackedInt32Array:
	var p := pos[hero_idx]
	var r2 := type_range_sq[hero_type]
	var rk := hero_range_mult()
	if rk != 1.0:
		r2 *= rk * rk   # карточка 41: радиус дуги (без карточки ветки нет — бит в бит)
	var reach := ceili(sqrt(r2) / CELL_SIZE)
	var cx := clampi(floori(p.x / CELL_SIZE), 0, GRID_W - 1)
	var cy := clampi(floori(p.y / CELL_SIZE), 0, GRID_H - 1)
	var fwd := Vector2.from_angle(hero_face_ang)
	var cos_half := cos(deg_to_rad(hero_arc_angle()) * 0.5) if arc else -2.0
	var k: int = hero_cfg.max_targets
	var tj := PackedInt32Array()     # цели по возрастанию расстояния (не больше k)
	var td := PackedFloat32Array()
	for ny in range(maxi(cy - reach, 0), mini(cy + reach, GRID_H - 1) + 1):
		for nx in range(maxi(cx - reach, 0), mini(cx + reach, GRID_W - 1) + 1):
			var c := nx + ny * GRID_W
			for q in range(cell_start[c], cell_start[c + 1]):
				var j := sorted_units[q]
				if team[j] != 1 or hp[j] <= 0.0:
					continue
				var d2 := p.distance_squared_to(pos[j])
				if d2 > r2 or (k > 0 and td.size() == k and d2 >= td[k - 1]):
					continue
				if (pos[j] - p).dot(fwd) < cos_half * sqrt(d2):
					continue   # вне сектора (зомби в той же точке, что герой, — в секторе)
				var at := td.size()
				while at > 0 and td[at - 1] > d2:
					at -= 1
				tj.insert(at, j)
				td.insert(at, d2)
				if k > 0 and tj.size() > k:
					tj.resize(k)
					td.resize(k)
	return tj


# Статы дуги удара с модификаторами (карточка 41, цель hero): читаются при каждом ударе и в отрисовке дуги. Угол — arc_angle
# hero.json плюс arc_angle add_flat (не больше 360), радиус — множитель arc_range к дальности героя. Без модификаторов — данные как есть.
func hero_arc_angle() -> float:
	var a := float(hero_cfg.arc_angle)
	if mods != null and mods.has_key("arc_angle", "hero"):
		a = clampf(a + mods.get_flat("arc_angle", "hero"), 1.0, 360.0)
	return a


func hero_range_mult() -> float:
	return mods.get_mult("arc_range", "hero") if mods != null else 1.0


# Удар героя по целям tj (можно пустым — мимо): урон, перезарядка с переносом остатка (как у юнитов), Клич Благодати ускоряет
# (у героя нет отряда — множитель клича напрямую). Задетые запоминаются для мигания (только отрисовка).
func _hero_swing(tj: PackedInt32Array) -> void:
	var h := hero_idx
	for j in tj:
		hp[j] -= type_damage[hero_type]   # у зомби нет щита и отряда: ни блока, ни снижения урона
		if hp[j] <= 0.0:
			hero_kills += 1
	hero_swing_n += 1
	hero_swing_ang = hero_face_ang
	hero_hit_idx = tj
	hero_hit_pos.resize(tj.size())
	hero_hit_dead.resize(tj.size())
	hero_hit_type.resize(tj.size())
	hero_hit_dir.resize(tj.size())
	hero_swing_from = pos[h]
	for n in tj.size():
		hero_hit_pos[n] = pos[tj[n]]
		hero_hit_dead[n] = 1 if hp[tj[n]] <= 0.0 else 0
		hero_hit_type[n] = unit_type[tj[n]]
		hero_hit_dir[n] = unit_dir[tj[n]]
	if not tj.is_empty():
		hero_swings += 1
		hero_hits += tj.size()
	var cry := war_cry_mult if war_cry_until >= 0 else 1.0
	cooldown[h] += type_cooldown[hero_type] / cry   # остаток (до type_cd_floor) переносится, как у юнитов
	unit_anim_t[h] = ATTACK_ANIM_T


# Значение из JSON с множителем масштаба (SCALE_REL или SPEED_REL), округлённое до 0.01.
func _scaled(v: float, rel: float) -> float:
	return roundf(v * rel * 100.0) / 100.0


func _type_of(type_name: String) -> int:
	if not type_id.has(type_name):
		push_error("%s: нет типа \"%s\"" % [UNIT_TYPES_PATH, type_name])
		return -1
	return type_id[type_name]


func _setup_data() -> void:
	if not _load_hero() or not _load_types():
		set_physics_process(false)
		set_process(false)
		return
	var infantry := _type_of("infantry")   # отряд 0
	var archer := _type_of("archer")       # отряд 1
	var peasant := _type_of("peasant")     # орда зомби
	var runner := _type_of("runner")
	var knight := _type_of("fallen_knight")
	var spearman := _type_of("spearman")   # копейщики
	if infantry == -1 or archer == -1 or peasant == -1 or runner == -1 or knight == -1 or spearman == -1 or not _load_castle() or not _load_waves() or not _load_shop() or not _load_run() or not _load_story() 			or not _load_mods():
		type_id = {}
		set_physics_process(false)
		set_process(false)
		return
	infantry_type = infantry
	archer_type = archer
	zombie_type = peasant
	runner_type = runner
	knight_type = knight
	spearman_type = spearman
	hero_type = _type_of("hero") if hero_on else -1
	if type_enabled[spearman] == 0:   # выключенный тип не продаётся, даже если товар включён
		shop_enabled[SHOP_ITEMS.find("spear_pack")] = 0
	_apply_mods()
	_read_wave_mods()
	# Все массивы юнитов — один раз на MAX_UNITS; живые юниты всегда в [0, count).
	pos.resize(MAX_UNITS)
	team.resize(MAX_UNITS)
	cell_of.resize(MAX_UNITS)
	sorted_units.resize(MAX_UNITS)
	cell_start.resize(CELL_COUNT + 1)
	cursor.resize(CELL_COUNT)
	hp.resize(MAX_UNITS)
	unit_type.resize(MAX_UNITS)
	cooldown.resize(MAX_UNITS)
	cooldown.fill(0.0)
	vel.resize(MAX_UNITS)
	vel.fill(Vector2.ZERO)   # стартовая скорость 0
	unit_squad.resize(MAX_UNITS)
	unit_slot.resize(MAX_UNITS)
	unit_slot_idx.resize(MAX_UNITS)
	slot_owner.resize(MAX_UNITS + WIDTH_MAX)   # индексы слотов < живых + ширина
	reflow_order.resize(MAX_UNITS)   # выделяется один раз
	slot_idx_prev.resize(MAX_UNITS)   # выделяется один раз
	sort_keys.resize(MAX_UNITS)       # выделяется один раз
	unit_state.resize(MAX_UNITS)
	unit_state.fill(ST_IDLE)
	unit_slot_changed_t.resize(MAX_UNITS)
	unit_rand.resize(MAX_UNITS)
	unit_anim_t.resize(MAX_UNITS)
	unit_anim_t.fill(0.0)
	unit_dir.resize(MAX_UNITS)
	unit_dir.fill(0)
	unit_render_off.resize(MAX_UNITS)
	unit_shot_t.resize(MAX_UNITS)
	unit_shot_t.fill(0.0)
	var upd := float(UPDATE_TICKS) / Engine.physics_ticks_per_second
	windup_cd = (roundf(WINDUP_T / upd) - 1.5) * upd
	# Лучники: грубая сетка зомби и очередь стрел, всё выделяется один раз.
	coarse_zcount.resize(COARSE_COUNT)
	coarse_sum.resize(COARSE_COUNT)
	coarse_start.resize(COARSE_COUNT + 1)
	coarse_start.fill(0)
	coarse_cursor.resize(COARSE_COUNT)
	coarse_units.resize(MAX_UNITS)
	coarse_cell_of.resize(MAX_UNITS)
	arrow_land.resize(ARROW_CAP)
	arrow_tick.resize(ARROW_CAP)
	arrow_dmg.resize(ARROW_CAP)
	arrow_from.resize(ARROW_CAP)
	arrow_t0.resize(ARROW_CAP)
	arrow_vid.resize(ARROW_CAP)
	arrow_count = 0
	arrow_rng.seed = spawn_seed + 7919   # отдельный seeded-генератор разброса стрел

	# Отряд 0: пехота игрока (team 0). Отряд 1: лучники (team 0): самостоятельный отряд;
	# при archers_follow идут за отрядом 0, как раньше.
	# Зомби (team 1) без отряда: орда идёт к HORDE_GOAL.
	# Все массивы отрядов — один раз на SQUAD_MAX; занятые индексы отмечены в squad_used.
	squad_used.resize(SQUAD_MAX)
	squad_n.resize(SQUAD_MAX)
	squad_pos.resize(SQUAD_MAX)
	squad_target.resize(SQUAD_MAX)
	squad_angle.resize(SQUAD_MAX)
	squad_team.resize(SQUAD_MAX)
	squad_stop_dist.resize(SQUAD_MAX)
	squad_width.resize(SQUAD_MAX)
	squad_rows.resize(SQUAD_MAX)
	squad_dirty.resize(SQUAD_MAX)
	squad_speed.resize(SQUAD_MAX)
	for arr in [squad_dmg_mult, squad_taken_mult, squad_speed_mult]:
		arr.resize(SQUAD_MAX)
		arr.fill(1.0)
	squad_atk_speed_mult.resize(SQUAD_MAX)
	squad_atk_speed_mult.fill(1.0)
	squad_rate_mult.resize(SQUAD_MAX)
	squad_rate_mult.fill(1.0)
	squad_block_bonus.resize(SQUAD_MAX)
	squad_block_bonus.fill(0.0)
	squad_skill_on.resize(SQUAD_MAX)
	squad_skill_on.fill(0)
	squad_start_n.resize(SQUAD_MAX)
	squad_start_n.fill(0)
	squad_fallen.resize(SQUAD_MAX)
	squad_fallen.fill(0)
	squad_recover_carry.resize(SQUAD_MAX)
	squad_recover_carry.fill(0.0)
	squad_center_off.resize(SQUAD_MAX)
	squad_reflow_n.resize(SQUAD_MAX)
	squad_front_row.resize(SQUAD_MAX)
	squad_follow.resize(SQUAD_MAX)
	squad_ranged.resize(SQUAD_MAX)
	squad_type.resize(SQUAD_MAX)
	squad_volley_mode.resize(SQUAD_MAX)
	squad_volley_t.resize(SQUAD_MAX)
	squad_volley_fired.resize(SQUAD_MAX)
	squad_arrows_fired.resize(SQUAD_MAX)
	squad_mode_switches.resize(SQUAD_MAX)
	squad_depth.resize(SQUAD_MAX)
	squad_front_x.resize(SQUAD_MAX)
	squad_user_width.resize(SQUAD_MAX)
	squad_aspect.resize(SQUAD_MAX)
	squad_order.resize(SQUAD_MAX)
	squad_dir_angle.resize(SQUAD_MAX)
	for s in SQUAD_MAX:
		_squad_reset(s)
	sel_mask = 1
	sel_primary = 0
	var squad_size := PackedInt32Array([INFANTRY_COUNT, ARCHER_COUNT])
	var start_type := PackedInt32Array([infantry, archer])
	var start_width := PackedInt32Array([START_WIDTH_INF, START_WIDTH_ARCH])   # лучники: шире и мельче (25 x 4)
	var start_aspect := PackedVector2Array([Vector2(20, 15), Vector2(25, 4)])   # для перестройки (_reflow_squad)
	for s in START_SQUADS:
		squad_used[s] = 1
		squad_n[s] = squad_size[s]
		squad_pos[s] = PLAYER_START   # временно: пехота после расстановки в PLAYER_START, лучники позади неё
		squad_type[s] = start_type[s]
		squad_ranged[s] = 1 if type_range_far[start_type[s]] > 0.0 else 0
		squad_width[s] = start_width[s]
		squad_aspect[s] = start_aspect[s]
		squad_rows[s] = ceili(squad_size[s] / float(squad_width[s]))
	squad_follow[1] = 0 if archers_follow else -1   # ведомым бывает только отряд 1
	col_map.resize(WIDTH_MAX)   # выделяется один раз
	unit_rng.seed = spawn_seed
	# Стартовый состав: пехота и лучники; зомби на старте — только без волн (как bak21).
	var n_start := UNIT_COUNT if not waves_enabled else INFANTRY_COUNT + ARCHER_COUNT
	count = n_start
	for i in n_start:
		unit_rand[i] = unit_rng.randf()
		unit_render_off[i] = _render_offset(i)
		var s := 0 if i < INFANTRY_COUNT else (1 if i < INFANTRY_COUNT + ARCHER_COUNT else -1)
		if s >= 0:
			unit_squad[i] = s
			team[i] = squad_team[s]
			unit_type[i] = squad_type[s]
			_set_line_slot(i, i - (0 if s == 0 else INFANTRY_COUNT), squad_width[s])
			pos[i] = squad_pos[s] + unit_slot[i].rotated(squad_angle[s])
			unit_dir[i] = _nearest_dir(squad_angle[s])
		else:
			unit_squad[i] = -1
			unit_slot_idx[i] = -1
			unit_slot[i] = Vector2.ZERO
			team[i] = 1
			unit_type[i] = peasant
			# Блок шириной 20 по центру дороги, лицом вниз (к игроку): передний край на ZOMBIE_FRONT_Y,
			# ряды уходят вверх. «Вперёд» блока = PI/2 (вниз), как у отряда, через _slot_vector.
			pos[i] = Vector2(ROAD_X, ZOMBIE_FRONT_Y) + _slot_vector(i - INFANTRY_COUNT - ARCHER_COUNT, 20).rotated(PI / 2.0)
		hp[i] = type_hp[unit_type[i]]
	unit_slot_changed_t.fill(-1000.0)   # стартовая расстановка — не смена слота
	for s in START_SQUADS:
		squad_reflow_n[s] = squad_size[s]
		_reanchor(s)   # squad_pos переезжает в центр строя, мировые позиции юнитов те же
	for s in START_SQUADS:
		var lead := squad_follow[s]
		if lead < 0 and s == 0:   # центр строя пехоты — в PLAYER_START
			var shift0 := PLAYER_START - squad_pos[s]
			squad_pos[s] += shift0
			for i in count:
				if unit_squad[i] == s:
					pos[i] += shift0
		if s == 1:   # лучники на старте стоят позади пехоты (и ведомые, и самостоятельные)
			var shift := _follow_target(s, 0) - squad_pos[s]
			squad_pos[s] += shift
			for i in count:
				if unit_squad[i] == s:
					pos[i] += shift
		squad_target[s] = squad_pos[s]
	prev_pos = pos.duplicate()   # иначе _remove_dead до первого физического тика выходит за границы prev_pos
	# Волны и экономика
	gold = wave_cfg.start_gold
	wave_income = 0.0
	gold_wave_start = gold
	zombie_alive = 0
	for i in count:
		if team[i] == 1:
			zombie_alive += 1
	wave_number = 0
	wave_remaining = 0
	wave_hp_mult = 1.0
	team_dmg_mult = PackedFloat32Array([1.0, 1.0])
	wave_state = WS_RESPITE if waves_enabled else WS_BATTLE
	wave_kills_by_type.resize(type_hp.size())
	wave_kills_by_type.fill(0)
	wave_plan = _plan_wave(1) if waves_enabled else []
	wave_plan_for = 1
	wave_bursts = _plan_bursts(1, wave_plan)
	for s in START_SQUADS:
		var min_speed := INF
		for i in count:
			if unit_squad[i] == s:
				min_speed = minf(min_speed, type_speed[unit_type[i]])
		squad_speed[s] = 0.75 * min_speed
	_add_start_units()
	for r in _cards():   # карточки, заданные до старта (бенчи): разовые эффекты сразу
		apply_on_pick(r)
	_prepare_cards()
	if hero_on:
		_spawn_hero(1.0)


func _setup_rendering() -> void:
	# Атлас: ячейки 16x16 в ряд. По порядку id типов — кадры листа каждого типа со спрайтом (type_sprite_base,
	# type_sprite_frames), последняя ячейка белая (цветные квадраты). Собирается в памяти; файлы PNG не меняются.
	# Лист не загрузился или не подошёл (высота не 16, ширина не кратна 16, кадров не 1-3) — тип рисуется квадратом,
	# с одним предупреждением.
	var sheets: Array[Image] = []
	type_sprite_scale.resize(type_sprite.size())
	type_sprite_scale.fill(1.0)
	type_sprite_scale[knight_type] = KNIGHT_SPRITE_SCALE
	type_walk_rate.resize(type_sprite.size())
	type_walk_rate.fill(0.0)
	if ZOMBIE_WALK_FRAME_T > 0.0:
		type_walk_rate[zombie_type] = 1.0 / ZOMBIE_WALK_FRAME_T
		type_walk_rate[runner_type] = RUNNER_ANIM_SPEED / ZOMBIE_WALK_FRAME_T
	atlas_cells = 0
	for t in type_sprite.size():
		type_sprite_frames[t] = 0
		type_sprite_base[t] = atlas_cells
		if type_sprite[t] == "":
			continue
		var tex := load(type_sprite[t]) as Texture2D if ResourceLoader.exists(type_sprite[t]) else null
		var sheet: Image = tex.get_image() if tex != null else null
		if sheet == null or sheet.get_height() != SPRITE_PX or sheet.get_width() % SPRITE_PX != 0 \
				or sheet.get_width() / SPRITE_PX < 1 or sheet.get_width() / SPRITE_PX > SPRITE_FRAMES_MAX:
			push_warning("Лист спрайта %s типа \"%s\" не подходит (нужны 1-%d кадров %dx%d в ряд): тип рисуется квадратами" % [
				type_sprite[t], type_label[t], SPRITE_FRAMES_MAX, SPRITE_PX, SPRITE_PX])
			continue
		if sheet.is_compressed():
			sheet.decompress()
		sheet.convert(Image.FORMAT_RGBA8)
		type_sprite_frames[t] = sheet.get_width() / SPRITE_PX
		atlas_cells += type_sprite_frames[t]
		sheets.append(sheet)
	cell_white = atlas_cells
	atlas_cells += 1
	var atlas := Image.create(SPRITE_PX * atlas_cells, SPRITE_PX, false, Image.FORMAT_RGBA8)
	atlas.fill_rect(Rect2i(SPRITE_PX * cell_white, 0, SPRITE_PX, SPRITE_PX), Color.WHITE)
	var next_sheet := 0
	for t in type_sprite.size():
		if type_sprite_frames[t] > 0:
			atlas.blit_rect(sheets[next_sheet], Rect2i(0, 0, SPRITE_PX * type_sprite_frames[t], SPRITE_PX), Vector2i(SPRITE_PX * type_sprite_base[t], 0))
			next_sheet += 1

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true   # custom.x = ячейка атласа
	# Единичный квадрат с явными UV (левый верх картинки — левый верх на экране); размер и поворот задаёт трансформ инстанса.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var quad := ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	multimesh.mesh = quad
	multimesh.instance_count = MAX_UNITS   # рисуется только visible_instance_count = count
	# Границы заданы явно (всё поле с запасом): иначе при смене сцены (change_scene_to_file) первый кадр рисуется до
	# первого _process, границы считаются по пустому буферу и юниты потом отсекаются как невидимые.
	multimesh.custom_aabb = AABB(Vector3(-FIELD.x, -FIELD.y, 0.0), Vector3(FIELD.x * 3.0, FIELD.y * 3.0, 0.0))

	# Буфер заполняем целиком ОДИН раз: всё, что не меняется (альфа); матрица, позиция, цвет и ячейка — в _process
	buf.resize(MAX_UNITS * FLOATS_PER_UNIT)
	for i in MAX_UNITS:
		var o := i * FLOATS_PER_UNIT
		buf[o + 0] = UNIT_QUAD   # x.x
		buf[o + 5] = UNIT_QUAD   # y.y
		buf[o + 11] = 1.0   # альфа
		buf[o + 12] = cell_white

	# Шейдер: UV квадрата сдвигается в ячейку атласа custom.x; цвет инстанса умножается как обычно
	# (спрайт — белый, квадрат — цвет типа по белой ячейке). custom.y — мигание белым (удар героя, задача 11): 0 — как было, 1 — белый силуэт.
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform float cells = 1.0;\nvarying float flash;\nvoid vertex() {\n\tUV.x = (UV.x + INSTANCE_CUSTOM.x) / cells;\n\tflash = INSTANCE_CUSTOM.y;\n}\nvoid fragment() {\n\tCOLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash);\n}\n"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("cells", float(atlas_cells))
	var node := MultiMeshInstance2D.new()
	node.multimesh = multimesh
	node.texture = ImageTexture.create_from_image(atlas)   # без mipmaps
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.material = mat
	add_child(node)
	unit_node = node
	if hero_on:
		_setup_hero_view()   # после MultiMesh: над юнитами; интерфейс — в CanvasLayer, выше
	_setup_hit_fx()   # резня, слой крови (задача 23) — и без героя; с героем уже установлено (после его спрайта)
	_setup_arrow_fx()


func _setup_fps_label() -> void:
	var layer := CanvasLayer.new()
	# Пауза: лёгкое затемнение поля под интерфейсом (первый в слое) и надпись под HUD
	pause_dim = ColorRect.new()
	pause_dim.color = Color(0.0, 0.0, 0.0, 0.12)
	pause_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_dim.visible = false
	layer.add_child(pause_dim)
	_load_ui_layout()
	if debug_fps_on():
		# Отладочная строка FPS (задача 24): внизу слева, вне окошек верхней панели и панели отрядов; растёт вверх
		fps_label = Label.new()
		fps_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		fps_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		fps_label.offset_left = 16.0
		fps_label.offset_top = -16.0
		fps_label.offset_bottom = -16.0   # нижний край на 16 px от низа экрана, высота — вверх
		fps_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		fps_label.add_theme_font_size_override("font_size", FONTS.px(13))
		fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
		fps_label.add_theme_constant_override("outline_size", FONTS.outline(4))
		fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(fps_label)
		fps_label.add_to_group(&"shot_hidden")   # режим скриншотов (задача 25): на кадрах нет
	# Баннер по центру сверху (верх на BANNER_TOP): заголовок, текст, дневник, подсказка на универсальной панели;
	# ширина BANNER_WIDTH вместе с полями панели, перенос по словам
	banner = PanelContainer.new()
	UI.frame_panel(banner)
	banner.self_modulate.a = BANNER_BG_ALPHA   # только рамка панели, не текст
	var banner_pad := UI.panel_margins().x   # поля панели слева и справа
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE   # клики по карте проходят сквозь баннер
	var banner_box := VBoxContainer.new()
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(banner_box)
	for k in 4:
		var l := Label.new()
		l.custom_minimum_size.x = BANNER_WIDTH - banner_pad
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", FONTS.px(44 if k == 0 else 36))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", FONTS.outline(8))
		if k == 2:
			l.add_theme_color_override("font_color", STORY_COLOR)
		l.visible = false
		banner_box.add_child(l)
		banner_labels.append(l)
	radiance_label = Label.new()   # «+N Сияния»: только на экране итога, перед подсказкой
	radiance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	radiance_label.add_theme_font_size_override("font_size", FONTS.px(36))
	radiance_label.add_theme_color_override("font_color", RADIANCE_COLOR)
	radiance_label.add_theme_color_override("font_outline_color", Color.BLACK)
	radiance_label.add_theme_constant_override("outline_size", FONTS.outline(8))
	radiance_label.visible = false
	banner_box.add_child(radiance_label)
	banner_box.move_child(radiance_label, 3)
	hub_button = Button.new()   # только на экране конца забега; баннер клики пропускает, кнопка — нет
	hub_button.text = "HUD_TO_HUB"
	hub_button.add_theme_font_size_override("font_size", FONTS.px(36))
	UI.frame_button(hub_button)
	hub_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hub_button.visible = false
	hub_button.pressed.connect(_to_hub)
	banner_box.add_child(hub_button)
	banner.visible = false
	layer.add_child(banner)
	esc_menu = ESC_MENU.new()
	esc_menu.before_menu = _abandon_run
	add_child(esc_menu)
	card_screen = CARD_PICK.new()
	card_screen.picked.connect(choose_card)
	card_screen.closed.connect(_on_cards_closed)
	add_child(card_screen)
	# Выбранные карточки: справа сверху, компактным списком названий
	cards_box = VBoxContainer.new()
	cards_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cards_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cards_box.position = Vector2(-16.0, 8.0)
	cards_box.add_theme_constant_override("separation", 0)
	cards_label = Label.new()
	cards_label.text = "HUD_CARDS"
	cards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cards_label.add_theme_font_size_override("font_size", FONTS.px(18))
	cards_label.add_theme_color_override("font_outline_color", Color.BLACK)
	cards_label.add_theme_constant_override("outline_size", FONTS.outline(5))
	cards_label.visible = false
	cards_box.add_child(cards_label)
	layer.add_child(cards_box)
	# Верхняя панель боя по центру сверху (задача 19); выбранные карточки справа и строка разведки слева — под ней
	top_hud = TOP_HUD.new()
	top_hud.source = _hud_value
	layer.add_child(top_hud)
	var below_hud := top_hud.bottom() + float(top_hud.cfg.gap)
	cards_box.position.y = below_hud
	info_label = Label.new()
	info_label.position = Vector2(16.0, below_hud)
	info_label.custom_minimum_size.x = INFO_WIDTH
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # уже переведённые строки
	info_label.add_theme_font_size_override("font_size", FONTS.px(22))
	info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	info_label.add_theme_constant_override("outline_size", FONTS.outline(6))
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(info_label)
	radiance_slot = TOP_HUD.corner_slot()   # «Сияние» на экране итога: баланс после забега и «+N» под окошком
	radiance_slot.visible = false
	layer.add_child(radiance_slot)
	radiance_earned_label = Label.new()
	radiance_earned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	radiance_earned_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	radiance_earned_label.add_theme_font_size_override("font_size", FONTS.px(22))
	radiance_earned_label.add_theme_color_override("font_color", RADIANCE_COLOR)
	radiance_earned_label.add_theme_color_override("font_outline_color", Color.BLACK)
	radiance_earned_label.add_theme_constant_override("outline_size", FONTS.outline(6))
	radiance_earned_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radiance_earned_label.visible = false
	layer.add_child(radiance_earned_label)
	# Сигнал всплеска: надпись вверху по центру, под HUD (без чисел и типов)
	burst_label = Label.new()
	burst_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	burst_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	burst_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	burst_label.position.y = top_hud.bottom() + 4.0   # сразу под панелью
	burst_label.add_theme_font_size_override("font_size", FONTS.px(30))
	burst_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	burst_label.add_theme_color_override("font_outline_color", Color.BLACK)
	burst_label.add_theme_constant_override("outline_size", FONTS.outline(8))
	burst_label.visible = false
	layer.add_child(burst_label)
	pause_label = Label.new()
	pause_label.text = "HUD_PAUSED"
	pause_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_label.position.y = burst_label.position.y + 40.0   # под панелью и строкой сигнала всплеска
	pause_label.add_theme_font_size_override("font_size", FONTS.px(30))
	pause_label.add_theme_color_override("font_outline_color", Color.BLACK)
	pause_label.add_theme_constant_override("outline_size", FONTS.outline(8))
	pause_label.visible = false
	layer.add_child(pause_label)
	hero_fallen_panel = PanelContainer.new()   # «Командир пал» (задача 10) на универсальной панели: пока приказы заблокированы
	UI.frame_panel(hero_fallen_panel)
	hero_fallen_panel.self_modulate.a = BANNER_BG_ALPHA
	hero_fallen_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_fallen_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hero_fallen_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hero_fallen_panel.position.y = 156.0   # под меткой паузы
	hero_fallen_label = Label.new()
	hero_fallen_label.text = "HUD_HERO_FALLEN"
	hero_fallen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_fallen_label.add_theme_font_size_override("font_size", FONTS.px(30))
	hero_fallen_label.add_theme_color_override("font_color", Color("#e43b44"))   # Endesga 32
	hero_fallen_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hero_fallen_label.add_theme_constant_override("outline_size", FONTS.outline(8))
	hero_fallen_label.visible = false
	hero_fallen_panel.add_child(hero_fallen_label)
	hero_fallen_panel.visible = false
	layer.add_child(hero_fallen_panel)
	# Магазин справа — выдвижная панель (задача 24): в передышке развёрнута, в начале волны уезжает за край экрана; кнопка под ней
	# и клавиша shop_toggle сворачивают и разворачивают. Внутри два блока: «Войска» (наборы отрядов) и «Улучшения». Панель
	# (MOUSE_FILTER_STOP) забирает клики — на поле боя они не проходят.
	shop_panel = PanelContainer.new()
	UI.frame_panel(shop_panel)
	shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var shop_box := VBoxContainer.new()
	shop_panel.add_child(shop_box)
	portraits.load_defs()
	for block in 2:   # 0 — войска (товары с типом юнита), 1 — улучшения
		var head := Label.new()
		head.text = "HUD_SHOP_TROOPS" if block == 0 else "HUD_SHOP_UPGRADES"
		head.add_theme_font_size_override("font_size", FONTS.px(FONTS.DEFAULT_SIZE))
		head.add_theme_color_override("font_color", SHOP_HEAD_COLOR)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shop_box.add_child(head)
		shop_blocks.append(head)
		for k in SHOP_ITEMS.size():
			if SHOP_PORTRAIT.has(SHOP_ITEMS[k]) != (block == 0):
				continue
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE   # иначе Space «нажимает» последнюю кнопку
			_fixed_button(b, ui_layout.shop_button_size)
			UI.frame_kind(b, "shop")   # задача 24: рамка ui_btn_shop_c*.png, нет файла — универсальная кнопка
			b.pressed.connect(_buy.bind(k))
			b.set_meta("shop_k", k)
			shop_box.add_child(b)
			portraits.apply(b, SHOP_PORTRAIT.get(SHOP_ITEMS[k], ""))   # «Оружие» и «Ворота» — без иллюстрации
	shop_buttons.resize(SHOP_ITEMS.size())   # порядок SHOP_ITEMS (покупка k, клавиша k), а не порядок на панели
	for c in shop_box.get_children():
		if c is Button:
			shop_buttons[c.get_meta("shop_k")] = c
	layer.add_child(shop_panel)
	shop_tab = Button.new()
	shop_tab.focus_mode = Control.FOCUS_NONE
	_fixed_button(shop_tab, ui_layout.panel_toggle_size)
	shop_tab.autowrap_mode = TextServer.AUTOWRAP_OFF
	shop_tab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shop_tab.alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.frame_button(shop_tab, false)
	shop_tab.pressed.connect(toggle_shop)
	layer.add_child(shop_tab)
	# Отряды слева: цветной квадрат, клавиша, название, живые, приказ; строки кликабельны
	squad_panel = VBoxContainer.new()
	squad_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	squad_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	squad_panel.position.x = 16.0
	var st := get_node_or_null("/root/Settings")
	squad_expanded = st == null or st.squad_panel_expanded
	squad_toggle = Button.new()   # сверху панели: свернуть (квадратики и числа) / развернуть (строки, действия, Клич)
	squad_toggle.focus_mode = Control.FOCUS_NONE
	_fixed_button(squad_toggle, ui_layout.panel_toggle_size)
	squad_toggle.autowrap_mode = TextServer.AUTOWRAP_OFF
	squad_toggle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	squad_toggle.alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.frame_button(squad_toggle, false)
	squad_toggle.pressed.connect(toggle_squad_panel)
	squad_panel.add_child(squad_toggle)
	for s in SQUAD_MAX:   # строка на каждый индекс; свободные скрыты (_update_squad_panel)
		var row := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(18, 18)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sw)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true   # нажатая = выбранная
		_fixed_button(b, ui_layout.squad_button_size)
		UI.frame_kind(b, "squad")   # задача 24: рамка ui_btn_squad_c*.png, нет файла — универсальная кнопка
		b.autowrap_mode = TextServer.AUTOWRAP_OFF   # одна строка фиксированной высоты (задача 22): длинное — многоточием,
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # целиком — во всплывающей подсказке; панель не растёт
		b.pressed.connect(_on_row_pressed.bind(s))
		row.add_child(b)
		var c := Button.new()   # свёрнутая панель: число живых рядом с цветным квадратиком; клик выбирает, как строка
		c.focus_mode = Control.FOCUS_NONE
		c.toggle_mode = true
		_fixed_button(c, ui_layout.squad_compact_size)
		UI.frame_kind(c, "squad")
		c.autowrap_mode = TextServer.AUTOWRAP_OFF
		c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		c.pressed.connect(_on_row_pressed.bind(s))
		c.visible = false
		row.add_child(c)
		squad_compact.append(c)
		squad_panel.add_child(row)
		squad_buttons.append(b)
		squad_rows_ui.append(row)
		squad_swatches.append(sw)
	# Внизу панели: создание, разделение, слияние (видны только в передышке)
	squad_actions = HBoxContainer.new()
	var action_calls := [_cmd_new_squad, _cmd_split, _cmd_merge]
	for k in action_calls.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		_fixed_button(b, ui_layout.action_button_size)   # задача 24: одна ширина на все три (рамка одного размера)
		b.autowrap_mode = TextServer.AUTOWRAP_OFF   # одна строка; переназначенная длинная клавиша — многоточием, целиком в подсказке
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		UI.frame_button(b, false)   # универсальная рамка, размер из ui_layout
		b.pressed.connect(action_calls[k])
		squad_actions.add_child(b)
		action_buttons.append(b)
	squad_panel.add_child(squad_actions)
	# Деление: доля уходящих (10-90%, шаг 5%) и кто уходит
	split_box = VBoxContainer.new()
	var split_row := HBoxContainer.new()
	split_label = Label.new()
	split_label.custom_minimum_size.x = 150.0
	split_row.add_child(split_label)
	split_slider = HSlider.new()
	split_slider.min_value = 10.0
	split_slider.max_value = 90.0
	split_slider.step = 5.0
	split_slider.value = roundi(split_frac * 100.0)
	split_slider.custom_minimum_size = Vector2(150, 24)
	split_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	split_slider.value_changed.connect(_set_split_frac)
	split_row.add_child(split_slider)
	split_box.add_child(split_row)
	split_mode_button = Button.new()
	split_mode_button.custom_minimum_size = Vector2(0, ui_layout.action_button_size.y)
	split_mode_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	split_mode_button.pressed.connect(_next_split_mode)
	split_box.add_child(split_mode_button)
	squad_panel.add_child(split_box)
	_update_split_ui()
	hint_label = Label.new()
	_setup_war_cry_ui(layer)
	hint_label.text = "HUD_MOUSE_HINT"
	hint_label.add_to_group(&"shot_hidden")   # служебная подсказка — не на скриншотах (задача 25)
	hint_label.add_theme_font_size_override("font_size", FONTS.px(13))
	hint_label.modulate = Color(1.0, 1.0, 1.0, 0.7)
	squad_panel.add_child(hint_label)
	layer.add_child(squad_panel)
	# Характеристики выбранного отряда (задача 26): тёмная панель под панелью отрядов, видна, пока отряд выбран
	squad_info = PanelContainer.new()
	UI.frame_panel_dark(squad_info)
	squad_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	squad_info.custom_minimum_size.x = ui_layout.info_width
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 0)
	squad_info.add_child(info_box)
	squad_info_title = Label.new()
	squad_info_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	squad_info_title.add_theme_font_size_override("font_size", FONTS.px(FONTS.DEFAULT_SIZE))
	squad_info_title.add_theme_color_override("font_color", INFO_FLASH_COLOR)
	info_box.add_child(squad_info_title)
	for fld in info_fields:
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # собранная строка
		l.add_theme_font_size_override("font_size", FONTS.px(18))
		info_box.add_child(l)
		squad_info_labels[fld] = l
	squad_info.visible = false
	layer.add_child(squad_info)
	hints = HINTS.new()
	hints.load_defs()
	layer.add_child(hints)
	add_child(layer)
	_no_focus(layer)
	_update_squad_panel()
	if wave_state == WS_RESPITE:
		_intro_text()   # задача 26: вступление не показывается само — отмечается прочитанным и ждёт в дневнике хаба
		_set_banner(func(): _show_banner("", "", tr("MSG_WAVE_START") % SETTINGS.key_label("wave_start")))
	_update_ui()


# Подписи с клавишами (кнопки отрядов, деления, магазина) — после переназначения в настройках.
func _on_settings_changed(key: String) -> void:
	if key == "input":
		war_cry_sig = -1   # клавиша в подписи Клича и строк отрядов
		squad_text_sig.fill(-1)
		_update_split_ui()
		_update_squad_panel()
		_update_ui()


# Ни один Control не берёт фокус клавиатуры: Space, Enter и стрелки не нажимают кнопки и не двигают ползунок.
func _no_focus(node: Node) -> void:
	if node is Control:
		(node as Control).focus_mode = Control.FOCUS_NONE
	for c in node.get_children():
		_no_focus(c)


# --- Выбор отрядов: sel_mask (бит на отряд) и sel_primary (главный) ---------------------

# Индексы выбранных отрядов по возрастанию.
func _sel_list() -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in SQUAD_MAX:
		if (sel_mask >> s) & 1 == 1:
			out.append(s)
	return out


func _is_sel(s: int) -> bool:
	return s >= 0 and (sel_mask >> s) & 1 == 1


# Выбранные отряды, которым можно приказать идти и строиться: с живыми юнитами и не ведомые (ведомому место задаёт ведущий).
func _order_list() -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in SQUAD_MAX:
		if (sel_mask >> s) & 1 == 1 and squad_used[s] == 1 and squad_n[s] > 0 and squad_follow[s] < 0:
			out.append(s)
	return out


# Выбрать можно занятый отряд игрока; без живых юнитов — только в передышке (созданный клавишей N ждёт покупки).
func _selectable(s: int) -> bool:
	return s >= 0 and s < SQUAD_MAX and squad_used[s] == 1 and squad_team[s] == 0 and (squad_n[s] > 0 or wave_state == WS_RESPITE)


func _select_only(s: int) -> void:
	if not _selectable(s):
		return   # клавиши 1-8: свободный индекс игнорируется
	sel_mask = 1 << s
	sel_primary = s
	_sel_changed()


# Shift: добавить отряд к выбранным или убрать из них.
func _toggle_sel(s: int) -> void:
	if not _selectable(s):
		return
	sel_mask ^= 1 << s
	if _is_sel(s):
		sel_primary = s
	elif sel_primary == s:
		sel_primary = _sel_nearest(s)
	_sel_changed()


func _select_all() -> void:
	var mask := 0
	for s in SQUAD_MAX:
		if _selectable(s):
			mask |= 1 << s
	_select_mask(mask, false)


func _clear_sel() -> void:
	sel_mask = 0
	sel_primary = -1
	_sel_changed()


# Выбрать набор (рамка, двойной клик, Ctrl+A); add — добавить к уже выбранным. Главный — prefer, если он в наборе,
# иначе прежний главный, иначе ближайший к нему.
func _select_mask(mask: int, add: bool, prefer := -1) -> void:
	sel_mask = (sel_mask | mask) if add else mask
	if _is_sel(prefer):
		sel_primary = prefer
	elif not _is_sel(sel_primary):
		sel_primary = _sel_nearest(maxi(sel_primary, 0))
	_sel_changed()


# Ближайший к s по индексу выбранный отряд (при равенстве — с меньшим индексом) или -1.
func _sel_nearest(s: int) -> int:
	for d in SQUAD_MAX:
		if _is_sel(s - d):
			return s - d
		if _is_sel(s + d):
			return s + d
	return -1


func _sel_changed() -> void:
	sel_touched = true    # выбор менял игрок (стартовый выбор отряда 1 ставится без этой функции) — для подсказок
	drag_active = false   # начатая протяжка относилась к прежнему набору
	_update_squad_panel()
	ui_t = 0.0            # подписи товаров «→ Отряд N» зависят от выбора
	queue_redraw()        # контуры и маркеры целей выбранных


# Выбор не держит свободные индексы и отряды без живых юнитов (кроме пустого отряда в передышке): бит снимается,
# главным становится ближайший оставшийся или -1.
func _prune_sel() -> void:
	if sel_mask == 0:
		return
	var mask := sel_mask
	for s in SQUAD_MAX:
		if (mask >> s) & 1 == 1 and not _selectable(s):
			mask &= ~(1 << s)
	if mask == sel_mask:
		return
	var old := sel_primary
	sel_mask = mask
	if not _is_sel(sel_primary):
		sel_primary = _sel_nearest(old)
	_sel_changed()


# Клик по строке панели: выбрать отряд, с Shift — добавить или убрать.
func _on_row_pressed(s: int) -> void:
	if mod_shift:
		_toggle_sel(s)
	else:
		_select_only(s)
	_update_squad_panel()   # кнопка-переключатель сама сменила вид: вернуть по выбору


# Отряд игрока под точкой p (ЛКМ): блок живых слотов (как в проверке пересечения), в который попала точка; из нескольких —
# тот, чей юнит ближе; мимо блоков — отряд ближайшего юнита игрока в PICK_RADIUS. Нет такого: -1.
func _pick_squad(p: Vector2) -> int:
	var near := PackedFloat32Array()
	near.resize(SQUAD_MAX)
	near.fill(INF)
	for i in count:
		var q := unit_squad[i]
		if q >= 0 and team[i] == 0:
			near[q] = minf(near[q], pos[i].distance_squared_to(p))
	var boxes := _squad_boxes()
	var best := -1
	for s in SQUAD_MAX:
		if squad_used[s] == 0 or squad_team[s] != 0 or near[s] == INF:
			continue
		if Geometry2D.is_point_in_polygon(p, _live_block(s, boxes, squad_pos[s])) and (best < 0 or near[s] < near[best]):
			best = s
	if best >= 0:
		return best
	for s in SQUAD_MAX:
		if squad_used[s] == 1 and squad_team[s] == 0 and near[s] <= PICK_RADIUS * PICK_RADIUS and (best < 0 or near[s] < near[best]):
			best = s
	return best


# ЛКМ-клик: отряд под курсором; Shift — добавить или убрать; двойной клик — все отряды того же типа (Shift — добавить).
# Мимо: без Shift выбор очищается.
func _click_select(p: Vector2, shift: bool, dbl: bool) -> void:
	var s := _pick_squad(p)
	if s < 0:
		if not shift:
			_clear_sel()
		return
	if dbl:
		var mask := 0
		for q in SQUAD_MAX:
			if squad_used[q] == 1 and squad_team[q] == 0 and squad_n[q] > 0 and squad_type[q] == squad_type[s]:
				mask |= 1 << q
		_select_mask(mask, shift, s)
	elif shift:
		_toggle_sel(s)
	else:
		_select_only(s)


# Рамка: отряды игрока, у которых центр в рамке или в ней не меньше BOX_SELECT_FRAC живых. add (Shift) — добавить;
# без Shift выбор заменяется (пустая рамка его очищает).
func _box_select(r: Rect2, add: bool) -> void:
	var inside := PackedInt32Array()
	inside.resize(SQUAD_MAX)
	for i in count:
		var q := unit_squad[i]
		if q >= 0 and team[i] == 0 and r.has_point(pos[i]):
			inside[q] += 1
	var mask := 0
	for s in SQUAD_MAX:
		if squad_used[s] == 1 and squad_team[s] == 0 and squad_n[s] > 0 and (r.has_point(squad_pos[s]) or inside[s] >= BOX_SELECT_FRAC * squad_n[s]):
			mask |= 1 << s
	if mask != 0 or not add:
		_select_mask(mask, add)


# Приказ всем выбранным отрядам.
func _set_order(o: int) -> void:
	if _orders_locked():
		return   # командир пал: приказы до конца волны недоступны
	for s in _sel_list():
		squad_order[s] = o
		if o == ORDER_RETREAT and squad_follow[s] < 0:
			squad_target[s] = gate_spot(s)   # отход — к своей точке у ворот (ведомый идёт за ведущим)
	_update_squad_panel()


# Точка отряда s у ворот: отход и появление нового отряда. Точки разнесены по номеру отряда (GATE_SPOTS, шаг GATE_SPOT_DX),
# чтобы отряды не сходились в одну; центр строя выше стены на 40 px и на половину глубины строя (большой отряд не упирается в стену).
func gate_spot(s: int) -> Vector2:
	return Vector2(GATE_POS.x + GATE_SPOTS[s % GATE_SPOTS.size()] * GATE_SPOT_DX, WALL_Y - 40.0 - squad_depth[s] * 0.5)


# Название отряда для панели и магазина: label типа, а если отрядов этого типа несколько — с номером по порядку.
# Номер отряда среди отрядов его типа (0 — отряд этого типа один): то, от чего зависит _squad_label, без строк.
func _squad_rank(s: int) -> int:
	var same := 0
	var rank := 0
	for q in SQUAD_MAX:
		if squad_used[q] == 1 and squad_type[q] == squad_type[s]:
			same += 1
			if q <= s:
				rank += 1
	return 0 if same < 2 else rank


func _squad_label(s: int) -> String:
	var same := 0
	var rank := 0
	for q in SQUAD_MAX:
		if squad_used[q] == 1 and squad_type[q] == squad_type[s]:
			same += 1
			if q <= s:
				rank += 1
	return tr(type_label[squad_type[s]]) if same < 2 else "%s %d" % [tr(type_label[squad_type[s]]), rank]


# --- Выдвижной магазин (задача 24) ---------------------------------------------------------------------------------------

# Кнопка и клавиша shop_toggle: свернуть или развернуть магазин. Только в передышке — в бою он закрыт (покупки только в передышке).
func toggle_shop() -> void:
	if wave_state != WS_RESPITE or shop_panel == null:
		return
	shop_open = not shop_open
	_update_shop_tab()


# Подпись кнопки под магазином (с актуальной клавишей); в бою кнопки нет.
func _update_shop_tab() -> void:
	if shop_tab == null:
		return
	shop_tab.visible = wave_state == WS_RESPITE
	var t: String = tr("HUD_SHOP_HIDE" if shop_open else "HUD_SHOP_SHOW") % SETTINGS.key_label("shop_toggle")
	if shop_tab.text != t:
		shop_tab.text = t
		shop_tab.tooltip_text = t
	_place_shop()


# Анимация выезда: shop_slide идёт к 1 (открыт) или 0 (закрыт) за shop_slide_time; каждый кадр из _process.
func shop_slide_step(delta: float) -> void:
	if shop_panel == null:
		return
	var target := 1.0 if shop_open else 0.0
	if shop_slide == target:
		return
	var dur: float = ui_layout.shop_slide_time
	shop_slide = move_toward(shop_slide, target, delta / dur if dur > 0.0 else 1.0)
	_place_shop()


# Положение магазина по доле выезда: открыт — правый край в 16 px от края экрана, закрыт — целиком за правым краем (и скрыт);
# по вертикали — по центру. Кнопка сворачивания стоит на месте: под магазином, у правого края.
func _place_shop() -> void:
	var vp := shop_panel.get_viewport_rect().size
	shop_panel.size = shop_panel.get_combined_minimum_size()
	var sz := shop_panel.size
	var e := smoothstep(0.0, 1.0, shop_slide)
	shop_panel.position = Vector2(roundf(lerpf(vp.x, vp.x - SHOP_EDGE - sz.x, e)), roundf((vp.y - sz.y) * 0.5))
	shop_panel.visible = shop_slide > 0.0
	shop_tab.position = Vector2(vp.x - SHOP_EDGE - shop_tab.size.x, shop_panel.position.y + sz.y + SHOP_TAB_GAP)


# --- Панель отрядов: развёрнутая и свёрнутая (задача 24) --------------------------------------------------------------------

# Кнопка и клавиша squad_panel_toggle; состояние хранится в настройках (Settings.squad_panel_expanded).
func toggle_squad_panel() -> void:
	squad_expanded = not squad_expanded
	var st := get_node_or_null("/root/Settings")
	if st != null:
		st.set_squad_panel_expanded(squad_expanded)
	_update_squad_panel()


# Левая панель отрядов: раз в 0.25 с и сразу при выборе / смене приказа. Строки свободных индексов скрыты,
# кнопки создания, разделения и слияния видны в передышке и на паузе в бою (на паузе работает только деление).
func _update_squad_panel() -> void:
	if squad_panel == null:
		return
	var acts := wave_state == WS_RESPITE or paused
	var ex := squad_expanded
	var sig := (1 if acts else 0) | (1 << 12 if ex else 0)
	for s in SQUAD_MAX:
		squad_rows_ui[s].visible = squad_used[s] == 1
		if squad_used[s] == 0:
			continue
		sig |= 2 << s
		squad_buttons[s].visible = ex
		squad_compact[s].visible = not ex
		squad_buttons[s].set_pressed_no_signal(_is_sel(s))
		squad_compact[s].set_pressed_no_signal(_is_sel(s))
		var tsig := (((squad_n[s] * 16 + squad_order[s]) * 2 + squad_skill_on[s]) * 64 + squad_type[s]) * 64 + _squad_rank(s)
		if squad_text_sig.size() == SQUAD_MAX and tsig == squad_text_sig[s]:
			continue   # подпись та же: строки не собираются
		if squad_text_sig.size() != SQUAD_MAX:
			squad_text_sig.resize(SQUAD_MAX)
			squad_text_sig.fill(-1)
		squad_text_sig[s] = tsig
		squad_swatches[s].color = type_color[squad_type[s]]
		portraits.apply(squad_buttons[s], type_id.find_key(squad_type[s]))   # тип отряда мог смениться (слияние, новый отряд)
		squad_buttons[s].text = "%s  %s — %d — %s" % [SETTINGS.key_label("squad_select_%d" % (s + 1)), _squad_label(s), squad_n[s], tr(ORDER_NAMES[squad_order[s]])]
		if squad_skill_on[s] == 1:   # навык «Стена щитов» действует — отметка и золотой цвет, как у горящих карточек
			squad_buttons[s].text += "  ● " + tr("UI_SKILL_SHIELD_WALL")
		squad_buttons[s].tooltip_text = squad_buttons[s].text   # строка может быть сокращена многоточием
		squad_compact[s].text = "%s  %d" % [SETTINGS.key_label("squad_select_%d" % (s + 1)), squad_n[s]]
		squad_compact[s].tooltip_text = squad_buttons[s].text
		_fit_text(squad_buttons[s])
		squad_buttons[s].add_theme_color_override("font_color", CARD_ON if squad_skill_on[s] == 1 else Color.WHITE)
	squad_actions.visible = acts and ex
	hint_label.visible = ex
	if war_cry_box != null:
		war_cry_box.visible = ex   # Клич — в развёрнутой панели; клавиша действует и в свёрнутой
	var tt: String = tr("HUD_SQUADS_COLLAPSE" if ex else "HUD_SQUADS_EXPAND") % SETTINGS.key_label("squad_panel_toggle")
	if squad_toggle.text != tt:
		squad_toggle.text = tt
		squad_toggle.tooltip_text = tt
	for k in action_buttons.size():   # подписи с актуальной клавишей (её могли переназначить)
		var t: String = tr(ACTION_TEXTS[k]) % SETTINGS.key_label(ACTION_KEYS[k])
		if action_buttons[k].text != t:
			action_buttons[k].text = t
			action_buttons[k].tooltip_text = t
			_fit_text(action_buttons[k])
	split_box.visible = acts and ex
	action_buttons[0].disabled = wave_state != WS_RESPITE   # новый отряд и слияние — только в передышке
	action_buttons[2].disabled = wave_state != WS_RESPITE
	if sig != squad_panel_sig:
		squad_panel_sig = sig
		# набор строк изменился: размер по содержимому, снова по центру левого края
		squad_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_update_squad_info()


# --- Подсказки первой минуты (задача 26) ------------------------------------------------------------------------------------

# Условия появления подсказок (имена — when в data/hints.json); squad_selected — отряд выбрал сам игрок. Не во время выбора карточки, паузы и экрана конца забега.
# Только чтение состояния боя.
func hint_conditions() -> Dictionary:
	var free := not _run_over() and not _picking() and not paused and not (esc_menu != null and esc_menu.visible)
	var near := false
	if free and wave_state == WS_BATTLE and hero_idx >= 0 and hero_idx < count and hp[hero_idx] > 0.0 and hints != null:
		near = _nearest_zombie_coarse(pos[hero_idx], float(hints.cfg.get("enemy_near_paces", 8)) * UNITS.world_unit_px()) >= 0
	return {"battle_start": free and wave_state == WS_BATTLE, "squad_selected": free and sel_touched and sel_mask != 0, "enemy_near_hero": near,
		"respite_after_wave": free and wave_state == WS_RESPITE and wave_number >= 1}


# Итоги боя для журнала забегов (Game.end_run).
func _run_stats() -> Dictionary:
	return {"hero_deaths": hero_deaths, "gold_spent": gold_spent}


# Действие игрока для подсказок (done_on): order, hero_attack, buy.
func _hint_event(name: String) -> void:
	if hints != null:
		hints.event(name)


# --- Характеристики отряда и «до → после» в магазине (задача 26) ------------------------------------------------------------
# Числа — из тех же массивов и функций, что у симуляции (type_*, _cd_actual, _wave_data); только чтение.

# Средний интервал удара типа t, с: по данным wd (_wave_data) или текущим. С переносом остатка (cd_floor != 0) — ровно
# cooldown, без него cooldown убывает шагами решения и интервал — _cd_actual(cooldown).
func _attack_interval(t: int, wd := {}) -> float:
	var cd: float = (type_cooldown if wd.is_empty() else wd.cooldown)[t]
	var fl: float = (type_cd_floor if wd.is_empty() else wd.cd_floor)[t]
	return cd if fl != 0.0 else _cd_actual(cd)


# Урон удара типа t (у стрелков — стрелы) по данным wd или текущим.
func _type_damage_of(t: int, wd := {}) -> float:
	if type_range_far[t] > 0.0:
		return (type_arrow_dmg if wd.is_empty() else wd.arrow)[t]
	return (type_damage if wd.is_empty() else wd.damage)[t]


# Характеристики отряда s: поле -> число. alive — живых, hp — средний HP, hp_max — максимум бойца, damage — урон удара,
# range — дальность px мира (стрелки — стрельбы), attack_rate — ударов в секунду (с бонусами отряда: Клич, карточки),
# speed — скорость строя px/с.
func squad_stats(s: int) -> Dictionary:
	var t := squad_type[s]
	var sum := 0.0
	var n := 0
	for i in count:
		if unit_squad[i] == s:
			sum += hp[i]
			n += 1
	var interval := _attack_interval(t) / squad_atk_speed_mult[s]
	return {"alive": squad_n[s], "hp": sum / n if n > 0 else 0.0, "hp_max": type_hp[t], "damage": _type_damage_of(t),
		"range": type_range_far[t] if type_range_far[t] > 0.0 else sqrt(type_range_sq[t]),
		"attack_rate": 1.0 / interval if interval > 0.0 else 0.0, "speed": squad_speed[s] * squad_speed_mult[s]}


# Строка поля для игрока.
func info_text(fld: String, st: Dictionary) -> String:
	match fld:
		"alive":
			return tr("HUD_INFO_ALIVE") % st.alive
		"hp":
			return tr("HUD_INFO_HP") % [UNITS.num(st.hp, 1), UNITS.num(st.hp_max, 1)]
		"damage":
			return tr("HUD_INFO_DAMAGE") % UNITS.num(st.damage, 2)
		"range":
			return tr("HUD_INFO_RANGE") % UNITS.dist_text(st.range)
		"attack_rate":
			return tr("HUD_INFO_ATTACK_RATE") % UNITS.num(st.attack_rate, 2)
		"speed":
			return tr("HUD_INFO_SPEED") % UNITS.dist_text(st.speed)
	return ""


# Панель характеристик главного выбранного отряда; число, изменённое покупкой, подсвечено info_flash_time с.
func _update_squad_info() -> void:
	if squad_info == null:
		return
	var s := sel_primary
	var on := s >= 0 and squad_used[s] == 1 and squad_n[s] > 0 and squad_team[s] == 0
	squad_info.visible = on
	if not on:
		info_for = -1
		return
	var st := squad_stats(s)
	var now := Time.get_ticks_msec()
	squad_info_title.text = "%d  %s" % [s + 1, _squad_label(s)]
	for fld in info_fields:
		var l: Label = squad_info_labels[fld]
		var t := info_text(fld, st)
		if l.text != t:
			l.text = t
		var lit: bool = info_flash.get(fld, 0) > now
		l.add_theme_color_override("font_color", INFO_FLASH_COLOR if lit else Color.WHITE)
	info_for = s
	info_shown = st
	squad_info.size = squad_info.get_combined_minimum_size()
	# под панелью отрядов у левого края (не на поле, где стоят войска); не помещается снизу — над ней
	var below := squad_panel.position.y + squad_panel.size.y + 12.0
	var vp := squad_info.get_viewport_rect().size
	squad_info.position = Vector2(squad_panel.position.x, below if below + squad_info.size.y <= vp.y - 16.0
		else maxf(squad_panel.position.y - 12.0 - squad_info.size.y, 16.0))
	for id in hud_flash:
		if top_hud != null and top_hud.slots.has(id):
			top_hud.slots[id].modulate = INFO_FLASH_COLOR if hud_flash[id] > now else Color.WHITE


# Что покажет панель и верхняя панель до покупки (снимок для подсветки изменённого).
func _flash_snapshot() -> Dictionary:
	var out := {"hud": {}, "info": {}}
	if top_hud == null:
		return out   # бенчи без интерфейса
	for id in top_hud.slots:
		if id != "gold":
			out.hud[id] = _hud_value(id)
	if sel_primary >= 0 and squad_used[sel_primary] == 1 and squad_n[sel_primary] > 0:
		out.info = squad_stats(sel_primary)
	return out


# После покупки: изменившиеся числа подсвечиваются на info_flash_time с (поля панели отряда, окошки верхней панели).
func _flash_changes(before: Dictionary) -> void:
	if top_hud == null:
		return
	var until := Time.get_ticks_msec() + int(ui_layout.info_flash_time * 1000.0)
	for id in before.hud:
		if _hud_value(id) != before.hud[id]:
			hud_flash[id] = until
	if not before.info.is_empty() and sel_primary >= 0 and squad_n[sel_primary] > 0:
		var now_st := squad_stats(sel_primary)
		for fld in info_fields:
			var k: String = "hp_max" if fld == "hp" else fld
			if not is_equal_approx(float(now_st[k]), float(before.info[k])):
				info_flash[fld] = until
	_update_squad_info()


# «До → после» покупки товара k: [[подпись, до, после, формат], ...]; формат — "rate" (ударов/с), "num", "int".
# Оружие — _wave_data с покупками сейчас и с ещё одной (та же функция, что пересчитывает данные волны);
# ворота — прибавка, как в _buy; набор — живых в отряде, куда пойдёт покупка, и + amount.
func shop_preview(k: int) -> Array:
	var out := []
	match SHOP_ITEMS[k]:
		"weapons":
			var b1 := shop_bought.duplicate()
			b1[k] += 1
			var w0 := _wave_data(shop_bought)
			var w1 := _wave_data(b1)
			var types := [infantry_type, archer_type]
			if type_enabled[spearman_type] == 1:
				types.append(spearman_type)
			for t in types:
				if weapon_stat == "attack_rate":
					out.append([tr(type_label[t]), 1.0 / _attack_interval(t, w0), 1.0 / _attack_interval(t, w1), "rate"])
				else:
					out.append([tr(type_label[t]), _type_damage_of(t, w0), _type_damage_of(t, w1), "num"])
		"gate":
			out.append([tr("HUD_STAT_GATE"), gate_hp_max, _gate_after_buy(gate_hp_max), "int"])
		_:
			var pack_type: int = {"inf_pack": infantry_type, "archer_pack": archer_type, "spear_pack": spearman_type}[SHOP_ITEMS[k]]
			var tg := _buy_target(pack_type)
			var n0 := squad_n[tg] if squad_used[tg] == 1 and squad_type[tg] == pack_type else 0
			out.append([tr("HUD_STAT_ALIVE"), n0, n0 + int(shop_param[k]), "int"])
	return out


# Число для «до → после».
func preview_num(v: float, fmt: String) -> String:
	match fmt:
		"rate":
			return tr("HUD_STAT_RATE") % UNITS.num(v, 2)
		"int":
			return str(roundi(v))
	return UNITS.num(v, 2)


func preview_delta(e: Array) -> String:
	return tr("HUD_SHOP_DELTA") % [preview_num(e[1], e[3]), preview_num(e[2], e[3])]


# Максимум ворот после ещё одного ремонта (прибавка gate_max_gain; ею же пользуется _buy).
func _gate_after_buy(gmax: float) -> float:
	return gmax + shop_param[SHOP_ITEMS.find("gate")]


# data/ui_layout.json поверх значений по умолчанию: размеры — [w, h] больше 0, числа — больше 0, флаги — true или false.
# Нет файла или поле неверно — предупреждение, остаётся значение по умолчанию (только интерфейс).
func _load_ui_layout() -> void:
	if not FileAccess.file_exists(UI_LAYOUT_PATH):
		push_warning("Нет %s: размеры кнопок по умолчанию" % UI_LAYOUT_PATH)
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(UI_LAYOUT_PATH))
	if not d is Dictionary:
		push_warning("%s: нужен JSON-объект: размеры кнопок по умолчанию" % UI_LAYOUT_PATH)
		return
	for key in ui_layout:
		var v = d.get(key)
		if ui_layout[key] is Vector2 and v is Array and v.size() == 2 and v.all(func(x): return (x is float or x is int) and x > 0):
			ui_layout[key] = Vector2(v[0], v[1])
		elif ui_layout[key] is float and (v is float or v is int) and v > 0:
			ui_layout[key] = float(v)
		elif ui_layout[key] is bool and v is bool:
			ui_layout[key] = v
		else:
			push_warning("%s: %s — %s; остаётся %s" % [UI_LAYOUT_PATH, key, "[w, h] больше 0" if ui_layout[key] is Vector2
				else ("true или false" if ui_layout[key] is bool else "число больше 0"), str(ui_layout[key])])
	var f = d.get("squad_info_fields")
	if f is Array and not f.is_empty() and f.all(func(x): return INFO_FIELD_KEYS.has(x)):
		info_fields = f.duplicate()
	else:
		push_warning("%s: squad_info_fields — список из %s; остаётся %s" % [UI_LAYOUT_PATH, str(INFO_FIELD_KEYS.keys()), str(info_fields)])


# Отладочная строка FPS (задача 24): только в отладочной сборке и только при флаге — debug_fps в data/ui_layout.json
# (по умолчанию false) или параметр запуска --debug-fps. В релизной сборке строки нет вовсе.
func debug_fps_on() -> bool:
	return fps_wanted(OS.is_debug_build(), ui_layout.debug_fps or debug_fps_force, OS.get_cmdline_args() + OS.get_cmdline_user_args())


static func fps_wanted(debug_build: bool, flag: bool, args: PackedStringArray) -> bool:
	return debug_build and (flag or "--debug-fps" in args)


# Кнопка фиксированного размера: size — и минимум, и ширина (текст не растягивает кнопку: обрезка и перенос по словам, кегль — _fit_text).
func _fixed_button(b: Button, size: Vector2) -> void:
	b.custom_minimum_size = size
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# Кегль текста кнопки фиксированного размера: сначала самый крупный (от кегля темы до FIT_MIN_FONT), при котором строки
# помещаются без переноса; не нашёлся — самый крупный, при котором помещается с переносом по словам (часть уходит на вторую строку).
# Размер — за вычетом отступов. Пересчёт только при смене текста.
func _fit_text(b: Button) -> void:
	if b.get_meta("fit_text", "") == b.text:
		return
	b.set_meta("fit_text", b.text)
	b.remove_theme_font_size_override("font_size")
	var font := b.get_theme_font("font")
	var base := b.get_theme_font_size("font_size")
	var room := b.custom_minimum_size - b.get_theme_stylebox("normal").get_minimum_size()
	var fs := -1
	for wrap in [false, true]:
		for f in FONTS.fit_sizes(base, FIT_MIN_FONT):
			var sz := font.get_multiline_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, room.x if wrap else -1.0, f, -1,
				(TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE) if wrap else TextServer.BREAK_MANDATORY)
			if sz.x <= room.x + 0.5 and sz.y <= room.y + 0.5:
				fs = f
				break
		if fs > 0:
			break
	fs = FONTS.px(FIT_MIN_FONT) if fs < 0 else fs
	if fs != base:
		b.add_theme_font_size_override("font_size", fs)


# Кнопка Клича Благодати под списком отрядов (только если дар куплен) и подсветка краёв экрана.
func _setup_war_cry_ui(layer: CanvasLayer) -> void:
	if war_cry_level <= 0:
		return
	war_cry_box = VBoxContainer.new()
	war_cry_box.add_theme_constant_override("separation", 2)
	war_cry_button = Button.new()
	war_cry_button.focus_mode = Control.FOCUS_NONE
	_fixed_button(war_cry_button, ui_layout.war_cry_size)
	UI.frame_button(war_cry_button, false)   # универсальная рамка, размер из ui_layout
	war_cry_button.pressed.connect(request_war_cry)
	war_cry_box.add_child(war_cry_button)
	war_cry_bar = ProgressBar.new()
	war_cry_bar.show_percentage = false
	war_cry_bar.min_value = 0.0
	war_cry_bar.max_value = 1.0
	war_cry_bar.custom_minimum_size = Vector2(ui_layout.war_cry_size.x, 8)
	war_cry_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # ширина кнопки Клича, а не панели
	war_cry_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	war_cry_box.add_child(war_cry_bar)
	squad_panel.add_child(war_cry_box)
	for side in 4:   # тонкие полосы по краям экрана: верх, низ, лево, право
		var r := ColorRect.new()
		r.color = WAR_CRY_GLOW
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var a: Array = [[0, 0, 1, 0], [0, 1, 1, 1], [0, 0, 0, 1], [1, 0, 1, 1]][side]   # left, top, right, bottom якоря
		r.anchor_left = a[0]
		r.anchor_top = a[1]
		r.anchor_right = a[2]
		r.anchor_bottom = a[3]
		var o: Array = [[0, 0, 0, WAR_CRY_GLOW_PX], [0, -WAR_CRY_GLOW_PX, 0, 0], [0, 0, WAR_CRY_GLOW_PX, 0], [-WAR_CRY_GLOW_PX, 0, 0, 0]][side]
		r.offset_left = o[0]
		r.offset_top = o[1]
		r.offset_right = o[2]
		r.offset_bottom = o[3]
		r.visible = false
		layer.add_child(r)
		war_cry_glow.append(r)


# Вид кнопки: готов — полная полоса; действует — золотая кнопка, остаток времени и убывающая полоса; перезарядка — заполнение до готовности.
func _update_war_cry_ui() -> void:
	if war_cry_button == null:
		return
	var tps := float(Engine.physics_ticks_per_second)
	var active := war_cry_until >= 0
	var gold_tint := Color(1.0, 0.85, 0.35) if active else Color.WHITE
	war_cry_button.modulate = gold_tint
	# подпись — только когда сменились состояние или показываемое число (строки не собираются каждые 0.1 с)
	var sig := 0
	if active:
		sig = 1000000 + int((war_cry_until - tick_counter) / tps * 10.0)
		war_cry_bar.value = float(war_cry_until - tick_counter) / maxf(war_cry_dur, 1)
	elif wave_state != WS_BATTLE:
		sig = 2000000
		war_cry_bar.value = 1.0
	elif tick_counter + 1 < war_cry_ready:
		sig = 3000000 + ceili((war_cry_ready - tick_counter) / tps)
		war_cry_bar.value = 1.0 - float(war_cry_ready - tick_counter) / maxf(war_cry_cd, 1)
	else:
		sig = 4000000
		war_cry_bar.value = 1.0
	war_cry_button.disabled = not active and not war_cry_can()
	if sig != war_cry_sig:
		war_cry_sig = sig
		var key := SETTINGS.key_label("war_cry")
		if active:
			war_cry_button.text = tr("HUD_WAR_CRY_ACTIVE") % [key, "%.1f" % ((war_cry_until - tick_counter) / tps)]
		elif wave_state != WS_BATTLE:
			war_cry_button.text = tr("HUD_WAR_CRY_BATTLE") % key
		elif tick_counter + 1 < war_cry_ready:
			war_cry_button.text = tr("HUD_WAR_CRY_WAIT") % [key, "%d" % ceili((war_cry_ready - tick_counter) / tps)]
		else:
			war_cry_button.text = tr("HUD_WAR_CRY_READY") % key
		_fit_text(war_cry_button)
	war_cry_bar.modulate = gold_tint
	for r in war_cry_glow:
		r.visible = active


# Значение окошка верхней панели id: Vector2i(число, максимум или -1). Новое окошко в data/ui_layout.json с одним из этих id —
# без правки кода панели. Войска — живые юниты игрока в отрядах (сумма squad_n, как в списке отрядов); герой не в отряде и не считается.
func _hud_value(id: String) -> Vector2i:
	match id:
		"wave":
			return Vector2i(wave_number, waves_per_run if run_limit else -1)
		"zombies":
			return Vector2i(zombie_alive, -1)
		"zombies_left":
			return Vector2i(zombie_alive + wave_remaining, -1)   # живые и ещё не вышедшие (как было в строке HUD)
		"troops":
			var n := 0
			for s in SQUAD_MAX:
				if squad_used[s] == 1 and squad_team[s] == 0:
					n += squad_n[s]
			return Vector2i(n, -1)
		"gate":
			return Vector2i(ceili(maxf(gate_hp, 0.0)), roundi(gate_hp_max))
		"gold":
			return Vector2i(floori(gold), -1)
		"kills":
			return Vector2i(run_kills, -1)
	return Vector2i(0, -1)


# Разведка (в передышке) и сообщение об отказе команды — под панелью слева; текст собирается, только когда они поменялись.
func _update_info() -> void:
	var plan := scout_shown and waves_enabled and wave_state == WS_RESPITE
	if plan == info_plan and hud_msg == info_msg and (not plan or wave_plan_for == info_plan_for):
		return
	info_plan = plan
	info_plan_for = wave_plan_for
	info_msg = hud_msg
	var lines := PackedStringArray()
	if plan:
		lines.append(_plan_text())
	if hud_msg != "":
		lines.append(hud_msg)
	info_label.text = "\n".join(lines)


# HUD и магазин: раз в 0.1 с (и сразу после покупки).
func _update_ui() -> void:
	if top_hud == null:
		return
	hero_fallen_label.visible = _orders_locked()
	hero_fallen_panel.visible = hero_fallen_label.visible
	top_hud.update()
	_update_info()
	_update_war_cry_ui()
	if cards_box != null and not card_defs.is_empty():
		_update_cards_ui()
	burst_label.text = burst_msg
	burst_label.visible = wave_state == WS_BATTLE and burst_msg != "" and wave_t < burst_msg_until
	if hints != null:
		hints.poll(hint_conditions())
	if wave_state != shop_state_seen:   # начало волны — магазин уезжает, передышка — выезжает
		shop_state_seen = wave_state
		shop_open = wave_state == WS_RESPITE
	_update_shop_tab()
	if wave_state != WS_RESPITE:
		return
	for k in shop_buttons.size():
		shop_buttons[k].visible = shop_enabled[k] == 1   # выключенный товар скрыт
		if shop_enabled[k] == 0:
			continue
		var price := _price(k)
		var capped := _at_cap(k)
		_shop_text(k, tr("HUD_SHOP_MAX") if capped else tr("HUD_SHOP_PRICE") % ceili(price))
		shop_buttons[k].disabled = capped or gold < price   # серая при нехватке золота или на пределе
		_fit_text(shop_buttons[k])


# Подпись кнопки магазина — всегда две строки (задача 22: высота кнопки — две строки кегля темы с полями, data/ui_layout.json):
#   наборы:          «Z  +50 пехоты — 100 зол.» / «→ Отряд 1 (Пехота)»; не влезает в ширину — цена во вторую строку;
#   оружие, ворота:  «C  Оружие: скорость атаки +10%» / «150 зол.».
# Вторичное — во всплывающей подсказке: сколько куплено и клавиша целиком (длинная клавиша, например «Средняя кнопка мыши»,
# в подписи сокращается многоточием, если иначе строка не помещается).
func _shop_text(k: int, cost: String) -> void:
	var b := shop_buttons[k]
	var key := SETTINGS.key_label(SHOP_ACTIONS[k])
	var title := _shop_title(k)
	# Юниты идут в выбранный отряд своего типа, иначе в первый отряд типа (копейщиков без отряда — в новый).
	var pack_type: int = {"inf_pack": infantry_type, "archer_pack": archer_type, "spear_pack": spearman_type}.get(SHOP_ITEMS[k], -1)
	var font := b.get_theme_font("font")
	var fs := FONTS.px(FONTS.DEFAULT_SIZE)
	var room := b.custom_minimum_size.x - b.get_theme_stylebox("normal").get_minimum_size().x
	var line1 := title
	var line2 := cost
	if pack_type >= 0:
		var target := _buy_target(pack_type)
		var to: String = tr("HUD_SHOP_TARGET") % [target + 1, _squad_label(target)] if squad_used[target] == 1 and squad_type[target] == pack_type \
			else tr("HUD_SHOP_NEW_SQUAD")
		line1 = SHOP_LINE_TITLE_COST % [title, cost]
		line2 = to
		if font.get_string_size(tr("HUD_SHOP_ROW_TITLE") % [key, line1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			line1 = title   # цена — во вторую строку, перед отрядом
			line2 = SHOP_LINE_COST_TARGET % [cost, to]
	var pv := shop_preview(k)   # задача 26: «до → после» — в подсказке всё, на кнопке улучшения — первое, если помещается
	if pack_type < 0 and not pv.is_empty() and cost != tr("HUD_SHOP_MAX"):
		var with_delta: String = SHOP_LINE_COST_DELTA % [cost, preview_delta(pv[0])]
		if font.get_string_size(with_delta, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= room:
			line2 = with_delta
	var shown := key
	while shown.length() > 1 and font.get_string_size(tr("HUD_SHOP_ROW_TITLE") % [shown, line1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		shown = shown.left(shown.length() - (1 if shown == key else 2)) + "…"
	b.text = tr("HUD_SHOP_ROW_TITLE") % [shown, line1] + "\n" + line2
	var tip := tr("HUD_SHOP_TIP") % [key, shop_bought[k]]
	for e in pv:
		tip += "\n" + tr("HUD_SHOP_TIP_DELTA") % [e[0], preview_delta(e)]
	b.tooltip_text = tip


# Симуляция: фиксированный шаг (по умолчанию 30 раз в секунду)
var sim_ms := 0.0
var draw_ms := 0.0
# Профиль фаз тика (PROFILE; бенчи включают profile): сетка, юниты, движение, смерти, грубая сетка, остальное
const PROF_NAMES := ["сетка", "юниты", "движение", "смерти", "грубая", "остальное"]   # tr-skip: отладка или контекст лога
var profile := PROFILE
var prof_acc := PackedFloat64Array([0, 0, 0, 0, 0, 0])   # мкс за текущие 60 тиков
var prof_avg := PackedFloat64Array([0, 0, 0, 0, 0, 0])   # мс на тик, среднее за прошлые 60 тиков
var prof_n := 0

func _physics_process(delta: float) -> void:
	if paused:
		return   # активная пауза: симуляция стоит целиком
	var t := Time.get_ticks_usec()
	prev_pos = pos.duplicate()   # для интерполяции в _process
	tick_counter += 1
	if hero_on:
		_hero_input()   # ввод героя (движение, взгляд, удар) — раз в тик симуляции
	if war_cry_level > 0:
		_tick_war_cry()
	if wave_state == WS_BATTLE and tick_counter % COND_EVERY == 0:
		_update_card_conditions()
	_update_waves(delta)
	_update_squads(delta)
	_update_unit_dirs()
	# Таймеры анимации убывают у всех юнитов каждый тик (а не у обновляемой половины): кадр «атака» и ожидание
	# собственного выпуска стрелы в залпе — в момент выпуска начинается «атака» (и отдача).
	for i in count:
		if unit_anim_t[i] > 0.0:
			unit_anim_t[i] = maxf(unit_anim_t[i] - delta, 0.0)
		if unit_shot_t[i] > 0.0:
			unit_shot_t[i] -= delta
			if unit_shot_t[i] <= 0.0:
				unit_shot_t[i] = 0.0
				unit_anim_t[i] = ATTACK_ANIM_T
	var m0 := Time.get_ticks_usec() if profile else 0
	_build_grid()
	grid_ms = (Time.get_ticks_usec() - t) / 1000.0
	var m1 := Time.get_ticks_usec() if profile else 0
	# Лучники: грубая сетка и режим раз в COARSE_EVERY тиков; выстрелы и падение стрел — каждый тик.
	if tick_counter % COARSE_EVERY == 1:
		_rebuild_coarse()
		for s in SQUAD_MAX:
			if squad_used[s] == 1 and squad_n[s] > 0 and squad_ranged[s] == 1:
				_update_archer_mode(s)
	var m2 := Time.get_ticks_usec() if profile else 0
	_update_archers(delta)
	_process_arrows()   # после _build_grid: мелкая сетка этого тика ещё актуальна
	if hero_idx >= 0:
		_update_hero(delta)   # каждый тик (не через половину, как юниты): ввод и удар героя
	var m3 := Time.get_ticks_usec() if profile else 0
	# За тик обновляется половина юнитов: чётные, затем нечётные.
	# Направление (tick_parity) меняется раз в 2 тика, чтобы каждая половина
	# по очереди проходилась и вперёд, и назад.
	if not update_odd:
		tick_parity = not tick_parity
	var half := 1 if update_odd else 0
	update_odd = not update_odd
	var dt2 := delta * 2.0   # юнит обновляется раз в 2 тика
	if tick_parity:
		for i in range(half, count, 2):
			_update_unit(i, dt2)
	else:
		var last := count - 1
		if (last - half) % 2 != 0:
			last -= 1
		for i in range(last, -1, -2):
			_update_unit(i, dt2)
	var m4 := Time.get_ticks_usec() if profile else 0
	_move_units(delta)   # двигаются все юниты каждый тик, а не только обновлённая половина
	var m5 := Time.get_ticks_usec() if profile else 0
	_remove_dead()
	_prune_sel()   # отряд без живых уходит из выбора
	if profile:
		var m6 := Time.get_ticks_usec()
		prof_acc[0] += m1 - m0
		prof_acc[1] += m4 - m3
		prof_acc[2] += m5 - m4
		prof_acc[3] += m6 - m5
		prof_acc[4] += m2 - m1
		prof_acc[5] += (m0 - t) + (m3 - m2)   # волны, отряды, копия prev_pos, выстрелы и стрелы
		prof_n += 1
		if prof_n >= 60:
			for q in 6:
				prof_avg[q] = prof_acc[q] / prof_n / 1000.0
			prof_acc.fill(0.0)
			prof_n = 0
	if gate_hp <= 0.0 and not _run_over():
		_on_defeat()
	sim_ms = (Time.get_ticks_usec() - t) / 1000.0
	sim_avg = lerpf(sim_avg, sim_ms, 0.05)
	sim_peak = maxf(sim_ms, sim_peak * 0.98)
	sim_max = maxf(sim_max, sim_ms)

func _process(delta: float) -> void:
	var t := Time.get_ticks_usec()
	_camera_frame(delta)
	_update_fx(delta)
	shop_slide_step(delta)
	ui_t -= delta
	if ui_t <= 0.0:
		ui_t = 0.1
		_update_ui()
		queue_redraw()   # маркеры целей отрядов
	if wave_state == WS_BATTLE and wave_t < signal_redraw_until:
		queue_redraw()   # полоса сигнала гаснет плавно
	if sel_mask != 0:
		# контуры выбранных: перерисовка, когда отряд сдвинулся, повернулся или сменил состав (и на паузе)
		var sig := 0.0
		for s in SQUAD_MAX:
			if (sel_mask >> s) & 1 == 1:
				sig += squad_pos[s].x * 1.3 + squad_pos[s].y * 2.7 + squad_angle[s] * 97.0 + squad_n[s] * 13.0 + squad_width[s]
		if sig != sel_sig:
			sel_sig = sig
			queue_redraw()
	if hud_msg_t > 0.0:
		hud_msg_t -= delta
		if hud_msg_t <= 0.0:
			hud_msg = ""
			ui_t = 0.0
	panel_t -= delta
	if panel_t <= 0.0:
		panel_t = 0.25
		_update_squad_panel()
	if color_mode == 1:
		# F2: передний занятый ряд каждого отряда
		squad_front_row.fill(1 << 30)
		for i in count:
			var s := unit_squad[i]
			if s >= 0:
				squad_front_row[s] = mini(squad_front_row[s], unit_slot_idx[i] / squad_width[s])
	var now := tick_counter / float(Engine.physics_ticks_per_second)
	var by_type := color_mode == 0
	var frac := Engine.get_physics_interpolation_fraction()
	# до первого физического тика prev_pos пуст; на паузе — pos без интерполяции (доля тика продолжает меняться)
	var have_prev := prev_pos.size() == pos.size() and not paused
	var sprites := sprites_on and by_type   # F2-F4: все квадратами, чтобы отладочный цвет читался
	if not paused:
		anim_clock += delta
	var jitter := RENDER_JITTER > 0.0
	# Замах стрелков по отряду (как в _unit_anim_state): 1 — залп натягивается или ждёт цель, 2 — одиночный огонь.
	var draw_mode := PackedByteArray()
	draw_mode.resize(SQUAD_MAX)
	for s in SQUAD_MAX:
		if squad_used[s] == 1 and squad_ranged[s] == 1 and squad_order[s] != ORDER_RETREAT:
			draw_mode[s] = 2 if squad_volley_mode[s] == MODE_SINGLE else (1 if squad_volley_fired[s] == 0 else 0)
	for i in count:
		var o := i * FLOATS_PER_UNIT
		var ut := unit_type[i]
		var anim := unit_anim_t[i]
		var rp := prev_pos[i].lerp(pos[i], frac) if have_prev else pos[i]   # позиция между тиками
		if jitter:
			rp += unit_render_off[i]   # статичный сдвиг ±RENDER_JITTER
		if anim > 0.0 and type_recoil[ut] > 0.0:
			# отдача: назад от взгляда, линейно затухает за время «атаки»
			rp -= DIR_VEC[unit_dir[i]] * (type_recoil[ut] * anim / ATTACK_ANIM_T)
		buf[o + 3] = rp.x
		buf[o + 7] = rp.y
		if i == hero_idx:   # герой рисуется своей нодой (hero_view): его ячейка буфера нулевого размера
			buf[o + 0] = 0.0
			buf[o + 1] = 0.0
			buf[o + 4] = 0.0
			buf[o + 5] = 0.0
			continue
		# матрицу, цвет и ячейку пишем каждый кадр: после _remove_dead на индекс i мог встать юнит другого типа.
		var frames := type_sprite_frames[ut]
		var sq := unit_squad[i]
		if sprites and frames > 0 and sq >= 0:
			# Юнит отряда со спрайтом: 16 px по направлению, цвет белый; состояние — как в _unit_anim_state (без вызова функции).
			var b := unit_dir[i] * 4
			buf[o + 0] = DIR_BASIS[b]
			buf[o + 1] = DIR_BASIS[b + 1]
			buf[o + 4] = DIR_BASIS[b + 2]
			buf[o + 5] = DIR_BASIS[b + 3]
			buf[o + 8] = 1.0
			buf[o + 9] = 1.0
			buf[o + 10] = 1.0
			var st := 0
			if anim > 0.0:
				st = 2
			elif (unit_state[i] == ST_ATTACK and cooldown[i] <= windup_cd) or unit_shot_t[i] > 0.0 \
					or draw_mode[sq] == 1 or (draw_mode[sq] == 2 and cooldown[i] <= windup_cd):
				st = 1
			buf[o + 12] = type_sprite_base[ut] + mini(st, frames - 1)
			continue
		if sprites and frames > 0:
			# Зомби со спрайтом. Взгляд — по движению за тик (в бою не меняется), с гистерезисом; пишется в unit_dir, бой его не читает.
			var zst := 0
			if anim > 0.0:
				zst = 2
			elif unit_state[i] == ST_ATTACK:
				if cooldown[i] <= windup_cd:
					zst = 1
			else:
				if have_prev:
					var dx := pos[i].x - prev_pos[i].x
					var dy := pos[i].y - prev_pos[i].y
					var ax := absf(dx)
					var ay := absf(dy)
					if ax + ay > ZOMBIE_TURN_MIN:
						if ax > ay * ZOMBIE_TURN_HYST:
							unit_dir[i] = 0 if dx > 0.0 else 2
						elif ay > ax * ZOMBIE_TURN_HYST:
							unit_dir[i] = 1 if dy > 0.0 else 3
				if type_walk_rate[ut] > 0.0:
					zst = ZOMBIE_WALK_SEQ[int(anim_clock * type_walk_rate[ut] + unit_rand[i] * 4.0) & 3]   # фаза шага у каждого своя
			var zb := unit_dir[i] * 4
			var zk := type_sprite_scale[ut]
			buf[o + 0] = DIR_BASIS[zb] * zk
			buf[o + 1] = DIR_BASIS[zb + 1] * zk
			buf[o + 4] = DIR_BASIS[zb + 2] * zk
			buf[o + 5] = DIR_BASIS[zb + 3] * zk
			buf[o + 8] = 1.0
			buf[o + 9] = 1.0
			buf[o + 10] = 1.0
			buf[o + 12] = type_sprite_base[ut] + mini(zst, frames - 1)
			continue
		buf[o + 0] = UNIT_QUAD
		buf[o + 1] = 0.0
		buf[o + 4] = 0.0
		buf[o + 5] = UNIT_QUAD
		# F1 без вызова функции: вызов на юнита стоит ~1.7 мс на 3000 юнитов.
		var c := type_color[ut] if by_type else _unit_color(i, now)
		buf[o + 8] = c.r
		buf[o + 9] = c.g
		buf[o + 10] = c.b
		buf[o + 12] = cell_white
	if hero_view != null:
		_hero_fx_frame(delta)   # вспышка удара и мигание задетых (до записи буфера)
	if not hit_cfg.is_empty():
		_hit_fx_frame(0.0 if paused else delta)   # резня, кровь, искры, слой пятен, тряска: на паузе стоят
	multimesh.visible_instance_count = count
	multimesh.buffer = buf          # один вызов вместо UNIT_COUNT
	if hero_view != null:
		_update_hero_view(frac, have_prev, 0.0 if paused else delta)
	if arrow_fx != null:
		_arrow_fx_frame(frac if have_prev else 1.0, 0.0 if paused else delta)
	draw_ms = (Time.get_ticks_usec() - t) / 1000.0
	if fps_label != null:   # отладочная строка есть только при флаге debug_fps в отладочной сборке (задача 24)
		fps_label.text = tr("DEBUG_FPS_LINE") % [
			Engine.get_frames_per_second(), count, sim_avg, sim_peak, grid_ms, color_mode + 1, gate_hp, arrows_fired, arrows_hit]
		if profile:
			var parts := []
			for q in 6:
				parts.append("%s %.2f" % [PROF_NAMES[q], prof_avg[q]])
			fps_label.text += "\n" + tr("DEBUG_FPS_PHASES") % [", ".join(parts), arrivals_10s_max]
	if gate_hp != drawn_gate_hp:
		queue_redraw()   # полоса HP ворот


# Сдвиг отрисовки юнита: две независимые функции от unit_rand, каждая в ±RENDER_JITTER. Не меняется со временем
# и не трогает pos: строй на экране не выглядит идеальной сеткой. Считается один раз при появлении юнита
# (unit_render_off) и переносится в _remove_dead.
func _render_offset(i: int) -> Vector2:
	var r := unit_rand[i]
	return Vector2(fposmod(r * 127.1, 1.0) * 2.0 - 1.0, fposmod(r * 311.7, 1.0) * 2.0 - 1.0) * RENDER_JITTER


# Состояние анимации юнита: 2 «атака» — ATTACK_ANIM_T после удара или собственного выпуска стрелы; 1 «замах»; 0 «стоит».
# У «атаки» приоритет. Замах в ближнем бою: юнит бьёт (враг в дальности атаки) и до следующего удара не больше WINDUP_T.
# cooldown — остаток до готовности, убывает на обновлении юнита (раз в UPDATE_TICKS тиков, шагом в период обновления);
# удар — на первом обновлении, где он уже 0, то есть ещё через одно обновление. Замах включается за
# round(WINDUP_T / период) обновлений до удара (при 30 тиках/с это 2 обновления, 4 тика): порог windup_cd стоит
# посередине между соседними значениями cooldown, чтобы остаток округления float его не сдвигал.
# Замах стрелка: в залпе — от начала натяжения отряда (и пока отряд ждёт цель натянутым) до собственного выпуска
# (unit_shot_t); в одиночном огне — когда cooldown дошёл до того же порога. При отходе отряд не стреляет.
func _unit_anim_state(i: int) -> int:
	if unit_anim_t[i] > 0.0:
		return 2
	if unit_state[i] == ST_ATTACK and cooldown[i] <= windup_cd:
		return 1
	var s := unit_squad[i]
	if s < 0 or squad_ranged[s] == 0:
		return 0
	if unit_shot_t[i] > 0.0:
		return 1
	if squad_order[s] == ORDER_RETREAT:
		return 0
	if squad_volley_mode[s] == MODE_SINGLE:
		return 1 if cooldown[i] <= windup_cd else 0
	return 1 if squad_volley_fired[s] == 0 else 0


# Кадр листа для состояния: состояние зажимается до последнего кадра типа (лист с одним кадром — всегда 0).
func _unit_frame(i: int) -> int:
	return mini(_unit_anim_state(i), maxi(type_sprite_frames[unit_type[i]], 1) - 1)


# Отдача юнита сейчас: смещение отрисовки назад от взгляда, recoil_px в момент «атаки», линейно до нуля за ATTACK_ANIM_T.
func _recoil_offset(i: int) -> Vector2:
	return -DIR_VEC[unit_dir[i]] * (type_recoil[unit_type[i]] * unit_anim_t[i] / ATTACK_ANIM_T)


# Ближайшее из четырёх направлений к углу мира (0 = вправо, PI/2 = вниз): 0 вправо, 1 вниз, 2 влево, 3 вверх.
func _nearest_dir(angle: float) -> int:
	return posmod(roundi(angle / (PI * 0.5)), 4)


# Направление с гистерезисом: текущее держится, пока угол не ушёл от центра его сектора дальше DIR_HYST (55°).
func _next_dir(cur: int, angle: float) -> int:
	return _nearest_dir(angle) if absf(angle_difference(cur * PI * 0.5, angle)) > DIR_HYST else cur


# unit_dir юнитов отрядов, у которых с прошлого раза изменился угол (или состав: squad_dir_angle = NAN).
# Вызывается из физического тика: на паузе направления стоят.
func _update_unit_dirs() -> void:
	var any := false
	for s in SQUAD_MAX:
		if squad_used[s] == 1 and squad_n[s] > 0 and not squad_dir_angle[s] == squad_angle[s]:
			any = true
	if not any:
		return
	for i in count:
		var s := unit_squad[i]
		if s >= 0 and not squad_dir_angle[s] == squad_angle[s]:
			unit_dir[i] = _next_dir(unit_dir[i], squad_angle[s])
	for s in SQUAD_MAX:
		if squad_used[s] == 1 and squad_n[s] > 0:
			squad_dir_angle[s] = squad_angle[s]


func _unit_color(i: int, now: float) -> Color:
	match color_mode:
		1:   # F2: передние 3 занятых ряда красные, остальные синие; без отряда серые
			var s := unit_squad[i]
			if s < 0:
				return Color.DIM_GRAY
			return Color.RED if unit_slot_idx[i] / squad_width[s] < squad_front_row[s] + 3 else Color.ROYAL_BLUE
		2:   # F3: по состоянию
			match unit_state[i]:
				ST_CHASE:
					return Color.RED
				ST_RETURN:
					return Color.LIME_GREEN
				ST_ATTACK:
					return Color.YELLOW
			return Color.ROYAL_BLUE
		3:   # F4: белый 0.5 с после смены slot_idx
			return Color.WHITE if now - unit_slot_changed_t[i] < 0.5 else Color.DIM_GRAY
	return type_color[unit_type[i]]   # F1: по типу


func _update_unit(i: int, delta: float) -> void:
	if i == hero_idx:
		return   # герой решает сам (_update_hero); без героя hero_idx -1
	var t := unit_type[i]
	var my_team := team[i]
	var p := pos[i]
	var cx := clampi(floori(p.x / CELL_SIZE), 0, GRID_W - 1)
	var cy := clampi(floori(p.y / CELL_SIZE), 0, GRID_H - 1)
	var best := -1
	var best_d := INF
	var push := Vector2.ZERO

	for ny in range(maxi(cy - 1, 0), mini(cy + 1, GRID_H - 1) + 1):
		for nx in range(maxi(cx - 1, 0), mini(cx + 1, GRID_W - 1) + 1):
			var c := nx + ny * GRID_W
			for k in range(cell_start[c], cell_start[c + 1]):
				var j := sorted_units[k]
				# j == i не проверяем: у самого себя d2 = 0, его отсекают d2 > 0.0001 и team
				var q := pos[j]
				var d2 := p.distance_squared_to(q)
				if d2 > VIEW_RANGE * VIEW_RANGE:
					continue   # большинство соседей окна 3x3 дальше VIEW_RANGE
				if d2 < MIN_DIST * MIN_DIST and d2 > 0.0001:
					var off := p - q
					var d := sqrt(d2)
					push += off / d * (MIN_DIST - d)
				if d2 < best_d and team[j] != my_team:
					best_d = d2
					best = j

	# Приказ отряда: отход — врага не ищем и не бьём (идём к слоту, см. ветку «врага нет»).
	var order := squad_order[unit_squad[i]] if unit_squad[i] >= 0 else ORDER_ATTACK
	if order == ORDER_RETREAT:
		best = -1
	# Орда без преследования (chase = 0): враг виден, но вне дальности атаки — идёт дальше к цели, как будто врага нет.
	if best != -1 and unit_squad[i] == -1 and type_chase[t] == 0 and best_d > type_range_sq[t]:
		best = -1

	# Здесь только решение: скорость, удар, перезарядка. Ход делает _move_units каждый тик.
	var v := Vector2.ZERO   # в дальности атаки стоим на месте
	if best != -1:
		# Мягкая привязь: дальше leash_start от слота скорость к врагу смешивается со скоростью
		# к слоту с весом w = smoothstep(leash_start, leash_end, d). Бьёт юнит при любом w.
		var leash_w := 0.0
		var slot_vel := Vector2.ZERO
		var sq := unit_squad[i]
		if sq >= 0:
			var slot_world := squad_pos[sq] + unit_slot[i].rotated(squad_angle[sq])
			var ds2 := p.distance_squared_to(slot_world)
			if ds2 > type_leash_start_sq[t]:
				var l0 := type_leash_start[t]
				var l1 := type_leash_end[t]
				leash_w = 1.0 if l1 <= l0 else smoothstep(l0, l1, sqrt(ds2))
				slot_vel = ((slot_world - p) * SLOT_GAIN).limit_length(type_speed[t] * squad_speed_mult[sq] * 1.3)
				if leash_w > 0.5:
					leash_ticks += 2   # решение действует 2 тика (юнит обновляется раз в 2 тика)
		if best_d > type_range_sq[t] and order == ORDER_HOLD:
			# Держать: к врагу не идём, остаёмся (возвращаемся) в слот; бьём только того, кто в дальности атаки.
			var hold_slot := squad_pos[sq] + unit_slot[i].rotated(squad_angle[sq])
			v = ((hold_slot - p) * SLOT_GAIN).limit_length(type_speed[t] * squad_speed_mult[sq] * 1.3)
			unit_state[i] = ST_RETURN if p.distance_squared_to(hold_slot) > SLOT_NEAR_SQ else ST_IDLE
		elif best_d > type_range_sq[t]:
			var dir := (pos[best] - p).normalized()
			if unit_squad[i] == -1:
				# Зомби подходит к врагу, качаясь вбок; фаза своя у каждого (unit_rand).
				dir += dir.orthogonal() * HORDE_CHAOS * sin(tick_counter * 0.15 + unit_rand[i] * TAU)
			v = dir * (type_speed[t] * (squad_speed_mult[unit_squad[i]] if unit_squad[i] >= 0 else 1.0))
			unit_state[i] = ST_CHASE
		else:
			unit_state[i] = ST_ATTACK
		if best_d <= type_range_sq[t] and cooldown[i] <= 0.0:
			var dmg := type_damage[t]
			if unit_squad[i] >= 0:
				dmg *= squad_dmg_mult[unit_squad[i]]   # условия карточек (без карточек 1.0)
			if WAVE_DMG_TO_UNITS and my_team == 1:
				dmg *= team_dmg_mult[1]   # сила зомби растёт с волной; без волн множитель 1.0
			var m := type_block_mult[unit_type[best]]
			if m < 1.0:
				total_hits += 1
				# Блок щитом: жертва в отряде, щит поднят (с её удара прошло >= SHIELD_DOWN_TIME;
				# cooldown = сколько осталось до её следующего удара), удар из переднего сектора.
				var sj := unit_squad[best]
				var blocked := false
				if sj >= 0 and type_cooldown[unit_type[best]] - cooldown[best] >= SHIELD_DOWN_TIME:
					var a := p - pos[best]
					if a.dot(Vector2.from_angle(squad_angle[sj])) > BLOCK_COS * a.length():
						dmg *= m
						blocked_hits += 1
						blocked = true
				# Бонус блока (стат block, карточка №9, «Стена щитов»): часть не отражённых по правилу ударов тоже отражается,
				# чтобы общий шанс стал block_chance + бонус (не выше BLOCK_CAP); выпадение — хэш, не ГСЧ. Без бонуса ветки нет.
				if not blocked and sj >= 0:
					var bt := unit_type[best]
					var extra := type_block_bonus[bt] + squad_block_bonus[sj]
					if extra > 0.0:
						var base := type_block_chance[bt]
						if base < 1.0 and block_roll(tick_counter, i, best) < (minf(base + extra, BLOCK_CAP) - base) / (1.0 - base):
							dmg *= m
							blocked_hits += 1
			if unit_squad[best] >= 0:
				dmg *= squad_taken_mult[unit_squad[best]]   # бонус к HP по условию — меньше получаемого урона
			elif best == hero_idx:
				dmg *= hero_taken_mult   # карточка 44 (hero_low): без неё 1.0
			hp[best] -= dmg
			if my_team == 1 and contact_tick < 0:
				contact_tick = tick_counter
			var cd := type_cooldown[t]
			if unit_squad[i] >= 0:
				cd /= squad_atk_speed_mult[unit_squad[i]]   # Клич Благодати (без него 1.0)
			cooldown[i] = cd + cooldown[i]   # cooldown <= 0: остаток (до -CD_CARRY) переносится, без модификатора скорости удара он 0
			unit_anim_t[i] = ATTACK_ANIM_T
		if leash_w > 0.0:
			v = v.lerp(slot_vel, leash_w)   # смесь «к врагу (или стоять и бить)» и «к слоту»
			if leash_w > 0.5:
				unit_state[i] = ST_RETURN
	else:
		var s := unit_squad[i]
		if s >= 0:
			var slot_world := squad_pos[s] + unit_slot[i].rotated(squad_angle[s])
			var lim := type_speed[t] * squad_speed_mult[s] * 1.3 * (RETREAT_SPEED_MULT if order == ORDER_RETREAT else 1.0)
			v = ((slot_world - p) * SLOT_GAIN).limit_length(lim)
			# дальше полуслота от своего места — «возвращается», иначе «стоит»
			unit_state[i] = ST_RETURN if p.distance_squared_to(slot_world) > SLOT_NEAR_SQ else ST_IDLE
		elif p.y >= WALL_Y - sqrt(type_range_sq[t]) and absf(p.x - GATE_POS.x) <= gate_half + GATE_SIDE_MARGIN:
			# У ворот (сначала проверка по y — она отсекает почти всех): стоит и бьёт ворота по cooldown.
			unit_state[i] = ST_ATTACK
			if cooldown[i] <= 0.0:
				var gd := type_damage[t] * gate_dmg_mult * team_dmg_mult[my_team]
				gate_hp -= gd
				gate_hits += 1
				gate_damage_total += gd
				cooldown[i] = type_cooldown[t]
				unit_anim_t[i] = ATTACK_ANIM_T
		else:
			unit_state[i] = ST_IDLE
			# Орда идёт к воротам; скорость у каждого зомби своя (±HORDE_SPEED_SPREAD).
			var to_goal := HORDE_GOAL - p
			if to_goal.length() > GOAL_STOP:
				v = to_goal.normalized() * type_speed[t] * (1.0 + HORDE_SPEED_SPREAD * (unit_rand[i] * 2.0 - 1.0))
	# Толчок не разовым сдвигом позиции, а добавкой к скорости на 2 тика до следующего решения:
	# delta здесь = 2 тика, поэтому за эти 2 тика юнит сместится ровно на push * PUSH_K_2.
	vel[i] = v + push * PUSH_K_2 / delta
	cooldown[i] = maxf(cooldown[i] - delta, type_cd_floor[t])


func _move_units(delta: float) -> void:
	for i in count:
		var p := (pos[i] + vel[i] * delta).clamp(Vector2.ZERO, FIELD)   # граница поля
		p.y = minf(p.y, WALL_Y)   # временный пол: ниже стены не заходит никто
		pos[i] = p


func _remove_dead() -> void:
	var i := 0
	while i < count:
		if hp[i] <= 0.0:
			if death_n < death_pos.size():   # событие смерти для эффектов (только отрисовка; эффекты выключены — буфер пуст)
				death_pos[death_n] = pos[i]
				death_team[death_n] = team[i]
				death_type[death_n] = unit_type[i]
				death_dir[death_n] = unit_dir[i]
				death_n += 1
			elif not death_pos.is_empty():
				death_over += 1
			if first_death_tick < 0:
				first_death_tick = tick_counter
			if team[i] == 1:   # убит зомби: счёт волны и золото
				zombie_alive -= 1
				wave_kills += 1
				run_kills += 1
				gold += wave_cfg.gold_per_kill * type_bounty_mult[unit_type[i]]
				wave_kills_by_type[unit_type[i]] += 1
			elif i == hero_idx:
				hero_idx = -1   # пал герой: не считается павшим отряда (карточка 24, recover)
				hero_dead = true
				hero_deaths += 1
			elif team[i] == 0:
				wave_fallen += 1   # пал свой (карточка 24)
				if unit_squad[i] >= 0:
					squad_fallen[unit_squad[i]] += 1   # павшие отряда (стат recover)
			if unit_squad[i] >= 0:
				squad_dirty[unit_squad[i]] = 1
				squad_n[unit_squad[i]] -= 1
			count -= 1
			if count == hero_idx:
				hero_idx = i   # герой был последним — переезжает на место удалённого
			pos[i] = pos[count]
			prev_pos[i] = prev_pos[count]   # та же перестановка, иначе lerp смешает разных юнитов
			vel[i] = vel[count]
			team[i] = team[count]
			hp[i] = hp[count]
			cooldown[i] = cooldown[count]
			unit_squad[i] = unit_squad[count]
			unit_slot[i] = unit_slot[count]
			unit_slot_idx[i] = unit_slot_idx[count]
			unit_type[i] = unit_type[count]
			unit_rand[i] = unit_rand[count]
			unit_state[i] = unit_state[count]
			unit_slot_changed_t[i] = unit_slot_changed_t[count]
			unit_anim_t[i] = unit_anim_t[count]
			unit_dir[i] = unit_dir[count]
			unit_render_off[i] = unit_render_off[count]
			unit_shot_t[i] = unit_shot_t[count]
		else:
			i += 1


func _build_grid() -> void:
	for i in count:
		var cx := clampi(floori(pos[i].x / CELL_SIZE), 0, GRID_W - 1)
		var cy := clampi(floori(pos[i].y / CELL_SIZE), 0, GRID_H - 1)
		cell_of[i] = cx + cy * GRID_W

	cell_start.fill(0)
	for i in count:
		cell_start[cell_of[i] + 1] += 1

	for c in CELL_COUNT:
		cell_start[c + 1] += cell_start[c]
		cursor[c] = cell_start[c]

	for i in count:
		var c := cell_of[i]
		sorted_units[cursor[c]] = i
		cursor[c] += 1


func _slot_vector(k: int, width: int) -> Vector2:
	var row := k / width
	var col := k % width
	return Vector2(-row * SLOT_SPACING, (col - (width - 1) * 0.5) * SLOT_SPACING)


func _set_line_slot(unit: int, k: int, width: int) -> void:
	unit_slot_idx[unit] = k
	unit_slot[unit] = _slot_vector(k, width) - squad_center_off[unit_squad[unit]]


# Якорь отряда в центр живых слотов. Мировые позиции слотов не меняются.
# Возвращает сдвиг центра в координатах слотов.
func _reanchor(s: int) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for i in count:
		if unit_squad[i] == s:
			c += unit_slot[i]
			n += 1
	if n == 0:
		return Vector2.ZERO
	c /= n
	# Отряд, уже стоявший у цели, переносит цель вместе с якорем, иначе пойдёт «возвращаться».
	var arrived := squad_pos[s].distance_to(squad_target[s]) <= maxf(squad_stop_dist[s], 1.0)
	for i in count:
		if unit_squad[i] == s:
			unit_slot[i] -= c
	squad_center_off[s] += c
	var shift := c.rotated(squad_angle[s])
	squad_pos[s] += shift
	if arrived:
		squad_target[s] += shift
	_update_squad_extent(s)
	return c


# Кеш глубины строя (занятые ряды * SLOT_SPACING) и локальной x переднего ряда.
# Обновляется при перестройке слотов (_reanchor) и развороте, а не каждый тик.
func _update_squad_extent(s: int) -> void:
	var width := squad_width[s]
	var rmin := 1 << 30
	var rmax := -1
	var fx := -INF
	for i in count:
		if unit_squad[i] == s:
			var r := unit_slot_idx[i] / width
			rmin = mini(rmin, r)
			rmax = maxi(rmax, r)
			fx = maxf(fx, unit_slot[i].x)
	squad_depth[s] = (rmax - rmin + 1) * SLOT_SPACING if rmax >= 0 else 0.0
	squad_front_x[s] = fx if rmax >= 0 else 0.0


# Место ведомого отряда: позади ведущего на половину глубины каждого строя плюс ARCHER_GAP.
func _follow_target(s: int, lead: int) -> Vector2:
	var back := squad_depth[lead] * 0.5 + squad_depth[s] * 0.5 + ARCHER_GAP
	return squad_pos[lead] - Vector2.from_angle(squad_angle[lead]) * back


# Замена убитых: в каждой колонке выжившие сдвигаются вперёд, к ряду 0, без дыр.
# Затем пустые колонки схлопываются: занятые встают подряд по центру строя.
func _compact_squad(s: int) -> void:
	_snapshot_slots(s)
	var width := squad_width[s]
	var rows := squad_rows[s]
	for k in rows * width:
		slot_owner[k] = -1
	for i in count:
		if unit_squad[i] == s:
			slot_owner[unit_slot_idx[i]] = i
	for col in width:
		var w := 0
		for row in rows:
			var i := slot_owner[row * width + col]
			if i == -1:
				continue
			_set_line_slot(i, w * width + col, width)
			w += 1

	# Схлопывание пустых колонок: номера занятых 0..n-1 слева направо, со сдвигом к центру.
	for col in width:
		col_map[col] = -1
	for i in count:
		if unit_squad[i] == s:
			col_map[unit_slot_idx[i] % width] = 0
	var n := 0
	for col in width:
		if col_map[col] != -1:
			col_map[col] = n
			n += 1
	var offset := (width - n) / 2
	for i in count:
		if unit_squad[i] == s:
			var k := unit_slot_idx[i]
			_set_line_slot(i, (k / width) * width + offset + col_map[k % width], width)
	_reanchor(s)
	_mark_slot_changes(s)


# Нужна ли перестройка глубины: колонки разной глубины (> 3) или потери >= 30% с прошлой перестройки.
func _needs_reflow(s: int) -> bool:
	var width := squad_width[s]
	for col in width:
		col_map[col] = 0
	var n := 0
	for i in count:
		if unit_squad[i] == s:
			col_map[unit_slot_idx[i] % width] += 1
			n += 1
	if n == 0:
		return false
	var lo := n
	var hi := 0
	for col in width:
		var h := col_map[col]
		if h > 0:
			lo = mini(lo, h)
			hi = maxi(hi, h)
	if squad_user_width[s] > 0:
		# Ширина задана игроком: перестройка, как только занятых колонок не столько, сколько нужно.
		var occupied := 0
		for col in width:
			if col_map[col] > 0:
				occupied += 1
		if occupied != _target_width(s, n):
			return true
	return hi - lo > 3 or n < 0.7 * squad_reflow_n[s]


# Ширина сетки для n живых: заданная игроком (не шире n, рядов не больше ROWS_MAX) или по пропорции squad_aspect.
func _target_width(s: int, n: int) -> int:
	if squad_user_width[s] > 0:
		return clampi(mini(squad_user_width[s], n), ceili(n / float(ROWS_MAX)), WIDTH_MAX)
	var asp := squad_aspect[s]
	return clampi(maxi(ceili(sqrt(n * asp.x / asp.y)), ceili(n / float(ROWS_MAX))), 1, WIDTH_MAX)


# Перестройка глубины: живые (колонка за колонкой по старым слотам, новые юниты с временными
# индексами — в конце) раздаются в новую сетку с пропорцией squad_aspect[s], колонка за колонкой;
# глубины колонок отличаются не больше чем на 1. Принимает любые уникальные slot_idx.
func _reflow_squad(s: int) -> void:
	_snapshot_slots(s)
	var width := squad_width[s]
	# Ключ сортировки: (колонка, ряд) старого слота; временные индексы — после всех; индекс юнита в младших битах.
	sort_keys.fill(0x7FFFFFFFFFFFFFFF)
	var n := 0
	for i in count:
		if unit_squad[i] == s:
			var k := unit_slot_idx[i]
			var order := (k % width) * (1 << 20) + k / width if k < TEMP_SLOT_BASE else (1 << 40) + k
			sort_keys[n] = (order << 13) | i   # MAX_UNITS < 2^13
			n += 1
	if n == 0:
		return
	sort_keys.sort()
	for m in n:
		reflow_order[m] = int(sort_keys[m] & ((1 << 13) - 1))
	var new_width := _target_width(s, n)
	var base := n / new_width
	var extra := n % new_width
	var m := 0
	for col in new_width:
		for row in base + (1 if col < extra else 0):
			_set_line_slot(reflow_order[m], row * new_width + col, new_width)
			m += 1
	squad_width[s] = new_width
	squad_rows[s] = ceili(n / float(new_width))
	squad_reflow_n[s] = n
	_reanchor(s)
	_mark_slot_changes(s)


# Строй по протяжке A -> B. A — якорь: первая точка переднего ряда всегда в A, строй растёт назад от линии.
# Лицо: front = (d.y, -d.x) для d = B - A (слева направо по экрану — лицом вверх, справа налево — вниз);
# flip (клавиша F во время протяжки) — наоборот. Ось колонок слота (локальная +y) = (-face.y, face.x):
# без flip она совпадает с направлением A -> B, поэтому колонка 0 стоит в A.
# Ширина w = clamp(round(L / SLOT_SPACING) + 1, ceil(n / ROWS_MAX), WIDTH_MAX): короткая линия растягивается
# только за курсор. Не помещается в поле или ниже WALL_Y - FORM_MARGIN — сначала длиннее за курсор (меньше рядов);
# если и так нет — adjusted (красный предпросмотр) и блок сдвигается вдоль лица на минимум (A уезжает).
# Возвращает n, width, rows, user_width (в squad_user_width), angle, centre (блока), front (середина переднего ряда),
# a и b (концы переднего ряда), adjusted, overlap (номер своего отряда, с которым блок пересекается слишком сильно, или -1).
func _formation_geometry(s: int, a: Vector2, b: Vector2, flip := false) -> Dictionary:
	var n := squad_n[s]
	var d := b - a
	var dir := d.normalized()
	var face := Vector2(d.y, -d.x).normalized()
	if flip:
		face = -face
	var w_min := maxi(ceili(n / float(ROWS_MAX)), 1)
	var length := maxf(d.length(), (w_min - 1) * SLOT_SPACING)
	var user_width := clampi(roundi(length / SLOT_SPACING) + 1, w_min, WIDTH_MAX)
	var w_top := maxi(mini(WIDTH_MAX, n), 1)
	var width := mini(user_width, w_top)
	var adjusted := false
	var shift := Vector2.ZERO
	if not _block_shift(a, dir, face, width, n).is_zero_approx():
		var w := width + 1
		while w <= w_top and not _block_shift(a, dir, face, w, n).is_zero_approx():
			w += 1
		if w <= w_top:
			width = w   # длиннее за курсор: меньше рядов, A на месте
			user_width = w
		else:
			adjusted = true
			shift = _block_shift(a, dir, face, width, n)
	var rows := maxi(ceili(n / float(width)), 1)
	var a_eff := a + shift
	var b_eff := a_eff + dir * (width - 1) * SLOT_SPACING
	var front := (a_eff + b_eff) * 0.5
	return {"n": n, "width": width, "rows": rows, "user_width": user_width, "angle": face.angle(),
		"centre": front - face * (rows - 1) * SLOT_SPACING * 0.5, "front": front, "a": a_eff, "b": b_eff, "adjusted": adjusted,
		"overlap": _overlap_squad(s, front - face * (rows - 1) * SLOT_SPACING * 0.5, face.angle(), width, rows)}


# Прямоугольник блока в мире: центр, угол лица, half — полуразмеры (вдоль лица, поперёк), уже с половиной слота по краям.
func _block_rect(centre: Vector2, angle: float, half: Vector2) -> PackedVector2Array:
	var face := Vector2.from_angle(angle)
	var lat := Vector2(-face.y, face.x)
	return PackedVector2Array([centre + face * half.x - lat * half.y, centre + face * half.x + lat * half.y,
		centre - face * half.x + lat * half.y, centre - face * half.x - lat * half.y])


func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for k in poly.size():
		a += poly[k].cross(poly[(k + 1) % poly.size()])
	return absf(a) * 0.5


# Новый блок отряда s (центр, угол, width × rows) против блоков других своих отрядов.
# Возвращает номер первого отряда, с которым пересечение не меньше OVERLAP_MAX площади меньшего блока, или -1.
# Каждый юнит занимает клетку SLOT_SPACING × SLOT_SPACING, поэтому соседние вплотную блоки только касаются.
func _overlap_squad(s: int, centre: Vector2, angle: float, width: int, rows: int) -> int:
	return _overlap_with(s, _block_rect(centre, angle, Vector2(rows, width) * SLOT_SPACING * 0.5),
		width * rows * SLOT_SPACING * SLOT_SPACING, _squad_boxes())


# Блок отряда s в нынешнем виде (угол и сетка те же, без поворота), если его якорь встанет в target:
# с каким своим отрядом он пересечётся слишком сильно (-1 — ни с каким). Для обычного клика.
func _target_overlap(s: int, target: Vector2, skip_mask := 0) -> int:
	var boxes := _squad_boxes()
	var lo: Vector2 = boxes[0][s]
	var hi: Vector2 = boxes[1][s]
	if hi.x < lo.x:
		return -1   # пустой отряд
	var half := (hi - lo) * 0.5 + Vector2(SLOT_SPACING, SLOT_SPACING) * 0.5
	return _overlap_with(s, _block_rect(target + ((lo + hi) * 0.5).rotated(squad_angle[s]), squad_angle[s], half), half.x * half.y * 4.0, boxes, skip_mask)


# Границы живых слотов каждого отряда в его локальных координатах: [lo, hi] по индексам отрядов (один проход по юнитам).
func _squad_boxes() -> Array:
	var lo := PackedVector2Array()
	var hi := PackedVector2Array()
	lo.resize(SQUAD_MAX)
	hi.resize(SQUAD_MAX)
	lo.fill(Vector2(INF, INF))
	hi.fill(Vector2(-INF, -INF))
	for i in count:
		var q := unit_squad[i]
		if q >= 0:
			lo[q] = lo[q].min(unit_slot[i])
			hi[q] = hi[q].max(unit_slot[i])
	return [lo, hi]


# Прямоугольник mine (площадь mine_area) отряда s против блоков других своих отрядов. Блок другого отряда —
# прямоугольник его живых слотов: там, где отряд стоит, а если он идёт — там, куда придёт (якорь в squad_target,
# угол нынешний). Отряды из skip_mask (остальные выбранные при групповом приказе) не проверяются.
func _overlap_with(s: int, mine: PackedVector2Array, mine_area: float, boxes: Array, skip_mask := 0) -> int:
	for q in SQUAD_MAX:
		var lo: Vector2 = boxes[0][q]
		var hi: Vector2 = boxes[1][q]
		if q == s or (skip_mask >> q) & 1 == 1 or squad_used[q] == 0 or squad_n[q] == 0 or squad_team[q] != squad_team[s] or hi.x < lo.x:
			continue
		var moving := squad_pos[q].distance_to(squad_target[q]) > maxf(squad_stop_dist[q], 1.0)
		var anchor := squad_target[q] if moving else squad_pos[q]
		var half := (hi - lo) * 0.5 + Vector2(SLOT_SPACING, SLOT_SPACING) * 0.5
		var other := _block_rect(anchor + ((lo + hi) * 0.5).rotated(squad_angle[q]), squad_angle[q], half)
		var common := 0.0
		for poly in Geometry2D.intersect_polygons(mine, other):
			common += _poly_area(poly)
		if common >= OVERLAP_MAX * minf(mine_area, half.x * half.y * 4.0) - 0.01:
			return q
	return -1


# Блок отряда s — прямоугольник его живых слотов с половиной слота по краям (как в проверке пересечения),
# якорь в anchor, угол нынешний. У пустого отряда — пустой массив.
func _live_block(s: int, boxes: Array, anchor: Vector2) -> PackedVector2Array:
	var lo: Vector2 = boxes[0][s]
	var hi: Vector2 = boxes[1][s]
	if hi.x < lo.x:
		return PackedVector2Array()
	return _block_rect(anchor + ((lo + hi) * 0.5).rotated(squad_angle[s]), squad_angle[s], (hi - lo) * 0.5 + Vector2(SLOT_SPACING, SLOT_SPACING) * 0.5)


# ПКМ-клик при нескольких выбранных: набор сдвигается целиком, середина его якорей идёт в p, взаимные смещения
# и углы те же. Всё или ничего: набор должен поместиться в поле и не ниже WALL_Y - FORM_MARGIN (вылез — сдвигается
# целиком на минимум), блоки у целей не пересекаются с невыбранными отрядами (между выбранными проверки нет).
func _cmd_move_group(list: PackedInt32Array, p: Vector2) -> bool:
	if _orders_locked():
		return false   # командир пал: приказы до конца волны недоступны
	var plan := _group_move_plan(list, p)
	if not plan.ok:
		_say(plan.msg, 2.0)   # цели не меняются ни у кого
		return false
	for s in list:
		squad_target[s] = squad_pos[s] + plan.delta
	return true


# План ПКМ-клика по набору list в точку p (без побочных эффектов; его же показывает призрак блока, задача 26):
# {ok, delta — сдвиг якорей, msg — почему нельзя}. Правила — у _cmd_move_group.
func _group_move_plan(list: PackedInt32Array, p: Vector2) -> Dictionary:
	var c := Vector2.ZERO
	var mask := 0
	for s in list:
		c += squad_pos[s]
		mask |= 1 << s
	var delta := p - c / list.size()
	var boxes := _squad_boxes()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in list:
		var b_lo: Vector2 = boxes[0][s]
		var b_hi: Vector2 = boxes[1][s]
		for corner: Vector2 in [b_lo, Vector2(b_lo.x, b_hi.y), b_hi, Vector2(b_hi.x, b_lo.y)]:
			var w := squad_pos[s] + delta + corner.rotated(squad_angle[s])
			lo = lo.min(w)
			hi = hi.max(w)
	var lim := Vector2(FIELD.x, WALL_Y - FORM_MARGIN)
	for axis in 2:
		if hi[axis] - lo[axis] > lim[axis] + 0.01:
			return {"ok": false, "delta": p - c / list.size(), "msg": tr("MSG_SQUADS_DONT_FIT")}
		if lo[axis] < 0.0:
			delta[axis] -= lo[axis]
		elif hi[axis] > lim[axis]:
			delta[axis] += lim[axis] - hi[axis]
	for s in list:
		var q := _target_overlap(s, squad_pos[s] + delta, mask)
		if q >= 0:
			return {"ok": false, "delta": delta, "msg": tr("MSG_BLOCK_OVERLAP") % (q + 1)}
	return {"ok": true, "delta": delta, "msg": ""}


# Обычный клик: цель отряда s. Не задаётся, если блок отряда в точке цели слишком пересечётся с другим своим отрядом.
func _cmd_move(s: int, target: Vector2) -> bool:
	if _orders_locked():
		return false   # командир пал: приказы до конца волны недоступны
	var plan := _move_plan(s, target)
	if not plan.ok:
		_say(plan.msg, 2.0)   # цель не меняется
		return false
	squad_target[s] = target
	return true


# План ПКМ-клика одного отряда (без побочных эффектов; его же показывает призрак): {ok, msg}.
func _move_plan(s: int, target: Vector2) -> Dictionary:
	var q := _target_overlap(s, target)
	return {"ok": false, "msg": tr("MSG_BLOCK_OVERLAP") % (q + 1)} if q >= 0 else {"ok": true, "msg": ""}


# Призрак ПКМ-клика (задача 26): s -> якорь блока, куда встанет отряд, если отпустить ПКМ сейчас, и можно ли.
# Пусто — призрака нет (ПКМ не зажата, протяжка длиннее drag_min, ничего не выбрано).
func ghost_plan() -> Dictionary:
	if not drag_active or drag_start.distance_to(drag_cur) >= ui_layout.drag_min:
		return {}
	var list := _order_list()
	if list.is_empty():
		return {}
	var out := {"ok": true, "msg": "", "anchors": {}}
	if list.size() == 1:
		var pl := _move_plan(list[0], drag_start)
		out.ok = pl.ok
		out.msg = pl.msg
		out.anchors[list[0]] = drag_start
	else:
		var pl := _group_move_plan(list, drag_start)
		out.ok = pl.ok
		out.msg = pl.msg
		for s in list:
			out.anchors[s] = squad_pos[s] + pl.delta
	return out


# Прозрачная копия блока живых слотов каждого отряда набора в точке приказа: тот же угол и строй, что сейчас; красная и
# с подписью, если приказ не пройдёт (не помещается, пересекается со своим отрядом).
func _draw_ghosts() -> void:
	var g := ghost_plan()
	if g.is_empty():
		return
	ghost_frame = Engine.get_process_frames()
	if sel_boxes.is_empty():
		sel_boxes = _squad_boxes()
	for s in g.anchors:
		var col: Color = type_color[squad_type[s]] if g.ok else GHOST_BAD_COLOR
		var poly := _live_block(s, sel_boxes, g.anchors[s])
		if poly.size() == 0:
			continue
		draw_colored_polygon(poly, Color(col, 0.22))
		poly.append(poly[0])
		draw_polyline(poly, Color(col, 0.75), 2.0)
	if not g.ok:
		_draw_cursor_text(g.msg, GHOST_BAD_COLOR)


# Подпись у курсора (протяжка, призрак): справа сверху от drag_cur, кегль 20; в px экрана при любом зуме (ui_k).
func _draw_cursor_text(text: String, col: Color) -> void:
	draw_set_transform(drag_cur, 0.0, Vector2.ONE * ui_k())
	draw_string(ThemeDB.fallback_font, Vector2(16.0, -12.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONTS.px(20), col)
	draw_set_transform(Vector2.ZERO)

# На сколько сдвинуть блок (передний ряд от a вдоль dir, width колонок, ряды назад от лица), чтобы все слоты
# были в поле и не ниже WALL_Y - FORM_MARGIN. Ноль — помещается. Сдвиг ищется вдоль лица (минимальный);
# если вдоль лица не решить (блок вылез вбок), — минимальный по осям поля.
func _block_shift(a: Vector2, dir: Vector2, face: Vector2, width: int, n: int) -> Vector2:
	var rows := maxi(ceili(n / float(width)), 1)
	var along := dir * (width - 1) * SLOT_SPACING
	var back := -face * (rows - 1) * SLOT_SPACING
	var lo := a.min(a + along).min(a + back).min(a + along + back)
	var hi := a.max(a + along).max(a + back).max(a + along + back)
	var lim := Vector2(FIELD.x, WALL_Y - FORM_MARGIN)
	var need := Vector2.ZERO   # минимальный сдвиг по осям поля
	var t_lo := -INF
	var t_hi := INF
	var feasible := true
	for axis in 2:
		if lo[axis] < -0.01:
			need[axis] = -lo[axis]
		elif hi[axis] > lim[axis] + 0.01:
			need[axis] = lim[axis] - hi[axis]
		var f: float = face[axis]
		if absf(f) < 0.000001:
			feasible = feasible and need[axis] == 0.0
		else:
			# сдвиг t вдоль лица: lo + t * f >= 0 и hi + t * f <= lim; блок длиннее поля по оси — промежуток пуст
			var t1 := -lo[axis] / f
			var t2 := (lim[axis] - hi[axis]) / f
			t_lo = maxf(t_lo, t1 if f > 0.0 else t2)
			t_hi = minf(t_hi, t2 if f > 0.0 else t1)
	if need == Vector2.ZERO:
		return Vector2.ZERO
	if feasible and t_lo <= t_hi:
		return face * clampf(0.0, t_lo, t_hi)
	return need

# Расстановка отряда по протяжке A -> B (flip — лицо наоборот): строй занимает место сразу, юниты бегут к слотам
# (как всегда, скорость x1.3).
# Слоты раздаются без пересечения путей: юниты сортируются поперёк нового строя и делятся на width колонок
# (глубины отличаются не больше чем на 1), внутри колонки — спереди назад.
func _place_formation(s: int, a: Vector2, b: Vector2, flip := false) -> void:
	var g := _formation_geometry(s, a, b, flip)
	var n: int = g.n
	if n == 0:
		return
	if g.overlap >= 0:
		_say(tr("MSG_BLOCK_OVERLAP") % (g.overlap + 1), 2.0)   # отряд остаётся на месте
		queue_redraw()
		return
	_apply_formation(s, g.width, g.rows, g.user_width, g.angle, g.centre, g.front)
	queue_redraw()


# Отряд s встаёт в блок: width колонок и rows рядов, лицо angle, центр блока centre, середина переднего ряда front.
func _apply_formation(s: int, width: int, rows: int, user_width: int, angle: float, centre: Vector2, front: Vector2) -> void:
	var n := squad_n[s]
	squad_user_width[s] = user_width
	_snapshot_slots(s)
	# Проход 1: по local.y (поперёк строя); индекс юнита в младших 32 битах.
	sort_keys.fill(0x7FFFFFFFFFFFFFFF)
	var m := 0
	for i in count:
		if unit_squad[i] == s:
			var local := (pos[i] - centre).rotated(-angle)
			sort_keys[m] = ((int(local.y * 16.0) + SORT_OFFSET) << 32) | i
			m += 1
	sort_keys.sort()
	# Проход 2: ключ (колонка, local.x от переднего к заднему).
	var base := n / width
	var extra := n % width
	m = 0
	for col in width:
		for q in base + (1 if col < extra else 0):
			var i := int(sort_keys[m] & 0xFFFFFFFF)
			var local_x := (pos[i] - centre).rotated(-angle).x
			sort_keys[m] = (((col << 24) | (SORT_OFFSET - int(local_x * 16.0))) << 32) | i
			m += 1
	sort_keys.sort()
	squad_width[s] = width
	squad_rows[s] = rows
	squad_reflow_n[s] = n
	squad_angle[s] = angle
	m = 0
	for col in width:
		for row in base + (1 if col < extra else 0):
			_set_line_slot(int(sort_keys[m] & 0xFFFFFFFF), row * width + col, width)
			m += 1
	_reanchor(s)
	# Якорь — центр живых слотов; середина переднего ряда (слот-вектор 0) должна попасть в front.
	squad_pos[s] = front + squad_center_off[s].rotated(angle)
	squad_target[s] = squad_pos[s]
	_mark_slot_changes(s)


# Несколько отрядов на одной линии A -> B: лицо, якорь A и растяжение за курсор — как у одного отряда. Отряды идут
# вдоль линии в порядке проекции их якорей на A -> B (при равенстве — по индексу), между соседними зазор SLOT_SPACING.
# Доля линии отряда: L_i = (L_eff - SLOT_SPACING * (k - 1)) * n_i / N, где L_eff = max(L, сумма минимальных длин
# с зазорами); ширина из L_i — как в _formation_geometry, ряды назад. Отрезки ставятся подряд по ширине в слотах,
# поэтому зазор ровно SLOT_SPACING. Группа не помещается в поле или ниже WALL_Y - FORM_MARGIN — сдвигается целиком
# вдоль лица на минимум (adjusted); не помещается и так — fits = false.
# Возвращает items (по отряду: s, n, width, rows, user_width, a, b, front, centre), angle, length (L_eff), adjusted, fits,
# overlap (номер невыбранного отряда, с которым пересекается чей-то блок, или -1).
func _multi_geometry(list: PackedInt32Array, a: Vector2, b: Vector2, flip := false) -> Dictionary:
	var d := b - a
	var dir := d.normalized()
	var face := Vector2(d.y, -d.x).normalized()
	if flip:
		face = -face
	var order := Array(list)
	order.sort_custom(func(x: int, y: int) -> bool:
		var px := squad_pos[x].dot(dir)
		var py := squad_pos[y].dot(dir)
		return px < py if px != py else x < y)
	var k := order.size()
	var total := 0
	var mask := 0
	var min_len := SLOT_SPACING * (k - 1)
	for s: int in order:
		total += squad_n[s]
		mask |= 1 << s
		min_len += (ceili(squad_n[s] / float(ROWS_MAX)) - 1) * SLOT_SPACING
	var length := maxf(d.length(), min_len)
	var share := length - SLOT_SPACING * (k - 1)
	var items := []
	var at := a
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s: int in order:
		var n := squad_n[s]
		var user_width := clampi(roundi(share * n / total / SLOT_SPACING) + 1, maxi(ceili(n / float(ROWS_MAX)), 1), WIDTH_MAX)
		var width := mini(user_width, maxi(mini(WIDTH_MAX, n), 1))
		var rows := maxi(ceili(n / float(width)), 1)
		var along := dir * (width - 1) * SLOT_SPACING
		var back := -face * (rows - 1) * SLOT_SPACING
		items.append({"s": s, "n": n, "width": width, "rows": rows, "user_width": user_width, "a": at, "b": at + along})
		lo = lo.min(at).min(at + along).min(at + back).min(at + along + back)
		hi = hi.max(at).max(at + along).max(at + back).max(at + along + back)
		at += along + dir * SLOT_SPACING
	var lim := Vector2(FIELD.x, WALL_Y - FORM_MARGIN)
	var shift := Vector2.ZERO
	var fits := true
	var adjusted := false
	if lo.x < -0.01 or lo.y < -0.01 or hi.x > lim.x + 0.01 or hi.y > lim.y + 0.01:
		var t_lo := -INF
		var t_hi := INF
		for axis in 2:
			var f: float = face[axis]
			if absf(f) < 0.000001:
				fits = fits and lo[axis] >= -0.01 and hi[axis] <= lim[axis] + 0.01
			else:
				var t1 := -lo[axis] / f
				var t2 := (lim[axis] - hi[axis]) / f
				t_lo = maxf(t_lo, t1 if f > 0.0 else t2)
				t_hi = minf(t_hi, t2 if f > 0.0 else t1)
		fits = fits and t_lo <= t_hi
		if fits:
			adjusted = true
			shift = face * clampf(0.0, t_lo, t_hi)
	var boxes := _squad_boxes()
	var overlap := -1
	for it in items:
		it.a += shift
		it.b += shift
		it.front = (it.a + it.b) * 0.5
		it.centre = it.front - face * (it.rows - 1) * SLOT_SPACING * 0.5
		if overlap < 0:
			overlap = _overlap_with(it.s, _block_rect(it.centre, face.angle(), Vector2(it.rows, it.width) * SLOT_SPACING * 0.5),
				it.width * it.rows * SLOT_SPACING * SLOT_SPACING, boxes, mask)
	return {"items": items, "angle": face.angle(), "length": length, "adjusted": adjusted, "fits": fits, "overlap": overlap}


# Расстановка нескольких отрядов по протяжке A -> B (см. _multi_geometry). Всё или ничего: группа не помещается
# в поле или чей-то блок пересекается с невыбранным отрядом — отказ с сообщением, все на месте.
# Один отряд — ровно _place_formation.
func _place_formation_multi(list: PackedInt32Array, a: Vector2, b: Vector2, flip := false) -> bool:
	if _orders_locked():
		return false   # командир пал: приказы до конца волны недоступны
	if list.is_empty():
		return false
	if list.size() == 1:
		_place_formation(list[0], a, b, flip)
		return true
	var g := _multi_geometry(list, a, b, flip)
	if not g.fits or g.overlap >= 0:
		_say(tr("MSG_FORMATION_DOESNT_FIT") if not g.fits else tr("MSG_BLOCK_OVERLAP") % (g.overlap + 1), 2.0)
		queue_redraw()
		return false
	for it in g.items:
		_apply_formation(it.s, it.width, it.rows, it.user_width, g.angle, it.centre, it.front)
	queue_redraw()
	return true


# Для раскраски F4: запомнить slot_idx юнитов отряда перед перестройкой...
func _snapshot_slots(s: int) -> void:
	for i in count:
		if unit_squad[i] == s:
			slot_idx_prev[i] = unit_slot_idx[i]


# ...и отметить время у тех, чей slot_idx после неё другой.
func _mark_slot_changes(s: int) -> void:
	var now := tick_counter / float(Engine.physics_ticks_per_second)
	for i in count:
		if unit_squad[i] == s and slot_idx_prev[i] != unit_slot_idx[i]:
			unit_slot_changed_t[i] = now


func _update_squads(delta: float) -> void:
	squad_compact_t += delta
	if squad_compact_t >= 0.5:
		for s in SQUAD_MAX:
			if squad_used[s] == 0:
				continue
			if squad_n[s] == 0:
				squad_dirty[s] = 0   # сжимать нечего
				continue
			if squad_dirty[s] == 1:
				_compact_squad(s)
				squad_dirty[s] = 0
			if _needs_reflow(s):
				_reflow_squad(s)
		squad_compact_t = 0.0
	for s in SQUAD_MAX:
		if squad_used[s] == 0 or squad_n[s] == 0:
			continue   # свободный или пустой отряд не ходит и не поворачивается
		var lead := squad_follow[s]
		if lead >= 0:
			# Ведомый отряд сам не поворачивается: угол копируется у ведущего. Если ведущий
			# развернулся «кругом», ведомый делает свой _about_face, чтобы слоты отразились на месте.
			if absf(angle_difference(squad_angle[s], squad_angle[lead])) > ABOUT_FACE_ANGLE:
				_about_face(s)
			squad_angle[s] = squad_angle[lead]
			squad_target[s] = _follow_target(s, lead)
			# Досягаемость стрелков: расстояние от их центра до переднего ряда ведущего, первые 10 с до контакта.
			if squad_ranged[s] == 1 and first_death_tick < 0 and tick_counter <= 10 * Engine.physics_ticks_per_second:
				var to_front := (squad_pos[lead] - squad_pos[s]).dot(Vector2.from_angle(squad_angle[lead])) + squad_front_x[lead]
				reach_dist_sum += to_front
				reach_sum += type_range_far[squad_type[s]] - to_front
				reach_n += 1
			var to_f := squad_target[s] - squad_pos[s]
			var dist_f := to_f.length()
			if dist_f > maxf(squad_stop_dist[s], 1.0):
				squad_pos[s] += to_f / dist_f * minf(squad_speed[s] * squad_speed_mult[s] * delta, dist_f)
			continue
		var to := squad_target[s] - squad_pos[s]
		var dist := to.length()
		if dist <= maxf(squad_stop_dist[s], 1.0):   # нижний предел 1 px: без дёргания у цели
			if squad_order[s] == ORDER_RETREAT:
				squad_order[s] = ORDER_HOLD   # отход закончен: держать
			continue
		var diff := angle_difference(squad_angle[s], to.angle())
		# Отряд не поворачивается к цели ближе 2 слотов.
		if dist > 2.0 * SLOT_SPACING:
			if absf(diff) > ABOUT_FACE_ANGLE:
				_about_face(s)
				diff = angle_difference(squad_angle[s], to.angle())
			squad_angle[s] += clampf(diff, -TURN_SPEED * delta, TURN_SPEED * delta)
		if absf(diff) < MOVE_ANGLE:
			var spd := squad_speed[s] * squad_speed_mult[s] * (RETREAT_SPEED_MULT if squad_order[s] == ORDER_RETREAT else 1.0)
			squad_pos[s] += to / dist * minf(spd * delta, dist)


func _about_face(s: int) -> void:
	# Разворот «кругом» вокруг центра живых слотов: squad_pos не двигается.
	# Ряды отражаются вокруг занятых рядов, колонки — вокруг занятых колонок, угол + PI.
	_compact_squad(s)
	var width := squad_width[s]
	var occ_rows := 0
	var col_lo := width
	var col_hi := -1
	for i in count:
		if unit_squad[i] == s:
			var k := unit_slot_idx[i]
			occ_rows = maxi(occ_rows, k / width + 1)
			col_lo = mini(col_lo, k % width)
			col_hi = maxi(col_hi, k % width)
	squad_angle[s] = wrapf(squad_angle[s] + PI, -PI, PI)
	if col_hi < 0:
		return   # пустой отряд
	_snapshot_slots(s)
	for i in count:
		if unit_squad[i] == s:
			var k := unit_slot_idx[i]
			var row := occ_rows - 1 - k / width
			var col := col_lo + col_hi - k % width
			unit_slot_idx[i] = row * width + col
			unit_slot[i] = -unit_slot[i]   # точное отражение: мировая позиция при угле + PI та же
	# Сетка отражена: _slot_vector(k') = -_slot_vector(k) + K, поэтому новое смещение центра = K - старое.
	var grid_k := Vector2(-(occ_rows - 1) * SLOT_SPACING, (col_lo + col_hi - (width - 1)) * SLOT_SPACING)
	squad_center_off[s] = grid_k - squad_center_off[s]
	squad_dirty[s] = 1   # короткие колонки сейчас у задней линии: подтянутся при ближайшем сжатии
	_mark_slot_changes(s)
	_update_squad_extent(s)

# --- Лучники ------------------------------------------------------------------

# Грубая сетка зомби (клетка COARSE_SIZE): counting sort, на клетку — число зомби и сумма позиций.
# Между пересчётами индексы в coarse_units могут устареть (swap-and-pop в _remove_dead),
# поэтому при чтении проверяется j < count и team[j] == 1, позиция берётся текущая.
func _rebuild_coarse() -> void:
	coarse_zcount.fill(0)
	coarse_sum.fill(Vector2.ZERO)
	for i in count:
		if team[i] != 1:
			coarse_cell_of[i] = -1
			continue
		var p := pos[i]
		var c := clampi(floori(p.x / COARSE_SIZE), 0, COARSE_W - 1) + clampi(floori(p.y / COARSE_SIZE), 0, COARSE_H - 1) * COARSE_W
		coarse_cell_of[i] = c
		coarse_zcount[c] += 1
		coarse_sum[c] += p
	var acc := 0
	for c in COARSE_COUNT:
		coarse_start[c] = acc
		coarse_cursor[c] = acc
		acc += coarse_zcount[c]
	coarse_start[COARSE_COUNT] = acc
	for i in count:
		var c := coarse_cell_of[i]
		if c >= 0:
			coarse_units[coarse_cursor[c]] = i
			coarse_cursor[c] += 1


# Ближайший живой зомби в 3x3 грубых клетках вокруг p, не дальше max_d; -1 если нет.
func _nearest_zombie_coarse(p: Vector2, max_d: float) -> int:
	var cx := clampi(floori(p.x / COARSE_SIZE), 0, COARSE_W - 1)
	var cy := clampi(floori(p.y / COARSE_SIZE), 0, COARSE_H - 1)
	var best := -1
	var best_d := max_d * max_d
	for ny in range(maxi(cy - 1, 0), mini(cy + 1, COARSE_H - 1) + 1):
		for nx in range(maxi(cx - 1, 0), mini(cx + 1, COARSE_W - 1) + 1):
			var c := nx + ny * COARSE_W
			for k in range(coarse_start[c], coarse_start[c + 1]):
				var j := coarse_units[k]
				if j >= count or team[j] != 1 or hp[j] <= 0.0:
					continue
				var d2 := p.distance_squared_to(pos[j])
				if d2 <= best_d:
					best_d = d2
					best = j
	return best


# Режим стрельбы по дистанции от прямоугольника живых слотов отряда до ближайшего зомби.
# Кандидаты — зомби из грубых клеток, перекрывающих прямоугольник с запасом. Гистерезис:
# ближе NEAR_RANGE — одиночный огонь, дальше NEAR_RANGE + MODE_HYST — залп, между — без смены.
func _update_archer_mode(s: int) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var n := 0
	for i in count:
		if unit_squad[i] == s:
			var q := unit_slot[i]
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
			n += 1
	if n == 0:
		return
	var reach := NEAR_RANGE + MODE_HYST
	var sp := squad_pos[s]
	var ang := squad_angle[s]
	var wlo := Vector2(INF, INF)
	var whi := Vector2(-INF, -INF)
	for corner in [Vector2(lo.x - reach, lo.y - reach), Vector2(hi.x + reach, lo.y - reach), Vector2(lo.x - reach, hi.y + reach), Vector2(hi.x + reach, hi.y + reach)]:
		var w: Vector2 = sp + corner.rotated(ang)
		wlo = Vector2(minf(wlo.x, w.x), minf(wlo.y, w.y))
		whi = Vector2(maxf(whi.x, w.x), maxf(whi.y, w.y))
	var d_min := INF
	for cy in range(clampi(floori(wlo.y / COARSE_SIZE), 0, COARSE_H - 1), clampi(floori(whi.y / COARSE_SIZE), 0, COARSE_H - 1) + 1):
		for cx in range(clampi(floori(wlo.x / COARSE_SIZE), 0, COARSE_W - 1), clampi(floori(whi.x / COARSE_SIZE), 0, COARSE_W - 1) + 1):
			var c := cx + cy * COARSE_W
			for k in range(coarse_start[c], coarse_start[c + 1]):
				var j := coarse_units[k]
				if j >= count or team[j] != 1:
					continue
				var local := (pos[j] - sp).rotated(-ang)
				var inside := Vector2(clampf(local.x, lo.x, hi.x), clampf(local.y, lo.y, hi.y))
				d_min = minf(d_min, local.distance_to(inside))
	var mode := squad_volley_mode[s]
	if d_min < NEAR_RANGE:
		mode = MODE_SINGLE
	elif d_min > NEAR_RANGE + MODE_HYST:
		mode = MODE_VOLLEY
	if mode != squad_volley_mode[s]:
		squad_volley_mode[s] = mode
		mode_switches += 1
		squad_mode_switches[s] += 1
		squad_volley_t[s] = 0.0   # залп после переключения начинается с натяжения
		squad_volley_fired[s] = 0


func _update_archers(delta: float) -> void:
	for s in SQUAD_MAX:
		if squad_used[s] == 0 or squad_n[s] == 0:
			continue
		if squad_ranged[s] == 0 or squad_order[s] == ORDER_RETREAT:   # при отходе не стреляют
			continue
		if squad_volley_mode[s] == MODE_SINGLE:
			_single_fire(s)
		else:
			_volley(s, delta)


# Одиночный огонь: каждый лучник раз в SINGLE_SCAN_T (сдвиг по индексу) ищет ближайшего
# зомби в 3x3 грубых клетках и стреляет, если готов его cooldown (общий с ближним боем).
func _single_fire(s: int) -> void:
	var scan := maxi(roundi(SINGLE_SCAN_T * Engine.physics_ticks_per_second), 1)
	for i in count:
		if unit_squad[i] != s or (tick_counter + i) % scan != 0 or cooldown[i] > 0.0:
			continue
		var t := unit_type[i]
		var j := _nearest_zombie_coarse(pos[i], type_range_far[t])
		if j == -1:
			continue
		_fire_arrow(i, pos[j], 0.0)
		cooldown[i] = type_cooldown[t] / squad_atk_speed_mult[s] + cooldown[i]   # cooldown <= 0: остаток переносится (см. type_cd_floor); Клич — скорострельность


# Залп: цикл draw (draw_time) -> fire -> reload до volley_period от начала цикла.
# Цель — самая плотная клетка в range_far от центра отряда; при archer_own_range стреляют только те, кто достаёт
# со своего места, иначе все лучники отряда.
# Если в момент выстрела цели нет, цикл ждёт на этой точке.
func _volley(s: int, delta: float) -> void:
	var ut := squad_type[s]
	var t := squad_volley_t[s] + delta
	if squad_volley_fired[s] == 0:
		if t < type_draw_time[ut]:
			squad_volley_t[s] = t
			return
		var cell := _volley_target_cell(s, type_range_far[ut])
		if cell == -1:
			squad_volley_t[s] = type_draw_time[ut]   # ждём цель натянутыми
			return
		# Каждая стрела целится в случайного живого зомби этой клетки (тот же seeded-генератор, что для разброса).
		var c0 := coarse_start[cell]
		var cn := coarse_start[cell + 1] - c0
		for i in count:
			if unit_squad[i] == s:
				var j := _random_zombie_in_cell(c0, cn)
				if j != -1:
					_fire_arrow(i, pos[j], (unit_rand[i] * 2.0 - 1.0) * VOLLEY_JITTER, archer_own_range, unit_rand[i] * 2.0 * VOLLEY_JITTER)
		squad_volley_fired[s] = 1
		if contact_tick < 0:
			volleys_before_contact += 1
		squad_volley_t[s] = t
	elif t >= type_volley_period[ut] / squad_atk_speed_mult[s]:   # Клич Благодати ускоряет цикл залпа (без него 1.0)
		squad_volley_t[s] = 0.0   # перезарядка закончилась: новый цикл с натяжения
		squad_volley_fired[s] = 0
	else:
		squad_volley_t[s] = t


# Самая плотная грубая клетка, зомби которой (их центр масс) не дальше range_far от центра отряда; -1 если нет.
# Окно поиска — все грубые клетки в квадрате ±range_far вокруг центра отряда, то есть весь радиус.
func _volley_target_cell(s: int, range_far: float) -> int:
	var sp := squad_pos[s]
	var best := -1
	var best_n := 0
	for cy in range(clampi(floori((sp.y - range_far) / COARSE_SIZE), 0, COARSE_H - 1), clampi(floori((sp.y + range_far) / COARSE_SIZE), 0, COARSE_H - 1) + 1):
		for cx in range(clampi(floori((sp.x - range_far) / COARSE_SIZE), 0, COARSE_W - 1), clampi(floori((sp.x + range_far) / COARSE_SIZE), 0, COARSE_W - 1) + 1):
			var c := cx + cy * COARSE_W
			var cn := coarse_zcount[c]
			# дальность — до центра масс зомби клетки, а не до её геометрического центра (он может быть до 0.7 клетки в стороне)
			if cn > best_n and (coarse_sum[c] / cn).distance_to(sp) <= range_far:
				best_n = cn
				best = c
	return best


# Случайный живой зомби из списка грубой клетки [c0, c0 + cn). Индексы могли устареть после
# _remove_dead: если выпал неживой или не зомби, берём следующего по кругу; никого — -1.
func _random_zombie_in_cell(c0: int, cn: int) -> int:
	if cn <= 0:
		return -1
	var start := arrow_rng.randi_range(0, cn - 1)
	for q in cn:
		var j := coarse_units[c0 + (start + q) % cn]
		if j < count and team[j] == 1 and hp[j] > 0.0:
			return j
	return -1


# Стрела-событие: точка падения = прицел + разброс (радиус spread * дистанция, seeded-генератор),
# тик падения = сейчас + задержка + дистанция / ARROW_SPEED. own_range: если точка падения дальше range_far
# от самого лучника, выстрела нет (arrows_out_of_range).
# release_in (только отрисовка): через сколько секунд лучник выпускает стрелу сам — в залпе это его задержка,
# отсчитанная от самого раннего выстрела залпа (0 .. 2 * VOLLEY_JITTER); 0 — сейчас.
func _fire_arrow(i: int, aim: Vector2, delay: float, own_range := false, release_in := 0.0) -> void:
	if arrow_count >= ARROW_CAP:
		arrows_dropped += 1
		return
	var t := unit_type[i]
	var dist := pos[i].distance_to(aim)
	var land := aim + Vector2.from_angle(arrow_rng.randf() * TAU) * (wave_spread[t] * dist * sqrt(arrow_rng.randf()))
	if own_range and pos[i].distance_to(land) > type_range_far[t]:
		arrows_out_of_range += 1
		return
	var ticks := roundi((delay + pos[i].distance_to(land) / ARROW_SPEED) * Engine.physics_ticks_per_second)
	arrow_land[arrow_count] = land
	arrow_tick[arrow_count] = tick_counter + maxi(ticks, 1)
	arrow_dmg[arrow_count] = type_arrow_dmg[t] * squad_dmg_mult[unit_squad[i]]
	arrow_from[arrow_count] = pos[i]   # только отрисовка: лучник, выпуск на экране (release_in), номер выстрела
	arrow_t0[arrow_count] = minf(tick_counter + release_in * Engine.physics_ticks_per_second, arrow_tick[arrow_count] - 1)
	arrow_vid[arrow_count] = arrows_fired
	arrow_count += 1
	if arrow_fx_on:   # только отрисовка (задача 29): стрела — в слот полёта scripts/arrow_fx.gd
		arrow_fx.fire(arrow_count - 1)
	arrows_fired += 1
	if contact_tick < 0:
		arrows_before_contact += 1
	squad_arrows_fired[unit_squad[i]] += 1
	if release_in > 0.0:
		unit_shot_t[i] = release_in
	else:
		unit_shot_t[i] = 0.0
		unit_anim_t[i] = ATTACK_ANIM_T


# Падение стрел этого тика: урон ближайшему живому зомби в ARROW_HIT_R (мелкая сетка, 3x3), иначе промах.
# Дружественного огня нет. Очередь — swap-and-pop.
func _process_arrows() -> void:
	var a := 0
	while a < arrow_count:
		if arrow_tick[a] > tick_counter:
			a += 1
			continue
		var p := arrow_land[a]
		var cx := clampi(floori(p.x / CELL_SIZE), 0, GRID_W - 1)
		var cy := clampi(floori(p.y / CELL_SIZE), 0, GRID_H - 1)
		var best := -1
		var best_d := ARROW_HIT_R * ARROW_HIT_R
		for ny in range(maxi(cy - 1, 0), mini(cy + 1, GRID_H - 1) + 1):
			for nx in range(maxi(cx - 1, 0), mini(cx + 1, GRID_W - 1) + 1):
				var c := nx + ny * GRID_W
				for k in range(cell_start[c], cell_start[c + 1]):
					var j := sorted_units[k]
					if team[j] != 1 or hp[j] <= 0.0:
						continue
					var d2 := p.distance_squared_to(pos[j])
					if d2 <= best_d:
						best_d = d2
						best = j
		if best != -1:
			hp[best] -= arrow_dmg[a]
			if hp[best] <= 0.0:
				kills_by_arrows += 1
			arrows_hit += 1
		if arrow_fx_on:   # только отрисовка (задача 29): попадание или промах — эффект в scripts/arrow_fx.gd
			arrow_fx.land(a, best != -1, pos[best] if best != -1 else p)
		arrow_count -= 1
		arrow_land[a] = arrow_land[arrow_count]
		arrow_tick[a] = arrow_tick[arrow_count]
		arrow_dmg[a] = arrow_dmg[arrow_count]
		arrow_from[a] = arrow_from[arrow_count]
		arrow_t0[a] = arrow_t0[arrow_count]
		arrow_vid[a] = arrow_vid[arrow_count]


# Shift на момент последнего события мыши или клавиатуры: клик по строке панели сюда приходит раньше, чем кнопке.
# Действие игры для нажатой клавиши или "". Сначала действия с модификаторами (Ctrl+A, Ctrl+R), затем остальные.
func _key_action(event: InputEvent) -> String:
	for a in KEY_ACTIONS:
		if InputMap.has_action(a) and event.is_action(a):
			return a
	return ""


func _input(event: InputEvent) -> void:
	if event is InputEventWithModifiers:
		mod_shift = event.shift_pressed
	if pan_active:   # задача 28: перетаскивание камеры — движение и отпускание средней кнопки где угодно, и над панелями
		if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) == 0:
			pan_end()   # отпускание не дошло (меню паузы на дереве, окно без фокуса): кнопка уже не зажата
		elif event is InputEventMouseMotion:
			pan_to(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
			pan_end()


func _unhandled_input(event: InputEvent) -> void:
	if _tune_key(event):
		return   # подгонка замка (F3, debug-сборка)
	# Сюда приходят только события, не съеденные интерфейсом: клик по панели карту не трогает.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# ЛКМ выбирает: клик — отряд под курсором, протяжка — рамка
		var p := (make_input_local(event) as InputEventMouseButton).position   # мировые координаты
		if event.pressed:
			if drag_active:
				drag_active = false   # ЛКМ во время ПКМ-протяжки отменяет её; рамка при этом не начинается
			else:
				box_active = true
				box_start = p
				box_cur = p
				box_dbl = event.double_click
			queue_redraw()
		elif box_active:
			box_active = false
			if box_start.distance_to(p) < ui_layout.drag_min:
				_click_select(box_start, event.shift_pressed, box_dbl)
			else:
				_box_select(Rect2(box_start, p - box_start).abs(), event.shift_pressed)
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		# ПКМ приказывает выбранным: клик — цель, протяжка — строй по линии. Ничего не выбрано — игнорируется.
		var p := (make_input_local(event) as InputEventMouseButton).position
		if event.pressed:
			if box_active:
				box_active = false   # ПКМ отменяет рамку
			elif sel_mask != 0 and not _orders_locked():
				drag_active = true
				drag_flip = false
				drag_start = p
				drag_cur = p
			queue_redraw()
		elif drag_active:
			drag_active = false
			var list := _order_list()   # ведомому цель и строй задаёт ведущий
			if drag_start.distance_to(p) >= ui_layout.drag_min:
				_place_formation_multi(list, drag_start, p, drag_flip)
			elif list.size() == 1:
				_cmd_move(list[0], drag_start)   # короткий клик: цель отряда (если блок не пересечётся с другим)
			elif list.size() > 1:
				_cmd_move_group(list, drag_start)
			_hint_event("order")
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			pan_begin(event.position)   # задача 28: зажатое колесо — перетаскивание камеры (движение — в _input)
	elif event is InputEventMouseMotion and (drag_active or box_active):
		var p := screen_to_world(event.position) if pan_active else (make_input_local(event) as InputEventMouseMotion).position
		if drag_active:
			drag_cur = p
		else:
			box_cur = p
		queue_redraw()   # предпросмотр и рамка перерисовываются только во время перетаскивания
	elif event is InputEventMouseButton and event.pressed and not event.shift_pressed and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# задача 27: колесо без Shift — зум к точке под курсором (вверх — ближе); factor — доля щелчка (тачпад)
		var f: float = event.factor if event.factor > 0.0 else 1.0
		zoom_by(f if event.button_index == MOUSE_BUTTON_WHEEL_UP else -f, event.position)
	elif event is InputEventMouseButton and event.pressed and event.shift_pressed and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		# Shift + колесо: поворот на месте (с Shift система может прислать горизонтальное колесо); без Shift — зум (выше)
		_cmd_rotate(-1 if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1)
	elif (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed
			and SETTINGS.MOUSE_BINDABLE.has(event.button_index)):
		# Команды игры — действия InputMap (клавиши по умолчанию в [input] project.godot, переназначение — Settings, можно
		# и на среднюю/боковые кнопки мыши); Esc и F1–F5 постоянные и идут по keycode.
		var key := event as InputEventKey   # null — кнопка мыши
		if _run_over():
			if event.is_action("to_hub") or event.is_action("wave_start"):
				_to_hub()
			elif key != null and key.keycode == KEY_ESCAPE:
				_open_esc_menu()
			return   # экран конца забега: остальные клавиши не действуют
		var act := _key_action(event)
		if act.begins_with("squad_select_"):
			var s := int(act.trim_prefix("squad_select_")) - 1
			if event.shift_pressed:
				_toggle_sel(s)
			else:
				_select_only(s)
		elif act in SHOP_ACTIONS:
			_buy(SHOP_ACTIONS.find(act))
		match act:
			"about_face":
				if drag_active:
					drag_flip = not drag_flip   # во время протяжки: лицо строя наоборот
					queue_redraw()
				else:
					_cmd_about_face()
			"banner_toggle":
				_toggle_banner()
			"auto_width":
				for s in (PackedInt32Array() if _orders_locked() else _sel_list()):
					squad_user_width[s] = 0   # ширина строя снова авто
			"debug_restart":
				if DEBUG_COLORS:
					get_tree().reload_current_scene()   # отладочный перезапуск боя
			"wave_start":
				if PAUSE_ENABLED and wave_state == WS_BATTLE:
					_set_paused(not paused)
				else:
					_start_wave()
			"pause":
				_set_paused(not paused)
			"split_side":
				_next_split_mode()
			"post_left":
				_cmd_side_post(SIDE_LEFT)
			"post_top":
				_cmd_side_post(SIDE_TOP)
			"post_right":
				_cmd_side_post(SIDE_RIGHT)
			"post_back":
				_cmd_side_post(-1)
			"select_all":
				_select_all()
			"squad_new":
				_cmd_new_squad()
			"squad_split":
				_cmd_split()
			"squad_merge":
				_cmd_merge()
			"order_attack":
				_set_order(ORDER_ATTACK)
			"order_hold":
				_set_order(ORDER_HOLD)
			"order_retreat":
				_set_order(ORDER_RETREAT)
			"war_cry":
				request_war_cry()
			"shop_toggle":
				toggle_shop()
			"squad_panel_toggle":
				toggle_squad_panel()
			"camera_zoom_reset":
				zoom_reset()
			"hero_attack":
				if hero_idx >= 0 and not paused:
					hero_attack_latch = true   # удар — во вводе ближайшего тика (_hero_input)
					_hint_event("hero_attack")
		if key == null:
			return
		match key.keycode:
			KEY_ESCAPE:
				if drag_active or box_active:
					drag_active = false   # Esc отменяет протяжку и рамку
					box_active = false
					queue_redraw()
				else:
					_open_esc_menu()
			KEY_F1:
				color_mode = 0
				_sync_fx_debug()
			KEY_F2, KEY_F3, KEY_F4:   # в debug-сборке F3 без Shift — подгонка замка (_tune_key), раскраска по состоянию — Shift+F3
				if DEBUG_COLORS:
					color_mode = event.keycode - KEY_F1
					_sync_fx_debug()
			KEY_F5:
				sprites_on = not sprites_on   # спрайты / все юниты квадратами
