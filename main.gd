@tool
extends Node3D

@export var cascades : Array[WaveCascade] :
	set(value):
		cascades = value
		for cascade in cascades: cascade.generate_spectrum()
		_update_texture_array_size(displacement_texture_array, len(cascades))
		_update_texture_array_size(normal_texture_array, len(cascades))
		if material:
			material.set_shader_parameter('num_cascades', len(cascades))

### How many times the wave simulation should update per second
@export var update_rate := 24.0

var displacement_texture_array := Texture2DArray.new()
var normal_texture_array := Texture2DArray.new()

@onready var material : ShaderMaterial = $MeshInstance3D.get_surface_override_material(0)
func _ready() -> void:
	#for cascade in cascades: cascade.generate_spectrum()
	var scales : PackedFloat32Array;
	while true:
		scales.resize(len(cascades))
		for i in range(len(self.cascades)):
			self.cascades[i].generate_maps()
			displacement_texture_array.update_layer(self.cascades[i].displacement_map_image, i)
			normal_texture_array.update_layer(self.cascades[i].normal_map_image, i)
			scales[i] = 1.0 / self.cascades[i].scale
		material.set_shader_parameter('displacements', displacement_texture_array)
		material.set_shader_parameter('normals', normal_texture_array)
		material.set_shader_parameter('scales', scales)
		await get_tree().create_timer(1.0 / update_rate).timeout

#func _process(delta: float) -> void:
	#var scales : PackedFloat32Array
	#for i in range(len(self.cascades)):
		#self.cascades[i].generate_maps()
		#displacement_texture_array.update_layer(self.cascades[i].displacement_map_image, i)
		#normal_texture_array.update_layer(self.cascades[i].normal_map_image, i)
		#scales.append(1.0 / self.cascades[i].scale)
	#material.set_shader_parameter('displacements', displacement_texture_array)
	#material.set_shader_parameter('normals', normal_texture_array)
	#material.set_shader_parameter('scales', scales)

func _notification(what):
	if what == NOTIFICATION_PREDELETE: 
		for cascade in self.cascades:
			cascade.cleanup_gpu()

func _update_texture_array_size(texture_array : Texture2DArray, size : int, placeholder_image := Image.create(256, 256, false, Image.FORMAT_RGBAH)) -> void:
	var image_array : Array[Image]; image_array.resize(size); image_array.fill(placeholder_image)
	texture_array.create_from_images(image_array)
