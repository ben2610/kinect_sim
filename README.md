# kinect_sim

This project aims at producing realist simulations of depth and infrared buffer produced by a Kinect 2.

The simulation consists in:
1) creating a virtual 3D scene with elements representing objects with physical characteristics
2) lighting the scene with spots that have the same position and characteristics than the infrared spots of the Kinect
3) rendering the scene with a camera having the same field of view and position than the time-of-flight captor or the Kinect
4) doing a 2D pass on the depth and luminance buffer to reproduce all the imperfections of the Kinect: lens distortion, noise, missing pixels, flying pixels
5) exporting the depth and luminance buffer in the same format than the kinect

The Blender gameengine will be used for that; it has all the features needed:
- 3D scene creation tool
- material & texturing to simulate physical properties of objects to infrared light
- animation tool to introduce variance in the scene
- vertex and fragment shader to introduce further variance in the scene
- 2D filter to apply one or more final passes to simulate distortion, noise, flying pixels, missing pixels, etc.

A modified version of Blender is required to simulate the lens distortion effect. This is because the transformation of a non distorted image to a distorted image can only be simulated via a table, i.e. a floating point texture in GLSL. Unfortunately, the 2D filters in blender do not support custom textures by default. The modified version add support for custom textures in 2D filters in a simple way: if the object on which the 2D filter is defined is a mesh and if its first material slot has texture channels, then these textures are available in the GLSL fragment shader as 'gl_ObjectTextureX' sampler2D uniform where X = 0 to 4 to match the texture channels 0 to 4. The modified blender 2.78 for Windows 10 64bits can be downloaded here:

https://drive.google.com/open?id=0Bw6tWmtzO4Kpd3BHMGlnZUtxWHc

The linux version (Ubuntu 16.04) can be downloaded here:

https://drive.google.com/open?id=0Bw6tWmtzO4KpQm1XYmtoS2Z0R28

Note: this version requires additional shared library that is not likely present in a standard Linux host. The extra libraries can be downloaded here:

https://drive.google.com/open?id=0Bw6tWmtzO4KpWTB2NWE1aFlfZk0

Here is how to use them: create a directory and unzip the library package in it. Then create a small shell script as follow:

```
#!/bin/bash
export LD_LIBRARY_PATH=/path/to/directory/with/extra/libraries
/path/to/blenderplayer -a /path/to/time_of_flight.blend
```

## Files

* __xy_table.dat__

  Lens distortion table obtained from the kinect. Each kinect has its own table.
  The table takes the form of a 512x424 lines with 2 comma separeted float per line  representing the X,Y distortion for each pixel of the kinect buffer. This table must be preprocessed before being usable in the shader.

* __prepare_xytable.py__

  Python3 script to convert the xy_table.dat into a EXR texture directly usable by the shader. The imageio python module is used to write the EXR texture; make sure it is installed (e.g. if you have pip: `pip install imageio` ). The supporting freeimage library must be installed too (`sudo apt-get install libfreeimage3`). The image is save in image/xytable.exr. Here is the math behind the conversion:
```
let (h,w) = (510,610) the size of the blender frame buffer.
let (cx,cy) the lens principal point expressed in kinect pixel value.
let fov = 40 the half field of view of the blender camera (in degree).
let (x,y) = value from the xy_table, one pair for each camera pixel
            Physical meaning of x,y is the tangent of angle between the ray that hit the camera pixel and the camera Z axis. It is the tangent of the angle projected onto the X (Y) axis that form the x (y) value.

Compute focal distance of blender (factor to convert tangent to pixel):
f = w/2/tan(fov) = 363.485
Compute the principal point in blender pixel unit:
Cx = cx+(w-512)/2 = cx+49
Cy = cx+(h-424)/2 = cx+43
Convert (x,y) in blender pixel units:
X = f*x+Cx
Y = f*y+Cy
Convert to UV coordinates in frame buffer
U = X/w
V = Y/h
```
  TBD: (cx,cy) are currently hardcoded in the script but they are different for every kinect. Put it in an external file instead.

* __time_of_flight.blend__

  Main blend file. It must be executed by the blenderplayer with alpha enabled to ensure full 32 bit output:
  > `# /path/to/modified/blenderplayer -a /path/to/time_of_flight.blend`

  The field of view of camera and size of the framebuffer were set according to these formulas:

  > min/max value from xy_table.dat  = min/max tangent of rays coming from the scene and reaching the kinect detector. The field of view can be deduced: approx(-37,+37) in X axis and (-32,+32) in Y axis, that are extended to (-40,+40) and (-35,+35) respectively in blender to make sure 100% of the kinect field of view is covered. => camera field of view is 80.

  > The undistorted kinect angular pixel size can be compute with the xy_table.dat near the principal point: it is simply the delta x and y values in the X and Y directions respectively near the principal point = 0.002743 in both directions (kinect pixels are square).

  > To minimize resampling aliasing during the 2D pass, make sure the blender and kinect angular pixel size are matching => tan(40)/w/2 = 0.002743 => w = 610.

  > The height of the framebuffer is derived from the aspect ratio: aspect_ratio = tan(40)/tan(35) =  w/h => h = 510 (round to even value).

* __terrain.py__

  Fractal terrain generation algorithm translated from javascript (source https://github.com/qiao/fractal-terrain-generator). It produces a NxM numpy array with heights values. Used in __tof.py__ to deform a cylinder (the height is converted to distance to axis).

* __tof.py__

  External python script linked to the blend file and automatically executed at each frame. It sets the uniforms and exports the framebuffer at each frame to kinect format (TBD).

  To simulate variance in the scene, a cylinder object is deformed each frame according to the random terrain generation algorithm in __terrain.py__.

  > A vertex shader could not be used because blender does not allow to modify the vertex shader alone. Chaing the vertex in python works because the BGE automatically recomputes the vertex normal at each frame.

* __image/xytable.exr__

  Image holding the converted XY table (see above). The image is linked to the blender file and automatically loaded at startup.
> Design note: for this image to be transferred unmodified to the GPU, precautions must be taken in blender:
> - Assign it as the texture channel 0 of a mesh object, e.g a plane
> - Set color space to non-color to disable color conversion on loading
> - Declare it as normal map to disable color conversion on uploading to GPU
> - Make sure the object is slightly in the camera frustrum to force the loading of the textures (if the object is culled, its textures are not even loaded)
> - In user preference, System panel, tick '16 Bit Float Textures' option. Otherwise blender sends only top 8bit of the texture to the GPU. Note that this option is non effective in the blenderplayer. The option is hardcoded in the blenderplayer of the modified blender package.

* __glsl/white_noise.glsl__

  shader to generate pure gaussian noise with sigma=50/256. This is used for the first pass of the 2D filter.
  This file is linked to the blend file but is not automatically reloaded when the game starts: blender
  detects the change of the file but does not reload. A manual reload action is necessary inside blender
  to refresh the text block, then save the blend.

* __glsl/filter.glsl__

  Second pass of the 2D filter. Outputs the kinext render (comments inside). Same comment as above for the modifications made to this file.
  This pass has a convolution filter to generate the noise with spacial correlation.
  There is also a method to produce flying pixels and random black pixels on borders of objects.


## To Do

* implement realistic convolution noise filter
* fine tune flying pixels and black pixels algorithm
* export kinect noisy and/or clean output at each frame
* implement game logic to change scene content at each frame
* calibrate spot position, intensity, field of view and light distribution
