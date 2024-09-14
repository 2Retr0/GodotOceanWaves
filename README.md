# GodotOceanWaves
An open ocean rendering experiment in the Godot Engine utilizing the inverse Fourier transform of directional ocean-wave spectra for wave generation. A consise set of parameters is exposed allowing scriptable, real-time modification of wave properties to emulate a wide-variety of ocean-wave environments.

[ocean_demo.mp4](https://github.com/user-attachments/assets/cacabd44-66c4-468b-933a-2ffe699efc6c)

## Introduction
### Why Use Fourier Transforms?
An common approach for animating water in video games (and one the reader may already be familiar with) is through the superposition of *Gerstner waves*. While Gerstner waves work well for modeling the lower-frequency details present in calmer waters, they fall short in accurately representing the 'choppier' surfaces present in an open ocean. To simulate the latter, a more complex approach uses the *inverse Fourier transform of ocean-wave spectra* modeled using empirical data gathered by oceanogrpahers. 

A benefit of working in frequency space using ocean-wave spectra is the ease of modifying ocean properties (e.g., how 'choppy' the surface is). When using Gerstner waves, it is not clear how waves (and their parameters) need to be changed to emulate a certain ocean state. In contrast, ocean-wave spectra expose parameters that change the properties of waves directly.

To compute the Fourier transform, a *fast Fourier transform* algorithm (FFT) is used specifically. On top of having a lower computational complexity than the classical discrete Fourier transform algorithm (O(N log N) versus O(N<sup>2</sup>)), the FFT is *scalable in a parallel sense* meaning it's perfect for running on the GPU. As opposed to using Gerstner waves, where each thread must perform N computations relating to each sinusoid, using FFT-based waves only require one thread to perform log(N) equivalent computations. At scale, this allows many more waves to be added to the system allowing for a more accurate surface simulation.
  
## Results
### Wave Simulation
The method used for generating surface waves closely follows the method originally described in Tessendorf. An ocean-wave spectrum function (yielding the energy of a wave given its frequency and direction) is multiplied with a Gaussian-distributed random numbers to generate an initial spectral sea state. The initial state is then propagated in time through a relation between the frequency of waves and their propagation speed. An inverse Fourier transform can then be applied to the propagated state to generate displacement and normal maps.

[ocean_param_demo.mp4](https://github.com/user-attachments/assets/7589758f-1233-4be8-accc-2902a1dd01ec)


### Wave Shading
![shading_demo](https://github.com/user-attachments/assets/c69766e7-711c-4909-a1fa-290bac0d577a)



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
