@tool
extends Node

@export var target_path: NodePath
@export var apply_in_editor: bool = true:
	set(v):
		apply_in_editor = v
		if Engine.is_editor_hint() and v:
			call_deferred("_run")

func _ready() -> void:
	# Editor preview matches game. This script never creates DirectionalLight3D.
	if Engine.is_editor_hint():
		if apply_in_editor:
			call_deferred("_run")
		return
	await get_tree().process_frame
	_run()

func _run() -> void:
	var target := get_node_or_null(target_path)
	if target == null:
		return
	_fix_materials_recursive(target)
	if not Engine.is_editor_hint():
		_add_collision_recursive(target)

func _fix_materials_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var old_mat = mi.get_active_material(i)
				var new_mat := StandardMaterial3D.new()
				if old_mat is StandardMaterial3D:
					var sm := old_mat as StandardMaterial3D
					new_mat.albedo_texture = sm.albedo_texture
					new_mat.albedo_color = sm.albedo_color
					new_mat.roughness = 0.8
					new_mat.metallic = 0.0
				else:
					new_mat.albedo_color = Color(1, 1, 1, 1)
				# No light-angle darkening. Editor preview stays bright without DirectionalLight.
				new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				new_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				new_mat.disable_receive_shadows = true
				mi.set_surface_override_material(i, new_mat)
	for child in node.get_children():
		_fix_materials_recursive(child)

func _add_collision_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.get_node_or_null(mesh_instance.name + "_collision") == null:
			var body := StaticBody3D.new()
			body.name = mesh_instance.name + "_collision"
			body.collision_layer = 1
			body.collision_mask = 1
			var shape := CollisionShape3D.new()
			shape.name = "CollisionShape3D"
			shape.shape = mesh_instance.mesh.create_trimesh_shape()
			body.add_child(shape)
			mesh_instance.add_child(body)
	for child in node.get_children():
		_add_collision_recursive(child)
