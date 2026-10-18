class_name DroneConfig
extends Resource
# Конфигурация дрона — data-driven подход: один класс физики, 5 разных конфигов.
# Все значения в СИ: кг, метры, Ньютон-метры, об/мин (RPM).

@export var drone_name: String = "Unnamed"           # Отображаемое имя дрона

# --- Масса и геометрия ---
@export var mass_kg: float = 0.6                     # Полётная масса с батареей, кг
@export var arm_length_m: float = 0.11               # Расстояние от центра до мотора, м

# --- Моторы и винты ---
@export var motor_kv: int = 1750                     # KV мотора (об/мин на вольт)
@export var battery_cells: int = 6                   # Количество ячеек S (1, 4, 6)
@export var propeller_size_inch: float = 5.0         # Диаметр пропеллера, дюймы
@export var propeller_pitch: float = 4.0             # Шаг пропеллера, дюймы

# --- Инерция ---
# Момент инерции по осям (roll, pitch, yaw), кг*м^2.
# Приближение: I ~ m * r^2 с поправками под класс дрона.
@export var moment_of_inertia: Vector3 = Vector3(0.002, 0.002, 0.003)

# --- Аэродинамика ---
@export var drag_coefficient: float = 0.05           # Линейное сопротивление, N/(m/s)
@export var quadratic_drag: float = 0.01             # Квадратичное сопротивление, N/(m/s)^2
@export var angular_drag: float = 0.02               # Сопротивление вращению, N*m/(rad/s)

# --- Тяга ---
@export var max_thrust_per_motor_n: float = 22.0     # Максимальная тяга одного мотора, N
@export var throttle_curve_exponent: float = 2.2     # Степень кривой газа (обычно 2.0-2.5)

# --- Динамика моторов ---
@export var motor_spinup_time: float = 0.15          # Время разгона мотора, с (торможение быстрее)
@export var gyro_effect_strength: float = 0.02       # Сила гироскопического эффекта

# --- Управление ---
@export var stick_expo: float = 0.25                 # Экспонента стиков (0.0-1.0)

# Вспомогательный метод: максимальные обороты мотора при полном газу.
# RPM_max = KV * Vmax, где Vmax ~ cells * 4.2 В (полный заряд LiPo/LiHV берём 4.2)
func get_max_rpm() -> float:
	return float(motor_kv) * float(battery_cells) * 4.2
