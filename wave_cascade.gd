@tool
class_name WaveCascade extends Resource

const G := 9.81

var context : RenderingContext
var pipelines : Dictionary
var descriptors : Dictionary
var descriptor_sets : Dictionary

var num_stages := 8
var map_size := 256 : 
	set(value):
		map_size = value
		num_stages = int(log(map_size) / log(2))

var displacement_map_image := Image.create(map_size, map_size, false, Image.FORMAT_RGBAH)
var normal_map_image := Image.create(map_size, map_size, false, Image.FORMAT_RGBAH)

@export_category("Wave Spectrum Parameters")
## Size of tile heightmap should cover (in meters)
@export var tile_length := Vector2(50, 50) :
	set(value): tile_length = value; generate_spectrum()
@export var wind_speed := 20.0 :
	set(value): wind_speed = value; generate_spectrum()
## Distance from shoreline (in kilometers)
@export var fetch_length := 550.0 :
	set(value): fetch_length = value; generate_spectrum()
@export var depth := 20.0 :
	set(value): depth = value; generate_spectrum()
@export_range(0, 5) var swell := 1.0 :
	set(value): swell = value; generate_spectrum()
## Rotational offset of the spectrum (in degrees)
@export_range(0, 360) var angle := 0.0 :
	set(value): angle = value; generate_spectrum()
@export_range(0, 2) var time_scale := 1.0
	
@export_category("Water Shader Parameters")
## The horizontal scaling of the displacement/normal maps
@export_range(0, 5) var tile_scale := 1.0
@export_range(0, 1) var foam_contribution := 1.0

func init_gpu() -> void:
	# --- DEVICE/SHADER CREATION ---
	context = RenderingContext.create()
	var spectrum_compute_shader := context.load_shader('./resources/shaders/compute/spectrum_compute.glsl')
	var fft_butterfly_shader := context.load_shader('./resources/shaders/compute/fft_butterfly.glsl')
	var spectrum_modulate_shader := context.load_shader('./resources/shaders/compute/spectrum_modulate.glsl')
	var fft_compute_shader := context.load_shader('./resources/shaders/compute/fft_compute.glsl')
	var transpose_shader := context.load_shader('./resources/shaders/compute/transpose.glsl')
	var fft_unpack_shader := context.load_shader('./resources/shaders/compute/fft_unpack.glsl')
	
	# --- DESCRIPTOR PREPARATION ---
	descriptors['spectrum_texture'] = context.create_texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT)
	# Buffer Size Explainiation: Butterfly texture->(#FFT stages * map size * sizeof(vec4)) + FFT buffer->(map size^2 * 4 FFTs * 2 temp buffers (for Stockham FFT) * sizeof(vec2))
	descriptors['fft_buffer']       = context.create_storage_buffer((num_stages*map_size)*(4*4) + (map_size*map_size)*4*2*(4*2))
	descriptors['displacement_map'] = context.create_texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	descriptors['normal_map']       = context.create_texture(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	
	var spectrum_set := context.create_descriptor_set([descriptors['spectrum_texture']], spectrum_compute_shader, 0)
	var modulate_set := context.create_descriptor_set([descriptors['spectrum_texture']], spectrum_modulate_shader, 1)
	var fft_set      := context.create_descriptor_set([descriptors['fft_buffer']], fft_compute_shader, 0)
	var unpack_set   := context.create_descriptor_set([descriptors['displacement_map'], descriptors['normal_map']], fft_unpack_shader, 1)
	
	# --- COMPUTE PIPELINE CREATION ---
	pipelines['spectrum_compute']  = context.create_pipeline([map_size/16, map_size/16, 1], [spectrum_set], spectrum_compute_shader)
	pipelines['fft_butterfly']     = context.create_pipeline([1, map_size/2/64, num_stages], [fft_set], fft_butterfly_shader)
	pipelines['spectrum_modulate'] = context.create_pipeline([map_size/16, map_size/16, 1], [fft_set, modulate_set], spectrum_modulate_shader)
	pipelines['fft_compute']       = context.create_pipeline([1, map_size, 4], [fft_set], fft_compute_shader)
	pipelines['transpose']         = context.create_pipeline([map_size/32, map_size/32, 4], [fft_set], transpose_shader)
	pipelines['fft_unpack']        = context.create_pipeline([map_size/16, map_size/16, 1], [fft_set, unpack_set], fft_unpack_shader)
	
func cleanup_gpu():
	if context: context.free()

func generate_spectrum() -> void:
	if not context: init_gpu()
	if context.needs_sync: context.sync()
	
	var alpha := JONSWAP_alpha(wind_speed, fetch_length*1e3)
	var omega := JONSWAP_peak_angular_frequency(wind_speed, fetch_length*1e3)
	
	# We precompute the initial spectrum (i.e., t=0) as well as the FFT butterfly
	# factors only when needed.
	var compute_list := context.compute_list_begin()
	pipelines['spectrum_compute'].call(context, compute_list, [tile_length.x, tile_length.y, alpha, omega, wind_speed, depth, swell, deg_to_rad(angle)])
	pipelines['fft_butterfly'].call(context, compute_list)
	context.compute_list_end()
	
	# Submit commands to GPU and immediately sync
	context.submit()
	context.sync()

func generate_maps() -> void:
	if context.needs_sync: 
		context.sync()
		displacement_map_image.set_data(map_size, map_size, false, Image.FORMAT_RGBAH, context.device.texture_get_data(descriptors['displacement_map'].rid, 0))
		normal_map_image.set_data(map_size, map_size, false, Image.FORMAT_RGBAH, context.device.texture_get_data(descriptors['normal_map'].rid, 0))

	var compute_list := context.compute_list_begin()
	pipelines['spectrum_modulate'].call(context, compute_list, [tile_length.x, tile_length.y, depth, Time.get_ticks_msec() * 1e-3 * time_scale])
	pipelines['fft_compute'].call(context, compute_list)
	pipelines['transpose'].call(context, compute_list)
	pipelines['fft_compute'].call(context, compute_list)
	# Note: We need not do a second transpose here since rotating the wave by pi/2 doesn't affect it visually.
	pipelines['fft_unpack'].call(context, compute_list)
	context.compute_list_end()
	context.submit()

# Source: https://wikiwaves.org/Ocean-Wave_Spectra#JONSWAP_Spectrum
static func JONSWAP_alpha(wind_speed:=20.0, fetch_length:=550e3) -> float:
	return 0.075 * pow(wind_speed**2 / (fetch_length*G), 0.22)

# Source: https://wikiwaves.org/Ocean-Wave_Spectra#JONSWAP_Spectrum
static func JONSWAP_peak_angular_frequency(wind_speed:=20.0, fetch_length:=550e3) -> float:
	return 22.0 * pow(G*G / (wind_speed*fetch_length), 0.3333)
