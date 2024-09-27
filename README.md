# GodotOceanWaves
An open ocean rendering experiment in the Godot Engine utilizing the inverse Fourier transform of directional ocean-wave spectra for wave generation. A concise set of parameters is exposed, allowing for scriptable, real-time modification of wave properties to emulate a wide-variety of ocean-wave environments.

[ocean_demo.mp4](https://github.com/user-attachments/assets/a8083878-a297-4536-a481-9123cea7e7df)

## Introduction
### Why Fourier Transforms?
A common approach for animating water in video games is by displacing vertices using *Gerstner waves*. While Gerstner waves work well for modeling the lower-frequency details in calmer waters, they fall short in accurately representing the choppy surfaces in an open ocean. To simulate the latter, a more complex approach simulates waves using the *inverse Fourier transform* of ocean-wave spectra modeled from empirical data gathered by oceanographers.

A benefit of working in frequency space using ocean-wave spectra is the ease of modifying ocean properties (e.g., surface choppiness). When using Gerstner waves, it is unclear how waves (and their parameters) need to be changed to emulate a certain ocean state. In contrast, ocean-wave spectra expose parameters that change waves' properties directly.

To compute the Fourier transform, a *fast Fourier transform* algorithm (FFT) is used specifically. On top of having a lower computational complexity than the classical discrete Fourier transform algorithm ($O(N \log N)$ versus $`O(N^2)`$), the FFT is *scalable as a parallel system*. This means that it is perfect for running on the GPU. Using Gerstner waves requires each thread to perform $N$ computations, one for each wave. In contrast, FFT-based waves only require each thread to perform $\log(N)$ equivalent computations. At scale, more waves can be added to the system (at the same performance cost), permitting more accurate surface simulation.

## Results
### Wave Shading
#### Lighting Model
The ocean lighting model largely follows the BSDF described in the 'Atlas' GDC talk. One deviation, however, is the use of the GGX distribution (rather than Beckmann distribution) for the microfacet distribution. This was due to the GGX distribution's 'flatter' and softer highlights providing a more uniform appearance in many of the ocean-wave environments tested.

The normal/foam map is sampled with a mix between bicubic and bilinear filtering depending on the world-space pixel density (a value dependent on the normal map texture resolution and texture UV tiling size). This effectively reduces texture aliasing artifacts at lower surface resolutions while maintaining the detail at higher surface resolutions.

#### Sea Foam
Tessendorf notes a method for determining when to generate sea foam by checking where the waves' peaks curl into themselves (i.e., when the Jacobian of the displacement is negative). Foam accumulates linearly and dissipates exponentially on a texture over multiple wave updates, and are controlled by "foam grow rate" and "foam decay rate" parameters respectively.

#### Sea Spray
Sea spray is modeled using particles via Godot's GPUParticles3D node and makes heavy use of a custom particle shader. Particles are distributed evenly across the plane within the GPUParticles3D node's bounding box. Then, they are culled based on the foam amount present at their position. Un-culled particles begin their lifecycle at a random offset.

Each sea spray particle uses a billboarded sprite with a single static texture. Over the course of their lifecycle, particles' scales and displacements are modified to emulate a splash's appearance. A dissolve effect in particles' mesh shader fades the sprite in a way that simulates how sea spray atomizes once in the air.

One *major* drawback of this method is that a large increase in particle amount only results in a small increase in sea spray density. This is due to the equal distribution of particles along the bounding box, which results in a majority of the added particles being culled.

![shading_demo](https://github.com/user-attachments/assets/c69766e7-711c-4909-a1fa-290bac0d577a)

### Wave Simulation
The method for generating surface waves closely follows Tessendorf. A directional ocean-wave spectrum function is multiplied with Gaussian-distributed random numbers to generate an initial spectral sea state. The initial state is then propagated in time through a "dispersion relation" (relating the frequency of waves and their propagation speed). An inverse Fourier transform can then be applied to the propagated state to generate displacement and normal maps.

The methodology Tessendorf describes was implemented through a compute shader pipeline using Godot's RenderingDevice abstraction. The following sections detail more on major aspects of the wave generation system.

#### Ocean-Wave Spectra
The directional ocean-wave spectrum function, $S(\omega, \theta)$, returns the energy of a wave given its frequency ($\omega$) and direction ($\theta$). It is comprised of a **non-directional spectrum function**, $S(\omega)$, and a **directional spread function**, $D(\omega, \theta)$; the choice of either is entirely independent.

 * For the **non-directional spectrum function**, the *Texel-Marsen-Arsloe* (TMA) spectrum described in Horvath was chosen. Given the wind speed ($U$), depth ($D$), and fetch length (i.e., distance from shoreline) ($F$), the TMA spectrum combines its preceding *JONSWAP* spectrum with a depth attenuation function and is defined as $S_{\text{TMA}}(\omega) = S_{\text{JONSWAP}}(\omega)\Phi(\omega)$ where:
```math
\begin{align*}
S_{\text{JONSWAP}}(\omega) &= \Big[0.076\Big(\tfrac{U^2}{F \cdot 9.81}\Big)^{0.22}\Big]\Big[\tfrac{9.81^2}{\omega^5}\exp\Big({-\tfrac 5 4}\big(\tfrac{\omega_p}{\omega}\big)^4\Big)\Big] \Big[3.3^{\exp\Big(-\tfrac{(\omega - \omega_p)^2}{2(0.07 + 0.02\cdot\mathrm{step}(\omega - \omega_p))^2\omega_p^2}\Big)}\Big]\\
\Phi(\omega) &\approx \tfrac 1 2 \omega_h^2 + ({-\omega}_h^2+2\omega_h-1)\cdot\mathrm{step}(\omega_h - 1)\\
\omega_p &= 22\Big(\tfrac{9.81^2}{U F}\Big)\\
\omega_h &= \omega \sqrt{\tfrac D {9.81}}
\end{align*}
```
 * For the **directional spread function**, a combination of the *flat* and *Hasselmann* directional spreadings described in Horvath—mixed by a 'spread' parameter ($\mu$)—was chosen. Horvath also proposes the addition of a 'swell' parameter ($\xi$) to model ocean-wave elongation—this was also incorporated into the spread model. The mixed spread function is defined as ${D_{\text{mixed}}(\omega, \theta) = \mathrm{lerp}((2\pi){^{-1}},\ Q(s+s_\xi)\text{|}\cos(\theta \text{/}2)\text{|}^{2(s+s_\xi)},\ \mu)}$ where:
```math
\begin{align*}
<!-- https://www.wolframalpha.com/input?i2d=true&i=taylor+series+Divide%5BPower%5B2%2C%5C%2840%292x-1%5C%2841%29%5D%2C%CF%80%5D*Divide%5BPower%5B%5C%2840%29x%21%5C%2841%29%2C2%5D%2C%5C%2840%292x%5C%2841%29%21%5D+at+x+%3D+0 -->
Q(\sigma) &\approx \begin{cases}
 0.09\sigma^3 + \big(\tfrac{\ln^2 2}{\pi} - \tfrac{\pi}{12}\big)\sigma^2+\big(\tfrac{\ln 2}{\pi}\big)\sigma+\tfrac{1}{2\pi} & \text{if } \sigma \leq 0.4\\
 \frac{\sqrt \sigma}{2\sqrt \pi} + \frac{1}{16\sqrt{\pi \sigma}} & \text{otherwise.}
\end{cases}\\
s &= \begin{cases}
 6.97\big(\tfrac \omega {\omega_p}\big){^{4.06}} & \text{if } \omega \leq \omega_p\\
 9.77\big(\tfrac \omega {\omega_p}\big){^{-2.33 -1.45(\omega_p U\text{/}9.81-1.17)}} & \text{otherwise.}
\end{cases}\\
s_\xi &= 16 \tanh\big(\tfrac{\omega_p}{\omega}\big)\xi^2
\end{align*}
```
$Q(\sigma)$ is a normalization factor used to satisfy the condition: $\int_{-\pi}^\pi D(\omega, \theta)d \theta = 1$. The Hasselmann directional spread was chosen due to its approximate analytical solution for $Q(\sigma)$ (as opposed to e.g., the Donelan-Banner directional spread also described in Horvath).

Following a suggestion in Tessendorf, the resultant spectrum function was also multiplied by a small-wave suppression term, $`\exp({-k}^2(1-\delta)^2)`$ (given the magnitude of the wave vector ($k$) and a 'detail' parameter ($\delta$)). Combining the above, our *final* directional ocean-wave spectrum function used can be denoted as:
```math
S(\omega, \theta) = S_{\text{TMA}}(\omega)D_{\text{mixed}}(\omega, \theta)\exp({-k}^2(1-\delta)^2)
```

#### Fast Fourier Transform
A custom FFT implementation was written for the GPU using compute shaders. The *Stockham* FFT algorithm was used over the Cooley-Tukey algorithm to avoid the initial bit-reversal permutation. Following Flügge, a 'butterfly' texture is computed, once per spectrum texture resolution change, encoding the dataflow of the FFT.

First, the FFT kernel is applied row-wise to perform the 2D FFT on the spectrum texture. The texture is then transposed using a compute shader, allowing the same row-wise FFT kernel to then be reused for—what is effectively—a column-wise FFT. This transposition also improves memory access patterns along with enabling pipeline reuse.

#### Wave Cascades
At large-enough distances—especially with sea foam present—tiling artifacts become very apparent. The wave generation system allows multiple wave cascades to be layered simultaneously to address this. Each cascade has its own tiling size and set of parameters. Cascades can be added/removed from the generation system dynamically in real-time. However, as all cascades use the same compute pipelines, they must have the same spectra texture resolution. Alternatively, blending wave displacements/normals with noise could also reduce tiling artifacts—at a lesser performance cost.

Each wave cascades’ parameters and size must be carefully chosen to avoid wave interference when layered. Similarly, the cascades' wave phases should be offset to avoid interference with other cascades. The generation system automatically attempts this by offsetting each cascades’ start times differently (honestly, not sure if it works lol).

#### Load Balancing
Due to the erratic nature of wave motion, their movement can appear perceptually smooth even without updating their displacements every frame. Thus, an "update rate" parameter was introduced to control how often wave cascades are updated per second. While this reduces the amount of GPU-time spent working on FFT, frames during which the wave generation pipeline runs still stutter.

An experiment to asynchronously compute cascade updates using Godot's local RenderingDevices, caused significant performance overhead due to transferring textures between the CPU and GPU. Instead, the wave generation system *attempts to load-balance cascades*. Whenever the frame time is shorter than the update rate, only one cascade is updated per frame. This reduces stuttering while still benefiting from the lower GPU workload of frame skipping.

The displacement, normal, and foam maps generated after running FFT on our directional ocean-wave spectrum function (along with its associated parameters) yield realistic surface motion across a broad range of ocean-wave environments.

[environment_demo.mp4](https://github.com/user-attachments/assets/7589758f-1233-4be8-accc-2902a1dd01ec)

## References
**Flügge, Fynn-Jorin**. **[Realtime GPGPU FFT Ocean Water Simulation](https://tore.tuhh.de/entities/publication/1cd390d3-732b-41c1-aa2b-07b71a64edd2)**. Hamburg University of Technology. (2017).\
**Gunnell, Garrett**. **[I Tried Simulating The Entire Ocean](https://www.youtube.com/watch?v=yPfagLeUa7k)**. (2023).\
**Horvath, Christopher J**. **[Empirical Directional Wave Spectra for Computer Graphics](https://dl.acm.org/doi/10.1145/2791261.2791267)**. DigiPro. (2015).\
**Tessendorf, Jerry**. **[Simulating Ocean Water](https://people.computing.clemson.edu/~jtessen/reports/papers_files/coursenotes2004.pdf)**. SIGGRAPH. (2004).\
**Matusiak, Robert**. **[Implementing Fast Fourier Transform Algorithms of Real-Valued Sequences](https://www.ti.com/lit/an/spra291/spra291.pdf)**. Texas Instruments. (2001).\
**Mihelich, Mark**. **[Wakes, Explosions and Lighting: Interactive Water Simulation in 'Atlas'](https://www.youtube.com/watch?v=Dqld965-Vv0)**. GDC. (2019).\
**Pensionerov, Ivan**. **[FFT-Ocean](https://github.com/gasgiant/FFT-Ocean)**. GitHub. (2020).

## Attribution
**[Evening Road 01 (Pure Sky)](https://polyhaven.com/a/evening_road_01_puresky)** by **Jarod Guest** is used under the [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) license.\
**[OTFFT DIT Stockham Algorithm](http://wwwa.pikara.ne.jp/okojisan/otfft-en/stockham3.html)** by **Takuya Okahisa** is used and modified under the [MIT](http://wwwa.pikara.ne.jp/okojisan/otfft-en/download.html) license.
