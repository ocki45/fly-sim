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

func _ready() -> void:
	# Гравитацию движка не используем — применяем свою из config.mass_kg
	gravity_scale = 0.0
	free_rotate = true
	can_sleep = false
	if config == null:
		push_error("DronePhysics: config не назначен!")

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if config == null:
		return
	var delta := get_physics_process_delta_time()  # Шаг физики (1/60 при настройках по умолчанию)

	# ---------- 1. Чтение ввода ----------
	# InputHandler отдаёт линейные значения; expo применяем здесь через config
	var expo := config.stick_expo
	var stick_roll := InputHandler.apply_expo(InputHandler.roll, expo)
	var stick_pitch := InputHandler.apply_expo(InputHandler.pitch, expo)
	var stick_yaw := InputHandler.apply_expo(InputHandler.yaw, expo)
	var throttle := pow(InputHandler.throttle, config.throttle_curve_exponent)

	# ---------- 2. Миксер Quad X: целевые обороты каждого мотора ----------
	# Знаки для Quad X (X-образная рама, моторы по диагоналям):
	#   FL(+) = газ + pitch + roll - yaw
	#   FR(-) = газ + pitch - roll + yaw
	#   BL(-) = газ - pitch + roll + yaw
	#   BR(+) = газ - pitch - roll - yaw
	var t_fl := clampf(throttle + stick_pitch + stick_roll - stick_yaw, 0.0, 1.0)
	var t_fr := clampf(throttle + stick_pitch - stick_roll + stick_yaw, 0.0, 1.0)
	var t_bl := clampf(throttle - stick_pitch + stick_roll + stick_yaw, 0.0, 1.0)
	var t_br := clampf(throttle - stick_pitch - stick_roll - stick_yaw, 0.0, 1.0)

	# ---------- 3. Инерция моторов (разгон медленнее торможения) ----------
	_rpm_fl = _spin_motor(_rpm_fl, t_fl, delta)
	_rpm_fr = _spin_motor(_rpm_fr, t_fr, delta)
	_rpm_bl = _spin_motor(_rpm_bl, t_bl, delta)
	_rpm_br = _spin_motor(_rpm_br, t_br, delta)

	# ---------- 4. Тяга каждого мотора: thrust = max_thrust * rpm^2 ----------
	# (rpm нормированы 0..1, поэтому квадрат относительных оборотов)
	var f_fl := config.max_thrust_per_motor_n * _rpm_fl * _rpm_fl
	var f_fr := config.max_thrust_per_motor_n * _rpm_fr * _rpm_fr
	var f_bl := config.max_thrust_per_motor_n * _rpm_bl * _rpm_bl
	var f_br := config.max_thrust_per_motor_n * _rpm_br * _rpm_br
	var total_thrust := f_fl + f_fr + f_bl + f_br

	# ---------- 5. Сила тяги в локальной системе дрона (локальная +Y вверх) ----------
	var local_up := Vector3(0, 1, 0)
	var global_transform_basis := state.transform.basis
	var thrust_force_world := global_transform_basis.xform(local_up) * total_thrust
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
	# Линейное + квадратичное сопротивление, направлено против скорости
	var drag_mag := config.drag_coefficient * speed + config.quadratic_drag * speed * speed
	var drag_force := -vel.normalized() * drag_mag if speed > 0.01 else Vector3.ZERO

	# ---------- 9. Управление угловой скоростью (rate-model без PID) ----------
	var ang_vel := state.angular_velocity
	# Моторы уже дают физический момент от миксера; сюда добавляем упругую
	# "стабилизацию" вокруг текущей стик-команды, чтобы дрон не закручивался
	# бесконечно и адекватно реагировал на мелкие возмущения.
	# Целевые угловые скорости: sign согласован со знаками моментов блока 6.
	var desired_ang := Vector3(
		stick_roll * MAX_RATE_ROLL_PITCH,   # +X = наклон вправо
		stick_yaw * MAX_RATE_YAW,           # +Y = yaw по часовой (справа вверх)
		-stick_pitch * MAX_RATE_ROLL_PITCH  # -Z = nose down при стике вверх
	)
	# Пропорциональный момент доворота к целевой скорости вращения
	var inertia := config.moment_of_inertia
	var rate_error := desired_ang - ang_vel
	var control_torque_local := Vector3(
		rate_error.x * inertia.x * RATE_STIFFNESS,
		rate_error.y * inertia.y * RATE_STIFFNESS,
		rate_error.z * inertia.z * RATE_STIFFNESS
	)
	# Угловое сопротивление (естественное затухание)
	var ang_damp := -ang_vel * config.angular_drag

	# Гиропрецессия от суммарного момента импульса винтов (см. блок 7):
	# наклон с скоростью ang_vel.z порождает момент вокруг X и наоборот.
	var gyro_torque_local := Vector3(
		-spin_total * config.gyro_effect_strength * ang_vel.z,
		0.0,
		spin_total * config.gyro_effect_strength * ang_vel.x
	)

	var torque_local := Vector3(torque_roll, torque_yaw, torque_pitch) \
		+ gyro_torque_local + control_torque_local + ang_damp
	var torque_world := global_transform_basis.xform(torque_local)

	# ---------- 10. Применение сил и моментов ----------
	state.add_force(thrust_force_world + gravity_force + drag_force)
	state.add_torque(torque_world)

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
