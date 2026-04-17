extends Control

var just_opened := false

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

func _process(_delta):
	if not visible:
		return

	if just_opened:
		just_opened = false
		return

	if Input.is_action_just_pressed("pause"):
		close_menu()

func open_menu():
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	just_opened = true

func close_menu():
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_resume_pressed() -> void:
	close_menu()

func _on_mainmenu_pressed() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://MainMenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()
