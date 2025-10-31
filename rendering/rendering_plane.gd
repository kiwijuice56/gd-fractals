@tool 
class_name RenderingPlane extends MeshInstance3D

@export var camera: Camera3D 

func _process(_delta: float) -> void:
	set_instance_shader_parameter("_position", global_position)
	set_instance_shader_parameter("_scale", scale.x) # Assumes uniform scaling
	set_instance_shader_parameter("_rotation", rotation)
	
	var target_camera: Camera3D = camera
	if not is_instance_valid(target_camera):
		target_camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	
	material_override.set_shader_parameter("_fov", target_camera.fov)
	material_override.set_shader_parameter("_cam_mat", target_camera.global_transform.basis)
