shader_type spatial;
render_mode unshaded, depth_prepass_alpha;

// Some constants that you probably don't need to change
const float MAX_DISTANCE = 10000.0; // Placeholder value for infinitely far away distances
const float SMOOTH_UNION_MULTIPLIER = 4.0; // See smooth_union(...)
const float BOUNCE_EPSILON_MULTIPLIER = 4.0; // Controls how far a ray should move away from a surface to prevent artifacts during shadows/bounces
const float SHADOW_EPSILON_MULTIPLIER = 4.0;

group_uniforms raymarching;
uniform int max_iterations = 256; // Max iterations any ray can march
uniform int max_bounce = 1; // Max times a ray can be reflected
uniform float collision_threshold = 0.01; // Min distance a ray can be from a surface for it to collide
uniform float normal_sample_length = 0.003; // How far along a collided surface to move when sampling for a normal
uniform float march_proportion : hint_range(0.0, 1.0) = 0.5; // Controls how far along the distance to advance the ray each step (lower = less artifacts, worse performance)
uniform float runaway_threshold = 10.0; // Distance where a ray is considered far enough to stop iteration
uniform float bounding_radius = 5.0; // Radius of the sphere bounding the entire scene (tighter = better performance)

group_uniforms fractal;
uniform int fractal_iterations = 4; // Max iterations of the fractal algoritms
uniform vec4 fractal_color_1: source_color = vec4(0.6, 0.0, 0.5, 1.0);
uniform vec4 fractal_color_2: source_color = vec4(0.0, 0.3, 0.2, 1.0);
uniform vec3 color_center_point = vec3(0.0, 0.5, -0.5); // Color parameters for fractal algorithms
uniform float color_balance: hint_range(0.0, 1.0) = 0.5; // Sliding scale for the two fractal colors
uniform float fractal_animation_amount = 0.3;

group_uniforms mandelbulb;
uniform float mandelbulb_power = 8.0;
uniform float mandelbulb_runaway_threshold = 2.0;

group_uniforms shape_modulus;
uniform float alpha = 3.15; // "cutoff" value of the fractal
uniform float beta = -0.135; // "thickness" of fractal surface
uniform sampler3D noise: repeat_enable, filter_linear; // Used to give surface fractal-like detail
uniform float noise_frequency = 2.0;
uniform vec3 portal_center = vec3(0.5, 0.6, 0.0); // Position of the portal
uniform vec3 portal_offset = vec3(0.45, 0.6, 0.2); // Position that the portal should teleport to
uniform float portal_radius = 0.3;
uniform float portal_scale = 4.0;

group_uniforms mesh;
uniform sampler3D sdf_texture: repeat_disable, filter_linear; // Signed distance function

// "real" shadows are calculated by bouncing rays in the direction of the light source
// "fake" shadows are calculated by comparing normals with the light direction
// Although ideally "real" shadows are the only necessary ones, having fake shadows can
// make details in the surface show and service when there are performance constraints
group_uniforms lighting;
uniform vec3 light_direction = vec3(0.0, -1.0, 0.0); // Should be synced in GDscript to some DirectionalLight3D
uniform float base_smoothness = 24.0;
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
	// Make the rendering plane a billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			MAIN_CAM_INV_VIEW_MATRIX[0],
			MAIN_CAM_INV_VIEW_MATRIX[1],
			MAIN_CAM_INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

/* Helper distance estimates */

// https://iquilezles.org/articles/distfunctions/
float smooth_union(float d1, float d2, float k) {
	k *= SMOOTH_UNION_MULTIPLIER;
	float h = max(k - abs(d1 - d2), 0.0);
	return min(d1, d2) - h * h / SMOOTH_UNION_MULTIPLIER / k;
}

// https://iquilezles.org/articles/distfunctions/
float smooth_intersection(float d1, float d2, float k) {
	return -smooth_union(-d1, -d2, k);
}

