# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GodotOceanWaves is a real-time ocean simulation system using inverse Fast Fourier Transform (FFT) for generating realistic ocean waves. The project demonstrates advanced GPU compute techniques within the Godot Engine, implementing scientifically accurate wave generation based on directional ocean-wave spectra.

## Development Environment

### Testing and Running
- Testing is done manually in Godot - no automated testing framework
- Run the project directly in Godot Editor or export and run as standalone
- Main scene: `main.tscn`
- Press `Cmd/Ctrl + H` to toggle ImGui interface for parameter adjustment
- Press `Cmd/Ctrl + F` to toggle fullscreen

### Build Requirements
- Godot Engine 4.4 with Forward Plus rendering
- ImGui addon for runtime parameter manipulation
- GPU with compute shader support for FFT calculations

## Core Architecture

### Wave Generation Pipeline
The system follows a multi-stage compute shader pipeline:

1. **Spectrum Generation** (`spectrum_compute.glsl`): Creates initial wave spectra based on oceanographic parameters
2. **Modulation** (`spectrum_modulate.glsl`): Applies time-based wave propagation using dispersion relations
3. **FFT Processing**: 
   - `fft_butterfly.glsl`: Pre-computes FFT butterfly factors
   - `fft_compute.glsl`: Performs row/column FFT using Stockham algorithm
   - `transpose.glsl`: Transposes texture for efficient column-wise FFT
4. **Map Generation** (`fft_unpack.glsl`): Generates final displacement, normal, and foam maps

### Key Components

**WaveGenerator** (`assets/water/wave_generator.gd`):
- Manages the complete GPU compute pipeline
- Handles FFT calculations and texture management
- Implements load balancing to distribute cascade updates across frames
- Core class for all wave computation

**Water** (`assets/water/water.gd`):
- Main water surface component extending MeshInstance3D
- Manages wave cascades and rendering parameters
- Interfaces between WaveGenerator and visual rendering
- Handles global shader parameter updates

**WaveCascadeParameters** (`assets/water/wave_cascade_parameters.gd`):
- Resource class containing oceanographic parameters
- Controls wind speed, direction, fetch length, swell, foam properties
- Each cascade represents a different scale of wave detail
- Parameters follow scientific ocean modeling (JONSWAP spectrum, Hasselmann directional spreading)

**RenderingContext** (`assets/render_context.gd`):
- Wrapper around Godot's RenderingDevice for compute operations
- Manages GPU resource allocation and cleanup
- Provides higher-level abstractions for compute pipeline creation

### Wave Cascade System
- Multiple wave cascades layer different scales of wave detail
- Each cascade has independent parameters and tiling sizes
- Automatic phase offsetting prevents wave interference
- Cascades must use same texture resolution but can have different tile sizes

### Performance Optimization
- **Load Balancing**: Updates one cascade per frame to reduce stutter
- **Update Rate Control**: Configurable updates per second (default 50fps)
- **Mesh Quality**: High/low quality clipmaps for different performance needs
- **Texture Resolutions**: 128x128 to 1024x1024 for FFT input size

## Shader Architecture

### Compute Shaders
All compute shaders located in `assets/shaders/compute/`:
- Use Godot's RenderingDevice abstraction
- Follow scientific oceanography algorithms (Tessendorf, JONSWAP)
- Implement Stockham FFT for GPU efficiency

### Spatial Shaders
Located in `assets/shaders/spatial/`:
- `water.gdshader`: Main water surface rendering with GGX microfacet distribution
- `sea_spray.gdshader`: Particle-based sea spray with dissolve effects
- `sea_spray_particle.gdshader`: Custom particle shader for spray particles

### Global Shader Parameters
Defined in `project.godot` and managed by Water class:
- `displacements`: Texture2DArray of displacement maps
- `normals`: Texture2DArray of normal maps  
- `water_color`, `foam_color`: Global water appearance
- `num_cascades`: Number of active wave cascades

## ImGui Integration
- Runtime parameter adjustment through ImGui interface
- Cascade-specific parameter tabs
- Real-time performance monitoring (FPS display)
- Color pickers for water/foam colors
- Camera and rendering controls

## File Organization

### Core Water System
- `assets/water/water.gd`: Main water surface manager
- `assets/water/wave_generator.gd`: GPU compute pipeline
- `assets/water/wave_cascade_parameters.gd`: Oceanographic parameters
- `assets/water/*.tres`: Material resources for water and spray

### Rendering Infrastructure  
- `assets/render_context.gd`: GPU resource management wrapper
- `assets/shaders/`: All GLSL compute and spatial shaders
- `assets/water/*.obj`: High/low quality clipmap meshes

### Scene Structure
- `main.tscn`: Main scene with Water node and camera
- `main.gd`: Scene controller with ImGui interface and audio management
- `assets/player/camera.gd`: Free-look camera controller

## Scientific Implementation Details

### Wave Spectrum Functions
- **TMA Spectrum**: Combines JONSWAP with depth attenuation
- **Directional Spreading**: Mixed flat/Hasselmann spreading with swell parameter
- **Small-wave Suppression**: Exponential term for detail control
- **Parameters**: Wind speed/direction, fetch length, depth, swell, spread, detail

### FFT Implementation  
- **Stockham Algorithm**: Avoids bit-reversal permutation
- **Butterfly Textures**: Pre-computed dataflow encoding
- **2D Processing**: Row-wise FFT → transpose → column-wise FFT
- **Complex Number Handling**: Stored in RG texture channels

### Foam Generation
- **Jacobian Detection**: Foam appears where wave peaks curl (negative Jacobian)
- **Accumulation Model**: Linear growth, exponential decay
- **Whitecap Threshold**: Configurable steepness threshold for foam generation

When modifying this system, ensure scientific accuracy is maintained and GPU performance considerations are respected. The compute pipeline is carefully optimized and changes should preserve the mathematical relationships between oceanographic parameters.