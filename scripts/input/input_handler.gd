extends Node
# InputHandler — autoload-синглтон (Проект > Автозагрузка > global).
# Читает RadioMaster Pocket через Input.get_joy_axis(), при отсутствии
# джойстика делает fallback на клавиатуру.

# --- Маппинг осей RadioMaster Pocket (режим Joystick, /dev/input/js0) ---
# ЕДИНСТВЕННО ВЕРНАЯ СХЕМА (стандарт Mode 2, зафиксирована по ТЗ пользователя):
#   ЛЕВЫЙ стик вертикаль (Ось 1 / JOY_AXIS_LEFT_Y)  = THROTTLE (газ, 0..1)
#   ЛЕВЫЙ стик горизонталь (Ось 0 / JOY_AXIS_LEFT_X)= YAW
#   ПРАВЫЙ стик горизонталь (Ось 2 / JOY_AXIS_RIGHT_X) = ROLL
#   ПРАВЫЙ стик вертикаль (Ось 3 / JOY_AXIS_RIGHT_Y)   = PITCH
#
# ВАЖНО ПРО ИНТЕРФЕЙС GODOT 4: констант вида JOY_AXIS_LEFT_X в Godot 4 НЕ
# СУЩЕСТВУЕТ (это был синтаксис Godot 3 / SDL). В Godot 4 enum JoyAxis содержит
# только AXIS_0..AXIS_5, поэтому соответствие «LEFT_X = Ось 0» закреплено здесь
# именами-алиасами ниже — дальше по коду читаем оси ТОЛЬКО по этим именам.
const JOY_AXIS_LEFT_X: int = 0    # alias: Ось 0 = левый стик горизонталь
const JOY_AXIS_LEFT_Y: int = 1    # alias: Ось 1 = левый стик вертикаль
const JOY_AXIS_RIGHT_X: int = 2   # alias: Ось 2 = правый стик горизонталь
const JOY_AXIS_RIGHT_Y: int = 3   # alias: Ось 3 = правый стик вертикаль

# Номера осей — @export: если на вашем экземпляре Pocket нумерация сбилась,
# поправьте в инспекторе узла InputHandler (НЕ в коде). Дефолты = стандарт Mode 2.
# ВНИМАНИЕ: значения НЕ сохраняются в main.tscn — единственный источник истины
# этот код. Если раньше в инспекторе стояли другие числа и жались «Сохранить сцену»,
# они могли перекрыть дефолты; сейчас таких property-строк в сцене нет (проверено),
# поэтому маппинг гарантированно = схема ниже.
@export var axis_yaw: int = JOY_AXIS_LEFT_X     # Ось 0: yaw
@export var axis_throttle: int = JOY_AXIS_LEFT_Y  # Ось 1: газ (без пружины!)
@export var axis_roll: int = JOY_AXIS_RIGHT_X   # Ось 2: roll
@export var axis_pitch: int = JOY_AXIS_RIGHT_Y  # Ось 3: pitch

# Инверсии осей. В Godot «вниз по стику» = +1. По ТЗ:
#   - газ ВВЕРХ на аппаратуре приходит как -1 => инвертируем (было 0 внизу);
#   - pitch: стик ВВЕРХ = наклон дрона вперёд => инвертируем;
#   - yaw/roll читаются напрямую (влево = -1, вправо = +1) => без инверсии.
@export var invert_throttle: bool = true
@export var invert_yaw: bool = false
@export var invert_roll: bool = false
@export var invert_pitch: bool = true

const DEADZONE := 0.05         # Мёртвая зона стиков
const EXPO := 0.3              # Expo-кривая для roll/pitch/yaw (ТЗ: output = in*(expo*in^2 + 1-expo))
const DEBUG_PRINT := true      # Флаг отладочного вывода в консоль (можно отключить)

# Текущие обработанные значения:
var throttle: float = 0.0      # 0..1 (газ)
var roll: float = 0.0          # -1..1
var pitch: float = 0.0         # -1..1
var yaw: float = 0.0           # -1..1

# СЫРЫЕ значения (после инверсии и deadzone, но ДО expo) — для оверлея стиков,
# чтобы точка двигалась линейно за стиком, как в Betaflight Configurator.
var raw_throttle: float = -1.0 # -1..1 (до маппинга в 0..1)
var raw_roll: float = 0.0
var raw_pitch: float = 0.0
var raw_yaw: float = 0.0

