class_name RenderingContext extends Object
### A wrapper around [RenderingDevice] that handles basic memory management/allocation 

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
	
class Descriptor:
	var rid : RID
	var type : RenderingDevice.UniformType
	
	func _init(rid_ : RID, type_ : RenderingDevice.UniformType) -> void:
		rid = rid_; type = type_
		
var device : RenderingDevice
var deletion_queue := DeletionQueue.new()
var needs_sync := false

static func create() -> RenderingContext:
	var context := RenderingContext.new()
	context.device = RenderingServer.create_local_rendering_device()
	return context
	
func free() -> void:
	if not device: return
	
	# All resources must be freed after use to avoid memory leaks.
	deletion_queue.flush(device)
	device.free()
	device = null
	
# --- WRAPPER FUNCTIONS ---
func submit() -> void: device.submit(); needs_sync = true
func sync() -> void: device.sync(); needs_sync = false
func compute_list_begin() -> int: return device.compute_list_begin()
func compute_list_end() -> void: device.compute_list_end()

# --- HELPER FUNCTIONS ---
### Loads and compiles a [code].glsl[/code] compute shader.
func load_shader(path : String) -> RID:
	var shader_spirv : RDShaderSPIRV = load(path).get_spirv()
	return deletion_queue.push(device.shader_create_from_spirv(shader_spirv))

func create_storage_buffer(size : int=0, data : PackedByteArray=[]) -> Descriptor:
	return Descriptor.new(deletion_queue.push(device.storage_buffer_create(size if size > 0 else data.size(), data)), RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER)

func create_texture(format : RenderingDevice.DataFormat, usage : RenderingDevice.TextureUsageBits=0xA8, dimensions:=Vector2(256, 256), view:=RDTextureView.new(), data : PackedByteArray=[]) -> Descriptor:
	var texture_format := RDTextureFormat.new()
	texture_format.format = format
	texture_format.width = dimensions.y
	texture_format.height = dimensions.x
	texture_format.usage_bits = usage # Default: TEXTURE_USAGE_STORAGE_BIT | TEXTURE_USAGE_CPU_READ_BIT | TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return Descriptor.new(deletion_queue.push(device.texture_create(texture_format, view, data)), RenderingDevice.UNIFORM_TYPE_IMAGE)

### Creates a descriptor set. The ordering of the provided descriptors matches the binding ordering
### within the shader.
func create_descriptor_set(descriptors : Array[Descriptor], shader : RID, descriptor_set_index :=0) -> RID:
	var uniforms : Array[RDUniform]
	for i in range(len(descriptors)):
		var uniform := RDUniform.new()
		uniform.uniform_type = descriptors[i].type
		uniform.binding = i  # This matches the binding in the shader.
		uniform.add_id(descriptors[i].rid)
		uniforms.push_back(uniform)
	return deletion_queue.push(device.uniform_set_create(uniforms, shader, descriptor_set_index))

### Returns a [Callable] which will dispatch a compute pipeline (within a compute) list based on the
### provided block dimensions. The ordering of the provided descriptor sets matches the set ordering
### within the shader.
func create_pipeline(block_dimensions : Array[int], descriptor_sets : Array[RID], shader : RID) -> Callable:
	assert(len(block_dimensions) == 3, 'Must specify block dimensions for all x, y, z dimensions!')
	var pipeline = deletion_queue.push(device.compute_pipeline_create(shader))
	return func(context : RenderingContext, compute_list : int, push_constants:=[]) -> void:
		var device := context.device
		device.compute_list_add_barrier(compute_list) # FIXME: Barrier may not always be needed, but whatever...
		device.compute_list_bind_compute_pipeline(compute_list, pipeline)
		
		for i in range(len(descriptor_sets)):
			device.compute_list_bind_uniform_set(compute_list, descriptor_sets[i], i)
			
		if not push_constants.is_empty():
			var packed_push_constants := _pack_data_f32(push_constants)
			device.compute_list_set_push_constant(compute_list, packed_push_constants, packed_push_constants.size())
			
		device.compute_list_dispatch(compute_list, block_dimensions[0], block_dimensions[1], block_dimensions[2])

### Returns a [PackedFloat32Array] from the provided data, whose size is rounded up to the nearest
### power of 2 with a minimum size of 16.
func _pack_data_f32(data : Array) -> PackedByteArray:
	var packed_data := PackedFloat32Array(data).to_byte_array()
	assert(packed_data.size() <= 1024, 'Push constant size must be less than 1024 bytes!')
	
	var s := packed_data.size() - 1; s |= s >> 1; s |= s >> 2; s |= s >> 4; s |= s >> 8; s |= s >> 16; s += 1
	var padding := maxi(s, 16) - packed_data.size()
	if padding >= 0:
		var padded_data : PackedByteArray; padded_data.resize(padding); padded_data.fill(0)
		packed_data.append_array(padded_data)
	return packed_data
