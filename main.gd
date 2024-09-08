@tool
extends Node3D

const WATER_MAT := preload('res://assets/mat_water.tres')
const WATER_MESH_HIGH := preload('res://assets/clipmap_high.obj')
const WATER_MESH_LOW := preload('res://assets/clipmap_low.obj')

@export_enum('128x128:128', '256x256:256', '512x512:512', '1024x1024:1024') var map_size := 1024 :
	set(value):
		map_size = value
		_setup_wave_generator()

# Use
@export var wave_cascades : Array[WaveCascadeParameters] :
	set(value):
		var new_size := len(value)
		# All below logic is basically just required for using in the editor!
		for i in range(new_size):
			# Ensure all values in the array have an associated cascade
			if not value[i]: value[i] = WaveCascadeParameters.new()
			value[i].spectrum_seed = Vector2i(rng.randi_range(-10000, 10000), rng.randi_range(-10000, 10000))
			value[i].time = 120.0 + PI*i # We make sure to choose a time offset such that cascades don't interfere!
		wave_cascades = value
		map_scales.resize(new_size)
		_setup_wave_generator()

@export var use_high_quality_mesh := true :
	set(value):
		use_high_quality_mesh = value
		$Water.mesh = WATER_MESH_HIGH if use_high_quality_mesh else WATER_MESH_LOW
		clipmap_tile_size = 1.0 if use_high_quality_mesh else 4.0

## How many times the wave simulation should update per second.
## Note: This doesn't reduce the frame stutter caused by FFT calculation, only
##       minimizes GPU time taken by it!
var updates_per_second := 50.0 :
	set(value):
		next_update_time = next_update_time - (1.0/(updates_per_second + 1e-10) - 1.0/(value + 1e-10))
		updates_per_second = value

var water_color : Color = WATER_MAT.get_shader_parameter('water_color')
var foam_color : Color = WATER_MAT.get_shader_parameter('foam_color')
var _water_color := [water_color.r, water_color.g, water_color.b]
var _foam_color := [foam_color.r, foam_color.g, foam_color.b]

var displacement_maps := Texture2DArrayRD.new()
var map_scales : PackedVector2Array
var normal_maps := Texture2DArrayRD.new()
var rng = RandomNumberGenerator.new()
var clipmap_tile_size := 1.0 # Not the smallest tile size, but one that reduces the amount of vertex jitter.

var wave_generator : WaveGenerator
var time := 0.0
var next_update_time := 0.0
var previous_tile := Vector3i.MAX
var should_render_imgui := not Engine.is_editor_hint()

@onready var viewport : Variant = Engine.get_singleton('EditorInterface').get_editor_viewport_3d(0) if Engine.is_editor_hint() else get_viewport()
@onready var camera : Variant = viewport.get_camera_3d()
@onready var camera_fov := [camera.fov]
@onready var wave_update_rate := [updates_per_second]
@onready var _use_high_quality_mesh := [use_high_quality_mesh]

func _init() -> void:
	rng.set_seed(1234)
	DisplayServer.window_set_size(DisplayServer.screen_get_size() * 0.75)
	DisplayServer.window_set_position(DisplayServer.screen_get_size() * 0.25 / 2.0)

func _process(delta : float) -> void:
	if not Engine.is_editor_hint():
		if should_render_imgui:
			_render_imgui()
		camera.enable_camera_movement = not (ImGui.IsWindowHovered(ImGui.HoveredFlags_AnyWindow) or ImGui.IsAnyItemActive())

	# Update waves once every 1.0/updates_per_second.
	if updates_per_second == 0 or time >= next_update_time:
		var target_update_delta := 1.0 / (updates_per_second + 1e-10)
		var update_delta := delta if updates_per_second == 0 else target_update_delta + (time - next_update_time)
		next_update_time = time + target_update_delta
		_update_water(update_delta)
	time += delta

