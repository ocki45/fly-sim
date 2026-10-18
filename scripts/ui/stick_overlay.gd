extends Control
class_name StickOverlay
# Визуализация стиков джойстика (как оверлей в Liftoff / Betaflight).
# Рисует два полупрозрачных круга с осями и движущимися точками:
#   левый круг  — ось 0 (Yaw) по X и ось 1 (Throttle) по Y;
#   правый круг — ось 2 (Roll) по X и ось 3 (Pitch) по Y.
# ВАЖНО: оси Throttle и Pitch инвертируются при отрисовке, потому что в Godot
# Y растёт ВНИЗ, а на аппаратуре «газ вверх» и «стик pitch вверх» — это -1.
# После поднятия точки вверх она должна рисоваться вверх — поэтому Y домножаем на -1.
#
# Как подключить: CanvasLayer -> Control (растянуть на весь экран, mouse_filter=Ignore)
# + этот скрипт. См. main.tscn (узел OSD/Sticks).

const JOY_ID := 0                    # Индекс джойстика (RadioMaster Pocket = js0)
const CIRCLE_R := 60.0               # Радиус круга, пикселей
const DOT_R := 8.0                   # Радиус точки стика, пикселей
const PADDING := 30.0                # Отступ снизу/по бокам
const FONT_SIZE := 14                # Размер подписей значений осей

# Номера осей RadioMaster Pocket в режиме Joystick (Mode 2):
const AXIS_YAW := JOY_AXIS_0         # Левый стик горизонталь
const AXIS_THROTTLE := JOY_AXIS_1    # Левый стик вертикаль (без пружины)
const AXIS_ROLL := JOY_AXIS_2        # Правый стик горизонталь
const AXIS_PITCH := JOY_AXIS_3       # Правый стик вертикаль

var _joy_connected := false

func _ready() -> void:
	# Оверлей не перехватывает клики/фокус
	mouse_filter = MOUSE_FILTER_IGNORE
	_joy_connected = Input.get_connected_joypads().size() > 0
	# Перепроверяем подключение джойстика при горячем подключении/отключении USB
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if device == JOY_ID:
		_joy_connected = connected
	queue_redraw()  # Перерисовать сразу (иначе точки «залипнут»)

func _process(_delta: float) -> void:
	# Перерисовываем каждый кадр — значения осей меняются непрерывно
	queue_redraw()

func _draw() -> void:
	var size_px := size  # Размер контрола = размер окна (anchor full rect)

	# Сырые значения осей с джойстика (-1..1). Если джойстика нет — рисуем нули.
	var v_yaw := 0.0
	var v_throttle := 0.0
	var v_roll := 0.0
	var v_pitch := 0.0
	if _joy_connected and Input.is_joy_known(JOY_ID):
		v_yaw = Input.get_joy_axis(JOY_ID, AXIS_YAW)
		v_throttle = Input.get_joy_axis(JOY_ID, AXIS_THROTTLE)
		v_roll = Input.get_joy_axis(JOY_ID, AXIS_ROLL)
		v_pitch = Input.get_joy_axis(JOY_ID, AXIS_PITCH)

	# --- Левый круг: Yaw (X) + Throttle (Y, ИНВЕРТИРОВАН: газ вверх = точка вверх)
	var left_center := Vector2(PADDING + CIRCLE_R, size_px.y - PADDING - CIRCLE_R)
	_draw_stick_circle(left_center, v_yaw, -v_throttle, "L: YAW / THR")

	# --- Правый круг: Roll (X) + Pitch (Y, ИНВЕРТИРОВАН: стик вверх = точка вверх)
	var right_center := Vector2(size_px.x - PADDING - CIRCLE_R, size_px.y - PADDING - CIRCLE_R)
	_draw_stick_circle(right_center, v_roll, -v_pitch, "R: ROLL / PITCH")

# Рисует один круг стика: фон, крест осей, рамку мёртвой зоны, точку и подписи.
func _draw_stick_circle(center: Vector2, axis_x: float, axis_y_up: float, title: String) -> void:
	# Полупрозрачный фон круга
	draw_circle(center, CIRCLE_R, Color(0.0, 0.0, 0.0, 0.35))
	# Обводка
	draw_arc(center, CIRCLE_R, 0.0, TAU, 48, Color(1, 1, 1, 0.7), 2.0)
	# Крест осей
	draw_line(center - Vector2(CIRCLE_R, 0), center + Vector2(CIRCLE_R, 0), Color(1, 1, 1, 0.35), 1.0)
	draw_line(center - Vector2(0, CIRCLE_R), center + Vector2(0, CIRCLE_R), Color(1, 1, 1, 0.35), 1.0)
	# Рамка мёртвой зоны (0.05) — чтобы видеть, где стик «не считается»
	var dz := CIRCLE_R * 0.05
	draw_rect(Rect2(center - Vector2(dz, dz), Vector2(dz * 2, dz * 2)), Color(1, 1, 0, 0.5), false, 1.0)

	# Точка стика: axis_y_up уже инвертирован вызывающим кодом (вверх = минус по экрану)
	var dot := center + Vector2(clampf(axis_x, -1.0, 1.0), -clampf(axis_y_up, -1.0, 1.0)) * CIRCLE_R
	draw_circle(dot, DOT_R, Color(0.2, 1.0, 0.3, 0.9))
	draw_circle(dot, DOT_R, Color(1, 1, 1, 0.9), false, 1.5)

	# Подписи: название над кругом, сырые значения осей под кругом
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(center.x - CIRCLE_R, center.y - CIRCLE_R - 8.0),
		title, HORIZONTAL_ALIGNMENT_CENTER, CIRCLE_R * 2.0, FONT_SIZE, Color(1, 1, 1, 0.8))
	# Показываем СЫРЫЕ значения осей (до инверсии отрисовки), чтобы видно было
	# реальное направление стика на аппаратуре (газ вверх = Y: -1.00).
	var label := "X: %+.2f  Y: %+.2f" % [axis_x, -axis_y_up]
	draw_string(font, Vector2(center.x - CIRCLE_R, center.y + CIRCLE_R + 18.0),
		label, HORIZONTAL_ALIGNMENT_CENTER, CIRCLE_R * 2.0, FONT_SIZE, Color(0.2, 1.0, 0.3))