var _joy_id: int = -1          # ID подключённого джойстика
var _debug_timer: float = 0.0  # Ограничитель частоты печати

# --- Живая диагностика осей перенесена в stick_overlay.gd (оверлей стиков):
# там она рисуется корректно на Control-узле. InputHandler больше НИЧЕГО не
# рисует сам — у Node-узла нет size, и _draw вызывался бы с ошибкой, ломая
# весь ввод (из-за этого оверлей «ничего не показывал»). Оставлен только флаг
# show_axis_debug для совместимости со сценой. ---
@export var show_axis_debug: bool = true

func _ready() -> void:
	# Применяем сохранённую калибровку из GameManager (user://calibration.cfg),
	# если синглтон подключён как autoload. Это дефолты Mode 2, пока пользователь
	# не перекалибрует пульт на экране калибровки.
	if "GameManager" in Engine or has_node("/root/GameManager"):
		var gm: Node = get_node_or_null("/root/GameManager")
		if gm != null and gm.current_mapping.has("throttle"):
			axis_throttle = int(gm.current_mapping["throttle"]["axis"])
			invert_throttle = bool(gm.current_mapping["throttle"]["inverted"])
			axis_yaw = int(gm.current_mapping["yaw"]["axis"])
			invert_yaw = bool(gm.current_mapping["yaw"]["inverted"])
			axis_pitch = int(gm.current_mapping["pitch"]["axis"])
			invert_pitch = bool(gm.current_mapping["pitch"]["inverted"])
			axis_roll = int(gm.current_mapping["roll"]["axis"])
			invert_roll = bool(gm.current_mapping["roll"]["inverted"])
			print("InputHandler: применена калибровка из GameManager")
	# Ищем уже подключённый джойстик
	for id in Input.get_connected_joypads():
		_joy_id = id
		print("InputHandler: найден джойстик #%d: %s" % [id, Input.get_joy_name(id)])
	# Ловим горячее подключение/отключение USB (сигнал есть в Godot 4)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_joy_connected(device)
	else:
		_joy_disconnected(device)

func _joy_connected(device: int) -> void:
	_joy_id = device
	print("InputHandler: джойстик подключён: #%d %s" % [device, Input.get_joy_name(device)])

func _joy_disconnected(device: int) -> void:
	if device == _joy_id:
		_joy_id = -1
		print("InputHandler: джойстик отключён")

func _process(delta: float) -> void:
	# Сигналы подключения ловим через polling (сигналы joy_connection_changed
	# требуют connect() — делаем проще и надёжнее):
	if _joy_id == -1:
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			_joy_connected(pads[0])

	if _joy_id != -1:
		_read_joystick()
	else:
		_read_keyboard()

	# --- Отладочный вывод (флаг DEBUG_PRINT) ---
	# Печатает обработанные каналы + ВСЕ сырые оси пульта, чтобы по консоли
	# было видно, перепутан ли маппинг именно на этом экземпляре Pocket.
	# Двигайте стики — реагирующая ось видна в строке AXIS DUMP.
	if DEBUG_PRINT:
		_debug_timer += delta
		if _debug_timer >= 0.25:
			_debug_timer = 0.0
			print("Throttle: %.2f, Roll: %.2f, Pitch: %.2f, Yaw: %.2f" % [throttle, roll, pitch, yaw])
			if show_axis_debug and _joy_id != -1:
				_dump_axes()

# Дамп всех сырых осей джойстика в консоль + текущий выбор маппинга.
# Вызывается из _process() раз в 0.25 с (см. DEBUG_PRINT). Количество осей
# берём из Input.get_joy_info() (в Godot 4.3 НЕТ метода get_joy_axis_count()).
func _dump_axes() -> void:
	var axes_count: int = 8  # запасное значение: RadioMaster Pocket отдаёт ~6-8 осей
	var info: Dictionary = Input.get_joy_info(_joy_id)
	if info.has("axis"):
		axes_count = int(info["axis"])
	var s := "AXIS DUMP:"
	for ax in axes_count:
		var v: float = Input.get_joy_axis(_joy_id, ax as JoyAxis)
		if absf(v) < 0.02:
			v = 0.0  # гасим шум покоя, чтобы глаз ловил только реальные движения
		s += " axis%d:%+.2f" % [ax, v]
	print(s)
	print("MAP: yaw=%d throttle=%d roll=%d pitch=%d | inv: thr=%s pitch=%s yaw=%s roll=%s" % [
		axis_yaw, axis_throttle, axis_roll, axis_pitch,
		str(invert_throttle), str(invert_pitch), str(invert_yaw), str(invert_roll)])

