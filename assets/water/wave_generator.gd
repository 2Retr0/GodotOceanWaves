@tool
class_name WaveGenerator extends Node
## Handles the compute pipeline for wave spectra generation/FFT.

const G := 9.81
const DEPTH := 20.0

var map_size : int
var context : RenderingContext
var pipelines : Dictionary
var descriptors : Dictionary

# Generator state per invocation of `update()`.
var pass_parameters : Array[WaveCascadeParameters]
var pass_num_cascades_remaining : int

func init_gpu(num_cascades : int) -> void:
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

	descriptors[&'spectrum'] = context.create_texture(dims, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT, num_cascades)
	descriptors[&'butterfly_factors'] = context.create_storage_buffer(num_fft_stages*map_size * 4 * 4)         # Size: (#FFT stages * map size * sizeof(vec4))
	descriptors[&'fft_buffer'] = context.create_storage_buffer(num_cascades * map_size*map_size * 4*2 * 2 * 4) # Size: (map size^2 * 4 FFTs * 2 temp buffers (for Stockham FFT) * sizeof(vec2))
	descriptors[&'displacement_map'] = context.create_texture(dims, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT, num_cascades)
	descriptors[&'normal_map'] = context.create_texture(dims, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT, num_cascades)

	var spectrum_set := context.create_descriptor_set([descriptors[&'spectrum']], spectrum_compute_shader, 0)
	var fft_butterfly_set := context.create_descriptor_set([descriptors[&'butterfly_factors']], fft_butterfly_shader, 0)
	var fft_compute_set := context.create_descriptor_set([descriptors[&'butterfly_factors'], descriptors[&'fft_buffer']], fft_compute_shader, 0)
	var fft_buffer_set := context.create_descriptor_set([descriptors[&'fft_buffer']], spectrum_modulate_shader, 1)
	var unpack_set := context.create_descriptor_set([descriptors[&'displacement_map'], descriptors[&'normal_map']], fft_unpack_shader, 0)

	# --- COMPUTE PIPELINE CREATION ---
	pipelines[&'spectrum_compute'] = context.create_pipeline([map_size/16, map_size/16, 1], [spectrum_set], spectrum_compute_shader)
	pipelines[&'spectrum_modulate'] = context.create_pipeline([map_size/16, map_size/16, 1], [spectrum_set, fft_buffer_set], spectrum_modulate_shader)
	pipelines[&'fft_butterfly'] = context.create_pipeline([map_size/2/64, num_fft_stages, 1], [fft_butterfly_set], fft_butterfly_shader)
	pipelines[&'fft_compute'] = context.create_pipeline([1, map_size, 4], [fft_compute_set], fft_compute_shader)
	pipelines[&'transpose'] = context.create_pipeline([map_size/32, map_size/32, 4], [fft_compute_set], transpose_shader)
	pipelines[&'fft_unpack'] = context.create_pipeline([map_size/16, map_size/16, 1], [unpack_set, fft_buffer_set], fft_unpack_shader)

	# We only need to generate butterfly factors once for each map_size.
	var compute_list := context.compute_list_begin()
	pipelines[&'fft_butterfly'].call(context, compute_list)
	context.compute_list_end()

func _process(delta: float) -> void:
	# Update one cascade each frame for load balancing.
	if pass_num_cascades_remaining == 0: return
	pass_num_cascades_remaining -= 1

	var compute_list := context.compute_list_begin()
	_update(compute_list, pass_num_cascades_remaining, pass_parameters)
	context.compute_list_end()

func _update(compute_list : int, cascade_index : int, parameters : Array[WaveCascadeParameters]) -> void:
	var params := parameters[cascade_index]
	## --- WAVE SPECTRA UPDATE ---
	if params.should_generate_spectrum:
		var alpha := JONSWAP_alpha(params.wind_speed, params.fetch_length*1e3)
		var omega := JONSWAP_peak_angular_frequency(params.wind_speed, params.fetch_length*1e3)
		pipelines[&'spectrum_compute'].call(context, compute_list, RenderingContext.create_push_constant([params.spectrum_seed.x, params.spectrum_seed.y, params.tile_length.x, params.tile_length.y, alpha, omega, params.wind_speed, deg_to_rad(params.wind_direction), DEPTH, params.swell, params.detail, params.spread, cascade_index]))
		params.should_generate_spectrum = false
	pipelines[&'spectrum_modulate'].call(context, compute_list, RenderingContext.create_push_constant([params.tile_length.x, params.tile_length.y, DEPTH, params.time, cascade_index]))

	## --- WAVE SPECTRA INVERSE FOURIER TRANSFORM ---
	var fft_push_constant := RenderingContext.create_push_constant([cascade_index])
	# Note: We need not do a second transpose after computing FFT on rows since rotating the wave by
	#       PI/2 doesn't affect it visually.
	pipelines[&'fft_compute'].call(context, compute_list, fft_push_constant)
	pipelines[&'transpose'].call(context, compute_list, fft_push_constant)
	context.compute_list_add_barrier(compute_list) # FIXME: Why is a barrier only needed here?!
	pipelines[&'fft_compute'].call(context, compute_list, fft_push_constant)

	## --- DISPLACEMENT/NORMAL MAP UPDATE ---
	pipelines[&'fft_unpack'].call(context, compute_list, RenderingContext.create_push_constant([cascade_index, params.whitecap, params.foam_grow_rate, params.foam_decay_rate]))

## Begins updating wave cascades based on the provided parameters. To balance stutter,
## the generator will schedule one cascade update per frame. All cascades from the
## previous invocation that have not been processed yet will be updated.
func update(delta : float, parameters : Array[WaveCascadeParameters]) -> void:
	assert(parameters.size() != 0)
	if not context:
		init_gpu(maxi(2, len(parameters))) # FIXME: This is needed because my RenderContext API sucks...
	elif pass_num_cascades_remaining != 0: # Update cascades from previous invocation that have yet to be processed...
		var compute_list := context.compute_list_begin()
		for i in range(pass_num_cascades_remaining):
			_update(compute_list, i, pass_parameters)
		context.compute_list_end()

	# Update each cascade's parameters that rely on time delta
	for i in len(parameters):
		var params := parameters[i]
		params.time += delta
		# Note: The constants are used to normalize parameters between 0 and 10.
		params.foam_grow_rate = delta * params.foam_amount*7.5
		params.foam_decay_rate = delta * maxf(0.5, 10.0 - params.foam_amount)*1.15

	pass_parameters = parameters
	pass_num_cascades_remaining = len(parameters)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if context: context.free()

# Source: https://wikiwaves.org/Ocean-Wave_Spectra#JONSWAP_Spectrum
static func JONSWAP_alpha(wind_speed:=20.0, fetch_length:=550e3) -> float:
	return 0.076 * pow(wind_speed**2 / (fetch_length*G), 0.22)

# Source: https://wikiwaves.org/Ocean-Wave_Spectra#JONSWAP_Spectrum
static func JONSWAP_peak_angular_frequency(wind_speed:=20.0, fetch_length:=550e3) -> float:
	return 22.0 * pow(G*G / (wind_speed*fetch_length), 1.0/3.0)