// http://blog.hvidtfeldts.net/index.php/2011/09/distance-estimated-3d-fractals-v-the-mandelbulb-different-de-approximations/
// https://iquilezles.org/articles/ftrapsgeometric/
float mandelbulb_DE(vec3 p, inout vec3 collision_info) {
	vec3 x = p;
	float r = 0.0;
	float dr = 1.0;

	for (int i = 0; i < fractal_iterations; i++) {
		r = length(x);
		if (r > mandelbulb_runaway_threshold) {
			break;
		}
		dr = pow(r, mandelbulb_power - 1.0) * mandelbulb_power * dr;

		// Mandelbulb folding
		float theta = acos(x.z / r);
		float phi = atan(x.y, x.x);
		theta = theta * mandelbulb_power;
		phi = phi * mandelbulb_power;
		x = p + pow(r, mandelbulb_power) * vec3(sin(theta) * cos(phi), sin(phi) * sin(theta), cos(theta));

		collision_info.r = min(collision_info.r, length(x - color_center_point));
	}
	collision_info.r *= color_balance;
	return 0.5 * log(r) * r/dr;
}

float julia_DE(vec3 p, inout vec3 collision_info) {
	vec4 x = vec4(p.x, p.z, 0.0, p.y);
	vec4 c = vec4(0.0, -0.3 - 0.5 * sin(TIME), -0.3, -0.6);
	float r = 0.0;
	float dr = 1.0;

	for (int i = 0; i < fractal_iterations; i++) {
		r = length(x);
		if (r > mandelbulb_runaway_threshold) {
			break;
		}
		dr = 2.0 * r * dr + 1.0;

		// Quaternion multiplication
		x = c + vec4(
			pow(x.w, 2) - pow(x.x, 2) - pow(x.y, 2) - pow(x.z, 2),
			2.0 * x.w * x.x,
			2.0 * x.w * x.y,
			2.0 * x.w * x.z
		);
	}
	return 0.5 * r * log(r) / dr;
}

float mesh_DE(vec3 p, inout vec3 collision_info) {
	return texture(sdf_texture, p).r * 2.0 - 1.0;
}

float mesh_fractal_DE(vec3 p, inout vec3 collision_info) {
	// Center the fractal
	vec4 x = vec4(p + vec3(0.5), 0.0);
	float r = 0.0;
	float dr = 1.0;

	for (int i = 0; i < fractal_iterations; i++) {
		r = length(x);

		float dist_to_portal = length(x.xyz - portal_center);
		if (dist_to_portal < portal_radius) {
			x.xyz = dist_to_portal * normalize(x.xyz - portal_center) * portal_scale + portal_offset;
			dr *= portal_scale;
		} else {
			vec3 D = normalize(texture(noise, fractal_animation_amount * sin(vec3(0.2, 0.3, 0.2) * TIME) + noise_frequency * x.xyz).rgb);
			vec3 _garbage;
			float R = exp(alpha * (mesh_DE(x.xyz, _garbage) + beta + 0.01 * sin(TIME) - 0.01));
			x.xyz = D * R;
			dr = alpha * R * dr + 1.0;
			collision_info.r += 32.0 * R * D.x;
		}
	}

	collision_info.r *= color_balance;
	return 0.5 * r * log(r) / dr;
}

float world_DE(vec3 p, inout int collider_id, inout vec3 collision_info) {
	collider_id = 1;
	collision_info = vec3(1.0, MAX_DISTANCE, 0.0);
	return mesh_fractal_DE(p, collision_info);
}

