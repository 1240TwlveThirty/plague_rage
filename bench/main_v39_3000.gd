extends Node2D

const INFANTRY_COUNT := 300   # отряд 0: пехота игрока
const ARCHER_COUNT := 100     # отряд 1: лучники игрока
const UNIT_COUNT := 3000       # стартовый состав без волн: остальные (UNIT_COUNT - INFANTRY_COUNT - ARCHER_COUNT) — зомби
const MAX_UNITS := 4000       # ёмкость всех массивов юнитов (выделяются один раз)
const WAVES_ENABLED := true   # false: как bak21 (300 зомби на старте, без волн) — для старых бенчей
const WAVES_PATH := "res://data/waves.json"
const SHOP_PATH := "res://data/shop.json"
const SHOP_ITEMS := ["inf_pack", "archer_pack", "weapons", "gate"]   # порядок = клавиши Z X C V
const SHOP_KEYS := [KEY_Z, KEY_X, KEY_C, KEY_V]
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
const ORDER_NAMES := ["атака", "держать", "отход"]
const UNIT_TYPES_PATH := "res://data/unit_types.json"
const CASTLE_PATH := "res://data/castle.json"
const RECORD_PATH := "user://record.json"   # прежний рекорд best_wave: в игре не читается и не пишется (рекорды в Game)
const RUN_PATH := "res://data/run.json"     # забег: waves_per_run, siege_count
const GAME_SCRIPT := preload("res://scripts/game.gd")   # общий загрузчик run.json
const STORY_PATH := "res://data/story.json"   # дневник: тексты баннеров (на механику не влияет)
const GIFTS_PATH := "res://data/gifts.json"   # дары: модификаторы забега
const MODS := preload("res://scripts/mods.gd")
const ESC_MENU := preload("res://scripts/esc_menu.gd")   # меню паузы по Esc: «Продолжить», «Выйти в меню», «Выход из игры»
const ESC_NOTE := "Выход в меню засчитает поражение"
const BANNER_WIDTH := 700.0                   # ширина баннера, px: длинный текст переносится по словам
const STORY_COLOR := Color(1.0, 0.88, 0.6)    # цвет текста дневника в баннере
const RADIANCE_COLOR := Color(0.6, 0.9, 1.0)  # цвет строки «+N Сияния» на экране итога
const SQUAD_MAX := 8                          # ёмкость всех массивов отрядов (выделяются один раз)
const START_SQUADS := 2                       # отряды 0 (пехота) и 1 (лучники) есть всегда и не освобождаются
const ROTATE_STEP := PI / 12.0                # Shift + колесо: поворот отряда на месте, 15°
const BANNER_TOP := 120.0                     # верхняя граница баннера, px от верха экрана
const BANNER_BG_ALPHA := 0.55                 # непрозрачность фона баннера
const OVERLAP_MAX := 0.25                     # расстановка: доля площади меньшего блока, с которой пересечение со своим отрядом запрещено
const DRAG_MIN := 24.0                       # px: короче — обычный клик, длиннее — расстановка строя по линии
const FORM_MARGIN := 12.0                     # строй при расстановке не ниже WALL_Y - FORM_MARGIN
const PAUSE_ENABLED := true                   # активная пауза в бою (Space, P); false — паузы нет, как раньше
const SIDE_POST_T := 0.45                     # стрелки: пост на отрезке ворота -> точка появления стороны, доля пути
const GATE_POST_BACK := 90.0                  # стрелка вниз: пост у ворот, на столько выше стены
const SPLIT_MODE_NAMES := ["правые", "левые", "задние", "передние"]
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
const FG_PATH := "res://art/castle_walls_and_trees.png"   # передний план (кроны, верх стены), прозрачный PNG того же размера
const BG_SCALE := 1056.0 / 859.0   # фон по высоте ровно на поле (1056 px), как прежний castle_bg.jpg 1500x704 с масштабом 1.5
const BG_OFFSET := Vector2(-21, 0)
const FG_ALPHA := 1.0              # прозрачность переднего плана
const FG_Z := 1                    # передний план выше юнитов, снарядов и полос HP ворот (всё на z 0), ниже интерфейса (CanvasLayer)
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
const DEBUG_COLORS := true            # F2–F4: отладочная раскраска; false в релизе (остаётся только F1)
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
var color_mode := 0                           # 0 = F1 по типу, 1 = F2 по ряду, 2 = F3 по состоянию, 3 = F4 смена слота
var squad_front_row := PackedInt32Array()     # scratch для F2: передний занятый ряд отряда

# --- Типы юнитов (data/unit_types.json): плоские массивы по номеру типа ---
var unit_type := PackedByteArray()
var type_hp := PackedFloat32Array()
var type_damage := PackedFloat32Array()
var type_range_sq := PackedFloat32Array()   # квадрат дальности атаки
var type_cooldown := PackedFloat32Array()
var type_speed := PackedFloat32Array()
var type_block_mult := PackedFloat32Array()   # множитель урона при блоке щитом; 1.0 = без щита
# Мягкая привязь к слоту: до leash_start юнит гонится за врагом, к leash_end — только к слоту.
var type_leash_start := PackedFloat32Array()
var type_leash_start_sq := PackedFloat32Array()
var type_leash_end := PackedFloat32Array()
var type_color := PackedColorArray()
var type_range_far := PackedFloat32Array()      # дальность стрельбы; 0 = не стреляет
var type_volley_period := PackedFloat32Array()  # период цикла залпа, с
var type_draw_time := PackedFloat32Array()      # натяжение перед залпом, с
var type_spread := PackedFloat32Array()         # разброс: радиус = spread * дистанция
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
var type_label := PackedStringArray()   # название типа для интерфейса

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
var mods: RefCounted = null            # MODS: спрашивается один раз в _apply_mods, тик его не вызывает
var income_pct := 0.0                  # дар на доход: эта доля дохода прошлой волны начисляется в начале волны
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
var zombie_alive := 0
var gold := 0.0
var unit_rng := RandomNumberGenerator.new()   # unit_rand, джиттер спавна, точки выхода из ворот
var infantry_type := -1
var archer_type := -1
var zombie_type := -1
var runner_type := -1
var knight_type := -1
const SIDE_TOP := 0     # стороны появления орды
const SIDE_LEFT := 1
const SIDE_RIGHT := 2
const SIDE_ARROWS := ["↑", "←", "→"]
const VIEW_HALF_H := 540.0   # и половина высоты
const SIDE_WORDS := ["сверху", "слева", "справа"]
const VIEW_HALF_W := 960.0   # половина ширины экрана в px мира (камера по центру поля): для маркеров разведки у края экрана
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
static var signal_warned := false      # предупреждение об отсутствии звука — один раз за запуск игры (R сцену пересоздаёт)
var sort_keys := PackedInt64Array()           # scratch для _reflow_squad
var squad_aspect := PackedVector2Array()      # пропорция строя (ширина, глубина): пехота 20/15, лучники 25/4
var shop_label := PackedStringArray()
var shop_base := PackedFloat64Array()   # float64: цены вида 100·1.2 без хвостов float32
var shop_growth := PackedFloat64Array()
var shop_param := PackedFloat64Array()        # amount / dmg_mult / gate_max_gain
var shop_bought := PackedInt32Array()
var shop_cap := PackedInt32Array()          # inf_pack / archer_pack: максимум живых юнитов этого типа
var hud_label: Label
var shop_panel: VBoxContainer
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
var hud_msg := ""                         # сообщение в HUD (отказ команды), гаснет через hud_msg_t секунд
var hud_msg_t := 0.0
var panel_t := 0.0                            # таймер обновления левой панели (4 Гц)

