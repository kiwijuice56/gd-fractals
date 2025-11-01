shader_type spatial;
render_mode unshaded, depth_prepass_alpha;

// Decrease iteration and bounce counts for better performance
// Increase collision threshold for lower detail and better performance
group_uniforms detail;
uniform int max_iter = 512; // Max iterations a regular collision ray can march
uniform int max_bounce = 2; // Max times a ray can be reflected
uniform float collision_threshold = 1.0e-3; // Min distance a ray can be from a surface for it to collide
uniform float normal_sample_length = 1.0e-2; // How far along a collided surface to move when sampling for a normal vector

group_uniforms fractal;
instance uniform int bulb_iter = 8; // Max iterations of the fractal algorithm
instance uniform float bulb_power = 8.0; // Dimension of the fractal
uniform float bulb_runaway_threshold = 2.0;
uniform vec3 color_center_point = vec3(0.0, 0.5, -0.5);
uniform float color_intensity = 0.5;

group_uniforms mesh;
uniform sampler3D sdf_texture: repeat_disable, filter_linear;

group_uniforms camera;
uniform float runaway_threshold = 8.0; // Distance where a ray is considered far enough to stop iteration

group_uniforms light;
uniform vec3 light_ray = vec3(0.0, -1.0, 0.0);
uniform vec3 specular_color: source_color = vec3(1.0, 1.0, 1.0);
uniform float specular_ratio = 1.0;
uniform vec4 glow_color: source_color = vec4(1.0, 1.0, 1.0, 0.01);
uniform float glow_distance = 0.5;

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

struct Material {
	float reflectivity;
	float roughness;
	float shadow_sharpness;
	float specular_alpha;
	vec4 albedo_color;
};

// Rotation functions

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

// Returns distance estimate to fractal
// `collision_info` parameter is overwritten with color information
// http://blog.hvidtfeldts.net/index.php/2011/09/distance-estimated-3d-fractals-v-the-mandelbulb-different-de-approximations/
// https://iquilezles.org/articles/ftrapsgeometric/
float mandelbulb_DE(vec3 p, inout vec3 collision_info) {
	p -= _position;
	p = rotate_xyz(p, _rotation); 
	p /= _scale;
	
	vec3 z = p;
	float dr = 1.0;
	float r = 0.0;
	
	for (int i = 0; i < bulb_iter; i++) {
		r = length(z);
		if (r > bulb_runaway_threshold)
			break;
		
		// Convert to polar coordinates
		float theta = acos(z.z/r);
		float phi = atan(z.y, z.x);
		dr = pow(r, bulb_power - 1.0) * bulb_power * dr;
		
		// Scale and rotate the point
		float zr = pow(r, bulb_power);
		theta = theta * bulb_power;
		phi = phi * bulb_power;
		
		// Convert back to cartesian coordinates
		z = zr * vec3(sin(theta) * cos(phi), sin(phi) * sin(theta), cos(theta));
		z += p;
		
		// Store minimum distance along orbit to a random (predetermined) point...
		// Creates nice colors along fractal "bulbs"
		collision_info.r = min(collision_info.r, length(z - color_center_point));
	}
	// Divide by arbitrary value
	collision_info.r *= color_intensity;
	return 1000.0;
	return (0.5 * log(r) * r/dr) * _scale;
}

float mesh_DE(vec3 p, inout vec3 collision_info) {
	vec3 uvw = clamp(p / 2.0, vec3(0.0), vec3(1.0));
	
	float raw_disance = texture(sdf_texture, uvw).r;
	float rescaled_distance = raw_disance * 2.0 - 1.0;
	
	// SDF is "exact", so we should scale it down slightly to prevent clipping 
	return clamp(rescaled_distance, -1.0, 1.0) * 0.2;
}

// Returns a vec4 of the color and distance to the closest object as rgba respectively
// `collision_info` holds extra information about the collision; Only stores
// distance values for coloring at this point
float world_DE(vec3 p, inout int collider_id, inout vec3 collision_info) {
	vec3 bulb_info = vec3(1.0, 1024.0, 0.0);
	float d1 = mandelbulb_DE(p, bulb_info);
	vec3 mesh_info = vec3(1.0, 1024.0, 0.0);
	float d2 = mesh_DE(p, mesh_info);
	if (d2 < d1) {
		collision_info = mesh_info;
		collider_id = 1;
		return d2;
	} else {
		collision_info = bulb_info;
		collider_id = 0; 
		return d1;
	}
}

