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
	# Камера — дочерний узел дрона: локальные позиция/поворот задаются один раз
	# и дальше «летают» вместе с родителем автоматически.
	position = Vector3(0.0, OFFSET_UP, -OFFSET_FORWARD)  # -Z = "вперёд" в Godot
	rotation_degrees = Vector3(TILT_DOWN_DEG, 0.0, 0.0)  # наклон ~10° вниз
	# Сглаживание движения (ТЗ: lerp с коэффициентом 0.2):
	# если дрон двигается дискретно (телепорт/спавн), камера мягко подтягивается.
	# Для обычной физики RigidBody эффект минимален — камера следует жёстко.
	if not drone.is_empty():
		var target_node := get_node_or_null(drone)
		if target_node is Node3D:
			_drone_node = target_node as Node3D

var _drone_node: Node3D = null  # Целевой дрон для сглаживания (если задан экспорт)

func _process(delta: float) -> void:
	if _drone_node == null or _drone_node == get_parent():
		return  # Жёсткая привязка (дочерний узел) — сглаживание не нужно
	# Плавное следование за дроном: экспоненциальный lerp ~0.2 за кадр 60 Гц
	var weight: float = 1.0 - pow(1.0 - 0.2, delta * 60.0)
	global_position = global_position.lerp(_drone_node.global_position + offset_from_drone(), weight)

# Смещение камеры относительно дрона в мировых осях (учитывает ориентацию дрона)
func offset_from_drone() -> Vector3:
	return _drone_node.global_transform.basis * Vector3(0.0, OFFSET_UP, -OFFSET_FORWARD)
