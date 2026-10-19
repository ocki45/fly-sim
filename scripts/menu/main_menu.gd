extends Control
# Главное меню: кнопки «Калибровка», «Выбор дрона», «Старт полёта».

func _ready() -> void:
	$BtnCalibrate.pressed.connect(_on_calibrate)
	$BtnSelectDrone.pressed.connect(_on_select)
	$BtnStartFlight.pressed.connect(_on_start)


func _on_calibrate() -> void:
	get_tree().change_scene_to_file("res://scenes/calibration.tscn")


func _on_select() -> void:
	get_tree().change_scene_to_file("res://scenes/drone_select.tscn")


func _on_start() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
