extends Control
# ============================================================
# Визуализация стиков (как оверлей в Liftoff / Betaflight Configurator).
# Два полупрозрачных круга внизу экрана:
#   ЛЕВЫЙ  — Yaw (горизонталь) и Throttle (вертикаль, без пружины);
#   ПРАВЫЙ — Roll (горизонталь) и Pitch (вертикаль).
#
# ИСТОЧНИК ДАННЫХ — синглтон InputHandler (autoload), а НЕ прямые вызовы
# Input.get_joy_axis(). Это гарантирует, что оверлей показывает РОВНО ТО,
# что получает физика дрона (те же оси, та же инверсия газа/pitch, те же
# мёртвые зоны). Если оверлей и поведение дрона расходятся — проблема в
# маппинге осей, и видно это сразу здесь.
#
# Если джойстик НЕ подключён — показывается клавиатурный fallback
# (W/S — газ, A/D — yaw, стрелки — roll/pitch), точки тоже двигаются.
#
# ВАЖНО про инверсию: InputHandler.throttle хранится как 0..1 (0 = стик
# вниз). Для отрисовки пересчитываем обратно в -1..1: t_raw = thr*2-1,
# и инвертируем знак по экранному Y (в Godot Y растёт ВНИЗ, а «газ вверх»
# должен рисоваться точкой ВВЕРХ). То же для pitch.
#
# Как подключить: CanvasLayer -> Control (anchors preset Full Rect,
# mouse_filter=Ignore) + этот скрипт. Уже настроено в main.tscn (узел OSD/Sticks).

const CIRCLE_R := 60.0        # Радиус круга, пикселей
const DOT_R := 8.0            # Радиус точки стика, пикселей
const PADDING := 30.0         # Отступ снизу/по бокам
const FONT_SIZE := 14         # Размер подписей значений осей

func _ready() -> void:
	# Оверлей не перехватывает клики/фокус
	mouse_filter = MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	# Перерисовываем каждый кадр — значения осей меняются непрерывно
	queue_redraw()

func _draw() -> void:
	# Проверка наличия autoload-синглтона (если забыли register в Project Settings)
	if not has_node("/root/InputHandler"):
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(20.0, 40.0),
			"ОШИБКА: InputHandler не зарегистрирован в Autoload!",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(1, 0.3, 0.3))
		return

	var ih := get_node("/root/InputHandler")

	# Значения ИЗ ФИЗИКИ (обработанные: deadzone+expo применены InputHandler'ом)
	var yaw_v: float = ih.yaw          # -1..1
	var roll_v: float = ih.roll        # -1..1
	var pitch_v: float = ih.pitch      # -1..1 (инверсия уже внутри InputHandler)
	var thr_v: float = ih.throttle     # 0..1

	# Пересчёт газа 0..1 -> -1..1 для отрисовки (вверх = +1 на экране)
	var throttle_draw: float = thr_v * 2.0 - 1.0

	# --- Левый круг: X = Yaw, Y = Throttle (точка вверх = газ вверх)
	var left_center := Vector2(PADDING + CIRCLE_R, size.y - PADDING - CIRCLE_R)
	_draw_stick_circle(left_center, yaw_v, throttle_draw, "L: YAW / THROTTLE")

	# --- Правый круг: X = Roll, Y = Pitch (точка вверх = стик на себя/nose up)
	var right_center := Vector2(size.x - PADDING - CIRCLE_R, size.y - PADDING - CIRCLE_R)
	_draw_stick_circle(right_center, roll_v, pitch_v, "R: ROLL / PITCH")

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

	# Точка стика: axis_y_up > 0 значит «вверх», а в экранных координатах
	# вверх = минус Y, поэтому второй компонент берём со знаком минус.
	var dot := center + Vector2(clampf(axis_x, -1.0, 1.0), -clampf(axis_y_up, -1.0, 1.0)) * CIRCLE_R
	draw_circle(dot, DOT_R, Color(0.2, 1.0, 0.3, 0.9))
	draw_circle(dot, DOT_R, Color(1, 1, 1, 0.9), false, 1.5)

	# Подписи: название над кругом, обработанные значения под кругом
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(center.x - CIRCLE_R, center.y - CIRCLE_R - 8.0),
		title, HORIZONTAL_ALIGNMENT_CENTER, CIRCLE_R * 2.0, FONT_SIZE, Color(1, 1, 1, 0.8))
	# Показываем значения так, как их видит физика: «вверх = +».
	# Для газа дополнительно в процентах.
	var label := ""
	if title.begins_with("L"):
		label = "Yaw: %+.2f  Thr: %.0f%%" % [axis_x, (axis_y_up + 1.0) * 50.0]
	else:
		label = "Roll: %+.2f  Pitch: %+.2f" % [axis_x, axis_y_up]
	draw_string(font, Vector2(center.x - CIRCLE_R, center.y + CIRCLE_R + 18.0),
		label, HORIZONTAL_ALIGNMENT_CENTER, CIRCLE_R * 2.0, FONT_SIZE, Color(0.2, 1.0, 0.3))
