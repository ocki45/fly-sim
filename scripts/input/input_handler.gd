extends Node
# InputHandler — autoload-синглтон (Проект > Автозагрузка > global).
# Читает RadioMaster Pocket через Input.get_joy_axis(), при отсутствии
# джойстика делает fallback на клавиатуру.

# --- Маппинг осей RadioMaster Pocket (режим Joystick, /dev/input/js0) ---
# ВАЖНО: на Linux маппинг зависит от режима передатчика (Mode 1/2), прошивки и
# udev-правил — у разных экземпляров Pocket оси НУМЕРУЮТСЯ ПО-РАЗНОМУ.
# Это @export переменные: меняются прямо в инспекторе Godot БЕЗ правки кода.
#
# ЭТАЛОННЫЙ МАППИНГ (согласно ТЗ, Mode 2):
#   Ось 0 = Yaw (левый стик горизонталь)
#   Ось 1 = Throttle (левый стик вертикаль, без пружины; Godot даёт -1 при газе
#           вверх => invert_throttle = true)
#   Ось 2 = Roll (правый стик горизонталь)
#   Ось 3 = Pitch (правый стик вертикаль; инвертирован аналогично)
# Если у вас поведение «перепутано» — НЕ гадайте: посмотрите панель «СЫРЫЕ ОСИ»
# на экране (stick_overlay.gd) или строку "AXIS DUMP" в консоли, и поставьте
# реагирующие номера сюда (или в инспектор узла InputHandler).
@export var axis_yaw: int = 0        # Ось 0: yaw (левый стик горизонталь)
@export var axis_throttle: int = 1   # Ось 1: газ (левый стик вертикаль, без пружины!)
@export var axis_roll: int = 2       # Ось 2: roll (правый стик горизонталь)
@export var axis_pitch: int = 3      # Ось 3: pitch (правый стик вертикаль)

# Инверсии ОСЕЙ «как есть» с аппаратуры (до обработки). Ставим галочку в инспекторе,
# если конкретная ось на вашем экземпляре Pocket читается наоборот
# (ориентир — диагностика: газ до упора ВВЕРХ должен давать ~ +1 после инверсии,
# точка на левом круге оверлея при этом идёт ВВЕРХ).
@export var invert_throttle: bool = true   # газ вверх на стике = -1 в Godot -> инвертируем
@export var invert_yaw: bool = false       # не инвертируем
@export var invert_roll: bool = false      # не инвертируем
@export var invert_pitch: bool = true      # стик вверх = -1 в Godot -> инвертируем

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

# Чтение со стиков аппаратуры
func _read_joystick() -> void:
	# `as JoyAxis` — приведение int-значений к enum-типу JoyAxis, который
	# требует Input.get_joy_axis() в Godot 4 (иначе ошибка типизации).
	# Номера осей берутся из @export axis_* — настраиваются в инспекторе.
	var rt := Input.get_joy_axis(_joy_id, axis_throttle as JoyAxis)
	var rr := Input.get_joy_axis(_joy_id, axis_roll as JoyAxis)
	var rp := Input.get_joy_axis(_joy_id, axis_pitch as JoyAxis)
	var ry := Input.get_joy_axis(_joy_id, axis_yaw as JoyAxis)

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

	# Газ: из -1..1 в 0..1 (нижняя половина диапазона = 0)
	throttle = clampf((rt + 1.0) * 0.5, 0.0, 1.0)
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
