extends RigidBody3D
class_name DronePhysics
# Физика квадрокоптера (Quad X). Без PID — прямой миксинг стиков в моторы.
# Данные берутся из DroneConfig (Resource), ввод — из autoload InputHandler.
# ВАЖНО: в сцене у RigidBody3D выставьте gravity_scale = 0 (сделано в main.tscn) —
# сила тяжести считается вручную из config.mass_kg, чтобы конфиг оставался
# единственным источником массы. Силы применяются в _integrate_forces() —
# это правильный способ для RigidBody3D в Godot 4.x (_physics_process задаёт
# кадр, интеграция движка происходит сразу после него).

@export var config: DroneConfig  # Конфиг дрона (.tres из /resources/drones/)

# Точки крепления моторов Quad X (дочерние Node3D в сцене):
@onready var motor_fl: Node3D = $MotorFL
@onready var motor_fr: Node3D = $MotorFR
@onready var motor_bl: Node3D = $MotorBL
@onready var motor_br: Node3D = $MotorBR

const GRAVITY := 9.81            # м/с^2
const MAX_RATE_ROLL_PITCH := deg_to_rad(400.0)  # Макс. угловая скорость по roll/pitch, рад/с
const MAX_RATE_YAW := deg_to_rad(250.0)          # Макс. угловая скорость по yaw, рад/с
const YAW_TORQUE_COEF := 0.08    # Коэффициент реактивного момента от дифф. тяги
const RATE_STIFFNESS := 15.0     # Резкость реакции стика (пропорц. момент доворота)

# Реальные обороты моторов (0..1 от максимума) — для асимметричного разгона
var _rpm_fl := 0.0
var _rpm_fr := 0.0
var _rpm_bl := 0.0
var _rpm_br := 0.0

# --- Телеметрия для OSD (обновляется каждый физический шаг) ---
var current_throttle: float = 0.0   # Сырой стик газа (0..1), до применения кривой
var current_voltage: float = 0.0    # Расчётное напряжение батареи с просадкой, В

