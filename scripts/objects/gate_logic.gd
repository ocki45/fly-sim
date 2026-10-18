extends Area3D
# gate_logic.gd — логика гоночных ворот.
# Наследуется от Area3D: ворота — триггер-зона. Когда дрон (RigidBody3D с именем
# "Drone") пролетает сквозь них, срабатывает встроенный сигнал body_entered и
# в консоль печатается "PRINT: Gate passed!".

## Сигнал испускается каждый раз, когда через ворота пролетает дрон.
## Удобно подключать из трассы/таймера (например, для подсчёта кругов).
signal gate_passed(body: Node3D)


func _ready() -> void:
	# Страховка: убеждаемся, что Area3D действительно детектит тела (RigidBody3D).
	monitoring = true
	monitorable = true
	# В Godot 4 у Area3D есть встроенный сигнал body_entered — подключаем его
	# программно, чтобы не зависеть от ручной связи в редакторе.
	body_entered.connect(_on_body_entered)


# Вызывается автоматически, когда физическое тело входит в зону ворот.
func _on_body_entered(body: Node3D) -> void:
	# Реагируем только на дрон (по имени узла в дереве сцены).
	if body.name == "Drone":
		print("PRINT: Gate passed!")
		gate_passed.emit(body)
