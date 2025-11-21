extends MeshInstance3D

func _process(delta: float) -> void:
	rotate_y(delta * 0.1)
