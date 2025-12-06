shader_type spatial;
render_mode unshaded, depth_draw_opaque;

// A simplified version of raymarcher.gdshader without the mesh capabilities

// Use this if you want to use the secondary fractals by themselves --
// the mesh shader is very performance intensive, so you can get a lot more detail
// by using this shader

// Some constants that you probably don't need to change
const float MAX_DISTANCE = 10000.0; // Placeholder value for infinitely far away distances
const float BOUNCE_EPSILON_MULTIPLIER = 4.0; // Controls how far a ray should move away from a surface to prevent artifacts during shadows/bounces
const float SHADOW_EPSILON_MULTIPLIER = 4.0;
const float DR_MIX = 0.4;
const float DR_SCALAR = 3.0;
const int SUB_RAY_DIVIDER = 3;
const float PLANE_SCALE = 4.0;

group_uniforms raymarching;
uniform int primary_max_iterations = 128; // Max iterations any ray can march
uniform int max_bounces = 1; // Max times a ray can be reflected
uniform float collision_threshold = 0.015; // Min distance a ray can be from a surface for it to collide
uniform float normal_sample_length = 0.015; // How far along a collided surface to move when sampling for a normal
uniform float march_proportion : hint_range(0.0, 1.0) = 0.2; // Controls how far along the distance to advance the ray each step (lower = less artifacts, worse performance)
uniform float runaway_threshold = 5.0; // Distance where a ray is considered far enough to stop iteration
uniform float bounding_radius = 1.0; // Radius of the sphere bounding the entire scene (tighter = better performance)

group_uniforms fractal;
uniform int fractal_iterations = 8; // Max iterations of the fractal algoritms
uniform vec4 fractal_color_1: source_color = vec4(0.6, 0.0, 0.5, 1.0);
uniform vec4 fractal_color_2: source_color = vec4(0.0, 0.3, 0.2, 1.0);
uniform float animation_speed = 1.0;
uniform float animation_intensity = 0.3; // Strength of the animations
uniform vec3 secondary_fractal_offset = vec3(-1.2, 0.0, 0.0);
uniform vec3 secondary_fractal_scale = vec3(0.333, 0.25, 0.333);
uniform int secondary_fractal_option: hint_enum("Mandelbulb", "Mandelbox", "Julia", "Sierpinski", "Mengersponge", "Brocolli") = 0;

group_uniforms mandelbulb;
uniform float mandelbulb_power = 8.0;
uniform float mandelbulb_runaway_threshold = 2.0;
uniform vec3 color_center_point = vec3(0.0, 0.5, -0.5); // Color parameters for fractal algorithms
uniform float color_balance: hint_range(0.0, 1.0) = 0.5; // Sliding scale for the two fractal colors (mandelbulb only)

group_uniforms mandebox;
uniform float mandelbox_scale = 3.0;

group_uniforms julia;
uniform vec4 julia_center = vec4(0.0, -0.3, 0.3, -0.6);
uniform float julia_runaway_threshold = 2.0;

group_uniforms sierpinski;
uniform float sierpinski_scale = 1.1;

group_uniforms brocolli;
uniform vec3 brocolli_offset = vec3 (2.0, 4.8, 0.0);
uniform float brocolli_runaway_threshold = 32.0;

group_uniforms shape_modulus;
uniform int versor_type : hint_enum("Noise", "Points") = 0;
uniform float color_frequency = 4.0;
uniform float alpha = 3.15; // "cutoff" value of the fractal
uniform float beta = -0.135; // "thickness" of fractal surface
uniform sampler3D noise: repeat_enable, filter_linear; // Used to give surface fractal-like detail
uniform float noise_frequency = 2.0;
uniform vec3 portal_center_1 = vec3(0.5, 0.6, 0.0); // Position of the portal
uniform vec3 portal_offset_1 = vec3(0.45, 0.6, 0.2); // Position that the portal should teleport to
uniform float portal_radius_1 = 0.3;
uniform float portal_scale_1 = 4.0;
uniform vec4 point1;
uniform vec4 point2;
uniform vec4 point3;

group_uniforms mesh;
uniform sampler3D sdf_texture: repeat_disable, filter_linear; // Signed distance function

