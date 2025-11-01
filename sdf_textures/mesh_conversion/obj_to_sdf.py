from mesh_to_sdf import mesh_to_voxels

import trimesh
import numpy as np

# Normalizes distances to 0 - 255 range to fit into a texture
def normalize_sdf(sdf_array):
    normalized = sdf_array + 1.0 / 2.0
    texture_data = (normalized * 255).astype(np.uint8)
    return texture_data

def save_as_raw(sdf_array, output_path):
    texture_data = normalize_sdf(sdf_array)

    with open(output_path, 'wb') as f:
        f.write(texture_data.tobytes())

mesh = trimesh.load('input/bunny.obj')
voxels = mesh_to_voxels(mesh, voxel_resolution=64, surface_point_method='scan', sign_method='normal',
                        scan_count=100, scan_resolution=400, sample_point_count=10000000,
                        normal_sample_count=11, pad=False, check_result=False, return_gradients=False)
save_as_raw(voxels, 'output/bunny.sdf')
