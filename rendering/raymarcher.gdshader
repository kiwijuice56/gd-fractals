shader_type spatial;
render_mode unshaded, depth_prepass_alpha;

const float MAX_DISTANCE = 10000.0;

// Decrease iteration and bounce counts for better performance
// Increase collision threshold for lower detail and better performance
group_uniforms detail;
uniform int max_iter = 512; // Max iterations a regular collision ray can march
uniform int max_bounce = 2; // Max times a ray can be reflected
uniform float collision_threshold = 6.0e-3; // Min distance a ray can be from a surface for it to collide
uniform float normal_sample_length = 32.0e-3; // How far along a collided surface to move when sampling for a normal vector
uniform float march_proportion = 0.5;

group_uniforms fractal;
uniform int fractal_iterations = 4; // Max iterations of the fractal algoritms
uniform vec3 color_center_point = vec3(0.0, 0.5, -0.5); // Color parameters for fractal algorithms
uniform float color_intensity = 0.5;

group_uniforms mandelbulb;
uniform float mandelbulb_power = 8.0; // Dimension of the fractal
uniform float mandelbulb_runaway_threshold = 2.0;

group_uniforms shape_modulus;
uniform float alpha = 3.15;
uniform float beta = -0.135;
uniform sampler3D noise: repeat_enable, filter_linear;
uniform float noise_frequency = 2.0;
uniform vec3 portal_center = vec3(0.5, 0.6, 0.0);
uniform float portal_radius = 0.3;
uniform float portal_scale = 4.0;

group_uniforms mesh;
uniform sampler3D sdf_texture: repeat_disable, filter_linear;

group_uniforms camera;
uniform float runaway_threshold = 8.0; // Distance where a ray is considered far enough to stop iteration

group_uniforms light;
uniform vec3 light_ray = vec3(0.0, -1.0, 0.0);
uniform float base_smoothness = 24.0;
uniform vec3 specular_color: source_color = vec3(1.0, 1.0, 1.0);
uniform float specular_ratio = 1.0;
uniform float shadow_strength = 0.75;
uniform vec3 shadow_absorption = vec3(1.2, 1.1, 1.0);

group_uniforms scene;
uniform vec4 clear_color: source_color;

// Updated by script only
group_uniforms internal;
uniform float _fov = 86.0;
uniform mat3 _cam_mat = mat3(0.0); // Camera basis matrix

// Transform of the fractal object
instance uniform vec3 _position = vec3(0.0);
instance uniform float _scale = 1.0;
instance uniform vec3 _rotation;

