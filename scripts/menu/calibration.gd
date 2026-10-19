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

@onready var lbl_hint: Label = $LblHint
@onready var lbl_result: Label = $LblResult
@onready var btn_next: Button = $BtnNext
@onready var btn_save: Button = $BtnSave
@onready var btn_back: Button = $BtnBack


func _ready() -> void:
	btn_next.pressed.connect(_on_next_pressed)
	btn_save.pressed.connect(_on_save_pressed)
	btn_back.pressed.connect(_on_back_pressed)
	_start_step(0, 0)


# Начало шага калибровки: фаза pos/neg конкретного канала.
func _start_step(chan_idx: int, phase_idx: int) -> void:
	current_channel = chan_idx
	current_phase = phase_idx
	collecting = true
	extremes = [{}, {}]  # очищаем накопленные экстремумы
	var ch: String = CHANNELS[chan_idx]
	var hint: String = HINTS_POS[ch] if phase_idx == 0 else HINTS_NEG[ch]
	var phase_txt: String = "ШАГ +%s" % ("1" if phase_idx == 0 else "2")
	lbl_hint.text = "%s (%d/%d), %s:\n%s" % [
		ch.to_upper(), chan_idx + 1, CHANNELS.size(), phase_txt, hint]
	lbl_result.text = "Удерживайте стик в этом положении 1-2 секунды..."


# Каждый кадр собираем миниумы/максимумы всех осей во время активной фазы.
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
# после neg -> переходим к следующему каналу.
func _on_next_pressed() -> void:
	collecting = false
	if current_phase == 0:
		_start_step(current_channel, 1)
	elif current_channel + 1 < CHANNELS.size():
		_start_step(current_channel + 1, 0)
	else:
		lbl_hint.text = "Все каналы откалиброваны. Нажмите СОХРАНИТЬ."
		lbl_result.text = ""


# Определение оси и инверсии для ТЕКУЩЕГО канала по двум фазам.
# Логика Liftoff/Gas Station:
#   - фаза pos: ищем ось с наибольшим МАКСИМУМОМ (она ушла в +1);
#   - фаза neg: проверяем ту же ось — если её МИНИМУМ близок к -1, ось верная;
#   - inverted = true, если при «положительном» движении стика сырая ось ушла
#     в отрицательную сторону (Godot Y вниз = +1, аппаратура часто отдаёт наоборот).
func _detect_channel(ch: String) -> Dictionary:
	var pos_data: Dictionary = extremes[0]
	var neg_data: Dictionary = extremes[1]
	# 1. Ось фазы pos: максимальный пик.
	var best_ax: int = -1
	var best_val: float = -2.0
	for ax in pos_data.keys():
		if pos_data[ax]["max"] > best_val:
			best_val = pos_data[ax]["max"]
			best_ax = ax
	if best_ax == -1 or best_val < 0.5:
		# Ничего не отклоняли — оставляем дефолт по имени канала (Mode 2).
		var defaults := {"throttle": 1, "yaw": 0, "pitch": 3, "roll": 2}
		return {"axis": defaults.get(ch, 0), "inverted": false}
	# 2. Инверсия: в фазу posGood стик ушёл в ПЛЮС (best_val > 0) => не инвертировать;
	#    если максимум так себе, а в фазу neg эта же ось ушла сильно в минус больше,
	#    чем ожидалось, это нормально. Инвертируем, если в фазе pos ось ушла в МИНУС:
	#    значит «правильное» направление стика даёт отрицательные значения сырой оси.
	var inverted: bool = false
	if neg_data.has(best_ax):
		# Разница: сколько ось прошла в плюс (pos) против минуса (neg).
		var up_span: float = pos_data[best_ax]["max"]
		var down_span: float = absf(neg_data[best_ax]["min"])
		# Если «вниз» прошёл заметно дальше, чем «вверх» — стик инвертирован.
		inverted = down_span > up_span + 0.4
	return {"axis": best_ax, "inverted": inverted}


func _on_save_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		push_error("GameManager не найден (проверьте Autoload)!")
		return
	# Собираем mapping: номер оси И инверсия для каждого канала (Liftoff-style).
	var mapping: Dictionary = {}
	for ch in CHANNELS:
		mapping[ch] = _detect_channel(ch)
	gm.current_mapping = mapping
	gm.save_calibration()
	lbl_result.text = "Сохранено в user://calibration.cfg\n%s" % JSON.stringify(mapping)
	print("Calibration: сохранён mapping ", mapping)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
