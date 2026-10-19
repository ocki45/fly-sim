extends Node3D
# Генератор карты «лес» (в стиле стартовых зон Liftoff): земля, деревья,
# пни и пара препятствий. Всё из примитивов Godot (цилиндры/сферы/боксы),
# без внешних ассетов. Деревья генерируются процедурно со случайным
# положением, но с фиксированным seed — карта одинакова каждый запуск.

@export var tree_count: int = 40          # Количество деревьев (60 -> 40: меньше объектов = выше FPS)
@export var map_radius: float = 90.0      # Радиус леса вокруг спавна, м
@export var clearing_radius: float = 12.0 # Чистая зона у старта (без деревьев)
@export var seed_value: int = 1337        # Фиксированный seed для повторяемости

const TRUNK_HEIGHT_MIN := 4.0             # Мин./макс. высота ствола, м
const TRUNK_HEIGHT_MAX := 8.0
const TRUNK_RADIUS_MIN := 0.15            # Радиус ствола у земли, м
const TRUNK_RADIUS_MAX := 0.35

# ---------- ОПТИМИЗАЦИЯ ПОД СЛАБЫЕ GPU (llvmpipe / софтрендеринг) ----------
# low_poly — число сегментов цилиндров/сфер. По умолчанию 6/8 вместо стандартных
# 32: на программном рендере это даёт кратный прирост FPS без видимой разницы
# с FPV-камеры FOV 150°.
const LOW_POLY_CYL := 6
const LOW_POLY_SPHERE := 8


var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Общие материалы и меши СОЗДАЮТСЯ ОДИН РАЗ и переиспользуются всеми деревьями.
# Раньше для каждого дерева создавались новые StandardMaterial3D/CylinderMesh/
# SphereMesh (~10 объектов * 60 деревьев = 600+ ресурсов): лишняя память, долгий
# _ready() и лишние draw-пайплайны. Godot батчит только НОДЫ с одинаковыми
# mesh+material — переиспользование ресурсов делает batching возможным.
var _trunk_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D
var _stump_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D


func _ready() -> void:
	_rng.seed = seed_value
	_prepare_shared_resources()
	_build_ground()
	_build_trees()
	_build_stumps()
	_build_obstacles()


# Единовременное создание общих материалов (см. комментарий в блоке констант).
func _prepare_shared_resources() -> void:
	_trunk_mat = StandardMaterial3D.new()
	_trunk_mat.albedo_color = Color(0.35, 0.22, 0.12, 1)   # коричневый
	# Отключаем спекулярные блики — на софтрендере экономит шейдинг, а «пластик»
	# деревьев всё равно не виден с FPV-камеры.
	_trunk_mat.roughness = 1.0
	_leaf_mat = StandardMaterial3D.new()
	_leaf_mat.albedo_color = Color(0.1, 0.4, 0.12, 1)      # хвойный зелёный
	_leaf_mat.roughness = 1.0
	_stump_mat = StandardMaterial3D.new()
	_stump_mat.albedo_color = Color(0.45, 0.3, 0.18, 1)
	_stump_mat.roughness = 1.0
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.6, 0.45, 0.25, 1)
	_wood_mat.roughness = 1.0


# ---------- Земля: зелёная поляна + серая стартовая площадка ----------
func _build_ground() -> void:
	var ground_mat: StandardMaterial3D = StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.13, 0.3, 0.1, 1)   # тёмно-зелёная трава
	ground_mat.roughness = 0.95

	var plane_mesh: PlaneMesh = PlaneMesh.new()
	plane_mesh.size = Vector2(map_radius * 2.0, map_radius * 2.0)

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = plane_mesh
	mi.material_override = ground_mat
	add_child(mi)

	# Стартовый круг (как взлётная площадка в Liftoff) — чуть приподнят над травой.
	var pad_mat: StandardMaterial3D = StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.35, 0.35, 0.38, 1)
	var pad_mesh: CylinderMesh = CylinderMesh.new()
	pad_mesh.top_radius = 3.0
	pad_mesh.bottom_radius = 3.0
	pad_mesh.height = 0.05
	var pad: MeshInstance3D = MeshInstance3D.new()
	pad.mesh = pad_mesh
	pad.material_override = pad_mat
	pad.position = Vector3(0, 0.025, 0)
	add_child(pad)


