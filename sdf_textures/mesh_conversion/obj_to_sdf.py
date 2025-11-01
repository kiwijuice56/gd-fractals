import trimesh
import numpy as np

####  Parameters ####

N = 64 # The texture size
model_input = 'teto.obj' # Should be inside input/ folder
model_output = 'teto_64.sdf' # Should be inside output/ folder
padding = 0.05

#####################

mesh = trimesh.load('input/' + model_input)
bounds_min = mesh.bounds[0] - padding * mesh.extents
bounds_max = mesh.bounds[1] + padding * mesh.extents
x = np.linspace(bounds_min[0], bounds_max[0], N)
y = np.linspace(bounds_min[1], bounds_max[1], N)
z = np.linspace(bounds_min[2], bounds_max[2], N)

# Final SDF output as a voxel grid
sdf_grid = np.zeros((N, N, N), dtype=np.float32)

# Process in slices to save memory
print("Progress: 0.00")
for i in range(0, N):
    # Create a list of (x,y,z) points corresponding to one cut along the x-axis (flattened)
    xx, yy, zz = np.meshgrid(x[i:i+1], y, z, indexing='ij')
    points = np.stack([xx.ravel(), yy.ravel(), zz.ravel()], axis=-1)

    # Calculate the SDF at all of those points, then reshape it back into a y-z plane
    sdf_chunk = trimesh.proximity.signed_distance(mesh, points)
    sdf_grid[i:i+1] = sdf_chunk.reshape(1, N, N)

    print(f"Progress: {(i + 1) / float(N):.2f}")

# Normalize to [-1, 1], then [0, 1], and finally 0 - 255 integers
sdf_grid = sdf_grid / np.abs(sdf_grid).max()
normalized = (sdf_grid + 1.0) / 2.0
texture_data = (normalized * 255).astype(np.uint8)

with open('output/' + model_output, 'wb') as f:
    f.write(texture_data.tobytes())