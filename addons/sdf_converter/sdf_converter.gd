@tool
class_name SdfConverter extends EditorPlugin
# Tool script to convert raw SDF files into Texture3D resources

signal process_completed

var pid: int = -1

var dock: Control
var generate_button: Button
var resolution_input: SpinBox
var input_path_input: LineEdit
var output_path_input: LineEdit

func _enter_tree() -> void:
	dock = Control.new()
	dock.name = "SDF Generator"
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.add_child(vbox)
	
	# Resolution input
	var res_label: Label = Label.new()
	res_label.text = "Resolution:"
	vbox.add_child(res_label)
	vbox
	
	resolution_input = SpinBox.new()
	resolution_input.min_value = 2
	resolution_input.max_value = 512
	resolution_input.step = 1
	resolution_input.value = 128
	vbox.add_child(resolution_input)
	
	# Input path
	var input_label: Label = Label.new()
	input_label.text = "Input Path (.obj):"
	vbox.add_child(input_label)
	
	input_path_input = LineEdit.new()
	input_path_input.placeholder_text = "Path to input .obj file (res://.../thing.obj)"
	vbox.add_child(input_path_input)
	
	# Output path
	var output_label: Label = Label.new()
	output_label.text = "Output Path (.res):"
	vbox.add_child(output_label)
	
	output_path_input = LineEdit.new()
	output_path_input.placeholder_text = "Path for output .res file (res://.../thing.res)"
	vbox.add_child(output_path_input)
	
	generate_button = Button.new()
	generate_button.text = "Generate SDF Texture"
	generate_button.pressed.connect(_on_generate_pressed)
	vbox.add_child(generate_button)
	
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)

func _on_generate_pressed() -> void:
	if input_path_input.text.is_empty() or output_path_input.text.is_empty():
		printerr("Input and output paths cannot be empty.")
		return
	if not input_path_input.text.ends_with(".obj") or not output_path_input.text.ends_with(".res"):
		printerr("Input and output paths should end with .obj and .res respectively.")
		return
	generate_button.disabled = true
	
	generate()

func generate() -> void:
	var script_path: String = ProjectSettings.globalize_path("res://addons/sdf_converter/obj_to_sdf.py")
	var obj_path: String = ProjectSettings.globalize_path(input_path_input.text)
	var resolution_string: String = str(int(resolution_input.value))
	
	if OS.get_name() == "Windows":
		var args: Array[String] = ["/C", "py", "-u", script_path, obj_path, resolution_string]
		pid = OS.create_process("cmd.exe", args, true)
	else: # NOTE: haven't tested because I don't run these platforms
		var cmd: String = "python3 -u '%s' %s %s" % [script_path, obj_path, resolution_string]
		pid = OS.create_process("x-terminal-emulator", ["-e", "bash", "-c", cmd], true)
	
	if pid != -1:
		print_rich("[color=777]Process started to generate .sdf file from .obj file.[/color]")
	else:
		printerr("Process failed to start.")

func check_for_completion() -> void:
	if pid == -1:
		return
	
	if not OS.is_process_running(pid):
		pid = -1
		
		print_rich("[color=#777]Process complete, now converting .sdf file to .res file[/color]")
		
		var res_path: String = ProjectSettings.globalize_path(output_path_input.text)
		var obj_path: String = ProjectSettings.globalize_path(input_path_input.text)
		var sdf_path: String = obj_path.replace(".obj", ".sdf")
		var texture: ImageTexture3D = load_sdf_texture(sdf_path, resolution_input.value)
		if texture == null:
			generate_button.disabled = false
			return
		
		ResourceSaver.save(texture, res_path)
		
		print_rich("[color=#777]Texture generation complete[/color]")
		
		generate_button.disabled = false

func _process(_delta: float) -> void:
	check_for_completion()

static func load_sdf_texture(path: String, texture_size: int = 64) -> ImageTexture3D:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	 
	if file == null:
		printerr(".sdf file not found, quitting.")
		return null
	
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