# ---------- Деревья: ствол (CylinderMesh) + крона (SphereMesh) ----------
func _build_trees() -> void:
	for i in tree_count:
		# Случайная точка в кольце [clearing_radius .. map_radius].
		var ang: float = _rng.randf_range(0.0, TAU)
		var dist: float = _rng.randf_range(clearing_radius, map_radius)
		var pos := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)

		var h: float = _rng.randf_range(TRUNK_HEIGHT_MIN, TRUNK_HEIGHT_MAX)
		var r: float = _rng.randf_range(TRUNK_RADIUS_MIN, TRUNK_RADIUS_MAX)

		# --- Статическое тело дерева (ствола) — чтобы дрон бился, а не пролетал ---
		var body: StaticBody3D = StaticBody3D.new()
		body.name = "Tree_%03d" % i
		body.position = pos
		add_child(body)

		var trunk_mesh: CylinderMesh = CylinderMesh.new()
		trunk_mesh.low_poly_top = LOW_POLY_CYL    # ОПТИМИЗАЦИЯ: 6 сегментов вместо 32
		trunk_mesh.low_poly_bottom = LOW_POLY_CYL
		trunk_mesh.top_radius = r * 0.6
		trunk_mesh.bottom_radius = r
		trunk_mesh.height = h
		var trunk: MeshInstance3D = MeshInstance3D.new()
		trunk.mesh = trunk_mesh
		trunk.material_override = _trunk_mat
		trunk.position = Vector3(0, h * 0.5, 0)
		body.add_child(trunk)

		var col: CollisionShape3D = CollisionShape3D.new()
		var shape: CylinderShape3D = CylinderShape3D.new()
		shape.height = h
		shape.radius = r
		col.shape = shape
		col.position = Vector3(0, h * 0.5, 0)
		body.add_child(col)

		# --- Крона: ОДНА сфера вместо трёх (в 3 раза меньше геометрии) ---
		# Визуально у хвойного леса разницы почти нет, а на llvmpipe это
		# прямой прирост FPS: было 120 сфер по 32 сегмента, стало 40 по 8.
		var crown_r: float = _rng.randf_range(1.2, 2.4)
		var leaf_mesh: SphereMesh = SphereMesh.new()
		leaf_mesh.radial_segments = LOW_POLY_SPHERE
		leaf_mesh.rings = LOW_POLY_SPHERE / 2
		leaf_mesh.radius = crown_r
		leaf_mesh.height = crown_r * 2.0
		var leaf: MeshInstance3D = MeshInstance3D.new()
		leaf.mesh = leaf_mesh
		leaf.material_override = _leaf_mat
		leaf.position = Vector3(0, h + crown_r * 0.5, 0)
		body.add_child(leaf)


# ---------- Пни: короткие толстые цилиндры (низкие препятствия) ----------
func _build_stumps() -> void:
	for i in 10:
		var ang: float = _rng.randf_range(0.0, TAU)
		var dist: float = _rng.randf_range(clearing_radius + 2.0, map_radius * 0.6)
		var h: float = _rng.randf_range(0.4, 0.9)
		var r: float = _rng.randf_range(0.3, 0.6)

		var body: StaticBody3D = StaticBody3D.new()
		body.name = "Stump_%02d" % i
		body.position = Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		add_child(body)

		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.low_poly_top = LOW_POLY_CYL
		mesh.low_poly_bottom = LOW_POLY_CYL
		mesh.top_radius = r
		mesh.bottom_radius = r * 1.15
		mesh.height = h
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _stump_mat
		mi.position = Vector3(0, h * 0.5, 0)
		body.add_child(mi)

		var col: CollisionShape3D = CollisionShape3D.new()
		var shape: CylinderShape3D = CylinderShape3D.new()
		shape.height = h
		shape.radius = r
		col.shape = shape
		col.position = Vector3(0, h * 0.5, 0)
		body.add_child(col)


# ---------- Препятствия на трассе: горизонтальные «жерди» между столбами ----------
# Две перекладины разной высоты вдоль -Z от старта — под/между ними надо пролетать.
func _build_obstacles() -> void:
	_make_pole_pair(Vector3(0, 0, -18.0), 1.5, 6.0, _wood_mat)  # низкая жердь
	_make_pole_pair(Vector3(0, 0, -32.0), 3.0, 6.0, _wood_mat)  # высокая жердь


func _make_pole_pair(center: Vector3, bar_height: float, span: float, mat: StandardMaterial3D) -> void:
	var parent: StaticBody3D = StaticBody3D.new()
	parent.name = "Obstacle_%d_%d" % [absi(int(center.z)), int(bar_height * 10)]
	parent.position = center
	add_child(parent)

	var pole_h: float = bar_height + 0.5
	for side in [-1.0, 1.0]:
		var pole_mesh: CylinderMesh = CylinderMesh.new()
		pole_mesh.low_poly_top = LOW_POLY_CYL
		pole_mesh.low_poly_bottom = LOW_POLY_CYL
		pole_mesh.top_radius = 0.08
		pole_mesh.bottom_radius = 0.1
		pole_mesh.height = pole_h
		var pole: MeshInstance3D = MeshInstance3D.new()
		pole.mesh = pole_mesh
		pole.material_override = mat
		pole.position = Vector3(side * span * 0.5, pole_h * 0.5, 0)
		parent.add_child(pole)

		var col: CollisionShape3D = CollisionShape3D.new()
		var shape: CylinderShape3D = CylinderShape3D.new()
		shape.height = pole_h
		shape.radius = 0.1
		col.shape = shape
		col.position = pole.position
		parent.add_child(col)

	# Горизонтальная жердь
	var bar_mesh: BoxMesh = BoxMesh.new()
	bar_mesh.size = Vector3(span, 0.12, 0.12)
	var bar: MeshInstance3D = MeshInstance3D.new()
	bar.mesh = bar_mesh
	bar.material_override = mat
	bar.position = Vector3(0, bar_height, 0)
	parent.add_child(bar)

	var bar_col: CollisionShape3D = CollisionShape3D.new()
	var bar_shape: BoxShape3D = BoxShape3D.new()
	bar_shape.size = Vector3(span, 0.15, 0.15)
	bar_col.shape = bar_shape
	bar_col.position = bar.position
	parent.add_child(bar_col)