# --- Отрисовка ---
var multimesh: MultiMesh
var fps_label: Label
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
	add_child(bg)
	# Передний план: те же позиция и масштаб, что у фона
	if not ResourceLoader.exists(FG_PATH):
		push_warning("Нет переднего плана %s: рисуется без него" % FG_PATH)
		return
	var fg := _map_sprite(FG_PATH)
	fg.z_index = FG_Z
	fg.modulate.a = FG_ALPHA
	add_child(fg)


func _map_sprite(path: String) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = load(path)
	sp.centered = false
	sp.scale = Vector2(BG_SCALE, BG_SCALE)
	sp.position = BG_OFFSET
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sp


# Фиксированная камера на центре поля, без отдаления.
func _setup_camera() -> void:
	var cam := Camera2D.new()
	cam.position = FIELD * 0.5
	cam.zoom = Vector2.ONE
	add_child(cam)
	cam.make_current()


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
	if box_active and box_start.distance_to(box_cur) >= DRAG_MIN:
		var box_rect := Rect2(box_start, box_cur - box_start).abs()
		draw_rect(box_rect, Color(0.2, 1.0, 0.3, 0.12))
		draw_rect(box_rect, Color(0.2, 1.0, 0.3, 0.9), false, 1.0)
	# Предпросмотр расстановки (ПКМ): контур блока (красный, если блок не помещается и будет сдвинут или слишком
	# пересекается с другим своим отрядом и поставлен не будет), яркий передний ряд, стрелка лица, подпись.
	# Несколько выбранных: блок каждого отряда цветом типа, подпись — число отрядов и длина линии.
	if drag_active and drag_start.distance_to(drag_cur) >= DRAG_MIN:
		var list := _order_list()
		if list.size() == 1:
			var g := _formation_geometry(list[0], drag_start, drag_cur, drag_flip)
			if g.n > 0:
				_draw_block_preview(type_color[squad_type[list[0]]], g.centre, g.front, g.angle, g.width, g.rows, g.adjusted or g.overlap >= 0)
				draw_string(ThemeDB.fallback_font, drag_cur + Vector2(16.0, -12.0), "%d × %d · %d юн." % [g.width, g.rows, g.n],
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color.WHITE)
		elif list.size() > 1:
			var mg := _multi_geometry(list, drag_start, drag_cur, drag_flip)
			for it in mg.items:
				_draw_block_preview(type_color[squad_type[it.s]], it.centre, it.front, mg.angle, it.width, it.rows, mg.adjusted or not mg.fits or mg.overlap >= 0)
			draw_string(ThemeDB.fallback_font, drag_cur + Vector2(16.0, -12.0), "%d отр. · %d px" % [list.size(), roundi(mg.length)],
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color.WHITE)
	# Сигнал всплеска: пульсирующая золотая полоса вдоль края экрана и мигающий (2 Гц) треугольник 48 px у своей стороны
	var view_lo := FIELD * 0.5 - Vector2(VIEW_HALF_W, VIEW_HALF_H)
	var view_size := Vector2(VIEW_HALF_W, VIEW_HALF_H) * 2.0
	# Слои: мягкая красная полоса у края экрана своей стороны — 0.30 у края, плавно до 0 на 100 px вглубь (10 ступеней)
	for side in 3:
		var sa := _signal_alpha(side)
		if sa <= 0.0:
			continue
		for q in 10:
			var band := Rect2(view_lo + Vector2(0.0, q * 10.0), Vector2(view_size.x, 10.0))
			if side == SIDE_LEFT:
				band = Rect2(view_lo + Vector2(q * 10.0, 0.0), Vector2(10.0, view_size.y))
			elif side == SIDE_RIGHT:
				band = Rect2(view_lo + Vector2(view_size.x - (q + 1) * 10.0, 0.0), Vector2(10.0, view_size.y))
			draw_rect(band, Color(0.85, 0.12, 0.12, sa * (1.0 - q / 10.0)))
		if SIGNAL_ICONS_SHOWN and fmod(wave_t * 2.0, 1.0) < 0.5:
			var tri_at := Vector2(wave_cfg.spawn_center_x, 150.0)
			var tri_dir := Vector2.DOWN
			if side == SIDE_LEFT:
				tri_at = Vector2(view_lo.x + 120.0, wave_cfg.spawn_left_y)
				tri_dir = Vector2.RIGHT
			elif side == SIDE_RIGHT:
				tri_at = Vector2(view_lo.x + view_size.x - 120.0, wave_cfg.spawn_right_y)
				tri_dir = Vector2.LEFT
			var tri_lat := Vector2(-tri_dir.y, tri_dir.x)
			draw_colored_polygon(PackedVector2Array([tri_at + tri_dir * 24.0, tri_at - tri_dir * 24.0 + tri_lat * 24.0, tri_at - tri_dir * 24.0 - tri_lat * 24.0]), Color(0.85, 0.12, 0.12, 0.95))
	for side in _burst_signals():
		var pulse := 0.5 + 0.5 * sin(wave_t * 2.0 * TAU)
		var strip := Rect2(view_lo, Vector2(view_size.x, 24.0))
		var icon_at := Vector2(wave_cfg.spawn_center_x, 150.0)
		var icon_dir := Vector2.DOWN
		if side == SIDE_LEFT:
			strip = Rect2(view_lo, Vector2(24.0, view_size.y))
			icon_at = Vector2(view_lo.x + 120.0, wave_cfg.spawn_left_y)
			icon_dir = Vector2.RIGHT
		elif side == SIDE_RIGHT:
			strip = Rect2(view_lo + Vector2(view_size.x - 24.0, 0.0), Vector2(24.0, view_size.y))
			icon_at = Vector2(view_lo.x + view_size.x - 120.0, wave_cfg.spawn_right_y)
			icon_dir = Vector2.LEFT
		draw_rect(strip, Color(1.0, 0.8, 0.2, 0.35 * pulse))
		if fmod(wave_t * 2.0, 1.0) < 0.5:
			var icon_lat := Vector2(-icon_dir.y, icon_dir.x)
			draw_colored_polygon(PackedVector2Array([icon_at + icon_dir * 24.0, icon_at - icon_dir * 24.0 + icon_lat * 24.0, icon_at - icon_dir * 24.0 - icon_lat * 24.0]), Color(1.0, 0.8, 0.2, 0.95))
	# Разведка в передышке: у каждой активной стороны треугольник внутрь поля и состав (цвет типа, число)
	for mk in _recon_markers():
		var d: Vector2 = mk.dir
		var side_lat := Vector2(-d.y, d.x)
		var at: Vector2 = mk.pos
		draw_colored_polygon(PackedVector2Array([at + d * 16.0, at - d * 8.0 + side_lat * 12.0, at - d * 8.0 - side_lat * 12.0]), Color(1.0, 0.35, 0.25, 0.9))
		var items: Array = mk.items
		var x0 := at.x - 22.0 - items.size() * 78.0 if mk.side == SIDE_RIGHT else at.x + 22.0   # справа список идёт влево от маркера
		for q in items.size():
			var cell := Vector2(x0 + q * 78.0, at.y - 7.0)
			draw_rect(Rect2(cell, Vector2(14, 14)), type_color[items[q][0]])
			draw_string(ThemeDB.fallback_font, cell + Vector2(18.0, 13.0), "×%d" % items[q][1], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color.WHITE)
	if not DEBUG_COLORS:
		return
	draw_circle(GATE_POS, 8.0, Color(1.0, 0.85, 0.2, 0.8))
	var y := 0.0
	while y <= WALL_Y:
		draw_circle(Vector2(ROAD_X, y), 3.0, Color(1.0, 1.0, 1.0, 0.5))
		y += 60.0


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
			"burst_target_size", "burst_gap", "burst_gap_jitter", "burst_signal_lead", "burst_chunk", "burst_chunk_interval"], WAVES_PATH):
		return false
	if not d.get("layers") is Array or d.layers.size() != 3:
		push_error("%s: нет массива layers из трёх слоёв" % WAVES_PATH)
		return false
	for q in 3:
		var layer = d.layers[q]
		if not layer is Dictionary or not _require_numbers(layer, ["gap", "gap_jitter", "signal_lead", "pair_prob", "group_max", "side_weight_top", "side_weight_left",
				"side_weight_right", "sides_from_wave", "burst_target_size", "burst_count_min", "burst_count_max"], "%s, слой %d" % [WAVES_PATH, q + 1]):
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
	var param_key := {"inf_pack": "amount", "archer_pack": "amount", "weapons": "dmg_mult", "gate": "gate_max_gain"}
	var n := SHOP_ITEMS.size()
	shop_label.resize(n)
	shop_base.resize(n)
	shop_growth.resize(n)
	shop_param.resize(n)
	shop_bought.resize(n)
	shop_bought.fill(0)
	shop_cap.resize(n)
	for k in n:
		var id: String = SHOP_ITEMS[k]
		var e = d.get(id)
		if not e is Dictionary:
			push_error("%s: нет товара %s" % [SHOP_PATH, id])
			return false
		var keys := ["base", "growth", param_key[id]]
		if id in ["inf_pack", "archer_pack"]:
			keys.append("cap")
		if not _require_numbers(e, keys, "%s, товар %s" % [SHOP_PATH, id]):
			return false
		if not e.get("label") is String:
			push_error("%s: у товара %s нет строкового поля label" % [SHOP_PATH, id])
			return false
		shop_label[k] = e.label
		shop_base[k] = e.base
		shop_growth[k] = e.growth
		shop_param[k] = e[param_key[id]]
		shop_cap[k] = e.get("cap", 0)   # только у отрядов; у остальных не используется
	return true


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
	var defs: Dictionary = MODS.load_gifts(gifts_path)
	if defs.is_empty():
		return false
	if game != null:
		active_gifts = game.active_gifts.duplicate()
	mods = MODS.new(defs)
	return mods.build(active_gifts)