# Чтение со стиков аппаратуры (схема строго по Mode 2, см. константы вверху)
func _read_joystick() -> void:
	# `as JoyAxis` — приведение int к enum-типу JoyAxis, который требует
	# Input.get_joy_axis() в Godot 4. Номера осей — из @export axis_*
	# (дефолты = JOY_AXIS_LEFT_X/Y, RIGHT_X/Y).
	var rt := Input.get_joy_axis(_joy_id, axis_throttle as JoyAxis)  # Ось 1: газ
	var rr := Input.get_joy_axis(_joy_id, axis_roll as JoyAxis)      # Ось 2: roll
	var rp := Input.get_joy_axis(_joy_id, axis_pitch as JoyAxis)     # Ось 3: pitch
	var ry := Input.get_joy_axis(_joy_id, axis_yaw as JoyAxis)       # Ось 0: yaw

	# Инверсии по @export invert_* (в Godot Y вниз = +1; на аппаратуре
	# «газ вверх» и «стик pitch вверх» читаются как -1 => инвертируем).
	if invert_throttle:
		rt = -rt
	if invert_pitch:
		rp = -rp
	if invert_yaw:
		ry = -ry
	if invert_roll:
		rr = -rr

	# Мёртвые зоны
	rt = _apply_deadzone(rt)
	rr = _apply_deadzone(rr)
	rp = _apply_deadzone(rp)
	ry = _apply_deadzone(ry)

	# Сохраняем СЫРЫЕ значения (до expo) — их рисует оверлей стиков
	raw_throttle = rt
	raw_roll = rr
	raw_pitch = rp
	raw_yaw = ry

	# Газ: формула из ТЗ — throttle = (ось1 + 1.0) / 2.0, диапазон 0..1
	# (стик до упора ВНИЗ = 0.0, до упора ВВЕРХ = 1.0)
	throttle = clampf((rt + 1.0) / 2.0, 0.0, 1.0)
	# Expo-кривая для roll/pitch/yaw: output = input * (expo*input^2 + (1-expo))
	# На газ expo НЕ вешаем (как в Betaflight).
	roll = apply_expo(rr, EXPO)
	pitch = apply_expo(rp, EXPO)
	yaw = apply_expo(ry, EXPO)

# Клавиатурный fallback
func _read_keyboard() -> void:
	# W/S — газ вверх/вниз (накопительное, как реальный стик без пружины)
	if Input.is_key_pressed(KEY_W):
		throttle = clampf(throttle + 0.8 * get_process_delta_time(), 0.0, 1.0)
	elif Input.is_key_pressed(KEY_S):
		throttle = clampf(throttle - 0.8 * get_process_delta_time(), 0.0, 1.0)
	raw_throttle = throttle * 2.0 - 1.0  # синхронизируем «сырой» газ для оверлея

	# A/D — yaw
	if Input.is_key_pressed(KEY_A):
		yaw = 1.0
	elif Input.is_key_pressed(KEY_D):
		yaw = -1.0
	else:
		yaw = 0.0
	raw_yaw = yaw  # на клавиатуре expo не применяется — raw == обработанное значение

	# Стрелки — roll/pitch (стрелка вверх = nose up)
	if Input.is_key_pressed(KEY_LEFT):
		roll = 1.0
	elif Input.is_key_pressed(KEY_RIGHT):
		roll = -1.0
	else:
		roll = 0.0

	if Input.is_key_pressed(KEY_UP):
		pitch = 1.0
	elif Input.is_key_pressed(KEY_DOWN):
		pitch = -1.0
	else:
		pitch = 0.0
	raw_roll = roll
	raw_pitch = pitch

# Мёртвая зона с рескейлом, чтобы не было скачка на границе
func _apply_deadzone(v: float) -> float:
	if absf(v) < DEADZONE:
		return 0.0
	return signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)

# Expo-кривая: output = input * (expo * input^2 + (1 - expo))
# Вынесена сюда, чтобы её могли использовать и физика, и OSD.
static func apply_expo(input: float, expo: float) -> float:
	return input * (expo * input * input + (1.0 - expo))
