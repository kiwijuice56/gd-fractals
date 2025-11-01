from mesh_to_sdf import mesh_to_voxels

import trimesh
import numpy as np

# Normalizes distances to 0-1 floating point range, then converts to uint8
def normalize_sdf(sdf_array):
    min_val = sdf_array.min()
    max_val = sdf_array.max()

    # Normalize to 0-1 range
    normalized = (sdf_array - min_val) / (max_val - min_val)

    # Convert to 0-255 uint8
    texture_data = (normalized * 255).astype(np.uint8)

    return texture_data

def save_as_raw(sdf_array, output_path):
    texture_data = normalize_sdf(sdf_array)

    with open(output_path, 'wb') as f:
        f.write(texture_data.tobytes())

N = 64
mesh = trimesh.load('input/teto_pear.obj')
voxels = mesh_to_voxels(mesh, voxel_resolution=N, surface_point_method='scan', sign_method='normal',
                        scan_count=100, scan_resolution=400, sample_point_count=10000000,
                        normal_sample_count=11, pad=False, check_result=False, return_gradients=False)
save_as_raw(voxels, 'output/teto_pear.sdf')
