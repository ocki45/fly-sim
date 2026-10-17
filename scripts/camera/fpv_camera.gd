extends Camera3D
class_name FpvCamera
# FPV-камера: жёстко привязана к дрону (дочерний узел DronePhysics).
# FOV 150°, позиция чуть впереди и выше центра, наклон ~10° вниз.

@export var drone: NodePath  # Путь к DronePhysics (если камера — sibling)

const FPV_FOV := 150.0            # Реальный угол обзора FPV-объективов
const TILT_DOWN_DEG := 10.0       # Наклон камеры вниз
const OFFSET_FORWARD := 0.05      # Смещение вперёд от центра дрона, м
const OFFSET_UP := 0.06           # Смещение вверх от центра дрона, м

func _ready() -> void:
	fov = FPV_FOV
	near = 0.05   # Ближняя плоскость — чтобы рама не резалась
	far = 1000.0
	# Позиция и наклон относительно дрона (локальные координаты)
	position = Vector3(0.0, OFFSET_UP, -OFFSET_FORWARD)  # -Z = "вперёд" в Godot
	rotation_degrees.x = TILT_DOWN_DEG
	# Если камера висит не на дроне, а рядом — следим через remote transform
	if not drone.is_empty():
		var node := get_node_or_null(drone)
		if node is Node3D and get_parent() != node:
			global_position = (node as Node3D).global_position
