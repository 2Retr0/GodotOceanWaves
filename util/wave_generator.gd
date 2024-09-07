@tool
class_name WaveGenerator extends Resource

const G := 9.81
const DEPTH := 20.0

var map_size : int
var parameters : Array[WaveCascadeParameters]
var context : RenderingContext
var pipelines : Dictionary
var descriptors : Dictionary

func init_gpu() -> void:
	print('init_gpu!')
	# --- DEVICE/SHADER CREATION ---
	if not context: context = RenderingContext.create(RenderingServer.get_rendering_device())
	var spectrum_compute_shader := context.load_shader('./assets/shaders/compute/spectrum_compute.glsl')
	var fft_butterfly_shader := context.load_shader('./assets/shaders/compute/fft_butterfly.glsl')
	var spectrum_modulate_shader := context.load_shader('./assets/shaders/compute/spectrum_modulate.glsl')
	var fft_compute_shader := context.load_shader('./assets/shaders/compute/fft_compute.glsl')
	var transpose_shader := context.load_shader('./assets/shaders/compute/transpose.glsl')
	var fft_unpack_shader := context.load_shader('./assets/shaders/compute/fft_unpack.glsl')

	# --- DESCRIPTOR PREPARATION ---
	var dims := Vector2i(map_size, map_size)
	var num_fft_stages := int(log(map_size) / log(2))
	var num_cascades := maxi(2, len(parameters)) # FIXME: idk why this is needed!

	descriptors['spectrum'] = context.create_texture(dims, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT, num_cascades)
	descriptors['butterfly_factors'] = context.create_storage_buffer(num_fft_stages*map_size * 4 * 4) # Size: (#FFT stages * map size * sizeof(vec4))
	descriptors['fft_buffer'] = context.create_storage_buffer(num_cascades * map_size*map_size * 4*2 * 2 * 4) # Size: (map size^2 * 4 FFTs * 2 temp buffers (for Stockham FFT) * sizeof(vec2))
	descriptors['displacement_map'] = context.create_texture(dims, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT, num_cascades)
	descriptors['normal_map'] = context.create_texture(dims, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT, num_cascades)

	var spectrum_set := context.create_descriptor_set([descriptors['spectrum']], spectrum_compute_shader, 0)
	var fft_butterfly_set := context.create_descriptor_set([descriptors['butterfly_factors']], fft_butterfly_shader, 0)
	var fft_compute_set := context.create_descriptor_set([descriptors['butterfly_factors'], descriptors['fft_buffer']], fft_compute_shader, 0)
	var fft_buffer_set := context.create_descriptor_set([descriptors['fft_buffer']], spectrum_modulate_shader, 1)
	var unpack_set := context.create_descriptor_set([descriptors['displacement_map'], descriptors['normal_map']], fft_unpack_shader, 0)

	# --- COMPUTE PIPELINE CREATION ---
	pipelines['spectrum_compute'] = context.create_pipeline([map_size/16, map_size/16, 1], [spectrum_set], spectrum_compute_shader)
	pipelines['spectrum_modulate'] = context.create_pipeline([map_size/16, map_size/16, 1], [spectrum_set, fft_buffer_set], spectrum_modulate_shader)
	pipelines['fft_butterfly'] = context.create_pipeline([map_size/2/64, num_fft_stages, 1], [fft_butterfly_set], fft_butterfly_shader)
	pipelines['fft_compute'] = context.create_pipeline([1, map_size, 4], [fft_compute_set], fft_compute_shader)
	pipelines['transpose'] = context.create_pipeline([map_size/32, map_size/32, 4], [fft_compute_set], transpose_shader)
	pipelines['fft_unpack'] = context.create_pipeline([map_size/16, map_size/16, 1], [unpack_set, fft_buffer_set], fft_unpack_shader)

	# We only need to generate butterfly factors once for each map_size.
	var compute_list := context.compute_list_begin()
	pipelines['fft_butterfly'].call(context, compute_list)
	context.compute_list_end()

func generate_maps(delta : float) -> void:
	if parameters.size() == 0: return
	if not context: init_gpu()

	var compute_list := context.compute_list_begin()
	for i in len(parameters):
		var params := parameters[i]
		params.time += delta * params.time_scale # Update each cascade's time based on its time scale parameter

		if params.should_generate_spectrum:
			var alpha := JONSWAP_alpha(params.wind_speed, params.fetch_length*1e3)
			var omega := JONSWAP_peak_angular_frequency(params.wind_speed, params.fetch_length*1e3)
			pipelines['spectrum_compute'].call(context, compute_list, RenderingContext.create_push_constant([params.spectrum_seed.x, params.spectrum_seed.y, params.tile_length.x, params.tile_length.y, alpha, omega, params.wind_speed, deg_to_rad(params.wind_direction), DEPTH, params.swell, params.detail, params.spread, i]))
			params.should_generate_spectrum = false
	#context.compute_list_add_barrier(compute_list)

	for i in len(parameters): pipelines['spectrum_modulate'].call(context, compute_list, RenderingContext.create_push_constant([parameters[i].tile_length.x, parameters[i].tile_length.y, DEPTH, parameters[i].time, i]))
	#context.compute_list_add_barrier(compute_list)
	for i in len(parameters): pipelines['fft_compute'].call(context, compute_list, RenderingContext.create_push_constant([i]))
	#context.compute_list_add_barrier(compute_list)
	for i in len(parameters): pipelines['transpose'].call(context, compute_list, RenderingContext.create_push_constant([i]))
	#context.compute_list_add_barrier(compute_list)
	for i in len(parameters): pipelines['fft_compute'].call(context, compute_list, RenderingContext.create_push_constant([i]))
	#context.compute_list_add_barrier(compute_list)
	## Note: We need not do a second transpose here since rotating the wave by pi/2 doesn't affect it visually.
	for i in len(parameters):
		var params := parameters[i]
		var foam_grow_rate := delta*params.time_scale * params.foam_amount*7.5
		var foam_decay_rate := delta*params.time_scale * maxf(0.5, 10.0 - params.foam_amount)*1.15
		pipelines['fft_unpack'].call(context, compute_list, RenderingContext.create_push_constant([i, params.whitecap, foam_grow_rate, foam_decay_rate]))
	context.compute_list_end()

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if context: context.free()

# Source: https://wikiwaves.org/Ocean-Wave_Spectra#JONSWAP_Spectrum
static func JONSWAP_alpha(wind_speed:=20.0, fetch_length:=550e3) -> float:
	return 0.076 * pow(wind_speed**2 / (fetch_length*G), 0.22)

# Source: https://wikiwaves.org/Ocean-Wave_Spectra#JONSWAP_Spectrum
static func JONSWAP_peak_angular_frequency(wind_speed:=20.0, fetch_length:=550e3) -> float:
	return 22.0 * pow(G*G / (wind_speed*fetch_length), 1.0/3.0)
