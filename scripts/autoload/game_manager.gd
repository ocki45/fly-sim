extends Node
# Менеджер игры (autoload-синглтон GameManager).
# Хранит выбранный конфиг дрона и калибровку пульта (JSON в user://calibration.cfg).

var selected_drone_config: String = "res://resources/drones/drone_220mm_freestyle.tres"
const CALIBRATION_PATH: String = "user://calibration.cfg"

# Схема по умолчанию — Mode 2 (RadioMaster Pocket):
# ось 1 = газ, ось 0 = yaw, ось 3 = pitch, ось 2 = roll.
var default_mapping: Dictionary = {
	"throttle": {"axis": 1, "inverted": false},
	"yaw": {"axis": 0, "inverted": false},
	"pitch": {"axis": 3, "inverted": false},
	"roll": {"axis": 2, "inverted": false}
}

# Текущая активная схема осей (может быть изменена экраном калибровки).
var current_mapping: Dictionary = {}


func _ready() -> void:
	load_calibration()


# Загрузка калибровки из JSON-файла; при ошибке/отсутствии — схема по умолчанию.
func load_calibration() -> void:
	if FileAccess.file_exists(CALIBRATION_PATH):
		var file: FileAccess = FileAccess.open(CALIBRATION_PATH, FileAccess.READ)
		var json: JSON = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			current_mapping = json.data
		else:
			current_mapping = default_mapping.duplicate(true)
	else:
		current_mapping = default_mapping.duplicate(true)


# Сохранение текущей схемы калибровки в JSON.
func save_calibration() -> void:
	var file: FileAccess = FileAccess.open(CALIBRATION_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(current_mapping, "\t"))


func set_drone_config(path: String) -> void:
	selected_drone_config = path


func get_drone_config() -> String:
	return selected_drone_config
