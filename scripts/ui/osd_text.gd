extends Label
# =============================================================================
# ЖИВОЙ ТЕКСТОВЫЙ OSD (osd_text.gd)
# Вешается на Label внутри CanvasLayer. Читает телеметрию из DronePhysics
# через get_telemetry() -> {voltage, throttle, speed}.
# Время полёта, напряжение батареи с просадкой, газ в %, скорость в м/с.
# Шрифт: моноширинный, зелёный, 20 px. Позиция: верхний левый угол.
# =============================================================================

@export var drone_path: NodePath  # Путь к узлу DronePhysics (RigidBody3D)

var _drone: RigidBody3D = null     # Ссылка на дрон (находим в _ready)
var _flight_time: float = 0.0      # Секунды с начала полёта
var _launched: bool = false        # Флаг взлёта (газ выше порога)

const LAUNCH_THROTTLE := 0.15      # Порог газа для запуска таймера

func _ready() -> void:
	# Моноширинный зелёный шрифт как у настоящего FPV-OSD
	add_theme_font_size_override("font_size", 20)
	add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_theme_constant_override("outline_size", 4)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	position = Vector2(20, 20)  # Верхний левый угол с отступом

	# Ищем дрон по экспортированному пути
	_drone = get_node_or_null(drone_path) as RigidBody3D
	if _drone == null:
		push_warning("osd_text: дрон не найден по пути %s" % [drone_path])

func _process(delta: float) -> void:
	if _drone == null:
		text = "OSD: дрон не подключён!"
		return

	# --- Живая телеметрия из физики дрона ---
	var tele: Dictionary = {}
	if _drone.has_method("get_telemetry"):
		tele = _drone.get_telemetry()

	var voltage: float = float(tele.get("voltage", 0.0))
	var throttle: float = float(tele.get("throttle", 0.0))
	var speed: float = float(tele.get("speed", _drone.linear_velocity.length()))

	# Таймер полёта: стартует при газе выше порога
	if not _launched and throttle > LAUNCH_THROTTLE:
		_launched = true
	if _launched:
		_flight_time += delta

	var minutes: int = int(_flight_time) / 60
	var seconds: int = int(_flight_time) % 60

	# Рендер текста OSD (строки как в Betaflight)
	text = "V: %5.2f\n" % [voltage]
	text += "T: %3.0f%%\n" % [throttle * 100.0]
	text += "SPD: %5.1f m/s\n" % [speed]
	text += "TIME: %02d:%02d" % [minutes, seconds]