# Эффективные характеристики забега — один раз, до создания юнитов: дальше бой читает только готовые числа.
# Урон, HP и награда умножаются прямо в массивах типов (type_damage, type_arrow_dmg, type_hp, type_bounty_mult),
# ворота — в gate_hp_max, доход — в income_pct. Тип игрока получает множители цели all_units и своей (infantry, archer).
# Без даров все множители ровно 1.0 и числа те же бит в бит.
func _apply_mods() -> void:
	var names := {infantry_type: "infantry", archer_type: "archer"}
	for t in names:
		var dmg: float = mods.get_mult("damage", "all_units") * mods.get_mult("damage", names[t])
		type_damage[t] *= dmg
		type_arrow_dmg[t] *= dmg
		type_hp[t] *= mods.get_mult("hp", "all_units") * mods.get_mult("hp", names[t])
	var bounty: float = mods.get_mult("bounty", "player")
	for t in type_bounty_mult.size():
		type_bounty_mult[t] *= bounty
	gate_hp_max *= mods.get_mult("gate_hp", "gate")
	gate_hp = gate_hp_max
	income_pct = mods.get_mult("income", "player") - 1.0


# Дар на стартовые юниты: прибавка каждому стартовому отряду, юниты выходят из ворот, как купленные.
func _add_start_units() -> void:
	for s in START_SQUADS:
		var n := int(mods.get_flat("start_units", "player"))
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
	var text := "Дальше: волна %d" % wave_plan_for
	for side in 3:
		if by_side[side] > 0:
			text += " · %s %d" % [SIDE_ARROWS[side], by_side[side]]
	var extra := PackedStringArray()
	if runners > 0:
		extra.append("бегуны %d" % runners)
	if knights > 0:
		extra.append("рыцари %d" % knights)
	return text if extra.is_empty() else text + " (%s)" % ", ".join(extra)


