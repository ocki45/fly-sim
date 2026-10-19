extends Node
# ============================================================
# GameManager — autoload-синглтон (менеджер игры).
# Хранит: выбранный конфиг дрона + калибровку пульта (JSON).
# Калибровка решают проблему перепутанных осей на Linux:
# экран калибровки сам определяет, какой канал джойстика
# за что отвечает, и сохраняет это в user://calibration.cfg.
# ============================================================

# Путь к выбранному .tres-конфигу дрона (ставится экраном выбора).
var selected_drone_config: String = "res://resources/drones/drone_220mm_freestyle.tres"

# Файл сохранения калибровки (user:// = writable dir Godot).
const CALIBRATION_PATH: String = "user://calibration.cfg"

# Схема по умолчанию — Mode 2 (RadioMaster Pocket):
# ось 1 = газ, ось 0 = yaw, ось 3 = pitch, ось 2 = roll.
# inverted=true означает: значение оси нужно развернуть (-(v)).
var default_mapping: Dictionary = {
	"throttle": {"axis": 1, "inverted": true},
	"yaw": {"axis": 0, "inverted": false},
	"pitch": {"axis": 3, "inverted": true},
	"roll": {"axis": 2, "inverted": false}
}

# Текущая активная схема осей (может быть перезаписана калибровкой).
var current_mapping: Dictionary = {}


func _ready() -> void:
	load_calibration()


# Загрузка калибровки из JSON-файла; при ошибке/отсутствии — дефолт.
func load_calibration() -> void:
	if FileAccess.file_exists(CALIBRATION_PATH):
		var file: FileAccess = FileAccess.open(CALIBRATION_PATH, FileAccess.READ)
		if file == null:
			current_mapping = default_mapping.duplicate(true)
			return
		var json: JSON = JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			current_mapping = json.data
		else:
			current_mapping = default_mapping.duplicate(true)
	else:
		current_mapping = default_mapping.duplicate(true)


# Сохранение текущей схемы калибровки в JSON-файл.
func save_calibration() -> void:
	var file: FileAccess = FileAccess.open(CALIBRATION_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameManager: не удалось открыть calibration.cfg для записи")
		return
	file.store_string(JSON.stringify(current_mapping, "\t"))


# Установка пути к .tres-конфигу выбранного дрона.
func set_drone_config(path: String) -> void:
	selected_drone_config = path


# Получение пути к выбранному конфигу дрона.
func get_drone_config() -> String:
	return selected_drone_config
