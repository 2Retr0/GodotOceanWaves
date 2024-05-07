@tool
class_name WaveCascade extends Resource

class DeletionQueue:
	var queue : Array[RID] = []
	
	func push(rid : RID) -> RID:
		queue.push_back(rid)
		return rid
	
	func flush(device : RenderingDevice) -> void:
		# We work backwards in order of allocation when freeing resources
		for i in range(queue.size() - 1, -1, -1):
			device.free_rid(queue[i])
			queue[i] = RID()
		queue.clear()

const G := 9.81

var device : RenderingDevice
var has_submitted := false
var deletion_queue := DeletionQueue.new()

var pipelines : Dictionary
var uniforms : Dictionary
var descriptor_sets : Dictionary

var displacement_map_image := Image.create(256, 256, false, Image.FORMAT_RGBAH)
var normal_map_image := Image.create(256, 256, false, Image.FORMAT_RGBAH)

### Size of tile heightmap should cover (in meters)
@export var tile_length := Vector2(50, 50) :
	set(value): tile_length = value; generate_spectrum()

@export var wind_speed := 20.0 :
	set(value): wind_speed = value; generate_spectrum()
	
### Distance from shoreline (in kilometers)
@export var fetch_length := 550.0 :
	set(value): fetch_length = value; generate_spectrum()
	
@export var scale := 50.0

func init_gpu() -> void:
	# --- DEVICE/SHADER CREATION ---
	device = RenderingServer.create_local_rendering_device()
	var spectrum_compute_shader := load_shader('./resources/shaders/compute/spectrum_compute.glsl')
	var spectrum_modulate_shader := load_shader('./resources/shaders/compute/spectrum_modulate.glsl')
	var ifft_compute_shader := load_shader('./resources/shaders/compute/fft_compute.glsl')
	var ifft_unpack_shader := load_shader('./resources/shaders/compute/fft_unpack.glsl')
	var transpose_shader := load_shader('./resources/shaders/compute/transpose.glsl')
	var fft_butterfly_shader := load_shader('./resources/shaders/compute/fft_butterfly.glsl')
	
	# --- DATA/UNIFORM PREPARATION ---
	uniforms['spectrum_texture'] = create_texture(create_texture_format(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT))
	uniforms['fft_buffer'] = create_storage_buffer((8*256)*(4*4) + (256*256)*4*2*(4*2))
	uniforms['displacement_map'] = create_texture(create_texture_format())
	uniforms['normal_map'] = create_texture(create_texture_format())
	
	descriptor_sets['uniform_set'] = create_descriptor_set([
		create_uniform(uniforms['spectrum_texture'], 0),
		create_uniform(uniforms['fft_buffer'], 1, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),
		create_uniform(uniforms['displacement_map'], 2),
		create_uniform(uniforms['normal_map'], 3)
	], spectrum_compute_shader, 0)
	
	# --- CREATE COMPUTE PIPELINES ---
	pipelines['spectrum_compute'] = create_pipeline(spectrum_compute_shader)
	pipelines['fft_butterfly'] = create_pipeline(fft_butterfly_shader)
	pipelines['spectrum_modulate'] = create_pipeline(spectrum_modulate_shader)
	pipelines['fft_compute'] = create_pipeline(ifft_compute_shader)
	pipelines['fft_unpack'] = create_pipeline(ifft_unpack_shader)
	pipelines['transpose'] = create_pipeline(transpose_shader)
	
func cleanup_gpu():
	if device == null: return
	
	# All resources must be freed after use to avoid memory leaks.
	deletion_queue.flush(device)
	device.free()
	device = null

func generate_spectrum() -> void:
	if not device: init_gpu()
	if has_submitted: 
		device.sync()
		has_submitted = false
	
	var alpha := JONSWAP_alpha(wind_speed, fetch_length*1e3)
	var peak_angular_frequency := JONSWAP_peak_angular_frequency(wind_speed, fetch_length*1e3)
	
	var compute_list := device.compute_list_begin()
	device.compute_list_bind_compute_pipeline(compute_list, pipelines['spectrum_compute'])
	device.compute_list_bind_uniform_set(compute_list, descriptor_sets['uniform_set'], 0)
	set_push_constant(compute_list, [tile_length.x, tile_length.y, alpha, peak_angular_frequency, wind_speed])
	device.compute_list_dispatch(compute_list, 256 / 16, 256 / 16, 1)
	device.compute_list_add_barrier(compute_list)
	device.compute_list_bind_compute_pipeline(compute_list, pipelines['fft_butterfly'])
	device.compute_list_bind_uniform_set(compute_list, descriptor_sets['uniform_set'], 0)
	device.compute_list_dispatch(compute_list, 1, 128 / 64, 8)
	device.compute_list_end()
	
	# Submit commands to GPU and immediately sync
	device.submit()
	device.sync()
	print('Generated ocean wave spectrum! (wind_speed=%.1fm/s, fetch_length=%.1fkm)' % [wind_speed, fetch_length])

