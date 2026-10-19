extends Control
# ============================================================
# Главное меню (Liftoff-style): Калибровка / Выбор дрона / Старт.
# Висячие кнопки заменены на программную сборку UI — сцене
# main_menu.tscn нужен только корневой Control с этим скриптом.
# ============================================================

# Пункты меню: подпись -> действие.
var _items: Array[Dictionary] = [
	{"label": "КАЛИБРОВКА ПУЛЬТА", "scene": "res://scenes/calibration.tscn"},
	{"label": "ВЫБОР ДРОНА", "scene": "res://scenes/drone_select.tscn"},
	{"label": "СТАРТ ПОЛЁТА", "scene": ""},  # пустая строка = текущая сцена полёта
]


func _ready() -> void:
	_build_ui()


# Полностью собираем интерфейс кодом (без внешних ассетов).
func _build_ui() -> void:
	# Тёмный фон всего экрана.
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Вертикальный контейнер по центру экрана.
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(360, 0)
	box.position = Vector2(-180, -160)
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	# Заголовок.
	var title: Label = Label.new()
	title.text = "FPV SIMULATOR"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# Подпись выбранного дрона (из GameManager).
	var drone_label: Label = Label.new()
	drone_label.name = "SelectedDroneLabel"
	drone_label.text = "Дрон: %s" % _drone_name_from_path(GameManager.get_drone_config())
	drone_label.add_theme_font_size_override("font_size", 18)
	drone_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	drone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(drone_label)

	box.add_child(_make_spacer(20))

	# Кнопки меню.
	for item: Dictionary in _items:
		var btn: Button = Button.new()
		btn.text = String(item["label"])
		btn.custom_minimum_size = Vector2(360, 52)
		btn.pressed.connect(_on_menu_button.bind(String(item["scene"])))
		box.add_child(btn)


# Универсальный обработчик: переход к сцене или прямой старт полёта.
func _on_menu_button(scene_path: String) -> void:
	if scene_path.is_empty():
		# Старт: сразу летим на выбранном дроне в основной сцене.
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		get_tree().change_scene_to_file(scene_path)


# Красивое имя дрона из пути .tres (для подписи в меню).
func _drone_name_from_path(path: String) -> String:
	var file_name: String = path.get_file().get_basename()
	return file_name.replace("drone_", "").replace("_", " ").to_upper()


# Пустая вертикальная отбивка между элементами.
func _make_spacer(height: float) -> Control:
	var sp: Control = Control.new()
	sp.custom_minimum_size = Vector2(0, height)
	return sp
