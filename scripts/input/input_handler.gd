extends Node
# InputHandler — autoload-синглтон (Проект > Автозагрузка > global).
# Читает RadioMaster Pocket через Input.get_joy_axis(), при отсутствии
# джойстика делает fallback на клавиатуру.

# --- Маппинг осей RadioMaster Pocket (режим Joystick, /dev/input/js0) ---
const JOY_AXIS_YAW := 0        # Левый стик горизонталь
const JOY_AXIS_THROTTLE := 1   # Левый стик вертикаль (без пружины!)
const JOY_AXIS_ROLL := 2       # Правый стик горизонталь
const JOY_AXIS_PITCH := 3      # Правый стик вертикаль

const DEADZONE := 0.05         # Мёртвая зона стиков
const EXPO := 0.3              # Expo-кривая для roll/pitch/yaw (ТЗ: output = in*(expo*in^2 + 1-expo))
const DEBUG_PRINT := true      # Флаг отладочного вывода в консоль (можно отключить)

# Текущие обработанные значения:
var throttle: float = 0.0      # 0..1 (газ)
var roll: float = 0.0          # -1..1
var pitch: float = 0.0         # -1..1
var yaw: float = 0.0           # -1..1

var _joy_id: int = -1          # ID подключённого джойстика
var _debug_timer: float = 0.0  # Ограничитель частоты печати

func _ready() -> void:
	# Ищем уже подключённый джойстик
	for id in Input.get_connected_joypads():
		_joy_id = id
		print("InputHandler: найден джойстик #%d: %s" % [id, Input.get_joy_name(id)])

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

	if DEBUG_PRINT:
		_debug_timer += delta
		if _debug_timer >= 0.25:
			_debug_timer = 0.0
			print("Throttle: %.2f, Roll: %.2f, Pitch: %.2f, Yaw: %.2f" % [throttle, roll, pitch, yaw])

# Чтение со стиков аппаратуры
func _read_joystick() -> void:
	# `as JoyAxis` — приведение int-констант к enum-типу JoyAxis, который
	# требует Input.get_joy_axis() в Godot 4 (иначе ошибка типизации).
	var raw_throttle := Input.get_joy_axis(_joy_id, JOY_AXIS_THROTTLE as JoyAxis)
	var raw_roll := Input.get_joy_axis(_joy_id, JOY_AXIS_ROLL as JoyAxis)
	var raw_pitch := Input.get_joy_axis(_joy_id, JOY_AXIS_PITCH as JoyAxis)
	var raw_yaw := Input.get_joy_axis(_joy_id, JOY_AXIS_YAW as JoyAxis)

	# В Godot Y вниз = +1, а на аппаратуре газ вверх = -1 => инвертируем
	raw_throttle = -raw_throttle
	# Pitch тоже инвертирован по той же причине (стек вверх = nose up)
	raw_pitch = -raw_pitch

	# Мёртвые зоны
	raw_throttle = _apply_deadzone(raw_throttle)
	raw_roll = _apply_deadzone(raw_roll)
	raw_pitch = _apply_deadzone(raw_pitch)
	raw_yaw = _apply_deadzone(raw_yaw)

	# Газ: из -1..1 в 0..1 (нижняя половина диапазона = 0)
	throttle = clampf((raw_throttle + 1.0) * 0.5, 0.0, 1.0)
	# Expo-кривая для roll/pitch/yaw: output = input * (expo*input^2 + (1-expo))
	# На газ expo НЕ вешаем (как в Betaflight).
	roll = apply_expo(raw_roll, EXPO)
	pitch = apply_expo(raw_pitch, EXPO)
	yaw = apply_expo(raw_yaw, EXPO)

# Клавиатурный fallback
func _read_keyboard() -> void:
	# W/S — газ вверх/вниз (накопительное, как реальный стик без пружины)
	if Input.is_key_pressed(KEY_W):
		throttle = clampf(throttle + 0.8 * get_process_delta_time(), 0.0, 1.0)
	elif Input.is_key_pressed(KEY_S):
		throttle = clampf(throttle - 0.8 * get_process_delta_time(), 0.0, 1.0)

	# A/D — yaw
	if Input.is_key_pressed(KEY_A):
		yaw = 1.0
	elif Input.is_key_pressed(KEY_D):
		yaw = -1.0
	else:
		yaw = 0.0

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

# Мёртвая зона с рескейлом, чтобы не было скачка на границе
func _apply_deadzone(v: float) -> float:
	if absf(v) < DEADZONE:
		return 0.0
	return signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)

# Expo-кривая: output = input * (expo * input^2 + (1 - expo))
# Вынесена сюда, чтобы её могли использовать и физика, и OSD.
static func apply_expo(input: float, expo: float) -> float:
	return input * (expo * input * input + (1.0 - expo))
