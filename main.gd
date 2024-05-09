@tool
extends Node3D

@export var cascades : Array[WaveCascade] :
	set(value):
		var new_size := len(value)
		for i in range(new_size):
			# Ensure all values in the array have an associated cascade
			if not value[i]: value[i] = WaveCascade.new()
			value[i].generate_spectrum()
		cascades = value
		_update_texture_array_size(displacement_texture_array, new_size)
		_update_texture_array_size(normal_texture_array, new_size)
		map_scales.resize(new_size); foam_scales.resize(new_size)
		if material:
			material.set_shader_parameter('num_cascades', new_size)

## How many times the wave simulation should update per second
@export var update_rate := 24.0

var map_scales : PackedVector2Array;
var foam_scales : PackedFloat32Array;
var displacement_texture_array := Texture2DArray.new()
var normal_texture_array := Texture2DArray.new()

@onready var material : ShaderMaterial = $MeshInstance3D.get_surface_override_material(0)
func _ready() -> void:
	while true:
		for i in range(len(self.cascades)):
			var cascade := self.cascades[i]
			cascade.generate_maps()
			displacement_texture_array.update_layer(cascade.displacement_map_image, i)
			normal_texture_array.update_layer(cascade.normal_map_image, i)
			map_scales[i] = Vector2(1.0, 1.0) / cascade.tile_length * cascade.tile_scale
			foam_scales[i] = cascade.foam_contribution
		material.set_shader_parameter('displacements', displacement_texture_array)
		material.set_shader_parameter('normals', normal_texture_array)
		material.set_shader_parameter('map_scales', map_scales)
		material.set_shader_parameter('foam_scales', foam_scales)
		await get_tree().create_timer(1.0 / update_rate).timeout

func _notification(what):
	if what == NOTIFICATION_PREDELETE: 
		for cascade in self.cascades:
			cascade.cleanup_gpu()

func _update_texture_array_size(texture_array : Texture2DArray, size : int, placeholder_image := Image.create(256, 256, false, Image.FORMAT_RGBAH)) -> void:
	var image_array : Array[Image]; image_array.resize(size); image_array.fill(placeholder_image)
	texture_array.create_from_images(image_array)
