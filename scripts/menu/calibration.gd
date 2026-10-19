extends Control
# Экран калибровки пульта в стиле Liftoff: для каждого канала (throttle/yaw/
# pitch/roll) пользователь по очереди отклоняет стик ДО УПОРА В ДВЕ СТОРОНЫ;
# скрипт определяет номер реагирующей сырой оси и её инверсию. Результат
# сохраняется GameManager'ом в user://calibration.cfg и подхватывается
# InputHandler при следующем старте полёта.

# Калибровка в стиле Liftoff: для КАЖДОГО канала пользователь отклоняет стик
# ДВА РАЗА — сначала ДО УПОРА В ОДНУ СТОРОНУ (шаг "+"), затем ДО УПОРА В ДРУГУЮ
# (шаг "-"). По этим двум точкам определяются и номер оси, и её инверсия
# (как у Gas Station / Liftoff: «Full stick forward», «Full stick back»).
# Результат (axis + inverted) сохраняется GameManager'ом в user://calibration.cfg
# и подхватывается InputHandler при следующем старте полёта.

const CHANNELS: Array[String] = ["throttle", "yaw", "pitch", "roll"]
# Подсказки для двух фаз каждого канала (Liftoff-style):
const HINTS_POS: Dictionary = {   # фаза 1: «положительное» направление стика
	"throttle": "ОТКЛОНИТЕ РУЧКУ ГАЗА ДО УПОРА ВВЕРХ (полный газ)",
	"yaw": "ОТКЛОНИТЕ ЛЕВЫЙ СТИК ДО УПОРА ВПРАВО",
	"pitch": "ОТКЛОНИТЕ ПРАВЫЙ СТИК ДО УПОРА ОТ СЕБЯ (нос вниз)",
	"roll": "ОТКЛОНИТЕ ПРАВЫЙ СТИК ДО УПОРА ВПРАВО",
}
const HINTS_NEG: Dictionary = {    # фаза 2: противоположный край
	"throttle": "ТЕПЕРЬ: ручка газа ДО УПОРА ВНИЗ",
	"yaw": "ТЕПЕРЬ: левый стик ДО УПОРА ВЛЕВО",
	"pitch": "ТЕПЕРЬ: правый стик ДО УПОРА НА СЕБЯ (нос вверх)",
	"roll": "ТЕПЕРЬ: правый стик ДО УПОРА ВЛЕВО",
}
const PHASES: Array[String] = ["pos", "neg"]  # порядок фаз

# Экстремумы каждой сырой оси, достигнутые во время соответствующей фазы:
# extremes[phase_index][axis] = {"min": ..., "max": ...}
var extremes: Array = [{}, {}]
var current_channel: int = 0        # Индекс калибруемого канала
var current_phase: int = 0          # 0 = pos, 1 = neg
var collecting: bool = false        # Идёт ли сбор данных на текущем шаге
# Результат по каждому каналу: {"axis": int, "inverted": bool}
var results: Dictionary = {}

@onready var lbl_hint: Label = $LblHint
@onready var lbl_result: Label = $LblResult
@onready var btn_next: Button = $BtnNext
@onready var btn_save: Button = $BtnSave
@onready var btn_back: Button = $BtnBack


func _ready() -> void:
	btn_next.pressed.connect(_on_next_pressed)
	btn_save.pressed.connect(_on_save_pressed)
	btn_back.pressed.connect(_on_back_pressed)
	results = {}  # сброс результатов при каждом входе на экран
	_start_step(0, 0)


# Начало шага калибровки: фаза pos/neg конкретного канала.
# ВАЖНО (исправление бага «оси путаются»): экстремумы очищаются ТОЛЬКО для
# текущей фазы, а не оба массива сразу — иначе данные фазы "+" терялись на
# фазе "-", и инверсия определялась неверно.
func _start_step(chan_idx: int, phase_idx: int) -> void:
	current_channel = chan_idx
	current_phase = phase_idx
	collecting = true
	extremes[phase_idx] = {}  # сбрасываем накопление только текущей фазы
	var ch: String = CHANNELS[chan_idx]
	var hint: String = HINTS_POS[ch] if phase_idx == 0 else HINTS_NEG[ch]
	var phase_txt: String = "ШАГ +%s" % ("1" if phase_idx == 0 else "2")
	lbl_hint.text = "%s (%d/%d), %s:\n%s" % [
		ch.to_upper(), chan_idx + 1, CHANNELS.size(), phase_txt, hint]
	lbl_result.text = "Удерживайте стик в этом положении 1-2 секунды..."


# Каждый кадр собираем минимумы/максимумы всех осей во время активной фазы.
func _process(_delta: float) -> void:
	if not collecting:
		return
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		lbl_result.text = "ДЖОЙСТИК НЕ НАЙДЕН! Подключите RadioMaster Pocket."
		return
	var joy: int = pads[0]
	var axes_count: int = mini(8, int(Input.get_joy_info(joy).get("axis", 8)))
	var cur: Dictionary = extremes[current_phase]
	for ax in axes_count:
		var v: float = Input.get_joy_axis(joy, ax as JoyAxis)
		if not cur.has(ax):
			cur[ax] = {"min": v, "max": v}
		else:
			cur[ax]["min"] = minf(cur[ax]["min"], v)
			cur[ax]["max"] = maxf(cur[ax]["max"], v)
	lbl_result.text = "Идёт сбор данных... (нажмите ДАЛЕЕ когда зафиксировали край)"


