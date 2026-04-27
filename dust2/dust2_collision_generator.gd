extends Node

@export var target_path: NodePath

func _ready() -> void:
	await get_tree().process_frame
	var target := get_node_or_null(target_path)
	if target == null:
		push_warning("Dust2 collision target not found: " + str(target_path))
		return
	_add_collision_recursive(target)
	print("Dust2 collision generated from mesh")

func _add_collision_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
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
