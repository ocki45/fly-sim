extends Node
# InputHandler — autoload-синглтон (Проект > Автозагрузка > global).
# Читает RadioMaster Pocket через Input.get_joy_axis(), при отсутствии
# джойстика делает fallback на клавиатуру.

# --- Маппинг осей RadioMaster Pocket (режим Joystick, /dev/input/js0) ---
# ВАЖНО: на Linux маппинг осей зависит от режима передатчика (Mode 1/2/3/4),
# прошивки и udev-правил — у разных владельцев Pocket оси НУМЕРУЮТСЯ ПО-РАЗНОМУ.
# Это @export переменные: меняются прямо в инспекторе Godot БЕЗ правки кода.
#
# Маппинг по вашему запросу: Yaw и Throttle ПОМЕНЯНЫ МЕСТАМИ относительно ТЗ —
# на вашем экземпляре Pocket левый стик вертикаль (ось 0) = газ, горизонталь (ось 1) = yaw.
# ВАЖНО: значения ниже — ДЕФАУЛТЫ скрипта. Если в main.tscn на узле InputHandler
# в инспекторе сохранены другие числа, они перекроют дефолт — проверьте свойства узла.
@export var axis_throttle: int = 0   # Ось 0: газ (левый стик вертикаль, без пружины!)
@export var axis_yaw: int = 1        # Ось 1: yaw (левый стик горизонталь)
@export var axis_roll: int = 2       # Ось 2: roll (правый стик горизонталь)
@export var axis_pitch: int = 3      # Ось 3: pitch (правый стик вертикаль)

# Инверсии ОСЕЙ «как есть» с аппаратуры (до обработки). Ставим галочку в инспекторе,
# если конкретная ось на вашем экземпляре Pocket читается наоборот
# (ориентир — диагностика: газ до упора ВВЕРХ должен давать ~ +1 после инверсии,
# точка на левом круге оверлея при этом идёт ВВЕРХ).
# PITCH ИНВЕРТИРОВАН (invert_pitch = true): стик вверх = -1 в Godot -> разворачиваем.
@export var invert_throttle: bool = true   # газ вверх на стике = -1 в Godot -> инвертируем
@export var invert_yaw: bool = false       # не инвертируем
@export var invert_roll: bool = false      # не инвертируем
@export var invert_pitch: bool = true      # стик вверх = -1 в Godot -> инвертируем

const DEADZONE := 0.05         # Мёртвая зона стиков
const EXPO := 0.3              # Expo-кривая для roll/pitch/yaw (ТЗ: output = in*(expo*in^2 + 1-expo))
const DEBUG_PRINT := true      # Флаг отладочного вывода в консоль (можно отключить)

# --- АВТОКАЛИБРОВКА маппинга осей по данным ядра Linux (/dev/input/js*) ---
# Проблема: у RadioMaster Pocket на Linux нумерация осей НЕ совпадает с ожидаемой
# (поэтому каналы «перепутаны жесть»: газ крутил pitch, yaw показывал roll и т.д.).
# Решение: читаем sysfs — там kernel сообщает тип/код каждой оси js-устройства:
#   /sys/bus/input/devices/js0/axes -> "0x01 0x01 0x03 0x04 ..."
#   код 0x01 = ABS_X, 0x02 = ABS_Y, 0x03 = ABS_Z, 0x04 = ABS_RZ ...
# Стики Pocket дают ДВЕ последовательные оси на стик; левый стик — первая пара,
# правый — вторая. Вертикаль стика (ABS_Y/ABS_RY) инвертируется отдельно.
# Если файл недоступен или осей мало — молча остаёмся на значениях из инспектора.
# --- АВТОКАЛИБРОВКА ОТКЛЮЧЕНА (auto_calibrate_axes = false) ---
# Почему: автокалибровка по кодам ABS_X/ABS_Y/ABS_Z/ABS_RZ НЕРАБОТОСПОСОБНА
# для RadioMaster Pocket на Linux. Драйвер js0 выдаёт НЕСОРТИРОВАННУЮ карту
# осей (например X на позиции 2, Y на позиции 3), и поиск первого вхождения
# кода возвращал индексы, которые у вас дали «перепутаны жесть»: газ крутил
# pitch, yaw показывал roll и т.д. Теперь единственный источник истины —
# @export axis_* ниже + живая диагностика осей на экране (stick_overlay.gd):
# двигаете стик — видите, какой номер реагирует, ставите его в инспекторе.
@export var auto_calibrate_axes: bool = false

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
	# Если джойстик уже был воткнут до старта — автокалибровка не запускалась
	# (_joy_connected вызывается только на сигнал подключения). Запускаем сами.
	if _joy_id != -1:
		call_deferred("_auto_calibrate")

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_joy_connected(device)
	else:
		_joy_disconnected(device)

func _joy_connected(device: int) -> void:
	_joy_id = device
	print("InputHandler: джойстик подключён: #%d %s" % [device, Input.get_joy_name(device)])
	# ВАЖНО: экспортные значения из main.tscn применяются Godot ПОСЛЕ _ready(),
	# поэтому автокалибровку делаем не сразу, а отложенно (в конце первого кадра) —
	# иначе она либо затрётся инспектором, либо наоборот перезапишет ручную настройку.
	call_deferred("_auto_calibrate")

# --- АВТОКАЛИБРОВКА: читаем /sys/bus/input/devices/jsN/device/axes ---
# Формат файла: список шестнадцатеричных кодов ABS-событий по порядку осей js.
# Пример Pocket (js0): "0x01 0x02 0x03 0x04 0x09 0x0a ..."
#   0x01 ABS_X  -> левый стик горизонталь = YAW
#   0x02 ABS_Y  -> левый стик вертикаль    = THROTTLE (инверт.)
#   0x03 ABS_Z  -> правый стик горизонталь = ROLL
#   0x04 ABS_RZ -> правый стик вертикаль   = PITCH (инверт.)
# Номера ОСЕЙ в списке = фактические индексы для Input.get_joy_axis().
# Если sysfs недоступен или коды не распознаны — молча остаётся маппинг из инспектора.
func _auto_calibrate() -> void:
	if not auto_calibrate_axes or _joy_id == -1:
		return
	var sys_path := "/sys/class/input/js%d/device/axes" % _joy_id
	if not FileAccess.file_exists(sys_path):
		sys_path = "/sys/bus/input/devices/js%d/axes" % _joy_id
	if not FileAccess.file_exists(sys_path):
		print("InputHandler: autocalib: sysfs-файл не найден, использую экспорт из инспектора")
		return
	var f := FileAccess.open(sys_path, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text().strip_edges()
	f.close()
	var parts := raw.split(" ", false)
	var codes: Array[int] = []
	for p in parts:
		codes.append(int(p))  # GDScript int() корректно парсит "0x03"
	if codes.size() < 4:
		print("InputHandler: autocalib: осей меньше 4 (%d), пропускаю" % codes.size())
		return
	# Ищем позиции канонических ABS-кодов стиков в порядке осей js.
	var idx_x := codes.find(0x01)   # ABS_X
	var idx_y := codes.find(0x02)   # ABS_Y
	var idx_z := codes.find(0x03)   # ABS_Z
	if idx_z == -1:
		idx_z = codes.find(0x09)    # запасной вариант: ABS_HAT0X
	var idx_rz := codes.find(0x04)  # ABS_RZ
	if idx_rz == -1:
		idx_rz = codes.find(0x0A)   # запасной вариант: ABS_HAT0Y
	if idx_x != -1 and idx_y != -1 and idx_z != -1 and idx_rz != -1:
		axis_yaw = idx_x
		axis_throttle = idx_y
		axis_roll = idx_z
		axis_pitch = idx_rz
		invert_throttle = true
		invert_pitch = true
		invert_yaw = false
		invert_roll = false
		print("InputHandler: AUTOCALIB применён: yaw=%d throttle=%d roll=%d pitch=%d" % [axis_yaw, axis_throttle, axis_roll, axis_pitch])
	else:
		print("InputHandler: autocalib: ABS-коды стиков не распознаны (%s), использую экспорт" % raw)

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