void vertex() {
	// Make the rendering plane a billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			MAIN_CAM_INV_VIEW_MATRIX[0],
			MAIN_CAM_INV_VIEW_MATRIX[1],
			MAIN_CAM_INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

/* Rotation functions */ 

mat3 rotation_x(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat3(
		vec3(1.0, 0.0, 0.0),
		vec3(0.0, c, -s),
		vec3(0.0, s, c)
	);
}

mat3 rotation_y(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat3(
		vec3(c, 0.0, s),
		vec3(0.0, 1.0, 0.0),
		vec3(-s, 0.0, c)
	);
}

mat3 rotation_z(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat3(
		vec3(c, -s, 0.0),
		vec3(s, c, 0.0),
		vec3(0.0, 0.0, 1.0)
	);
}

vec3 rotate_xyz(vec3 p, vec3 angles) {
	return rotation_z(angles.z) * rotation_y(angles.y) * rotation_x(angles.x) * p;
}


/* Helper distance estimates */

// https://iquilezles.org/articles/distfunctions/
float smooth_union(float d1, float d2, float k) {
	k *= 4.0;
	float h = max(k - abs(d1-d2), 0.0);
	return min(d1, d2) - h * h * 0.25/k;
}

// https://iquilezles.org/articles/distfunctions/
float smooth_intersection(float d1, float d2, float k) {
	return -smooth_union(-d1,-d2,k);
}

// Returns distance estimate to fractal
// http://blog.hvidtfeldts.net/index.php/2011/09/distance-estimated-3d-fractals-v-the-mandelbulb-different-de-approximations/
// https://iquilezles.org/articles/ftrapsgeometric/
float mandelbulb_DE(vec3 p, inout vec3 collision_info) {
	vec3 x = p;
	float dr = 1.0;
	float r = 0.0;
	for (int i = 0; i < fractal_iterations; i++) {
		r = length(x);
		
		if (r > mandelbulb_runaway_threshold) {
			break;
		}
		
		dr = pow(r, mandelbulb_power - 1.0) * mandelbulb_power * dr;
		
		float xr = pow(r, mandelbulb_power);
		
		float theta = acos(x.z / r);
		float phi = atan(x.y, x.x);
		theta = theta * mandelbulb_power;
		phi = phi * mandelbulb_power;
		
		x = xr * vec3(sin(theta) * cos(phi), sin(phi) * sin(theta), cos(theta));
		x += p;
		
		collision_info.r = min(collision_info.r, length(x - color_center_point));
	}
	collision_info.r *= color_intensity;
	return 0.5 * log(r) * r/dr;
}

float julia_DE(vec3 p, inout vec3 collision_info) {
	vec4 x = vec4(p.x, p.z, 0.0, p.y);
	vec4 c = vec4(0.0, -0.3 - 0.5 * sin(TIME), -0.3, -0.6); // Fluid center point
	float dr = 1.0;
	for (int i = 0; i < fractal_iterations; i++) {
		if (length(x) > mandelbulb_runaway_threshold) {
			break;
		}
		dr = 2.0 * length(x) * dr + 1.0;
		
		// Quaternion multiplication
		x = c + vec4( 
			pow(x.w, 2) - pow(x.x, 2) - pow(x.y, 2) - pow(x.z, 2),
			2.0 * x.w * x.x,
			2.0 * x.w * x.y,
			2.0 * x.w * x.z
		);
	}
	return 0.5 * length(x) * log(length(x)) / dr;
}

float mesh_DE(vec3 p, inout vec3 collision_info) {
	return texture(sdf_texture, p).r * 2.0 - 1.0;
}

float mesh_fractal_DE(vec3 p, inout vec3 collision_info) {
	vec3 _garbage;
	vec4 x = vec4(p, 0.0);
	float dr = 1.0;
	
	for (int i = 0; i < fractal_iterations; i++) {
		collision_info.r = min(collision_info.r, length(x.xyz - color_center_point));
		
		float dist_to_portal = length(x.xyz - portal_center);
		if (dist_to_portal < portal_radius) {
			x.xyz = dist_to_portal * normalize(x.xyz - portal_center) * portal_scale; 
			dr *= portal_scale;
		} else {
			vec3 D = normalize(texture(noise, noise_frequency * x.xyz).rgb);
			float R = exp(alpha * (mesh_DE(x.xyz, _garbage) + beta));
			x.xyz = D * R;
			dr = alpha * R * dr + 1.0;
		}
	}
	
	collision_info.r *= color_intensity;
	return 0.5 * length(x) * log(length(x)) / dr;
}

float world_DE(vec3 p, inout int collider_id, inout vec3 collision_info) {
	p -= _position;
	p = rotate_xyz(p, _rotation);
	p /= _scale;
	
	collider_id = 1;
	collision_info.r = 1.0;
	collision_info.g = MAX_DISTANCE;
	collision_info.b = 0.0;
	
	return _scale * mesh_fractal_DE(p, collision_info);
}

int march(inout vec3 ray_pos, vec3 ray_dir, inout int id, inout vec3 collision_info) {
	int iter = 0;
	for (; iter < max_iter; iter++) {
		float dist = abs(world_DE(ray_pos, id, collision_info));
		collision_info.g = min(collision_info.g, dist);
		
		ray_pos += ray_dir * dist * march_proportion;
		
		if (dist > runaway_threshold) {
			iter = max_iter;
			break;
		}
		
		if (dist < collision_threshold) {
			break;
		}
	}
	return iter;
}

vec3 get_normal(vec3 ray_pos) {
	int _id; vec3 _garbage;
	return normalize(
		vec3(
			world_DE(ray_pos + vec3(normal_sample_length, 0.0, 0.0), _id, _garbage) - world_DE(ray_pos - vec3(normal_sample_length, 0.0, 0.0), _id, _garbage),
			world_DE(ray_pos + vec3(0.0, normal_sample_length, 0.0), _id, _garbage) - world_DE(ray_pos - vec3(0.0, normal_sample_length, 0.0), _id, _garbage),
			world_DE(ray_pos + vec3(0.0, 0.0, normal_sample_length), _id, _garbage) - world_DE(ray_pos - vec3(0.0, 0.0, normal_sample_length), _id, _garbage)
			)
		);
}

struct Material {
	float reflectivity;
	float roughness;
	float shadow_sharpness;
	float specular_alpha;
	vec4 albedo_color;
};

// https://www.scratchapixel.com/lessons/3d-basic-rendering/ray-tracing-generating-camera-rays/generating-camera-rays.html
void fragment() {
	// Initialize materials
	Material fractal_material = Material(0.25, 0.5, 5.0, 0.95, vec4(0.5, 0.2, 0.5, 1.0));
	Material mesh_material    = Material(0.55, 0.7, 5.0, 0.95, vec4(0.5, 0.2, 0.1, 1.0));

	// Take the pixel position (UV) and convert it into a ray based on the camera's orientation
	vec3 ray_pos = CAMERA_POSITION_WORLD;
	vec2 uv = SCREEN_UV;
	float aspect_ratio = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float px = aspect_ratio * (2.0 * uv.x - 1.0) * tan(_fov * PI / 360.0);
	float py = (1.0 - 2.0 * uv.y) * tan(_fov * PI / 360.0);
	vec3 ray_dir = vec3(px, py, -1);
	ray_dir = _cam_mat * normalize(ray_dir);

	// March through scene, bouncing at collisions to create reflections
	vec4 pixel_color = clear_color;
	float previous_reflectance = 1.0;
	for (int i = 0; i < max_bounce; i++) {
		int collider_id;
		vec3 collision_info = vec3(1.0, MAX_DISTANCE, 0.0);
		int iter = march(ray_pos, ray_dir, collider_id, collision_info);
		
		if (iter == max_iter) {
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

		// Reflect the ray
		ray_dir = ray_dir - 2.0 * dot(ray_dir, normal) * normal;
		ray_pos += ray_dir * collision_threshold * 4.0;
		
		// Albedo (slightly hacky, changes based on what fractal/DE is being rendered)
		float fractal_mix = fract(collision_info.r);
		vec4 hit_color = vec4(0.8, 0.0, 0.5, 1.0) * fractal_mix + vec4(0.0, 0.2, 0.2, 1.0) * (1.0 - fractal_mix);
		
		// Ambient occlusion
		float aa = float(iter) / float(max_iter);
		hit_color.rgb = clear_color.rgb * aa + (1.0 - aa) * hit_color.rgb;
		
		// Shadows based on the normal only
		float normal_shadow = ((1.0 - shadow_strength) + shadow_strength* pow(max(0.0, specular_ratio * dot(normal, -normalize(light_ray))), 1.0/2.4));
		hit_color *= vec4(pow(normal_shadow, shadow_absorption.r), pow(normal_shadow, shadow_absorption.g), normal_shadow, shadow_absorption.b);
		
		// Specular highlights
		float specular = clamp(dot(-normalize(light_ray), ray_dir), 0.0, 1.0);
		float specular_power = pow(base_smoothness * (surface_material.roughness - 1.0), 2.0) + 2.0;
		hit_color += specular_ratio * vec4(specular_color.rgb, 1.0) * vec4(surface_material.specular_alpha) * pow(specular, specular_power);
		
		// Mix reflections
		pixel_color += hit_color * previous_reflectance;
		previous_reflectance = surface_material.reflectivity;
	}
	ALBEDO.rgb = clamp(pixel_color.rgb, vec3(0.0), vec3(1.0));
}