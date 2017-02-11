# kinect_sim

This project aims at producing realist simulation of depth buffer and infrared buffer produced by a Kinect 2.

The simulation consists in:
1) creating a virtual 3D scene with elements representing physical objects with their characteristic
2) lighting the scene with spots that have the same position and characteristic than the infrared spots of the Kinect 
3) rendering the scene with a camera with the same field of view and position than the time-of-flight captor or the Kinect
4) doing a 2D pass on the depth and luminance buffer to reproduce all the imperfections of the Kinect: spherical distortion, noise, missing pixels, flying pixels
5) exporting the depth and luminance buffer in the same format than the kinect

The Blender gameengine will be used for that; it has all the features needed:
- 3D scene creation tool
- material & texturing to represent properties of physical object to infrared light
- animation tool to introduce variance in the scene
- vertex and fragment shader to introduce further variance in the scene
- 2D filter to apply final pass

Use Blender 2.78 or later to run this tool.


