@tool 
class_name RenderingPlane extends MeshInstance3D

@export var camera: Camera3D 

func _process(_delta: float) -> void:
	set_instance_shader_parameter("_frac_pos", global_position)
	material_override.set_shader_parameter("_fov", camera.fov)
	material_override.set_shader_parameter("_cam_mat", camera.global_transform.basis)
	material_override.set_shader_parameter("_aspect_ratio", float(get_window().size.x) / get_window().size.y)