func _physics_process(delta: float) -> void:
	# Shift water mesh whenever player moves into a new tile.
	var tile := (Vector3(camera.global_position.x, 0.0, camera.global_position.z) / clipmap_tile_size).ceil()
	if not tile.is_equal_approx(previous_tile):
		$Water.global_position = tile * clipmap_tile_size
		previous_tile = tile

	# Vary audio samples based on total wind speed across all cascades.
	var total_wind_speed := 0.0
	for params in wave_cascades:
		total_wind_speed += params.wind_speed
	$OceanAudioPlayer.volume_db = lerpf(-30.0, 15.0, minf(total_wind_speed/15.0, 1.0))
	$WindAudioPlayer.volume_db = lerpf(5.0, -30.0, minf(total_wind_speed/15.0, 1.0))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed('toggle_imgui'):
		should_render_imgui = not should_render_imgui
	elif event.is_action_pressed('toggle_fullscreen'):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED else DisplayServer.WINDOW_MODE_WINDOWED)
	elif event.is_action_pressed('ui_cancel'):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _setup_wave_generator() -> void:
	if wave_cascades.size() <= 0: return
	for param in wave_cascades:
		param.should_generate_spectrum = true

	wave_generator = WaveGenerator.new()
	wave_generator.parameters = wave_cascades
	wave_generator.map_size = map_size
	wave_generator.init_gpu()

	displacement_maps.texture_rd_rid = RID()
	normal_maps.texture_rd_rid = RID()
	displacement_maps.texture_rd_rid = wave_generator.descriptors['displacement_map'].rid
	normal_maps.texture_rd_rid = wave_generator.descriptors['normal_map'].rid

	WATER_MAT.set_shader_parameter('num_cascades', wave_cascades.size())
	WATER_MAT.set_shader_parameter('displacements', displacement_maps)
	WATER_MAT.set_shader_parameter('normals', normal_maps)

func _update_water(delta : float) -> void:
	wave_generator.generate_maps(delta)

	for i in len(wave_cascades):
		map_scales[i] = Vector2.ONE / wave_cascades[i].tile_length
	WATER_MAT.set_shader_parameter('map_scales', map_scales)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		displacement_maps.texture_rd_rid = RID()
		normal_maps.texture_rd_rid = RID()

func imgui_text_tooltip(title : String, tooltip : String) -> void:
	ImGui.Text(title); if ImGui.IsItemHovered() and not tooltip.is_empty(): ImGui.SetTooltip(tooltip)

