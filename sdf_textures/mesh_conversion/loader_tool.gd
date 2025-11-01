@tool
class_name LoaderTool extends EditorScript
# Tool script to use SDFLoader within the editor

func _run() -> void:
	var file_name: String = "teto_64"
	var texture: ImageTexture3D = SDFLoader.load_sdf_texture("res://sdf_textures/mesh_conversion/output/" + file_name + ".sdf", 64)
	ResourceSaver.save(texture, "res://sdf_textures/" + file_name + ".res")
