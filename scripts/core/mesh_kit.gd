class_name MeshKit
extends RefCounted
## Small helpers for building low-poly models and level geometry in code.
## Everything in this project is built procedurally, so these are used everywhere.


static func mat(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func emissive(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Dirty, noisy surface (rust, grime, mud). Generated once per call, so cache the result.
static func grime(base: Color, dark: Color, frequency := 0.05, roughness := 0.9, metallic := 0.0, uv_scale := 1.0) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, dark)
	ramp.set_color(1, base)
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.uv1_triplanar = true
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, pos, material, rot_deg)


static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, rot_deg := Vector3.ZERO, segments := 12, top_radius := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return _add(parent, mesh, pos, material, rot_deg)


static func sphere(parent: Node3D, radius: float, pos: Vector3, material: Material, scale := Vector3.ONE, segments := 12) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(4, segments / 2)
	var mi := _add(parent, mesh, pos, material, Vector3.ZERO)
	mi.scale = scale
	return mi


static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 12
	mesh.ring_segments = 8
	return _add(parent, mesh, pos, material, rot_deg)


static func prism(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg := Vector3.ZERO, left_to_right := 0.0) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.left_to_right = left_to_right
	return _add(parent, mesh, pos, material, rot_deg)


## Static body with a box collider and a matching mesh. Used for walls, junk stacks, buildings.
static func solid_box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation_degrees = rot_deg
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	box(body, size, Vector3.ZERO, material)
	return body


## Static body whose collider is built from the given mesh (convex). Good for ramps.
static func solid_mesh(parent: Node3D, mesh_instance: MeshInstance3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = mesh_instance.transform
	parent.add_child(body)
	mesh_instance.get_parent().remove_child(mesh_instance)
	mesh_instance.transform = Transform3D.IDENTITY
	body.add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	shape.shape = mesh_instance.mesh.create_convex_shape()
	body.add_child(shape)
	return body


static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi
