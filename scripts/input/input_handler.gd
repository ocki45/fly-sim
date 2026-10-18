extends Node
# InputHandler — autoload-синглтон (Проект > Автозагрузка > global).
# Читает RadioMaster Pocket через Input.get_joy_axis(), при отсутствии
# джойстика делает fallback на клавиатуру.

# --- Маппинг осей RadioMaster Pocket (режим Joystick, /dev/input/js0) ---
# ВАЖНО: на Linux маппинг осей зависит от режима передатчика (Mode 1/2/3/4),
# прошивки и udev-правил — у разных владельцев Pocket оси НУМЕРУЮТСЯ ПО-РАЗНОМУ.
# Теперь это @export переменные: меняются прямо в инспекторе Godot БЕЗ правки кода.
# Как настроить за 1 минуту: запустите сцену main.tscn (F8) — вверху экрана появится
# ДИАГНОСТИЧЕСКАЯ ПАНЕЛЬ со ВСЕМИ осями пульта. Подвигайте стики — вы увидите, какой
# номер оси реагирует на yaw/throttle/roll/pitch, и впишите его в инспекторе.
@export var axis_yaw: int = 0        # Левый стик горизонталь (Mode 2)
@export var axis_throttle: int = 1   # Левый стик вертикаль (без пружины!)
@export var axis_roll: int = 2       # Правый стик горизонталь
@export var axis_pitch: int = 3      # Правый стик вертикаль

# Инверсии ОСЕЙ «как есть» с аппаратуры (до обработки). Ставим галочку в инспекторе,
# если конкретная ось на вашем экземпляре Pocket читается наоборот
# (ориентир — диагностика: газ до упора ВВЕРХ должен давать ~ +1 после инверсии).
@export var invert_yaw: bool = false
@export var invert_throttle: bool = true   # газ вверх на стике = -1 в Godot -> инвертируем
@export var invert_roll: bool = false
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

# --- Живая диагностика осей. Рисуется в _draw() самого InputHandler: Godot
# вызывает _draw у ЛЮБОГО узла (не только Control), а рисование идёт на
# 2D-экран в координатах пикселей. Это гарантирует, что панель со ВСЕМИ осями
# появится даже если весь остальной UI сломан — именно это нужно для
# поиска перепутанного маппинга. Отключается флагом show_axis_debug. ---
@export var show_axis_debug: bool = true
const DBG_FONT_SIZE := 15
const DBG_LINE_H := 19

func _ready() -> void:
	# Ищем уже подключённый джойстик
	for id in Input.get_connected_joypads():
		_joy_id = id
		print("InputHandler: найден джойстик #%d: %s" % [id, Input.get_joy_name(id)])
	# Ловим горячее подключение/отключение USB (сигнал есть в Godot 4)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _draw() -> void:
	if not show_axis_debug:
		return
	var font := ThemeDB.fallback_font
	var lines: Array[String] = []
	if _joy_id == -1:
		lines.append("JOY NOT FOUND — работает клавиатура (W/S газ, A/D yaw, стрелки)")
	else:
		var axes_count: int = Input.get_joy_axis_count(_joy_id)
		lines.append("СЫРЫЕ ОСИ #%d (%s): подвигайте стиками!" % [_joy_id, Input.get_joy_name(_joy_id)])
		for ax in axes_count:
			var v: float = Input.get_joy_axis(_joy_id, ax as JoyAxis)
			if absf(v) < 0.02:
				v = 0.0  # гасим шум покоя, чтобы глаз ловил только реальные движения
			var tag := ""
			if ax == axis_yaw:
				tag = " <- YAW"
			elif ax == axis_throttle:
				tag = " <- THROTTLE"
			elif ax == axis_roll:
				tag = " <- ROLL"
			elif ax == axis_pitch:
				tag = " <- PITCH"
			lines.append("ось %d: %+0.2f%s" % [ax, v, tag])

	var panel_h := float(lines.size()) * DBG_LINE_H + 12.0
	draw_rect(Rect2(Vector2(16, 70), Vector2(560, panel_h)), Color(0, 0, 0, 0.65))
	var y := 70.0 + DBG_FONT_SIZE + 6.0
	for i in lines.size():
		var col := Color(0.8, 0.9, 1.0) if i > 0 else Color(1.0, 0.9, 0.3)
		if lines[i].contains("<-"):
			col = Color(0.2, 1.0, 0.3)
		draw_string(font, Vector2(28.0, y), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, DBG_FONT_SIZE, col)
		y += DBG_LINE_H

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

	if DEBUG_PRINT:
		_debug_timer += delta
		if _debug_timer >= 0.25:
			_debug_timer = 0.0
			print("Throttle: %.2f, Roll: %.2f, Pitch: %.2f, Yaw: %.2f" % [throttle, roll, pitch, yaw])

	if show_axis_debug:
		queue_redraw()  # обновляем диагностическую панель осей каждый кадр

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
