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

## Files

* __xy_table.dat__

  Lens distortion table obtained from the kinect. Each kinect has its own table.
  The table takes the form of a 512x424 lines with 2 comma separeted float per line  representing the X,Y distortion for each pixel of the kinect buffer. This table must be preprocessed before being usable in the shader.

* __prepare_xytable.py__

  Python3 script to convert the xy_table.dat into a EXR texture directly usable by the shader. The imageio python module is used to write the EXR texture; make sure it is installed (e.g. if you have pip: `pip install imageio` ). The supporting freeimage library must be installed too (`sudo apt-get install libfreeimage3`). The image is save in image/xytable.exr. Here is the math behind the conversion:
```
let (h,w) = (510,610) the size of the blender frame buffer.
let (cx,cy) the lens principal point expressed in kinect pixel value.
let fov = 40 the field of view of the blender camera (in degree).
let (x,y) = value from the xy_table
          = tangent of the X and Y deviation of the ray to the Z axis of the camera
Compute focal distance (factor to convert tangent to pixel):
f = w/2/tan(fov) = 363.485
Compute the principal point in blender pixel unit:
Cx = cx+(w-424)/2 = cx+49
Cy = cx+(h-512)/2 = cx+43
Convert (x,y) in pixel in frame buffer:
X = f*x+Cx
Y = f*y+Cy
Convert to UV coordinates:
U = X/w
V = Y/h
```
  TBD: (cx,cy) are currently hardcoded in the script but they are different for every kinect. Put it in an external file instead.

* __time_of_flight.blend__

  Main blend file. It must be executed by the blenderplayer with alpha on frame buffer to ensure full 32 bit output:
  > `# /path/to/modified/blenderplayer -a /path/to/time_of_flight.blend`

  The field of view of camera and size of the framebuffer is computed as follow:

  > min/max value from xy_table.dat  = min/max tangent of rays coming from the scene and reaching the kinect detector. The field of view can be deduced: approx(-37,+37) in X axis and (-32,+32) in Y axis, that are extended to (-40,+40) and (-35,+35) respectively in blender to make sure 100% of the kinect field of view is covered.

  > The undistorted kinect angular pixel size can be compute with the xy_table.dat near the principal point: it is simply the delta X and Y values in the X and Y directions near the principal point = 0.002743 in both X and Y direction (kinect pixels are square).

  > To minimize resampling aliasing during the 2D pass, make sure the blender and kinect angular pixel size are matching => tan(40)/w/2 = 0.002743 => w = 610.

  > The height of the framebuffer is derived from the aspect ratio: aspect_ratio = tan(40)/tan(35) =  w/h => h = 510 (round to even value).


* __tof.py__

  External python script linked to the blend file and automatically executed at each frame. It set the uniforms and export the framebuffer at each frame to kinect format (TBD).

* __image/xytable.exr__

  Image holding the converted XY table (see above). The image is linked to the blender file and automatically loaded at startup.
> Design note: for this image to be transferred unmodified to the GPU, precautions must be taken in blender:
> - Assign it as the texture channel 0 of a mesh object, e.g a plane
> - Set color space to non-color to disable color conversion on loading
> - Declare it as normal map to disable color conversion on uploading to GPU
> - Make sure the object is slightly in the camera frustrum to force the loading of the textures (if the object is culled, its textures are not even loaded)

* __glsl/tof_noise_bge.glsl__

  Main shader for computing the kinect render. Comments inside.

## To Do

* implement realistic noise model (perhaps via another lookup texture)
* implement flying pixels and missing pixels algorithm
* export kinect clean and noisy output at each frame
* implement game logic to change scene content at each frame
* calibrate spot