# Кнопка ДАЛЕЕ: завершаем фазу pos -> запускаем фазу neg того же канала;
# после neg -> определяем ось+инверсию КАНАЛА СРАЗУ (по его собственным
# данным, а не по последнему каналу — это второе исправление бага) и
# переходим к следующему каналу.
func _on_next_pressed() -> void:
	collecting = false
	if current_phase == 0:
		_start_step(current_channel, 1)
		return
	# Фаза "-" завершена: фиксируем результат текущего канала.
	var ch: String = CHANNELS[current_channel]
	results[ch] = _detect_channel(ch)
	print("Calibration: %s -> axis=%d inverted=%s" % [
		ch, results[ch]["axis"], results[ch]["inverted"]])
	if current_channel + 1 < CHANNELS.size():
		_start_step(current_channel + 1, 0)
	else:
		var summary := "Все каналы откалиброваны. Нажмите СОХРАНИТЬ.\n"
		for k in CHANNELS:
			summary += "%s: ось %d, инверсия %s\n" % [
				k, results[k]["axis"], str(results[k]["inverted"])]
		lbl_hint.text = summary
		lbl_result.text = ""


# Определение оси и инверсии канала ПО ЕГО ДВУМ ФАЗАМ.
# Алгоритм:
#   1. Реагирующая ось = та, у которой размах (max-min) за обе фазы наибольший
#      и превышает порог 0.5 (остальные оси стояли на месте).
#   2. Инверсия: фаза "+" — это ПРАВИЛЬНОЕ направление стика из подсказки
#      (газ вверх / yaw вправо / pitch от себя / roll вправо). Если в этой
#      фазе ось ушла в ОТРИЦАТЕЛЬНую сторону (|min| > max) — симулятор должен
#      инвертировать её, чтобы стик давал ожидаемый знак канала.
func _detect_channel_for(chan_idx: int) -> Dictionary:
	var ch: String = CHANNELS[chan_idx]
	var pos_data: Dictionary = extremes[0]
	var neg_data: Dictionary = extremes[1]
	# 1. Ищем ось с наибольшим размахом между двумя фазами.
	var best_ax: int = -1
	var best_span: float = 0.0
	for ax in pos_data.keys():
		if not neg_data.has(ax):
			continue
		var hi: float = maxf(pos_data[ax]["max"], neg_data[ax]["max"])
		var lo: float = minf(pos_data[ax]["min"], neg_data[ax]["min"])
		var span: float = hi - lo
		if span > best_span:
			best_span = span
			best_ax = ax
	if best_ax == -1 or best_span < 0.5:
		# Ничего не отклоняли — оставляем дефолт Mode 2 без инверсии.
		var defaults := {"throttle": 1, "yaw": 0, "pitch": 3, "roll": 2}
		return {"axis": defaults.get(ch, 0), "inverted": false}
	# 2. Инверсия по фазе "+": правильному движению стика соответствует
	#    положительное значение канала. Смотрим, куда ушла ось в фазе pos.
	var p_max: float = pos_data[best_ax]["max"]
	var p_min: float = pos_data[best_ax]["min"]
	var inverted: bool = absf(p_min) > p_max  # «правильный» край дал минус
	return {"axis": best_ax, "inverted": inverted}


# Совместимость со старым вызовом по имени канала.
func _detect_channel(ch: String) -> Dictionary:
	var idx: int = CHANNELS.find(ch)
	if idx < 0:
		return {"axis": 0, "inverted": false}
	return _detect_channel_for(idx)


func _on_save_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		push_error("GameManager не найден (проверьте Autoload)!")
		return
	# Собираем mapping: номер оси И инверсия для каждого канала.
	# Используем результаты, зафиксированные ПОСЛЕ каждого канала (правильные
	# пары фаз), а не пересчёт по глобальным extremes (старый баг: все четыре
	# канала считались по данным последнего — отсюда «оси путаются жесть»).
	var mapping: Dictionary = {}
	for ch in CHANNELS:
		if results.has(ch):
			mapping[ch] = results[ch]
		else:
			mapping[ch] = {"axis": {"throttle": 1, "yaw": 0, "pitch": 3, "roll": 2}[ch], "inverted": false}
	gm.current_mapping = mapping
	gm.save_calibration()
	lbl_result.text = "Сохранено в user://calibration.cfg\n%s" % JSON.stringify(mapping)
	print("Calibration: сохранён mapping ", mapping)
	# Мгновенно применяем к активному InputHandler (без перезапуска сцены).
	var ih: Node = get_node_or_null("/root/InputHandler")
	if ih != null and ih.has_method("reload_calibration"):
		ih.reload_calibration()
	# Как в Liftoff: после сохранения сразу возвращаемся в главное меню.
	get_tree().create_timer(1.2).timeout.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