func _render_imgui() -> void:
	var fps := Engine.get_frames_per_second()
	ImGui.Begin(' ', [], ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoMove)
	ImGui.SetWindowPos(Vector2(20, 20))
	ImGui.SeparatorText('OceanWaves')
	ImGui.Text('FPS:                %d (%s)' % [fps, '%.2fms' % (1.0 / fps*1e3)])
	ImGui.Text('Wave Resolution:   '); ImGui.SameLine()
	if ImGui.BeginCombo('##resolution', '%dx%d' % [map_size, map_size]):
		for resolution in [128, 256, 512, 1024]:
			if ImGui.Selectable('%dx%d' % [resolution, resolution]):
				map_size = resolution
		ImGui.EndCombo()
	imgui_text_tooltip('Updates per Second:', 'Denotes how many times wave spectrums will be modulated per second.\n(0 is uncapped)'); ImGui.SameLine(); if ImGui.SliderFloat('##update_rate', wave_update_rate, 0, 60): updates_per_second = wave_update_rate[0]
	ImGui.Text('Water Color:       '); ImGui.SameLine(); if ImGui.ColorButtonEx('##water_color_button', water_color, ImGui.ColorEditFlags_Float, Vector2(ImGui.GetColumnWidth(), ImGui.GetFrameHeight())): ImGui.OpenPopup('water_color_picker')
	if ImGui.BeginPopup('water_color_picker'):
		if ImGui.ColorPicker3('##water_color_picker', _water_color, ImGui.ColorEditFlags_Float | ImGui.ColorEditFlags_NoSidePreview | ImGui.ColorEditFlags_DisplayRGB | ImGui.ColorEditFlags_DisplayHex):
			var color := Color(_water_color[0], _water_color[1], _water_color[2])
			water_color = color
			WATER_MAT.set_shader_parameter('water_color', color)
		ImGui.EndPopup()
	ImGui.Text('Foam Color:        '); ImGui.SameLine(); if ImGui.ColorButtonEx('##foam_color_button', foam_color, ImGui.ColorEditFlags_Float, Vector2(ImGui.GetColumnWidth(), ImGui.GetFrameHeight())): ImGui.OpenPopup('foam_color_picker')
	if ImGui.BeginPopup('foam_color_picker'):
		if ImGui.ColorPicker3('##foam_color_picker', _foam_color, ImGui.ColorEditFlags_Float | ImGui.ColorEditFlags_NoSidePreview | ImGui.ColorEditFlags_DisplayRGB | ImGui.ColorEditFlags_DisplayHex):
			var color := Color(_foam_color[0], _foam_color[1], _foam_color[2])
			foam_color = color
			WATER_MAT.set_shader_parameter('foam_color', color)
		ImGui.EndPopup()
	ImGui.Text('Use Fancy Mesh:    '); ImGui.SameLine(); if ImGui.Checkbox('##use_high_quality_mesh', _use_high_quality_mesh): use_high_quality_mesh = _use_high_quality_mesh[0]

	ImGui.SeparatorText('Wave Cascade Parameters')
	if ImGui.BeginTabBar('##cascades'):
		for i in len(wave_cascades):
			var cascade := wave_cascades[i]
			if ImGui.BeginTabItem('Cascade %d' % (i + 1)):
				imgui_text_tooltip('Tile Length:       ', 'Denotes the distance the cascade\'s tile should cover (in meters).'); ImGui.SameLine(); if ImGui.InputFloat2('##tile_length', cascade._tile_length): cascade.tile_length = Vector2(cascade._tile_length[0], cascade._tile_length[1])
				imgui_text_tooltip('Time Scale:        ', ''); ImGui.SameLine(); if ImGui.SliderFloat('##time_scale', cascade._time_scale, 0, 2): cascade.time_scale = cascade._time_scale[0]
				ImGui.Dummy(Vector2(0,0)); ImGui.Separator(); ImGui.Dummy(Vector2(0,0))
				imgui_text_tooltip('Wind Speed:        ', 'Denotes the average wind speed above the water (in meters per second).\nIncreasing makes waves steeper and more \'chaotic\'.'); ImGui.SameLine(); if ImGui.InputFloat('##wind_speed', cascade._wind_speed): cascade.wind_speed = cascade._wind_speed[0]
				imgui_text_tooltip('Wind Direction:    ', ''); ImGui.SameLine(); if ImGui.SliderAngle('##wind_direction', cascade._wind_direction): cascade.wind_direction = rad_to_deg(cascade._wind_direction[0])
				imgui_text_tooltip('Fetch Length:      ', 'Denotes the distance from shoreline (in kilometers).\nIncreasing makes waves steeper, but reduces their \'choppiness\'.'); ImGui.SameLine(); if ImGui.InputFloat('##fetch_length', cascade._fetch_length): cascade.fetch_length = cascade._fetch_length[0]
				imgui_text_tooltip('Swell:             ', 'Modifies waves to clump in a more elongated, parallel manner.'); ImGui.SameLine(); if ImGui.SliderFloat('##swell', cascade._swell, 0, 2): cascade.swell = cascade._swell[0]
				imgui_text_tooltip('Detail:            ', 'Modifies the attenuation of high frequency waves.'); ImGui.SameLine(); if ImGui.SliderFloat('##detail', cascade._detail, 0, 1): cascade.detail = cascade._detail[0]
				imgui_text_tooltip('Spread:            ', 'Modifies how much wind and swell affect the direction of the waves.'); ImGui.SameLine(); if ImGui.SliderFloat('##spread', cascade._spread, 0, 1): cascade.spread = cascade._spread[0]
				ImGui.Dummy(Vector2(0,0)); ImGui.Separator(); ImGui.Dummy(Vector2(0,0))
				imgui_text_tooltip('Whitecap:          ', 'Modifies how steep a wave needs to be before foam can accumulate.'); ImGui.SameLine(); if ImGui.SliderFloat('##white_cap', cascade._whitecap, 0, 2): cascade.whitecap = cascade._whitecap[0]
				imgui_text_tooltip('Foam Amount:       ', ''); ImGui.SameLine(); if ImGui.SliderFloat('##foam_amount', cascade._foam_amount, 0, 10): cascade.foam_amount = cascade._foam_amount[0]
				ImGui.EndTabItem()
		ImGui.EndTabBar()

	ImGui.SeparatorText('Camera')
	ImGui.Text('Camera Position:    %+.2v' % camera.global_position)
	ImGui.Text('Camera FOV:        '); ImGui.SameLine(); if ImGui.SliderFloat('##fov_float', camera_fov, 20, 170): camera.fov = camera_fov[0]

	ImGui.Dummy(Vector2(0,0)); ImGui.Separator(); ImGui.Dummy(Vector2(0,0))
	ImGui.PushStyleColor(ImGui.Col_Text, Color.WEB_GRAY);
	ImGui.Text('Press %s-H to toggle GUI visibility!' % ['Cmd' if OS.get_name() == 'macOS' else 'Ctrl']);
	ImGui.Text('Press %s-F to toggle fullscreen!' % ['Cmd' if OS.get_name() == 'macOS' else 'Ctrl']);
	ImGui.PopStyleColor()
	ImGui.End()
