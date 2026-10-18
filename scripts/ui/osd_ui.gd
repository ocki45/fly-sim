extends Label
class_name OsdUi
# Базовый OSD квадрокоптера (как в Betaflight).
# Вешается на Label, который лежит внутри CanvasLayer в сцене main.tscn.
# Показывает: напряжение батареи (с просадкой от газа), таймер полёта,
# газ в %, скорость в м/с, имя дрона.

@export var drone_path: NodePath  # Путь к DronePhysics (RigidBody3D)

var _drone: RigidBody3D = null
var _config: DroneConfig = null

# --- Модель батареи ---
const CELL_FULL_V := 4.2      # Вольт на ячейку при полном заряде (LiPo)
const CELL_SAG_OHMS := 0.012  # Внутреннее сопротивление одной ячейки, Ом
const LOAD_CURRENT_A := 60.0  # Ток при 100% газа, А (упрощённая модель просадки)

# --- Таймер полёта: стартует, когда газ выше порога ---
const LAUNCH_THROTTLE := 0.15
var _flight_time: float = 0.0
var _launched: bool = false

func _ready() -> void:
	# Моноширинный зелёный шрифт, как у настоящего OSD
	add_theme_font_size_override("font_size", 20)
	add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_theme_constant_override("outline_size", 4)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_drone = get_node_or_null(drone_path) as RigidBody3D
	if _drone != null and _drone is DronePhysics:
		_config = (_drone as DronePhysics).config
	else:
		push_warning("OSD: узел дрона не найден по пути %s" % [drone_path])

func _process(delta: float) -> void:
	if _drone == null or _config == null:
		text = "OSD: дрон не подключён!"
		return

	# Телеметрия из физики дрона (get_telemetry() в drone_physics.gd)
	var tele := {}
	if _drone is DronePhysics:
		tele = (_drone as DronePhysics).get_telemetry()

	# Фолбэк, если словарь пустой — берём газ напрямую из InputHandler
	var throttle := float(tele.get("throttle", InputHandler.throttle))
	var voltage := float(tele.get("voltage", 0.0))
	var speed := float(tele.get("speed", _drone.linear_velocity.length()))

	# Таймер: считаем секунды после взлёта (газ > порога)
	if not _launched and throttle > LAUNCH_THROTTLE:
		_launched = true
	if _launched:
		_flight_time += delta

	# Форматирование времени mm:ss
	var minutes := int(_flight_time) / 60
	var seconds := int(_flight_time) % 60

	text = "%s\n" % [_config.drone_name]
	text += "T:%3.0f%%\n" % [throttle * 100.0]
	text += "V:%5.2f\n" % [voltage]
	text += "SPD:%5.1f m/s\n" % [speed]
	text += "TIME:%02d:%02d" % [minutes, seconds]