// "real" shadows are calculated by bouncing rays in the direction of the light source
// "fake" shadows are calculated by comparing normals with the light direction
// Although ideally "real" shadows are the only necessary ones, having fake shadows can
// make details in the surface show and service when there are performance constraints
group_uniforms lighting;
uniform vec3 light_direction = vec3(0.0, -1.0, 0.0); // Should be synced in GDscript to some DirectionalLight3D
uniform float smoothness = 24.0;
uniform float reflectivity = 0.25;
uniform vec3 specular_color: source_color = vec3(1.0, 1.0, 1.0);
uniform float specular_ratio : hint_range(0.0, 1.0) = 1.0;
uniform bool real_shadows_enabled = true;
uniform float fake_shadow_darkness : hint_range(0.0, 1.0) = 0.75;
uniform float real_shadow_darkness : hint_range(0.0, 1.0) = 0.65;
uniform vec3 shadow_absorption = vec3(1.2, 1.1, 1.0);
uniform float shadow_softness : hint_range(0.0, 1.0) = 0.416;

group_uniforms scene;
uniform vec4 clear_color: source_color;

void vertex() {
    // Billboard
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		MAIN_CAM_INV_VIEW_MATRIX[0],
		MAIN_CAM_INV_VIEW_MATRIX[1],
		MAIN_CAM_INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	VERTEX.xy *= PLANE_SCALE; // Multiplier to cover entire screen
}

vec4 quat_mul(vec4 q1, vec4 q2) {
	vec3 v1 = q1.xyz;
	vec3 v2 = q2.xyz;
	float w1 = q1.w;
	float w2 = q2.w;

	return vec4(
		w1 * v2 + w2 * v1 + cross(v1, v2),
		w1 * w2 - dot(v1, v2)
	);
}

// Returns the time value that a ray intersects with a sphere
float intersect_sphere(vec3 ray_pos, vec3 ray_dir, float radius) {
	float b = dot(ray_pos, ray_dir);
	float c = dot(ray_pos, ray_pos) - radius * radius;
	float h = b * b - c;

	if (h < 0.0) {
		return -1.0;
	}

	return -b - sqrt(h);
}

void sphere_fold(inout vec3 p, inout float dz) {
	float r2 = max(0.25, p.x * p.x + p.y * p.y + p.z * p.z);
	if (r2 < 0.5) {
		p *= 0.5 / r2;
		dz *= 0.5 / r2;
	}
}

void box_fold(inout vec3 p) {
	p = clamp(p, -0.5, 0.5) * 2.0 - p;
}

// http://blog.hvidtfeldts.net/index.php/2011/11/distance-estimated-3d-fractals-vi-the-mandelbox/
float mandelbox_DE(vec3 p, inout vec3 collision_info) {
	float dz = 1.0;
	vec3 original = p;
	float scale = sin(TIME * animation_speed) * animation_intensity * mandelbox_scale + mandelbox_scale * 2.0;
	for (int i = 0; i < 10; i++) {
		box_fold(p);
		sphere_fold(p, dz);
		p = p * scale + original;
		dz = dz * scale + 1.0;
	}
	return length(p) / dz;
}

// http://blog.hvidtfeldts.net/index.php/2011/08/distance-estimated-3d-fractals-iii-folding-space/
float tetrahedron_DE(vec3 p, inout vec3 collision_info) {
	vec3 offset = vec3(1.0);
	float scale = sierpinski_scale + sin(TIME * animation_speed) * animation_intensity * 0.1;
	for (int i = 0; i < fractal_iterations; i++) {
		if(p.x + p.y < 0.0) p.xy = -p.yx; // fold 1
		if(p.x + p.z < 0.0) p.xz = -p.zx; // fold 2
		if(p.y + p.z < 0.0) p.zy = -p.yz; // fold 3
		p = p * scale - offset * (scale - 1.0);
	}
	return length(p) * pow(scale, -16.0);
}

mat2 rotate(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat2(vec2(c, -s), vec2(s, c));
}