func _ready() -> void:
	# Гравитацию движка не используем — применяем свою из config.mass_kg
	gravity_scale = 0.0
	# free_rotate удалён: в Godot 4 его нет (был только в Godot 3).
	# RigidBody3D всегда свободно вращается — нам это и нужно.
	can_sleep = false
	if config == null:
		push_error("DronePhysics: config не назначен!")

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if config == null:
		return
	# Явное указание типа float + берём шаг ПРЯМО из state (надёжнее, чем
	# get_physics_process_delta_time(): в некоторых сборках Godot тот возвращает 0).
	# maxf(...) гарантирует, что ноль никогда не попадёт в знаменатель.
	var delta: float = maxf(state.get_step(), 0.0001)  # Шаг физики (1/60 по умолчанию)

	# ---------- 1. Чтение ввода ----------
	# InputHandler уже применяет мёртвую зону и expo (ТЗ: формула в input_handler.gd).
	# Здесь expo НЕ повторяем — иначе кривая применится дважды и стики станут «ватными».
	var stick_roll := InputHandler.roll
	var stick_pitch := InputHandler.pitch
	var stick_yaw := InputHandler.yaw
	# Сохраняем сырой газ и расчётное напряжение для OSD (телеметрия)
	current_throttle = InputHandler.throttle
	current_voltage = _battery_voltage(current_throttle)
	var throttle := pow(InputHandler.throttle, config.throttle_curve_exponent)

	# ---------- 2. Миксер Quad X: целевые обороты каждого мотора ----------
	# Знаки для Quad X (X-образная рама, моторы по диагоналям):
	#   FL(+) = газ + pitch + roll - yaw
	#   FR(-) = газ + pitch - roll + yaw
	#   BL(-) = газ - pitch + roll + yaw
	#   BR(+) = газ - pitch - roll - yaw
	# Микшер с headroom: отклонения стиков делят свободный диапазон (1 - газ),
	# поэтому суммарная тяга на зависании не «съедается» и не обнуляется при
	# полном стике (раньше clampf глушил моторы диагонали -> дрон падал).
	var t_fl := clampf(throttle + (1.0 - throttle) * (stick_pitch + stick_roll - stick_yaw), 0.0, 1.0)
	var t_fr := clampf(throttle + (1.0 - throttle) * (stick_pitch - stick_roll + stick_yaw), 0.0, 1.0)
	var t_bl := clampf(throttle + (1.0 - throttle) * (-stick_pitch + stick_roll + stick_yaw), 0.0, 1.0)
	var t_br := clampf(throttle + (1.0 - throttle) * (-stick_pitch - stick_roll - stick_yaw), 0.0, 1.0)

	# ---------- 3. Инерция моторов (разгон медленнее торможения) ----------
	_rpm_fl = _spin_motor(_rpm_fl, t_fl, delta)
	_rpm_fr = _spin_motor(_rpm_fr, t_fr, delta)
	_rpm_bl = _spin_motor(_rpm_bl, t_bl, delta)
	_rpm_br = _spin_motor(_rpm_br, t_br, delta)

	# ---------- 4. Тяга каждого мотора: thrust = max_thrust * rpm^2 ----------
	# (rpm нормированы 0..1, поэтому квадрат относительных оборотов)
	# Явные типы float во всей цепочке — чтобы компилятор гарантированно
	# выводил типы (исключает ошибку "Cannot infer the type ...").
	var f_fl: float = config.max_thrust_per_motor_n * _rpm_fl * _rpm_fl
	var f_fr: float = config.max_thrust_per_motor_n * _rpm_fr * _rpm_fr
	var f_bl: float = config.max_thrust_per_motor_n * _rpm_bl * _rpm_bl
	var f_br: float = config.max_thrust_per_motor_n * _rpm_br * _rpm_br
	var total_thrust: float = f_fl + f_fr + f_bl + f_br

	# ---------- 5. Сила тяги в мировой системе координат ----------
	var local_up: Vector3 = Vector3(0, 1, 0)  # локальная +Y дрона = «вверх»
	# В Godot 4 у Basis НЕТ метода .xform() — правильный способ: оператор *
	var global_transform_basis: Basis = state.transform.basis
	var thrust_force_world: Vector3 = (global_transform_basis * local_up) * total_thrust
	# Собственная гравитация (массу RigidBody берём из конфига)
	var gravity_force := Vector3(0, -config.mass_kg * GRAVITY, 0)

	# ---------- 6. Моменты сил от дифференциальной тяги (плечо = arm_length) ----------
	# В локальных осях Godot: +X = наклон вправо (roll right), +Y = yaw влево (CCW сверху),
	# +Z = nose up. Знаки подобраны так, что стик вправо/вверх даёт наклон вправо/nose down —
	# как у реального дрона в Acro-режиме (полный стик = быстрый флип).
	var a := config.arm_length_m * 0.7071  # Проекция плеча на оси X/Z (моторы на диагоналях)
	var torque_roll := -(f_fl + f_bl - f_fr - f_br) * a    # правые моторы сильнее -> наклон вправо
	var torque_pitch := -(f_fl + f_fr - f_bl - f_br) * a   # передние сильнее -> nose down
	# Yaw: диагональные пары вращаются в одну сторону (CW: FL+BR, CCW: FR+BL).
	# Реактивный момент от дисбаланса пар:
	var torque_yaw := -(f_fr + f_bl - f_fl - f_br) * YAW_TORQUE_COEF

	# ---------- 7. Гирроскопический эффект (параметр) ----------
	# Общая раскрутка винтов используется ниже в блоке гиропрецессии.
	var spin_total := _rpm_fl + _rpm_fr + _rpm_bl + _rpm_br  # (0..4)

	# ---------- 8. Аэродинамическое сопротивление поступательного движения ----------
	var vel := state.linear_velocity
	var speed := vel.length()
	# Линейное + квадратичное сопротивление, направлено против скорости.
	# Ограничение — по Ускорению (макс. decel = тяга/масса), а не «силой ≤ вес»:
	# для лёгких дронов (whoop 30 г) старое ограничение глушило тягу и дрон
	# не мог взлететь даже на 100% газа.
	var max_drag_accel_n: float = (4.0 * config.max_thrust_per_motor_n)  # Н = m*a_max
	var drag_mag := config.drag_coefficient * speed + config.quadratic_drag * speed * speed
	drag_mag = minf(drag_mag, max_drag_accel_n)
	var drag_force := -vel.normalized() * drag_mag if speed > 0.01 else Vector3.ZERO

	# ---------- 9. Rate-контроллер (стабилизатор угловой скорости) ----------
	# ВАЖНО: это НЕ PID в понимании Betaflight — это один пропорциональный (P)
	# закон, удерживающий угловую скорость вокруг стик-команды. Без него чистый
	# микшер разгоняет дрон до тысяч °/с (нет физического демпфирования), и
	# dependent от шага интегрирования — численная неустойчивость (NaN).
	# Все величины считаются В ЛОКАЛЬНЫХ осях дрона (момент инерции диагонален).
	var ang_local := global_transform_basis.transposed() * state.angular_velocity
	# Целевые угловые скорости: sign согласован со знаками моментов блока 6.
	var desired_ang_local := Vector3(
		stick_roll * MAX_RATE_ROLL_PITCH,   # +X = наклон вправо
		stick_yaw * MAX_RATE_YAW,           # +Y = yaw по часовой (справа вверх)
		-stick_pitch * MAX_RATE_ROLL_PITCH  # -Z = nose down при стике вверх
	)
	var inertia := config.moment_of_inertia
	# Суммарный локальный момент: физика + управление + демпфирование + гиро
	var total_torque_local := Vector3(torque_roll, torque_yaw, torque_pitch)
	for axis in 3:
		var i_axis: float = [inertia.x, inertia.y, inertia.z][axis]
		var err := desired_ang_local[axis] - ang_local[axis]
		total_torque_local[axis] += err * i_axis * RATE_STIFFNESS  # P-доворот до цели
		total_torque_local[axis] -= ang_local[axis] * config.angular_drag  # затухание
	# Гиропрецессия от момента импульса винтов (блок 7): наклон по X порождает
	# момент вокруг Z и наоборот (перекрёстное произведение L и omega корпуса).
	total_torque_local.x += -spin_total * config.gyro_effect_strength * ang_local.z
	total_torque_local.z += spin_total * config.gyro_effect_strength * ang_local.x

	# ---------- 9b. ЧИСЛЕННАЯ УСТОЙЧИВОСТЬ ----------
	# Явный Эйлер для вращения неустойчив, когда жёсткость контроллера велика
	# относительно момента инерции и шага интегрирования: условие устойчивости
	# явной схемы dt < 2*I/K. Godot может давать большие шаги (просадки кадров),
	# поэтому ограничиваем эффективную жёсткость под текущий шаг...
	var min_i: float = minf(minf(inertia.x, inertia.y), inertia.z)
	# ИСПРАВЛЕНИЕ: step_delta был необъявлен (Parse Error). Шаг физики — delta из начала функции.
	var eff_stiffness: float = minf(RATE_STIFFNESS, 1.8 * min_i / maxf(delta, 0.0001))
	# ...и пересчитывательную часть момента с ней (демпфер остаётся как есть).
	for axis in 3:
		var i_axis2: float = [inertia.x, inertia.y, inertia.z][axis]
		var err2 := desired_ang_local[axis] - ang_local[axis]
		total_torque_local[axis] += err2 * i_axis2 * (eff_stiffness - RATE_STIFFNESS)

	# Жёсткий предохранитель: реальные FPV-дроны не вращаются быстрее ~600°/s.
	var max_rate_hard: float = deg_to_rad(600.0)
	if absf(ang_local.x) > max_rate_hard or absf(ang_local.y) > max_rate_hard \
			or absf(ang_local.z) > max_rate_hard:
		ang_local.x = clampf(ang_local.x, -max_rate_hard, max_rate_hard)
		ang_local.y = clampf(ang_local.y, -max_rate_hard, max_rate_hard)
		ang_local.z = clampf(ang_local.z, -max_rate_hard, max_rate_hard)
		# Синхронизируем состояние движка: в Godot 4 это свойства объекта
		# state (PhysicsDirectBodyState3D), а НЕ свойства узла RigidBody3D.
		# Иначе следующий физический шаг унаследует «взрывную» скорость.
		state.angular_velocity = global_transform_basis * ang_local

	# Перевод локального момента в мировые координаты: Basis * vector (Godot 4)
	# (объявлена ровно один раз — ранее была ошибка дублирования объявления)
	var torque_world := global_transform_basis * total_torque_local

	# ---------- 10. Применение сил и моментов ----------
	# ВАЖНО (Godot 4.x!): у PhysicsDirectBodyState3D НЕТ методов add_force /
	# add_torque (это синтаксис Godot 3). Правильный API Godot 4:
	#   apply_central_force() — сила через центр масс (в мировых координатах)
	#   apply_torque()        — непрерывный момент (Н*м), движок сам домножит на шаг
	var total_force: Vector3 = thrust_force_world + gravity_force + drag_force
	state.apply_central_force(total_force)
	state.apply_torque(torque_world)

	# ---------- 11. Автозапуск: сброс при падении ниже земли ----------
	if state.transform.origin.y < -5.0:
		state.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0))
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO

# Асимметричный разгон/торможение мотора.
# target — целевые нормированные обороты (0..1), возвращает новые (0..1).
func _spin_motor(current: float, target: float, delta: float) -> float:
	# Разгон: tau = motor_spinup_time. Торможение: в 2 раза быстрее (нет нагрузки тягой)
	var tau := config.motor_spinup_time if target > current else config.motor_spinup_time * 0.5
	# Экспоненциальное приближение к цели (сглаживание первого порядка)
	var alpha := 1.0 - exp(-delta / maxf(tau, 0.001))
	return lerpf(current, target, alpha)

# Упрощённая модель батареи для OSD: номинал ячеек минус просадка от тока.
func _battery_voltage(throttle: float) -> float:
	const CELL_FULL_V := 4.2       # В на ячейку (полный заряд LiPo)
	const CELL_SAG_OHMS := 0.012   # Внутреннее сопротивление ячейки, Ом
	const LOAD_CURRENT_A := 60.0   # Ток при 100% газа, А
	var cells := float(config.battery_cells)
	var sag := throttle * LOAD_CURRENT_A * CELL_SAG_OHMS * cells
	return cells * CELL_FULL_V - sag

# Телеметрия для OSD (Задача 3): словарь с напряжением, газом и скоростью.
func get_telemetry() -> Dictionary:
	return {
		"voltage": current_voltage,          # В, расчётное с просадкой
		"throttle": current_throttle,        # 0..1, сырой стик газа
		"speed": linear_velocity.length(),   # м/с относительно земли
	}
