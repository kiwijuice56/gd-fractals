extends Camera3D

func _process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")
	position += Vector3(direction.x, 0.0, direction.y) * delta * 0.5