// https://github.com/pedrotrschneider/shader-fractals/blob/main/3D/MengerBrocolli.glsl
float brocolli_DE(vec3 z, inout vec3 collision_info) {
	float brocolli_scale = 0.7 + sin(animation_speed * TIME) * 0.1 + 0.9;
	vec3 anim_brocolli_offset = brocolli_offset + animation_intensity * sin(animation_speed * TIME * 0.2) * vec3(0.2, 0.3, 0.1);

	float r = length(z);
	int n = 0;
	for (; n < fractal_iterations; n++) {
		if (r > brocolli_runaway_threshold) break;
		z.x = abs (z.x);
		z.y = abs (z.y);
		z.z = abs (z.z);

		if (z.x - z.y < 0.0) z.xy = z.yx; // fold 1
		if (z.x - z.z < 0.0) z.xz = z.zx; // fold 2
		if (z.y - z.z < 0.0) z.zy = z.yz; // fold 3

		z.yx *= rotate(0.436332 + sin(animation_speed * TIME * 0.9) * 0.1 + 4.9);

		z.x = z.x * brocolli_scale - anim_brocolli_offset.x * (brocolli_scale - 1.0);
		z.y = z.y * brocolli_scale - anim_brocolli_offset.y * (brocolli_scale - 1.0);
		z.z = z.z * brocolli_scale;

		if (z.z > 0.25 * anim_brocolli_offset.z * (brocolli_scale - 1.0)) {
			z.z -= anim_brocolli_offset.z * (brocolli_scale - 1.0);
		}

		r = length (z);
		collision_info.r = min(collision_info.r, length(z - color_center_point));
	}

	return (length(z) - 2.0) * pow(brocolli_scale, -float(n));
}

// http://www.fractalforums.com/ifs-iterated-function-systems/revenge-of-the-half-eaten-menger-sponge/15/
float mengersponge_DE(vec3 p, inout vec3 collision_info) { // by recursively digging a box
	// Center the fractal
	p = p * 0.5 + 0.5;
	vec3 q = abs(p - 0.5) - 0.5;
	float d1 = max(q.x, max(q.y, q.z)); // distance to the box
	float d = d1; // current computed distance
	float scale = 1.0 ;
	for (int i = 0; i < fractal_iterations; i++) {
		vec3 pa = mod(p * 3.0 * scale, 3.0);
		scale *= 3.0;
		q = vec3(0.5) - abs(pa - 1.5);
		d1 = min(max(q.x, q.z), min(max(q.x, q.y), max(q.y, q.z))) / scale; //distance inside the 3 axis-aligned square tubes
		d = max(d, d1); //intersection
	}
	return d;
}

// Distance estimate for a mandelbulb fractal
// http://blog.hvidtfeldts.net/index.php/2011/09/distance-estimated-3d-fractals-v-the-mandelbulb-different-de-approximations/
// https://iquilezles.org/articles/ftrapsgeometric/
float mandelbulb_DE(vec3 p, inout vec3 collision_info) {
	vec3 x = p;
	float r = 0.0;
	float dr = 1.0;
	float animated_power = mandelbulb_power + animation_intensity * sin(animation_speed * TIME) * 4.0;
	for (int i = 0; i < fractal_iterations; i++) {
		r = length(x);
		if (r > mandelbulb_runaway_threshold) {
			break;
		}
		dr = pow(r, animated_power - 1.0) * animated_power * dr;

		float theta = acos(x.z / r);
		float phi = atan(x.y, x.x);
		theta = theta * animated_power;
		phi = phi * animated_power;
		x = p + pow(r, animated_power) * vec3(sin(theta) * cos(phi), sin(phi) * sin(theta), cos(theta));
		collision_info.r = min(collision_info.r, length(x - color_center_point));
	}
	collision_info.r *= color_balance;
	return 0.5 * log(r) * r / dr;
}

float julia_DE(vec3 p, inout vec3 collision_info) {
	vec4 x = vec4(p.x, p.z, p.y, p.x + p.z); // This ordering is arbitrary
	vec4 center = julia_center + vec4(sin(TIME * animation_speed)) * animation_intensity;
	float r = 0.0;
	float dr = 1.0;

	for (int i = 0; i < fractal_iterations; i++) {
		r = length(x);
		if (r > julia_runaway_threshold) {
			break;
		}
		dr = 2.0 * r * dr + 1.0;

		// Quaternion multiplication
		x = center + vec4(
			pow(x.w, 2) - pow(x.x, 2) - pow(x.y, 2) - pow(x.z, 2),
			2.0 * x.w * x.x,
			2.0 * x.w * x.y,
			2.0 * x.w * x.z
		);
	}
	return 0.5 * r * log(r) / dr;
}

// Distance estimate read from a .sdf texture (converted to a 3D texture resource)
float mesh_DE(vec3 p, inout vec3 collision_info) {
	return texture(sdf_texture, p).r * 2.0 - 1.0;
}