# Маркеры разведки (только в передышке): на сторону — точка у края, направление внутрь поля и состав [тип, число].
# Верх: (spawn_center_x, 150); левая и правая — в 120 px от края экрана на высоте своей точки появления.
func _recon_markers() -> Array:
	var out := []
	if not scout_shown or not waves_enabled or wave_state != WS_RESPITE:
		return out
	var at := [Vector2(wave_cfg.spawn_center_x, 150.0), Vector2(FIELD.x * 0.5 - VIEW_HALF_W + 120.0, wave_cfg.spawn_left_y),
		Vector2(FIELD.x * 0.5 + VIEW_HALF_W - 120.0, wave_cfg.spawn_right_y)]
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
	var lead: float = _layer().signal_lead
	while burst_signal_n < wave_bursts.size() and wave_t >= wave_bursts[burst_signal_n].t_group - lead:
		var g: int = wave_bursts[burst_signal_n].group
		var words := PackedStringArray()
		while burst_signal_n < wave_bursts.size() and wave_bursts[burst_signal_n].group == g:
			words.append(SIDE_WORDS[wave_bursts[burst_signal_n].side])
			burst_signal_n += 1
		if SIGNAL_TEXT_SHOWN:
			burst_msg = "Всплеск: %s" % ", ".join(words)
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
	while burst_signal_n < wave_bursts.size() and wave_t >= wave_bursts[burst_signal_n].t_start - wave_cfg.burst_signal_lead:
		burst_msg = "Всплеск: %s" % SIDE_WORDS[wave_bursts[burst_signal_n].side]
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
	if not waves_enabled or wave_state != WS_RESPITE:
		return
	wave_number += 1
	wave_state = WS_BATTLE
	_set_paused(false)
	if income_pct != 0.0:
		gold += wave_income * income_pct
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
	arrows_fired = 0   # в отладочной строке — за текущую волну
	arrows_hit = 0
	arrows_out_of_range = 0
	contact_tick = -1
	volleys_before_contact = 0
	arrows_before_contact = 0
	kills_by_arrows = 0
	subwave_timer = 0.0
	wave_t = 0.0
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
	var names := ["крестьяне", "бегуны", "рыцари"]
	var types := [zombie_type, runner_type, knight_type]
	for q in 3:
		if wave_kills_by_type[types[q]] > 0:
			parts.append("%s %d" % [names[q], wave_kills_by_type[types[q]]])
	return "" if parts.is_empty() else "убито: " + ", ".join(parts)


func _wave_cleared() -> void:
	if run_limit and wave_number == waves_per_run:
		_on_win()   # последняя волна забега: передышки не будет
		return
	gold += wave_cfg.wave_bonus_gold
	wave_income = gold - gold_wave_start
	for i in count:
		if team[i] == 0:
			hp[i] = type_hp[unit_type[i]]   # бесплатное лечение армии
	wave_state = WS_RESPITE
	_set_paused(false)
	_free_empty_squads()
	wave_plan = _plan_wave(wave_number + 1)   # состав и всплески следующей волны известны с начала передышки
	wave_plan_for = wave_number + 1
	wave_bursts = _plan_bursts(wave_plan_for, wave_plan)
	var summary := "Волна %d пройдена: убито %d, +%d золота. Space — волна %d" % [
		wave_number, wave_kills, int(wave_cfg.wave_bonus_gold), wave_number + 1]
	var killed := _kills_text()
	_show_banner(summary if killed == "" else summary + "\n" + killed, _entry_text(wave_number))
	queue_redraw()   # маркеры разведки

# --- Магазин ------------------------------------------------------------------

func _price(k: int) -> float:
	return shop_base[k] * (1.0 + shop_growth[k] * shop_bought[k])


# Отряд упёрся в cap: живых этого типа плюс покупка больше предела.
func _at_cap(k: int) -> bool:
	var type := -1
	match SHOP_ITEMS[k]:
		"inf_pack":
			type = infantry_type
		"archer_pack":
			type = archer_type
	if type < 0:
		return false
	var alive := 0
	for i in count:
		if unit_type[i] == type:
			alive += 1
	return alive + int(shop_param[k]) > shop_cap[k]


# Покупка только в передышке, при достаточном золоте и не сверх cap. Возвращает, состоялась ли.
func _buy(k: int) -> bool:
	if wave_state != WS_RESPITE or gold < _price(k) or _at_cap(k):
		return false
	gold -= _price(k)
	shop_bought[k] += 1
	match SHOP_ITEMS[k]:
		"inf_pack":
			_squad_add_units(_buy_target(infantry_type), infantry_type, int(shop_param[k]))
		"archer_pack":
			_squad_add_units(_buy_target(archer_type), archer_type, int(shop_param[k]))
		"weapons":
			type_damage[infantry_type] *= shop_param[k]
			type_arrow_dmg[archer_type] *= shop_param[k]
		"gate":
			gate_hp_max += shop_param[k]   # фиксированная прибавка gate_max_gain
			gate_hp = gate_hp_max
	ui_t = 0.0   # обновить HUD и магазин сразу
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
		squad_pos[s] = Vector2(GATE_POS.x, WALL_Y - 40.0)
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


# Новый пустой отряд по образцу отряда src (тип, команда, пропорция строя) в первом свободном индексе
# >= START_SQUADS. Стоит у ворот лицом вверх, приказ «атака». Возвращает индекс или -1, если все заняты.
func _squad_create(src: int) -> int:
	for s in range(START_SQUADS, SQUAD_MAX):
		if squad_used[s] == 1:
			continue
		_squad_reset(s)
		squad_used[s] = 1
		squad_type[s] = squad_type[src]
		squad_team[s] = squad_team[src]
		squad_ranged[s] = squad_ranged[src]
		squad_aspect[s] = squad_aspect[src]
		squad_speed[s] = 0.75 * type_speed[squad_type[src]]
		squad_width[s] = maxi(int(squad_aspect[src].x), 1)
		squad_pos[s] = Vector2(GATE_POS.x, WALL_Y - 40.0)
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
	if wave_state != WS_RESPITE:
		return false
	if sel_primary < 0:
		_say("Выбери отряд")
		return false
	var s := _squad_create(sel_primary)
	if s < 0:
		_say("Свободных отрядов нет: занято %d из %d" % [SQUAD_MAX, SQUAD_MAX])
		return false
	_select_only(s)
	return true


# G: часть выбранного отряда уходит в новый отряд с той же командой, целью, углом, приказом и шириной строя;
# оба перестраиваются, выбор переходит на новый. Уходит k = clamp(floor(n * split_frac), 1, n - 1) юнитов:
# split_mode 0 и 1 — с наибольшей / наименьшей local.y (правые / левые), 2 и 3 — с наименьшей / наибольшей
# local.x (задние / передние ряды). В бою — только на паузе. Позиции юнитов не меняются. Выбран должен быть ровно один отряд.
func _cmd_split() -> bool:
	if _run_over():
		return false
	if wave_state == WS_BATTLE and not paused:
		if PAUSE_ENABLED:
			_say("Поставь паузу (Space)")
		return false
	if sel_mask == 0 or sel_mask & (sel_mask - 1) != 0:
		_say("Выбери один отряд")
		return false
	var s := sel_primary
	var n := squad_n[s]
	if squad_used[s] == 0 or n < 2:
		_say("В отряде меньше 2 юнитов: делить нечего")
		return false
	var t := _squad_create(s)
	if t < 0:
		_say("Свободных отрядов нет: занято %d из %d" % [SQUAD_MAX, SQUAD_MAX])
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
	split_label.text = "Доля ухода: %d%%" % roundi(split_frac * 100.0)
	split_mode_button.text = "Уходят: %s (K)" % SPLIT_MODE_NAMES[split_mode]