func generate_maps() -> void:
	# 870 fps base
	if has_submitted: 
		device.sync()
		has_submitted = false
		# 150 fps hit
		displacement_map_image = Image.create_from_data(256, 256, false, Image.FORMAT_RGBAH, device.texture_get_data(uniforms['displacement_map'], 0))
		normal_map_image = Image.create_from_data(256, 256, false, Image.FORMAT_RGBAH, device.texture_get_data(uniforms['normal_map'], 0))
	
	var compute_list := device.compute_list_begin()
	# 5 fps hit
	device.compute_list_bind_compute_pipeline(compute_list, pipelines['spectrum_modulate'])
	device.compute_list_bind_uniform_set(compute_list, descriptor_sets['uniform_set'], 0)
	set_push_constant(compute_list, [tile_length.x, tile_length.y, Time.get_ticks_msec() * 1e-3])
	device.compute_list_dispatch(compute_list, 256 / 16, 256 / 16, 1)
	## 280-290 FPS
	##for i in range(2):
	# 110 fps hit
	device.compute_list_add_barrier(compute_list)
	device.compute_list_bind_compute_pipeline(compute_list, pipelines['fft_compute'])
	device.compute_list_bind_uniform_set(compute_list, descriptor_sets['uniform_set'], 0)
	device.compute_list_dispatch(compute_list, 1, 256, 4)
	
	device.compute_list_add_barrier(compute_list)
	device.compute_list_bind_compute_pipeline(compute_list, pipelines['transpose'])
	device.compute_list_bind_uniform_set(compute_list, descriptor_sets['uniform_set'], 0)
	device.compute_list_dispatch(compute_list, 256 / 32, 256 / 32, 4)
	
	device.compute_list_add_barrier(compute_list)
	device.compute_list_bind_compute_pipeline(compute_list, pipelines['fft_compute'])
	device.compute_list_bind_uniform_set(compute_list, descriptor_sets['uniform_set'], 0)
	device.compute_list_dispatch(compute_list, 1, 256, 4)
	
	# 110 fps hit
	device.compute_list_add_barrier(compute_list)
	device.compute_list_bind_compute_pipeline(compute_list, pipelines['fft_unpack'])
	device.compute_list_bind_uniform_set(compute_list, descriptor_sets['uniform_set'], 0)
	device.compute_list_dispatch(compute_list, 256 / 16, 256 / 16, 1)
	device.compute_list_end()
	device.submit()
	has_submitted = true

# Source: https://wikiwaves.org/Ocean-Wave_Spectra#JONSWAP_Spectrum
static func JONSWAP_alpha(wind_speed:=20.0, fetch_length:=550e3) -> float:
	return 0.075 * pow(wind_speed**2 / (fetch_length*G), 0.22)

# Source: https://wikiwaves.org/Ocean-Wave_Spectra#JONSWAP_Spectrum
static func JONSWAP_peak_angular_frequency(wind_speed:=20.0, fetch_length:=550e3) -> float:
	return 22.0 * pow(G*G / (wind_speed*fetch_length), 0.3333)

func load_shader(path : String) -> RID:
	var shader_spirv : RDShaderSPIRV = load(path).get_spirv()
	return deletion_queue.push(device.shader_create_from_spirv(shader_spirv))

func create_storage_buffer(size : int=0, data : PackedByteArray=[]) -> RID:
	return deletion_queue.push(device.storage_buffer_create(size if size > 0 else data.size(), data))

func create_pipeline(shader : RID) -> RID:
	return deletion_queue.push(device.compute_pipeline_create(shader))

func create_descriptor_set(uniforms : Array[RDUniform], shader : RID, descriptor_set_index : int=0) -> RID:
	return deletion_queue.push(device.uniform_set_create(uniforms, shader, descriptor_set_index))

func create_texture(format : RDTextureFormat, view : RDTextureView=RDTextureView.new(), data : PackedByteArray=[]) -> RID:
	return deletion_queue.push(device.texture_create(format, view, data))

func create_texture_format(format:=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage : RenderingDevice.TextureUsageBits=0xA8, dimensions:=Vector2(256, 256)) -> RDTextureFormat:
	var texture_format := RDTextureFormat.new()
	texture_format.format = format
	texture_format.width = dimensions.y
	texture_format.height = dimensions.x
	texture_format.usage_bits = usage # Default: TEXTURE_USAGE_STORAGE_BIT | TEXTURE_USAGE_CPU_READ_BIT | TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return texture_format

func create_uniform(id : RID, binding : int, type:=RenderingDevice.UNIFORM_TYPE_IMAGE) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding  # This matches the binding in the shader.
	uniform.add_id(id)
	return uniform

func set_push_constant(compute_list : int, data:=[]) -> void:
	var packed_data := PackedFloat32Array(data).to_byte_array()
	assert(data.size() <= 1024, 'Push constant size must be less than 1024 bytes!')
	var s := packed_data.size() - 1; s |= s >> 1; s |= s >> 2; s |= s >> 4; s |= s >> 8; s |= s >> 16; s = max(s - (packed_data.size() - 1), 16 - packed_data.size())
	var padding := s
	
	if padding >= 0:
		var padded_data := PackedByteArray()
		padded_data.resize(padding)
		padded_data.fill(0)
		packed_data.append_array(padded_data)
	return device.compute_list_set_push_constant(compute_list, packed_data, packed_data.size())
