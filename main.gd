@tool
extends Node3D

@export var cascades : Array[WaveCascade] :
	set(value):
		cascades = value
		var num_cascades := len(cascades)
		var placeholder_image := Image.create(256, 256, false, Image.FORMAT_RGBAH)
		var image_array : Array[Image]
		image_array.resize(num_cascades); image_array.fill(placeholder_image)
		
		for cascade in cascades: cascade.generate_spectrum()
		displacement_texture_array.create_from_images(image_array)
		normal_texture_array.create_from_images(image_array)
	
var displacement_texture_array := Texture2DArray.new()
var normal_texture_array := Texture2DArray.new()
	
@onready var material : ShaderMaterial = $MeshInstance3D.get_surface_override_material(0)
#func _ready() -> void:
	#var placeholder_image := Image.create(256, 256, false, Image.FORMAT_RGBAH)
	#displacement_texture_array.create_from_images([placeholder_image, placeholder_image, placeholder_image])
	#normal_texture_array.create_from_images([placeholder_image, placeholder_image, placeholder_image])
	#material.set_shader_parameter('num_cascades', len(cascades))
	#
	#for cascade in self.cascades:
		#cascade.generate_spectrum()
	
	#while true:
		#for i in range(len(self.cascades)):
			#self.cascades[i].generate_maps()
			#material.set_shader_parameter('displacement_map%d' % i, self.cascades[i].displacement_map_image)
			#material.set_shader_parameter('normal_map%d' % i, self.cascades[i].normal_map_image)
			#material.set_shader_parameter('scale%d' % i, 1.0 / self.cascades[i].scale)
		#await get_tree().create_timer(1.0/24.0).timeout

func _process(delta: float) -> void:
	var scales : PackedFloat32Array
	for i in range(len(self.cascades)):
		self.cascades[i].generate_maps()
		displacement_texture_array.update_layer(self.cascades[i].displacement_map_image, i)
		normal_texture_array.update_layer(self.cascades[i].normal_map_image, i)
		#displacements.push_back(self.cascades[i].displacement_map_image)
		#normals.push_back(self.cascades[i].normal_map_image)
		scales.append(1.0 / self.cascades[i].scale)
		#material.set_shader_parameter('displacement_map%d' % i, self.cascades[i].displacement_map_image)
		#material.set_shader_parameter('normal_map%d' % i, self.cascades[i].normal_map_image)
	material.set_shader_parameter('num_cascades', len(cascades))
	material.set_shader_parameter('displacements', displacement_texture_array)
	material.set_shader_parameter('normals', normal_texture_array)
	material.set_shader_parameter('scales', scales)

func _notification(what):
	if what == NOTIFICATION_PREDELETE: 
		for cascade in self.cascades:
			cascade.cleanup_gpu()