float mesh_fractal_DE(vec3 p, inout vec3 collision_info) {
	// Center the fractal around the origin (mesh_DE is offset)
	vec4 x = vec4(p + vec3(0.5), 0.0);
	float r = 0.0;
	float dr = 1.0;
	float animated_beta = beta + animation_intensity * 0.01 * sin(animation_speed * TIME) - 0.01;

	for (int i = 0; i < fractal_iterations; i++) {
		r = length(x);
		float dist_to_portal_1 = length(x.xyz - portal_center_1);
		if (dist_to_portal_1 <= portal_radius_1) {
			x.xyz = dist_to_portal_1 * normalize(x.xyz - portal_center_1) * portal_scale_1 + portal_offset_1;
			dr *= portal_scale_1;
		} else {
			vec3 D;

			if (versor_type == 0) {
				D = normalize(texture(noise, animation_intensity * sin(animation_speed * vec3(0.2, 0.3, 0.2) * TIME) + noise_frequency * x.xyz).rgb);
			} else if (versor_type == 1) {
				D = normalize(quat_mul(x - point1, quat_mul(x - point2, x - point3)).xyz);
			}

			vec3 _garbage;
			float R = exp(alpha * (mesh_DE(x.xyz, _garbage) + animated_beta));
			x.xyz = D * R;
			dr *= alpha * R * DR_SCALAR;
			dr = mix(dr, sqrt(dr), DR_MIX); // More resistant to noise, but hacky
			collision_info.r += color_frequency * exp(D.x);
		}
	}
	return length(x) / dr;
}

float world_DE(vec3 p, inout vec3 collision_info) {
	// Collision info inputs
	collision_info = vec3(1.0, MAX_DISTANCE, 0.0);
	float secondary_fractal_dist = MAX_DISTANCE;

	switch (secondary_fractal_option) {
		case 0: secondary_fractal_dist = mandelbulb_DE((p - secondary_fractal_offset) / secondary_fractal_scale, collision_info); break;
		case 1: secondary_fractal_dist = mandelbox_DE((p - secondary_fractal_offset) / secondary_fractal_scale, collision_info); break;
		case 2: secondary_fractal_dist = julia_DE((p - secondary_fractal_offset) / secondary_fractal_scale, collision_info); break;
		case 3: secondary_fractal_dist = tetrahedron_DE((p - secondary_fractal_offset) / secondary_fractal_scale, collision_info); break;
		case 4: secondary_fractal_dist = mengersponge_DE((p - secondary_fractal_offset) / secondary_fractal_scale, collision_info); break;
		case 5: secondary_fractal_dist = brocolli_DE((p - secondary_fractal_offset) / secondary_fractal_scale, collision_info); break;
	}

	return secondary_fractal_scale.x * secondary_fractal_dist;
}

// Advances a ray along the world distance estimate
int march(int max_iterations, inout vec3 ray_pos, vec3 ray_dir, inout vec3 collision_info) {
	int iter = 0;
	for (; iter < max_iterations; iter++) {
		float dist = abs(world_DE(ray_pos, collision_info));

		ray_pos += ray_dir * dist * march_proportion;

		if (dist > runaway_threshold) {
			iter = max_iterations;
			break;
		}

		if (dist < collision_threshold) {
			break;
		}
	}
	return iter;
}

vec3 get_normal(vec3 ray_pos) {
	vec3 _garbage;
	return normalize(vec3(
		world_DE(ray_pos + vec3(normal_sample_length, 0.0, 0.0), _garbage) - world_DE(ray_pos - vec3(normal_sample_length, 0.0, 0.0), _garbage),
		world_DE(ray_pos + vec3(0.0, normal_sample_length, 0.0), _garbage) - world_DE(ray_pos - vec3(0.0, normal_sample_length, 0.0), _garbage),
		world_DE(ray_pos + vec3(0.0, 0.0, normal_sample_length), _garbage) - world_DE(ray_pos - vec3(0.0, 0.0, normal_sample_length), _garbage)
	));
}

