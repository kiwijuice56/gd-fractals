shader_type canvas_item;

uniform sampler3D sdf_texture: repeat_enable, filter_nearest;
uniform float cycle_speed = 0.1;

void fragment() {
	COLOR = texture(sdf_texture, vec3(UV, cycle_speed * TIME));
}