int march(inout vec3 ray_pos, vec3 ray_dir, inout int id, inout vec3 collision_info) {
	int iter = 0;
	for (; iter < max_iterations; iter++) {
		float dist = abs(world_DE(ray_pos, id, collision_info));
		collision_info.g = min(collision_info.g, dist);

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

float intersect_sphere(vec3 ray_pos, vec3 ray_dir, float radius) {
	float b = dot(ray_pos, ray_dir);
	float c = dot(ray_pos, ray_pos) - radius * radius;
	float h = b * b - c;

	if (h < 0.0) return -1.0;

	return -b - sqrt(h);
}


vec3 get_normal(vec3 ray_pos) {
	int _id; vec3 _garbage;
	return normalize(vec3(
		world_DE(ray_pos + vec3(normal_sample_length, 0.0, 0.0), _id, _garbage) - world_DE(ray_pos - vec3(normal_sample_length, 0.0, 0.0), _id, _garbage),
		world_DE(ray_pos + vec3(0.0, normal_sample_length, 0.0), _id, _garbage) - world_DE(ray_pos - vec3(0.0, normal_sample_length, 0.0), _id, _garbage),
		world_DE(ray_pos + vec3(0.0, 0.0, normal_sample_length), _id, _garbage) - world_DE(ray_pos - vec3(0.0, 0.0, normal_sample_length), _id, _garbage)
	));
}

struct Material {
	float reflectivity;
	float roughness;
	float shadow_sharpness;
	float specular_alpha;
};

void fragment() {
	Material fractal_material = Material(0.25, 0.5, 5.0, 0.95);
	Material mesh_material    = Material(0.25, 0.7, 5.0, 0.95);

	// Take the pixel position (UV) and convert it into a ray based on the camera's orientation and node transform
	vec3 ray_pos = CAMERA_POSITION_WORLD;
	vec2 uv = SCREEN_UV;
	float aspect_ratio = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float fov = atan(-1.0 / PROJECTION_MATRIX[1][1]);
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

		// March through scene, bouncing at collisions to create reflections
		vec4 pixel_color = vec4(0.0);
		float previous_reflectance = 1.0;
		for (int i = 0; i < max_bounce; i++) {
			// Find contact point and object
			int collider_id;
			vec3 collision_info = vec3(1.0, MAX_DISTANCE, 0.0);
			int iter = march(ray_pos, ray_dir, collider_id, collision_info);

			if (iter == max_iterations) {
				pixel_color += clear_color * previous_reflectance;
				break;
			}

			Material surface_material;
			if (collider_id == 0) {
				surface_material = fractal_material;
			} else if (collider_id == 1) {
				surface_material = mesh_material;
			}

			vec3 normal = -get_normal(ray_pos);

			// Shadow raymarching
			float shadow_occlusion = 1.0;
			if (real_shadows_enabled) {
				vec3 old_ray = ray_pos;
				int shadow_collider_id;
				vec3 shadow_collision_info = vec3(1.0, MAX_DISTANCE, 0.0);
				vec3 corrected_light_direction =  normalize(inverse(MODEL_MATRIX) * vec4(light_direction, 0.0)).xyz;
				ray_pos -= corrected_light_direction * collision_threshold * SHADOW_EPSILON_MULTIPLIER;
				int shadow_iter = march(ray_pos, -corrected_light_direction, shadow_collider_id, shadow_collision_info);
				shadow_occlusion = (1.0 - real_shadow_darkness) + real_shadow_darkness * pow(float(shadow_iter) / float(max_iterations), 0.5);
				ray_pos = old_ray;
			}

			// Reflect the ray for future bounces
			ray_dir = ray_dir - 2.0 * dot(ray_dir, normal) * normal;
			ray_pos += ray_dir * collision_threshold * BOUNCE_EPSILON_MULTIPLIER;

			// Albedo (slightly hacky, changes based on what fractal/DE is being rendered)
			float fractal_mix = 0.5 + 0.5 * sin(collision_info.r);
			vec4 hit_color = fractal_color_1 * fractal_mix + fractal_color_2 * (1.0 - fractal_mix);

			// Ambient occlusion
			float aa = float(iter) / float(max_iterations);
			hit_color.rgb = clear_color.rgb * aa + (1.0 - aa) * hit_color.rgb;

			// Shadows based on normal only
			vec3 corrected_light_direction =  normalize(inverse(MODEL_MATRIX) * vec4(light_direction, 0.0)).xyz;
			float normal_shadow = ((1.0 - fake_shadow_darkness) + fake_shadow_darkness * pow(max(0.0, specular_ratio * dot(normal, -normalize(corrected_light_direction))), shadow_softness));
			hit_color *= vec4(pow(normal_shadow, shadow_absorption.r), pow(normal_shadow, shadow_absorption.g), normal_shadow, shadow_absorption.b);

			// Shadows based on geometry
			hit_color *= vec4(pow(shadow_occlusion, shadow_absorption.r), pow(shadow_occlusion, shadow_absorption.g), shadow_occlusion, shadow_absorption.b);

			// Specular highlights
			float specular = clamp(dot(-normalize(light_direction), ray_dir), 0.0, 1.0);
			float specular_power = pow(base_smoothness * (surface_material.roughness - 1.0), 2.0);
			hit_color += specular_ratio * vec4(specular_color.rgb, 1.0) * vec4(surface_material.specular_alpha) * pow(specular, specular_power);

			// Mix reflections
			pixel_color += hit_color * previous_reflectance;
			previous_reflectance = surface_material.reflectivity;
		}
		ALBEDO.rgb = clamp(pixel_color.rgb, vec3(0.0), vec3(1.0));
		ALPHA = pixel_color.a;
	} else {
		ALBEDO = clear_color.rgb;
		ALPHA = clear_color.a;
	}
}