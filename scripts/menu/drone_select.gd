extends Control
# Экран выбора дрона: список из 5 .tres-конфигов, выбор сохраняется в GameManager.

const DRONE_LIST: Array[String] = [
	"res://resources/drones/drone_75mm_whoop.tres",
	"res://resources/drones/drone_220mm_freestyle.tres",
	"res://resources/drones/drone_220mm_race.tres",
	"res://resources/drones/drone_250mm_cinewhoop.tres",
	"res://resources/drones/drone_380mm_longrange.tres",
]

@onready var list_box: ItemList = $ItemList
@onready var btn_select: Button = $BtnSelect
@onready var btn_back: Button = $BtnBack


func _ready() -> void:
	# Заполняем список названиями из конфигов.
	for path in DRONE_LIST:
		var cfg: Resource = load(path)
		var name_txt: String = cfg.drone_name if ("drone_name" in cfg) else path.get_file()
		list_box.add_item(name_txt)
	btn_select.pressed.connect(_on_select_pressed)
	btn_back.pressed.connect(_on_back_pressed)


func _on_select_pressed() -> void:
	var sel: Array[int] = list_box.get_selected_items()
	if sel.is_empty():
		return
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm != null:
		gm.set_drone_config(DRONE_LIST[sel[0]])
		print("DroneSelect: выбран конфиг ", DRONE_LIST[sel[0]])
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