int march(inout vec3 ray_pos, vec3 ray_dir, inout int id, inout vec3 collision_info) {
	float dist = 10000.0; // Arbitrary max distance
	int iter = 0;
	for (int i = 0; i < max_iter; i++) {
		dist = abs(world_DE(ray_pos, id, collision_info));
		collision_info.g = min(collision_info.g, dist);
		ray_pos += ray_dir * dist * 0.4;
		// We can quit marching early if we are extremely far from the fractal
		if (dist > runaway_threshold) {
			iter = max_iter;
			break;
		}
		// Once we are close enough to the fractal, we say we collided with it
		if (dist < collision_threshold)
			break;
		iter++;
	}
	return iter;
}

vec3 get_normal(vec3 ray_pos) {
	int _id;
	vec3 _col_info;
	return normalize(
		vec3(
			world_DE(ray_pos + vec3(normal_sample_length, 0.0, 0.0), _id, _col_info) - world_DE(ray_pos - vec3(normal_sample_length, 0.0, 0.0), _id, _col_info),
			world_DE(ray_pos + vec3(0.0, normal_sample_length, 0.0), _id, _col_info) - world_DE(ray_pos - vec3(0.0, normal_sample_length, 0.0), _id, _col_info),
			world_DE(ray_pos + vec3(0.0, 0.0, normal_sample_length), _id, _col_info) - world_DE(ray_pos - vec3(0.0, 0.0, normal_sample_length), _id, _col_info)
			)
		);
}

// https://www.scratchapixel.com/lessons/3d-basic-rendering/ray-tracing-generating-camera-rays/generating-camera-rays.html
void fragment() {
	// Initialize materials
	Material fractal_material = Material(0.07, 0.5, 5.0, 0.95, vec4(0.5, 0.5, 0.5, 1.0));
	Material mesh_material = Material(0.07, 0.5, 5.0, 0.95, vec4(0.5, 0.5, 0.5, 1.0));
	
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
	for (int i = 0; i < max_bounce; i++) {
		int collider_id;
		vec3 collision_info = vec3(1.0, 1024.0, 0.0);
		int iter = march(ray_pos, ray_dir, collider_id, collision_info);
		
		// If we iterated up to the maximum amount of times and still haven't collided,
		// we probably escaped any objects; Apply some glow based on the closest distance we reached
		if (iter == max_iter) {
			pixel_color = mix(glow_color, clear_color, clamp(pow(collision_info.g, 2) / glow_distance, 0.0, 1.0));
			break;
		}
		
		Material surface_material;
		float x = collision_info.r;
		x -= floor(x);
		if (collider_id == 0) {
			surface_material = fractal_material;
		} else if (collider_id == 1) {
			surface_material = mesh_material;
		}
		
		vec3 normal = get_normal(ray_pos);
		
		// Reflect the ray
		ray_dir = ray_dir - 2.0 * dot(ray_dir, normal) * normal;
		ray_pos += ray_dir * collision_threshold * 4.0;
		
		vec4 hit_color = surface_material.albedo_color;
		
		// Ambient occlusion
		float aa = float(iter) / float(max_iter);
		hit_color.rgb = clear_color.rgb * aa + (1.0 - aa) * hit_color.rgb;
		
		// Shadows based on the normal vector at this surface
		float normal_shadow = (0.25 + 0.75 * pow(max(0.0, specular_ratio * dot(normal, -normalize(light_ray))), 1.0/2.4));
		hit_color *= vec4(pow(normal_shadow, 1.2), pow(normal_shadow, 1.1), normal_shadow, 1.0);
		
		// Specular highlights
		float specular = dot(-normalize(light_ray), ray_dir);
		float specular_power = pow(25.0 * (surface_material.roughness - 1.0), 2.0) + 2.0;
		hit_color += specular_ratio * vec4(specular_color.rgb, 1.0) * vec4(surface_material.specular_alpha) * pow(specular, specular_power);
		pixel_color = hit_color;
		
		// Mix reflections
		pixel_color = mix(pixel_color, hit_color, surface_material.reflectivity);
	}
	
	ALBEDO.rgb = pixel_color.rgb;
	ALPHA = clamp(pixel_color.a, 0.0, 1.0);
}