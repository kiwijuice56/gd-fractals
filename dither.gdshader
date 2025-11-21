// https://godotshaders.com/shader/simple-ordered-dithering-and-screen-pixelation/
shader_type canvas_item;
uniform sampler2D view: hint_screen_texture, filter_nearest, repeat_disable;
uniform float resolution_downsampling: hint_range(1.0, 8.0, 1.0);
uniform float bit_depth: hint_range(0.0, 64.0, 2.0);
const mat4 bayer_matrix_4x4 = mat4(
	vec4(    -0.5,       0.0,  -0.375,   0.125 ),
	vec4(    0.25,   -0.25,   0.375, - 0.125 ),
	vec4( -0.3125,  0.1875, -0.4375,  0.0625 ),
	vec4(  0.4375, -0.0625,  0.3125, -0.1875 )
);

void fragment() {
	vec2 UV_new = SCREEN_UV -  mod(SCREEN_UV, SCREEN_PIXEL_SIZE * resolution_downsampling);
	vec3 tex = texture(view, UV_new).rgb;
	vec2 pix_id = vec2(SCREEN_UV.x / (SCREEN_PIXEL_SIZE.x * resolution_downsampling), SCREEN_UV.y / (SCREEN_PIXEL_SIZE.y * resolution_downsampling));
	float bayer_shift = bayer_matrix_4x4[int(mod(pix_id.x, 4.0))][int(mod(pix_id.y, 4.0))];
	tex += vec3(bayer_shift / bit_depth);
	tex.r = round(tex.r * bit_depth-1.0) / (bit_depth-1.0);
	tex.g = round(tex.g * bit_depth-1.0) / (bit_depth-1.0);
	tex.b = round(tex.b * bit_depth-1.0) / (bit_depth-1.0);
	COLOR.rgb = tex.rgb;
	COLOR.a = 1.0;
}