# Пауза только в бою. При включении prev_pos = pos: после снятия юниты не отскакивают на долю тика назад.
func _set_paused(v: bool) -> void:
	v = v and PAUSE_ENABLED and wave_state == WS_BATTLE
	if v == paused:
		return
	paused = v
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
			_say("Нет другого отряда этого типа")
			return false
		if src < START_SQUADS:
			srcs[0] = dst
			dst = src
	else:
		dst = srcs[0]
		for s in srcs:
			if squad_type[s] != squad_type[dst]:
				_say("Сливаются только отряды одного типа")
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
		_show_banner("", _ending_text(wave_number), "R — заново")
		return
	game.end_run("loss", wave_number, run_kills)
	_show_banner("", _ending_text(wave_number), "Лучшая волна осады %s: %d. Enter — в хаб" % [
		GAME_SCRIPT.roman(game.siege), game.records[game.siege].best_wave])
	_show_radiance(game.last_run.radiance)
	_show_hub_button()


# Последняя волна забега пройдена: бой останавливается (как при поражении), итог уходит в Game, Enter — в хаб.
func _on_win() -> void:
	wave_state = WS_WIN
	_set_paused(false)   # при победе пауза недоступна
	set_physics_process(false)
	best_wave = maxi(best_wave, wave_number)
	game.end_run("win", wave_number, run_kills)
	_show_banner("Осада пережита. Волн: %d из %d." % [wave_number, waves_per_run], story_victories.get(debug_layer, ""), "Enter — в хаб")
	_show_radiance(game.last_run.radiance)
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
	game.end_run("loss", w, run_kills)


# Экран итога: строка «+N Сияния» между дневником и подсказкой (после _show_banner: он её прячет).
func _show_radiance(n: int) -> void:
	banner_radiance = "+%d Сияния" % n
	if radiance_label == null:
		return
	radiance_label.text = banner_radiance
	radiance_label.visible = true
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
	banner.visible = any
	# размер по содержимому, по центру сверху: иначе после длинного текста баннер остаётся высоким
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	banner.position.y = BANNER_TOP


# H в передышке: скрыть или показать баннер.
func _toggle_banner() -> void:
	if wave_state != WS_RESPITE:
		return
	banner_hidden = not banner_hidden
	if banner != null:
		banner.visible = banner_any and not banner_hidden


# F вне протяжки: каждый выбранный отряд разворачивается «кругом» на месте (слоты в мире не двигаются).
func _cmd_about_face() -> bool:
	var list := _order_list()
	for s in list:
		_about_face(s)
	queue_redraw()
	return not list.is_empty()


# Shift + колесо: каждый выбранный отряд поворачивается на месте на steps * 15° вокруг центра своих живых слотов
# (squad_pos). Цель отряда не меняется; при «отходе» команда игнорируется.
func _cmd_rotate(steps: int) -> bool:
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
	return e.text


# Вступление для стартового баннера: с синглтоном — только пока оно не прочитано. "" — баннер без дневника.
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
	return "" if best < 0 else story_end_text[best].replace("{wave}", str(w))


func _load_types() -> bool:
	var data = _load_json(UNIT_TYPES_PATH)
	if data == null:
		return false
	if not data is Array or data.is_empty():
		push_error("%s: ожидается непустой JSON-массив типов" % UNIT_TYPES_PATH)
		return false
	var n: int = data.size()
	type_hp.resize(n)
	type_damage.resize(n)
	type_range_sq.resize(n)
	type_cooldown.resize(n)
	type_speed.resize(n)
	type_block_mult.resize(n)
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
				"range_far", "volley_period", "draw_time", "spread", "arrow_dmg", "bounty_mult", "chase", "recoil_px"], "%s, тип \"%s\"" % [UNIT_TYPES_PATH, e.name]):
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


# Значение из JSON с множителем масштаба (SCALE_REL или SPEED_REL), округлённое до 0.01.
func _scaled(v: float, rel: float) -> float:
	return roundf(v * rel * 100.0) / 100.0


func _type_of(type_name: String) -> int:
	if not type_id.has(type_name):
		push_error("%s: нет типа \"%s\"" % [UNIT_TYPES_PATH, type_name])
		return -1
	return type_id[type_name]


func _setup_data() -> void:
	if not _load_types():
		set_physics_process(false)
		set_process(false)
		return
	var infantry := _type_of("infantry")   # отряд 0
	var archer := _type_of("archer")       # отряд 1
	var peasant := _type_of("peasant")     # орда зомби
	var runner := _type_of("runner")
	var knight := _type_of("fallen_knight")
	if infantry == -1 or archer == -1 or peasant == -1 or runner == -1 or knight == -1 or not _load_castle() or not _load_waves() or not _load_shop() or not _load_run() or not _load_story() 			or not _load_mods():
		type_id = {}
		set_physics_process(false)
		set_process(false)
		return
	infantry_type = infantry
	archer_type = archer
	zombie_type = peasant
	runner_type = runner
	knight_type = knight
	_apply_mods()
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
	# (спрайт — белый, квадрат — цвет типа по белой ячейке).
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform float cells = 1.0;\nvoid vertex() {\n\tUV.x = (UV.x + INSTANCE_CUSTOM.x) / cells;\n}\n"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("cells", float(atlas_cells))
	var node := MultiMeshInstance2D.new()
	node.multimesh = multimesh
	node.texture = ImageTexture.create_from_image(atlas)   # без mipmaps
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.material = mat
	add_child(node)


