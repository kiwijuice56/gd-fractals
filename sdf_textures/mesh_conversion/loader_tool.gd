@tool
class_name LoaderTool extends EditorScript
# Tool script to convert raw SDF files into Texture3D resources

func _run() -> void:
	var file_name: String = "bunny"
	var resolution: int = 64
	var texture: ImageTexture3D = load_sdf_texture("res://sdf_textures/mesh_conversion/output/%s_%d.sdf" % [file_name, resolution], resolution)
	ResourceSaver.save(texture, "res://sdf_textures/%s_%d.res" % [file_name, resolution])

static func load_sdf_texture(path: String, texture_size: int = 64) -> ImageTexture3D:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	 
	var data: PackedByteArray = file.get_buffer(texture_size * texture_size * texture_size)
	file.close()
	 
	var images: Array[Image] = []
	var bytes_per_slice = texture_size * texture_size
	
	for z in range(texture_size):
		var start: int = z * bytes_per_slice
		var end: int = (z + 1) * bytes_per_slice
		var slice_data: PackedByteArray = data.slice(start, end)
		var img: Image= Image.create_from_data(texture_size, texture_size, false, Image.FORMAT_R8, slice_data)
		images.append(img)
	var texture: ImageTexture3D = ImageTexture3D.new()
	texture.create(Image.FORMAT_R8, texture_size, texture_size, texture_size, false, images)
	
	return texture
