@tool
extends EditorPlugin

const preview_scene = preload("res://addons/anthonyec.camera_preview/preview.tscn")

var preview: CameraPreview
var current_main_screen_name: String

func _enter_tree() -> void:
	main_screen_changed.connect(_on_main_screen_changed)
	EditorInterface.get_selection().selection_changed.connect(_on_editor_selection_changed)
	
	# Initialise preview panel and add to main screen.
	preview = preview_scene.instantiate() as CameraPreview
	preview.request_hide()
	
	var main_screen = EditorInterface.get_editor_main_screen()
	main_screen.add_child(preview)
	
func _exit_tree() -> void:
	if preview:
		preview.queue_free()
		
func _ready() -> void:
	# TODO: Currently there is no API to get the main screen name without 
	# listening to the `EditorPlugin.main_screen_changed` signal:
	# https://github.com/godotengine/godot-proposals/issues/2081
	EditorInterface.set_main_screen_editor("Script")
	EditorInterface.set_main_screen_editor("3D")
	
func _on_main_screen_changed(screen_name: String) -> void:
	current_main_screen_name = screen_name
	
	 # TODO: Bit of a hack to prevent pinned staying between view changes on the same scene.
	preview.unlink_camera()
	_on_editor_selection_changed()

func _on_editor_selection_changed() -> void:
	if not is_main_screen_viewport():
		# This hides the preview "container" and not the preview itself, allowing
		# any locked previews to remain visible once switching back to 3D tab.
		preview.visible = false
		return
		
	preview.visible = true
	
	var selected_nodes = EditorInterface.get_selection().get_selected_nodes()
	
	var selected_camera_3d: Camera3D = find_camera_3d_or_null(selected_nodes)
	var selected_camera_2d: Camera2D = find_camera_2d_or_null(selected_nodes)
	
	if selected_camera_3d and current_main_screen_name == "3D":
		preview.link_with_camera_3d(selected_camera_3d)
		preview.request_show()
	
	elif selected_camera_2d and current_main_screen_name == "2D":
		preview.link_with_camera_2d(selected_camera_2d)
		preview.request_show()
		
	else:
		preview.request_hide()
	
func is_main_screen_viewport() -> bool:
	return current_main_screen_name == "3D" or current_main_screen_name == "2D"
	
func find_camera_3d_or_null(nodes: Array[Node]) -> Camera3D:
	var camera: Camera3D
	
	for node in nodes:
		if node is Camera3D:
			camera = node as Camera3D
			break
			
	return camera
	
func find_camera_2d_or_null(nodes: Array[Node]) -> Camera2D:
	var camera: Camera2D
	
	for node in nodes:
		if node is Camera2D:
			camera = node as Camera2D
			break
			
	return camera

func _on_selected_camera_3d_tree_exiting() -> void:
	preview.unlink_camera()