func _setup_fps_label() -> void:
	var layer := CanvasLayer.new()
	# Пауза: лёгкое затемнение поля под интерфейсом (первый в слое) и надпись под HUD
	pause_dim = ColorRect.new()
	pause_dim.color = Color(0.0, 0.0, 0.0, 0.12)
	pause_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_dim.visible = false
	layer.add_child(pause_dim)
	fps_label = Label.new()
	layer.add_child(fps_label)
	# Баннер по центру сверху (верх на BANNER_TOP): заголовок, текст, дневник, подсказка на полупрозрачном фоне;
	# ширина BANNER_WIDTH вместе с полями, перенос по словам
	banner = PanelContainer.new()
	var banner_bg := StyleBoxFlat.new()
	banner_bg.bg_color = Color(0.0, 0.0, 0.0, BANNER_BG_ALPHA)
	banner_bg.set_content_margin_all(16.0)
	banner.add_theme_stylebox_override("panel", banner_bg)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE   # клики по карте проходят сквозь баннер
	var banner_box := VBoxContainer.new()
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(banner_box)
	for k in 4:
		var l := Label.new()
		l.custom_minimum_size.x = BANNER_WIDTH - 32.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 44 if k == 0 else 36)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 8)
		if k == 2:
			l.add_theme_color_override("font_color", STORY_COLOR)
		l.visible = false
		banner_box.add_child(l)
		banner_labels.append(l)
	radiance_label = Label.new()   # «+N Сияния»: только на экране итога, перед подсказкой
	radiance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	radiance_label.add_theme_font_size_override("font_size", 36)
	radiance_label.add_theme_color_override("font_color", RADIANCE_COLOR)
	radiance_label.add_theme_color_override("font_outline_color", Color.BLACK)
	radiance_label.add_theme_constant_override("outline_size", 8)
	radiance_label.visible = false
	banner_box.add_child(radiance_label)
	banner_box.move_child(radiance_label, 3)
	hub_button = Button.new()   # только на экране конца забега; баннер клики пропускает, кнопка — нет
	hub_button.text = "В хаб"
	hub_button.add_theme_font_size_override("font_size", 36)
	hub_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hub_button.visible = false
	hub_button.pressed.connect(_to_hub)
	banner_box.add_child(hub_button)
	banner.visible = false
	layer.add_child(banner)
	esc_menu = ESC_MENU.new()
	esc_menu.before_menu = _abandon_run
	add_child(esc_menu)
	# HUD сверху по центру
	hud_label = Label.new()
	hud_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_label.position.y = 8.0
	hud_label.add_theme_font_size_override("font_size", 22)
	hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud_label)
	# Сигнал всплеска: надпись вверху по центру, под HUD (без чисел и типов)
	burst_label = Label.new()
	burst_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	burst_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	burst_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	burst_label.position.y = 72.0
	burst_label.add_theme_font_size_override("font_size", 30)
	burst_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	burst_label.add_theme_color_override("font_outline_color", Color.BLACK)
	burst_label.add_theme_constant_override("outline_size", 8)
	burst_label.visible = false
	layer.add_child(burst_label)
	pause_label = Label.new()
	pause_label.text = "ПАУЗА"
	pause_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_label.position.y = 112.0   # под HUD и строкой сигнала всплеска
	pause_label.add_theme_font_size_override("font_size", 30)
	pause_label.add_theme_color_override("font_outline_color", Color.BLACK)
	pause_label.add_theme_constant_override("outline_size", 8)
	pause_label.visible = false
	layer.add_child(pause_label)
	# Магазин справа (виден только в передышке)
	shop_panel = VBoxContainer.new()
	shop_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	shop_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	shop_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	shop_panel.position.x -= 16.0
	for k in SHOP_ITEMS.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE   # иначе Space «нажимает» последнюю кнопку
		b.custom_minimum_size = Vector2(320, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_buy.bind(k))
		shop_panel.add_child(b)
		shop_buttons.append(b)
	layer.add_child(shop_panel)
	# Отряды слева: цветной квадрат, клавиша, название, живые, приказ; строки кликабельны
	squad_panel = VBoxContainer.new()
	squad_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	squad_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	squad_panel.position.x = 16.0
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
		b.custom_minimum_size = Vector2(260, 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_row_pressed.bind(s))
		row.add_child(b)
		squad_panel.add_child(row)
		squad_buttons.append(b)
		squad_rows_ui.append(row)
		squad_swatches.append(sw)
	# Внизу панели: создание, разделение, слияние (видны только в передышке)
	squad_actions = HBoxContainer.new()
	var action_names := ["+ Отряд (N)", "Разделить (G)", "Слить (M)"]
	var action_calls := [_cmd_new_squad, _cmd_split, _cmd_merge]
	for k in action_names.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 36)
		b.text = action_names[k]
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
	split_mode_button.custom_minimum_size = Vector2(0, 36)
	split_mode_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	split_mode_button.pressed.connect(_next_split_mode)
	split_box.add_child(split_mode_button)
	squad_panel.add_child(split_box)
	_update_split_ui()
	hint_label = Label.new()
	hint_label.text = "ЛКМ выбор · ПКМ приказ · Shift добавить"
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.modulate = Color(1.0, 1.0, 1.0, 0.7)
	squad_panel.add_child(hint_label)
	layer.add_child(squad_panel)
	add_child(layer)
	_no_focus(layer)
	_update_squad_panel()
	if wave_state == WS_RESPITE:
		var intro := _intro_text()
		_show_banner("", intro, "Расставь отряды. Space — начать волну 1", "Дневник военачальника" if intro != "" else "")
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
	for s in _sel_list():
		squad_order[s] = o
	_update_squad_panel()


# Название отряда для панели и магазина: label типа, а если отрядов этого типа несколько — с номером по порядку.
func _squad_label(s: int) -> String:
	var same := 0
	var rank := 0
	for q in SQUAD_MAX:
		if squad_used[q] == 1 and squad_type[q] == squad_type[s]:
			same += 1
			if q <= s:
				rank += 1
	return type_label[squad_type[s]] if same < 2 else "%s %d" % [type_label[squad_type[s]], rank]


# Левая панель отрядов: раз в 0.25 с и сразу при выборе / смене приказа. Строки свободных индексов скрыты,
# кнопки создания, разделения и слияния видны в передышке и на паузе в бою (на паузе работает только деление).
func _update_squad_panel() -> void:
	if squad_panel == null:
		return
	var acts := wave_state == WS_RESPITE or paused
	var sig := 1 if acts else 0
	for s in SQUAD_MAX:
		squad_rows_ui[s].visible = squad_used[s] == 1
		if squad_used[s] == 0:
			continue
		sig |= 2 << s
		squad_swatches[s].color = type_color[squad_type[s]]
		squad_buttons[s].text = "%d  %s — %d — %s" % [s + 1, _squad_label(s), squad_n[s], ORDER_NAMES[squad_order[s]]]
		squad_buttons[s].set_pressed_no_signal(_is_sel(s))
	squad_actions.visible = acts
	split_box.visible = acts
	action_buttons[0].disabled = wave_state != WS_RESPITE   # новый отряд и слияние — только в передышке
	action_buttons[2].disabled = wave_state != WS_RESPITE
	if sig != squad_panel_sig:
		squad_panel_sig = sig
		# набор строк изменился: размер по содержимому, снова по центру левого края
		squad_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 16)