void fragment() {
	// Take the pixel position (UV) and convert it into a ray based on the camera's orientation and node transform
	vec3 ray_pos = CAMERA_POSITION_WORLD;
	vec2 uv = SCREEN_UV;
	float aspect_ratio = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float fov = -1.0 / PROJECTION_MATRIX[1][1];
	float px = aspect_ratio * (2.0 * uv.x - 1.0) * fov;
	float py = (1.0 - 2.0 * uv.y) * fov;
	vec3 ray_dir = vec3(px, py, -1);
	ray_dir = (INV_VIEW_MATRIX * vec4(normalize(ray_dir), 0.0)).xyz;
	ray_dir = normalize(inverse(MODEL_MATRIX) * vec4(ray_dir, 0.0)).xyz;
	ray_pos = (inverse(MODEL_MATRIX) * vec4(ray_pos, 1.0)).xyz;

	float t = intersect_sphere(ray_pos, ray_dir, bounding_radius);
	bool inside_bound = length(ray_pos) < bounding_radius;

	if (inside_bound || t > 0.0) {
		// Project to outside of bounding sphere to reduce wasted marches far away
		if (!inside_bound) {
			ray_pos = ray_pos + ray_dir * t;
		}

		vec3 final_ray_pos;

		// March through scene, bouncing at collisions to create reflections
		vec4 pixel_color = vec4(0.0);
		float previous_reflectance = 1.0;
		for (int i = 0; i < max_bounces; i++) {
			vec3 collision_info = vec3(1.0, MAX_DISTANCE, 0.0);
			int iter = march(primary_max_iterations, ray_pos, ray_dir, collision_info);

			if (i == 0) final_ray_pos = ray_pos;

			if (iter == primary_max_iterations) {
				pixel_color += clear_color * previous_reflectance;
				break;
			}

			vec3 normal = get_normal(ray_pos);

			// Shadow raymarching
			float shadow_occlusion = 1.0;
			if (real_shadows_enabled) {
				vec3 old_ray = ray_pos;
				vec3 garbage_ = vec3(1.0, MAX_DISTANCE, 0.0);
				vec3 corrected_light_direction = normalize(inverse(MODEL_MATRIX) * vec4(light_direction, 0.0)).xyz;
				ray_pos -= corrected_light_direction * collision_threshold * SHADOW_EPSILON_MULTIPLIER;
				int shadow_iter = march(primary_max_iterations / SUB_RAY_DIVIDER, ray_pos, -corrected_light_direction, garbage_);
				shadow_occlusion = (1.0 - real_shadow_darkness) + real_shadow_darkness * pow(float(shadow_iter) / float(primary_max_iterations / SUB_RAY_DIVIDER), 0.5);
				ray_pos = old_ray;
			}

			// Reflect the ray for future bounces
			ray_dir = ray_dir - 2.0 * dot(ray_dir, normal) * normal;
			ray_pos += ray_dir * collision_threshold * BOUNCE_EPSILON_MULTIPLIER;

			// Albedo
			float fractal_mix = 0.5 + 0.5 * sin(collision_info.r); // Kinda hacky
			vec4 hit_color = fractal_color_1 * fractal_mix + fractal_color_2 * (1.0 - fractal_mix);

			// Ambient occlusion
			float aa = float(iter) / float(primary_max_iterations);
			hit_color.rgb = clear_color.rgb * aa + (1.0 - aa) * hit_color.rgb;

			// Shadows based on normal only
			vec3 corrected_light_direction =  normalize(inverse(MODEL_MATRIX) * vec4(light_direction, 0.0)).xyz;
			float normal_shadow = ((1.0 - fake_shadow_darkness) + fake_shadow_darkness * pow(max(0.0, specular_ratio * dot(normal, -normalize(corrected_light_direction))), shadow_softness));
			hit_color *= vec4(pow(normal_shadow, shadow_absorption.r), pow(normal_shadow, shadow_absorption.g), normal_shadow, shadow_absorption.b);

			// Shadows based on geometry
			hit_color *= vec4(pow(shadow_occlusion, shadow_absorption.r), pow(shadow_occlusion, shadow_absorption.g), shadow_occlusion, shadow_absorption.b);

			// Specular highlights
			float specular = clamp(dot(-normalize(light_direction), ray_dir), 0.0, 1.0);
			float specular_power = pow(smoothness, 2.0);
			hit_color += specular_ratio * vec4(specular_color.rgb, 1.0) * pow(specular, specular_power);

			// Mix reflections
			pixel_color += hit_color * previous_reflectance;
			previous_reflectance = reflectivity;
		}
		ALBEDO.rgb = clamp(pixel_color.rgb, vec3(0.0), vec3(1.0));
		ALPHA = pixel_color.a;
		vec4 clip_pos = PROJECTION_MATRIX * VIEW_MATRIX * MODEL_MATRIX * vec4(final_ray_pos, 1.0);
		DEPTH = clip_pos.z / clip_pos.w;
	} else {
		ALBEDO = clear_color.rgb;
		ALPHA = clear_color.a;
	}
}