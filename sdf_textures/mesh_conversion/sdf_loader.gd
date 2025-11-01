class_name SDFLoader extends Object
# Loads signed distance field (SDF) files and converts them to 3D textures

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