# HUD и магазин: раз в 0.1 с (и сразу после покупки).
func _update_ui() -> void:
	if hud_label == null:
		return
	hud_label.text = "Волна %s · зомби: %d · ворота: %d/%d · золото: %d" % [
		"%d/%d" % [wave_number, waves_per_run] if run_limit else str(wave_number), zombie_alive + wave_remaining, ceili(maxf(gate_hp, 0.0)), roundi(gate_hp_max), floori(gold)]
	if scout_shown and waves_enabled and wave_state == WS_RESPITE:
		hud_label.text += "\n" + _plan_text()   # разведка
	burst_label.text = burst_msg
	burst_label.visible = wave_state == WS_BATTLE and burst_msg != "" and wave_t < burst_msg_until
	if hud_msg != "":
		hud_label.text += "\n" + hud_msg
	shop_panel.visible = wave_state == WS_RESPITE
	if not shop_panel.visible:
		return
	var key_names := ["Z", "X", "C", "V"]
	for k in shop_buttons.size():
		var price := _price(k)
		var capped := _at_cap(k)
		shop_buttons[k].text = "%s  %s — %s (куплено %d)" % [key_names[k], shop_label[k], "макс." if capped else "%d зол." % ceili(price), shop_bought[k]]
		# Юниты идут в выбранный отряд своего типа, иначе в первый отряд типа.
		var pack_type := infantry_type if SHOP_ITEMS[k] == "inf_pack" else (archer_type if SHOP_ITEMS[k] == "archer_pack" else -1)
		if pack_type >= 0:
			var target := _buy_target(pack_type)
			shop_buttons[k].text += "\n→ Отряд %d (%s)" % [target + 1, _squad_label(target)]
		shop_buttons[k].disabled = capped or gold < price   # серая при нехватке золота или на пределе


# Симуляция: фиксированный шаг (по умолчанию 30 раз в секунду)
var sim_ms := 0.0
var draw_ms := 0.0
# Профиль фаз тика (PROFILE; бенчи включают profile): сетка, юниты, движение, смерти, грубая сетка, остальное
const PROF_NAMES := ["сетка", "юниты", "движение", "смерти", "грубая", "остальное"]
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
	multimesh.visible_instance_count = count
	multimesh.buffer = buf          # один вызов вместо UNIT_COUNT
	draw_ms = (Time.get_ticks_usec() - t) / 1000.0
	fps_label.text = "FPS: %d | units: %d | sim avg: %.1f peak: %.1f | grid: %.1f ms | цвет: F%d | ворота: %.0f | стрелы за волну: %d/%d" % [
		Engine.get_frames_per_second(), count, sim_avg, sim_peak, grid_ms, color_mode + 1, gate_hp, arrows_fired, arrows_hit]
	if profile:
		var parts := []
		for q in 6:
			parts.append("%s %.2f" % [PROF_NAMES[q], prof_avg[q]])
		fps_label.text += "\nфазы, мс/тик: " + ", ".join(parts) + " | появилось за 10 с, максимум: %d" % arrivals_10s_max
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
				slot_vel = ((slot_world - p) * SLOT_GAIN).limit_length(type_speed[t] * 1.3)
				if leash_w > 0.5:
					leash_ticks += 2   # решение действует 2 тика (юнит обновляется раз в 2 тика)
		if best_d > type_range_sq[t] and order == ORDER_HOLD:
			# Держать: к врагу не идём, остаёмся (возвращаемся) в слот; бьём только того, кто в дальности атаки.
			var hold_slot := squad_pos[sq] + unit_slot[i].rotated(squad_angle[sq])
			v = ((hold_slot - p) * SLOT_GAIN).limit_length(type_speed[t] * 1.3)
			unit_state[i] = ST_RETURN if p.distance_squared_to(hold_slot) > SLOT_NEAR_SQ else ST_IDLE
		elif best_d > type_range_sq[t]:
			var dir := (pos[best] - p).normalized()
			if unit_squad[i] == -1:
				# Зомби подходит к врагу, качаясь вбок; фаза своя у каждого (unit_rand).
				dir += dir.orthogonal() * HORDE_CHAOS * sin(tick_counter * 0.15 + unit_rand[i] * TAU)
			v = dir * type_speed[t]
			unit_state[i] = ST_CHASE
		else:
			unit_state[i] = ST_ATTACK
		if best_d <= type_range_sq[t] and cooldown[i] <= 0.0:
			var dmg := type_damage[t]
			if WAVE_DMG_TO_UNITS and my_team == 1:
				dmg *= team_dmg_mult[1]   # сила зомби растёт с волной; без волн множитель 1.0
			var m := type_block_mult[unit_type[best]]
			if m < 1.0:
				total_hits += 1
				# Блок щитом: жертва в отряде, щит поднят (с её удара прошло >= SHIELD_DOWN_TIME;
				# cooldown = сколько осталось до её следующего удара), удар из переднего сектора.
				var sj := unit_squad[best]
				if sj >= 0 and type_cooldown[unit_type[best]] - cooldown[best] >= SHIELD_DOWN_TIME:
					var a := p - pos[best]
					if a.dot(Vector2.from_angle(squad_angle[sj])) > BLOCK_COS * a.length():
						dmg *= m
						blocked_hits += 1
			hp[best] -= dmg
			if my_team == 1 and contact_tick < 0:
				contact_tick = tick_counter
			cooldown[i] = type_cooldown[t]
			unit_anim_t[i] = ATTACK_ANIM_T
		if leash_w > 0.0:
			v = v.lerp(slot_vel, leash_w)   # смесь «к врагу (или стоять и бить)» и «к слоту»
			if leash_w > 0.5:
				unit_state[i] = ST_RETURN
	else:
		var s := unit_squad[i]
		if s >= 0:
			var slot_world := squad_pos[s] + unit_slot[i].rotated(squad_angle[s])
			var lim := type_speed[t] * 1.3 * (RETREAT_SPEED_MULT if order == ORDER_RETREAT else 1.0)
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
	cooldown[i] = maxf(cooldown[i] - delta, 0.0)


func _move_units(delta: float) -> void:
	for i in count:
		var p := (pos[i] + vel[i] * delta).clamp(Vector2.ZERO, FIELD)   # граница поля
		p.y = minf(p.y, WALL_Y)   # временный пол: ниже стены не заходит никто
		pos[i] = p


