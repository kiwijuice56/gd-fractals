import trimesh
import numpy as np

# Normalizes distances to 0 - 255 range to fit into a texture
def normalize_sdf(sdf_array):
    normalized = (sdf_array + 1.0) / 2.0
    texture_data = (normalized * 255).astype(np.uint8)
    return texture_data

# Save as byte array
def save_as_raw(sdf_array, output_path):
    texture_data = normalize_sdf(sdf_array)

    with open(output_path, 'wb') as f:
        f.write(texture_data.tobytes())

mesh = trimesh.load('input/bunny.obj')

bounds_min = mesh.bounds[0] - 0.1 * mesh.extents
bounds_max = mesh.bounds[1] + 0.1 * mesh.extents

N = 64
x = np.linspace(bounds_min[0], bounds_max[0], N)
y = np.linspace(bounds_min[1], bounds_max[1], N)
z = np.linspace(bounds_min[2], bounds_max[2], N)

# Create voxel grid
xx, yy, zz = np.meshgrid(x, y, z, indexing='ij')
points = np.stack([xx.ravel(), yy.ravel(), zz.ravel()], axis=-1)

# Compute SDF exactly
sdf = trimesh.proximity.signed_distance(mesh, points)
sdf_grid = sdf.reshape(N, N, N)
sdf_grid = sdf_grid / np.abs(sdf_grid).max()

save_as_raw(sdf_grid, 'output/bunny.sdf')