@tool
class_name LoaderTool extends EditorScript
# Tool script to use SDFLoader within the editor

func _run() -> void:
	var texture: ImageTexture3D = SDFLoader.load_sdf_texture("res://sdf_textures/mesh_conversion/output/teto.sdf", 64)
	ResourceSaver.save(texture, "res://sdf_textures/teto.res")