func _remove_dead() -> void:
	var i := 0
	while i < count:
		if hp[i] <= 0.0:
			if first_death_tick < 0:
				first_death_tick = tick_counter
			if team[i] == 1:   # убит зомби: счёт волны и золото
				zombie_alive -= 1
				wave_kills += 1
				run_kills += 1
				gold += wave_cfg.gold_per_kill * type_bounty_mult[unit_type[i]]
				wave_kills_by_type[unit_type[i]] += 1
			if unit_squad[i] >= 0:
				squad_dirty[unit_squad[i]] = 1
				squad_n[unit_squad[i]] -= 1
			count -= 1
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
			_say("Отряды не помещаются в поле", 2.0)
			return false
		if lo[axis] < 0.0:
			delta[axis] -= lo[axis]
		elif hi[axis] > lim[axis]:
			delta[axis] += lim[axis] - hi[axis]
	for s in list:
		var q := _target_overlap(s, squad_pos[s] + delta, mask)
		if q >= 0:
			_say("Блок пересекается с отрядом %d" % (q + 1), 2.0)   # цели не меняются ни у кого
			return false
	for s in list:
		squad_target[s] = squad_pos[s] + delta
	return true


# Обычный клик: цель отряда s. Не задаётся, если блок отряда в точке цели слишком пересечётся с другим своим отрядом.
func _cmd_move(s: int, target: Vector2) -> bool:
	var q := _target_overlap(s, target)
	if q >= 0:
		_say("Блок пересекается с отрядом %d" % (q + 1), 2.0)   # цель не меняется
		return false
	squad_target[s] = target
	return true

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
		_say("Блок пересекается с отрядом %d" % (g.overlap + 1), 2.0)   # отряд остаётся на месте
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
	if list.is_empty():
		return false
	if list.size() == 1:
		_place_formation(list[0], a, b, flip)
		return true
	var g := _multi_geometry(list, a, b, flip)
	if not g.fits or g.overlap >= 0:
		_say("Строй не помещается в поле" if not g.fits else "Блок пересекается с отрядом %d" % (g.overlap + 1), 2.0)
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
				squad_pos[s] += to_f / dist_f * minf(squad_speed[s] * delta, dist_f)
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
			var spd := squad_speed[s] * (RETREAT_SPEED_MULT if squad_order[s] == ORDER_RETREAT else 1.0)
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
		cooldown[i] = type_cooldown[t]


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
	elif t >= type_volley_period[ut]:
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
	var land := aim + Vector2.from_angle(arrow_rng.randf() * TAU) * (type_spread[t] * dist * sqrt(arrow_rng.randf()))
	if own_range and pos[i].distance_to(land) > type_range_far[t]:
		arrows_out_of_range += 1
		return
	var ticks := roundi((delay + pos[i].distance_to(land) / ARROW_SPEED) * Engine.physics_ticks_per_second)
	arrow_land[arrow_count] = land
	arrow_tick[arrow_count] = tick_counter + maxi(ticks, 1)
	arrow_dmg[arrow_count] = type_arrow_dmg[t]
	arrow_count += 1
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
		arrow_count -= 1
		arrow_land[a] = arrow_land[arrow_count]
		arrow_tick[a] = arrow_tick[arrow_count]
		arrow_dmg[a] = arrow_dmg[arrow_count]


# Shift на момент последнего события мыши или клавиатуры: клик по строке панели сюда приходит раньше, чем кнопке.
func _input(event: InputEvent) -> void:
	if event is InputEventWithModifiers:
		mod_shift = event.shift_pressed


func _unhandled_input(event: InputEvent) -> void:
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
			if box_start.distance_to(p) < DRAG_MIN:
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
			elif sel_mask != 0:
				drag_active = true
				drag_flip = false
				drag_start = p
				drag_cur = p
			queue_redraw()
		elif drag_active:
			drag_active = false
			var list := _order_list()   # ведомому цель и строй задаёт ведущий
			if drag_start.distance_to(p) >= DRAG_MIN:
				_place_formation_multi(list, drag_start, p, drag_flip)
			elif list.size() == 1:
				_cmd_move(list[0], drag_start)   # короткий клик: цель отряда (если блок не пересечётся с другим)
			elif list.size() > 1:
				_cmd_move_group(list, drag_start)
			queue_redraw()
	elif event is InputEventMouseMotion and (drag_active or box_active):
		var p := (make_input_local(event) as InputEventMouseMotion).position
		if drag_active:
			drag_cur = p
		else:
			box_cur = p
		queue_redraw()   # предпросмотр и рамка перерисовываются только во время перетаскивания
	elif event is InputEventMouseButton and event.pressed and event.shift_pressed and event.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		# Shift + колесо: поворот на месте (с Shift система может прислать горизонтальное колесо); без Shift колесо не занято
		_cmd_rotate(-1 if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if _run_over():
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R]:
				_to_hub()
			elif event.keycode == KEY_ESCAPE:
				_open_esc_menu()
			return   # экран конца забега: остальные клавиши не действуют
		match event.keycode:
			KEY_ESCAPE:
				if drag_active or box_active:
					drag_active = false   # Esc отменяет протяжку и рамку
					box_active = false
					queue_redraw()
				else:
					_open_esc_menu()
			KEY_F:
				if drag_active:
					drag_flip = not drag_flip   # во время протяжки: лицо строя наоборот
					queue_redraw()
				else:
					_cmd_about_face()
			KEY_H:
				_toggle_banner()
			KEY_T:
				for s in _sel_list():
					squad_user_width[s] = 0   # ширина строя снова авто
			KEY_R:
				if DEBUG_COLORS and event.ctrl_pressed:
					get_tree().reload_current_scene()   # отладочный перезапуск боя
			KEY_SPACE:
				if PAUSE_ENABLED and wave_state == WS_BATTLE:
					_set_paused(not paused)
				else:
					_start_wave()
			KEY_P:
				_set_paused(not paused)
			KEY_K:
				_next_split_mode()
			KEY_LEFT:
				_cmd_side_post(SIDE_LEFT)
			KEY_UP:
				_cmd_side_post(SIDE_TOP)
			KEY_RIGHT:
				_cmd_side_post(SIDE_RIGHT)
			KEY_DOWN:
				_cmd_side_post(-1)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				if event.shift_pressed:
					_toggle_sel(event.keycode - KEY_1)
				else:
					_select_only(event.keycode - KEY_1)
			KEY_A:
				if event.ctrl_pressed:
					_select_all()
			KEY_N:
				_cmd_new_squad()
			KEY_G:
				_cmd_split()
			KEY_M:
				_cmd_merge()
			KEY_Q:
				_set_order(ORDER_ATTACK)
			KEY_W:
				_set_order(ORDER_HOLD)
			KEY_E:
				_set_order(ORDER_RETREAT)
			KEY_Z, KEY_X, KEY_C, KEY_V:
				_buy(SHOP_KEYS.find(event.keycode))
			KEY_F1:
				color_mode = 0
			KEY_F2, KEY_F3, KEY_F4:
				if DEBUG_COLORS:
					color_mode = event.keycode - KEY_F1
			KEY_F5:
				sprites_on = not sprites_on   # спрайты / все юниты квадратами
