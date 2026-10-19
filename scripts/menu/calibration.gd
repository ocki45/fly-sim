extends Control
# Экран калибровки пульта.
# Логика: пользователь отклоняет каждый стик по очереди — скрипт запоминает,
# какая сырая ось джойстика при этом изменилась сильнее всего, и назначает её
# каналу (throttle/yaw/pitch/roll). Результат сохраняется GameManager'ом в
# user://calibration.cfg и подхватывается InputHandler при следующем старте.

const CHANNELS: Array[String] = ["throttle", "yaw", "pitch", "roll"]
const HINTS: Dictionary = {
	"throttle": "Двигайте РУЧКУ ГАЗА (левый стик) вверх-вниз до упора",
	"yaw": "Двигайте левый стик ВЛЕВО-ВПРАВО до упора",
	"pitch": "Двигайте правый стик ВВЕРХ-ВНИЗ до упора",
	"roll": "Двигайте правый стик ВЛЕВО-ВПРАВО до упора",
}

var current_channel: int = 0          # Индекс калибруемого канала
var best_axis: int = -1               # Ось с наибольшим размахом на ТЕКУЩЕМ шаге
var best_range: float = 0.0           # Размах значения оси (-min..max)
var channel_best_axis: Array[int] = []  # Лучшая ось для каждого канала (по индексу CHANNELS)
var axis_min: Array[float] = []       # Миниумы по осям
var axis_max: Array[float] = []       # Максимумы по осям
var collecting: bool = false          # Идёт ли сбор данных сейчас

@onready var lbl_hint: Label = $LblHint
@onready var lbl_result: Label = $LblResult
@onready var btn_next: Button = $BtnNext
@onready var btn_save: Button = $BtnSave
@onready var btn_back: Button = $BtnBack


func _ready() -> void:
	btn_next.pressed.connect(_on_next_pressed)
	btn_save.pressed.connect(_on_save_pressed)
	btn_back.pressed.connect(_on_back_pressed)
	for i in CHANNELS.size():
		channel_best_axis.append(-1)
	_start_channel(0)


# Начало калибровки канала: сбрасываем статистику осей.
func _start_channel(idx: int) -> void:
	current_channel = idx
	collecting = true
	best_axis = -1
	best_range = 0.0
	axis_min.clear()
	axis_max.clear()
	for ax in 8:
		axis_min.append(1.0)
		axis_max.append(-1.0)
	lbl_hint.text = "Калибровка %s (%d/%d):\n%s" % [
		CHANNELS[idx], idx + 1, CHANNELS.size(), HINTS[CHANNELS[idx]]]
	lbl_result.text = "Сбор данных... отклоните стик."


# Каждый кадр обновляем миниумы/максимумы всех осей текущего джойстика.
func _process(_delta: float) -> void:
	if not collecting:
		return
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		lbl_result.text = "ДЖОЙСТИК НЕ НАЙДЕН! Подключите RadioMaster Pocket."
		return
	var joy: int = pads[0]
	# Количество осей берём из get_joy_info(); запасное значение 8 (Pocket ~6-8 осей).
	var axes_count: int = mini(8, int(Input.get_joy_info(joy).get("axis", 8)))
	for ax in axes_count:
		var v: float = Input.get_joy_axis(joy, ax as JoyAxis)
		axis_min[ax] = minf(axis_min[ax], v)
		axis_max[ax] = maxf(axis_max[ax], v)
		var range_now: float = axis_max[ax] - axis_min[ax]
		if range_now > best_range:
			best_range = range_now
			best_axis = ax
	lbl_result.text = "Лучшая ось: %d (размах %.2f)" % [best_axis, best_range]


# Переход к следующему каналу: запоминаем выбранную ось для текущего.
func _on_next_pressed() -> void:
	channel_best_axis[current_channel] = best_axis if best_axis >= 0 else current_channel
	if current_channel + 1 < CHANNELS.size():
		_start_channel(current_channel + 1)
	else:
		collecting = false
		lbl_hint.text = "Все каналы собраны. Нажмите СОХРАНИТЬ."


func _on_save_pressed() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm == null:
		push_error("GameManager не найден (проверьте Autoload)!")
		return
	# Собираем mapping: для каждого канала запоминается Ось, которая сильнее
	# всего отклонялась именно на шаге калибровки этого канала (а не одна и та же
	# «лучшая» ось на все четыре). Инверсии — дефолты Mode 2; газ и pitch
	# инвертируются внутри InputHandler по своим флагам.
	var mapping: Dictionary = {}
	for i in CHANNELS.size():
		mapping[CHANNELS[i]] = {"axis": channel_best_axis[i], "inverted": false}
	gm.current_mapping = mapping
	gm.save_calibration()
	lbl_result.text = "Сохранено в user://calibration.cfg"
	print("Calibration: сохранён mapping ", mapping)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
