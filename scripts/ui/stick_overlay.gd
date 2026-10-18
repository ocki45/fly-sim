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

# Параметры панели диагностики сырых осей (строки 102-112 их использовали,
# но объявлены не были — из-за этого был Parse Error и оверлей не грузился)
const DBG_FONT_SIZE := 13     # Размер шрифта строк диагностики
const DBG_LINE_H := 17.0      # Высота одной строки диагностики, пикселей

func _ready() -> void:
	# Мы — Control внутри CanvasLayer (StickOverlay, layer=10). Раньше скрипт
	# мог висеть на самом CanvasLayer и вызывать size/queue_redraw/_draw у него —
	# это ломало оверлей (ничего не рисовалось). Теперь растягиваемся на весь
	# экран, включаем пофреймовый redraw и гарантируем видимость.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true          # узел в main.tscn мог остаться со visible=false
	set_process(true)
	# ВАЖНО: без цвета текста draw_string() рисует НечТО невидимое на тёмном фоне
	# (по умолчанию цвет шрифта может совпасть с фоном панели). Ставим белый.
	self_modulate = Color(1, 1, 1, 1)
	modulate = Color(1, 1, 1, 1)
	# Принудительно перерисуем на следующий кадр после установки anchors — иначе
	# size ещё не обновится и круги вылезут за левый край экрана.
	call_deferred("queue_redraw")

func _process(_delta: float) -> void:
	# Перерисовываем каждый кадр — значения осей меняются непрерывно
	if has_node("/root/InputHandler"):
		_update_axis_debug(get_node("/root/InputHandler"))
	queue_redraw()

func _draw() -> void:
	# Проверка наличия autoload-синглтона (если забыли register в Project Settings)
	if not has_node("/root/InputHandler"):
		var f := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2(16, 16), Vector2(560, 44)), Color(0, 0, 0, 0.7))
		draw_string(f, Vector2(28.0, 44.0),
			"ОШИБКА: InputHandler не зарегистрирован в Autoload!",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(1, 0.3, 0.3))
		return

	var ih := get_node("/root/InputHandler")

	# === ЖИВАЯ ДИАГНОСТИКА СЫРЫХ ОСЕЙ (главный инструмент против перепутанного маппинга) ===
	# Показывает ВСЕ оси пульта прямо на экране: подвигайте стики и смотрите,
	# какой номер реагирует. Текущий выбор (axis_yaw/throttle/roll/pitch) подсвечен.
	var font := ThemeDB.fallback_font
	_draw_axis_debug(ih, font)

	# Значения ИЗ ФИЗИКИ (обработанные: deadzone+expo применены InputHandler'ом).
	# ВАЖНО: берём СЫРЫЕ значения до expo (raw_*), чтобы точка шла линейно за
	# стиком (как в Betaflight Configurator) — так лучше видно инверсии/перепутанные оси.
	var yaw_v: float = ih.raw_yaw        # -1..1
	var roll_v: float = ih.raw_roll      # -1..1
	var pitch_v: float = ih.raw_pitch    # -1..1 (инверсия уже внутри InputHandler)
	var thr_v: float = ih.throttle       # 0..1

	# Пересчёт газа 0..1 -> -1..1 для отрисовки (вверх = +1 на экране)
	var throttle_draw: float = thr_v * 2.0 - 1.0

	# --- Левый круг: X = Yaw, Y = Throttle (точка вверх = газ вверх)
	var left_center := Vector2(PADDING + CIRCLE_R, size.y - PADDING - CIRCLE_R)
	_draw_stick_circle(left_center, yaw_v, throttle_draw, "L: YAW / THROTTLE", font)

	# --- Правый круг: X = Roll, Y = Pitch (точка вверх = nose up)
	var right_center := Vector2(size.x - PADDING - CIRCLE_R, size.y - PADDING - CIRCLE_R)
	_draw_stick_circle(right_center, roll_v, pitch_v, "R: ROLL / PITCH", font)

# Кэш списка осей для диагностики: пересобираем не каждый кадр, а раз в 0.5 с.
# Это снимает нагрузку и делает панель стабильной.
var _dbg_lines: Array[String] = ["ОСИ: инициализация..."]
var _dbg_timer: float = 1.0

# Обновляет список строк диагностики сырых осей (вызывается из _process).
func _update_axis_debug(ih: Node) -> void:
	_dbg_timer -= get_process_delta_time()
	if _dbg_timer > 0.0:
		return
	_dbg_timer = 0.5  # обновляем панель 2 раза в секунду — значения видны «живьём»

	var joy_id: int = ih._joy_id
	var lines: Array[String] = []
	if joy_id == -1:
		lines.append("JOY NOT FOUND — работает клавиатура (W/S газ, A/D yaw, стрелки)")
	else:
		# ВАЖНО (Godot 4.3): НЕ используем Input.get_joy_axis_count() — его нет как
		# статического метода (был Parse Error). Количество осей берём из
		# Input.get_joy_info(joy_id) — словарь JoyConnection с ключом "axis".
		var axes_count: int = 0
		var info: Dictionary = Input.get_joy_info(joy_id)
		if info.has("axis"):
			axes_count = int(info["axis"])
		else:
			axes_count = 8  # запасное значение: RadioMaster Pocket отдаёт ~6-8 осей
		lines.append("СЫРЫЕ ОСИ #%d (%s): подвигайте стиками!" % [joy_id, Input.get_joy_name(joy_id)])
		for ax in axes_count:
			var v: float = Input.get_joy_axis(joy_id, ax as JoyAxis)
			if absf(v) < 0.02:
				v = 0.0  # гасим шум покоя, чтобы глаз ловил только реальные движения
			var tag := ""
			if ax == ih.axis_yaw:        tag = " <- YAW"
			elif ax == ih.axis_throttle: tag = " <- THROTTLE"
			elif ax == ih.axis_roll:     tag = " <- ROLL"
			elif ax == ih.axis_pitch:    tag = " <- PITCH"
			lines.append("ось %d: %+0.2f%s" % [ax, v, tag])
	_dbg_lines = lines

# Рисует панель со ВСЕМИ сырыми осями джойстика (для настройки маппинга).
func _draw_axis_debug(_ih: Node, font: Font) -> void:
	# Фон панели (размер по текущему числу строк)
	var panel_h := float(_dbg_lines.size()) * DBG_LINE_H + 12.0
	draw_rect(Rect2(Vector2(16, 16), Vector2(560, panel_h)), Color(0, 0, 0, 0.65))
	var y := 16.0 + float(DBG_FONT_SIZE) + 6.0
	for i in _dbg_lines.size():
		var col := Color(0.8, 0.9, 1.0) if i > 0 else Color(1.0, 0.9, 0.3)
		# Подсвечиваем строки выбранных осей зелёным
		if _dbg_lines[i].contains("<-"):
			col = Color(0.2, 1.0, 0.3)
		draw_string(font, Vector2(28.0, y), _dbg_lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, DBG_FONT_SIZE, col)
		y += DBG_LINE_H

# Рисует один круг стика: фон, крест осей, рамку мёртвой зоны, точку и подписи.
func _draw_stick_circle(center: Vector2, axis_x: float, axis_y_up: float, title: String, font: Font) -> void:
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
	# (font передаётся параметром — локальное объявление убрано, не затеняет аргумент)
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
