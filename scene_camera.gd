class_name SceneCamera extends Camera3D

func _process(delta: float) -> void:
	rotation.z += 0.2 * delta
