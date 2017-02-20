#version 330 core

// Notes: * We need version 330 because we use uintBitsToFloat and floatBitsToUint
//          functions to produce pseudo random values. It's much more difficult to
//          produce clean noise without them.
//        * This shader is linked to a text block inside the time_of_flight.blend
//          Each time you modify it, it is necessary to reload it in blender.
//          Too bad this isn't done automatically when blender starts.

// access to RGB color, we will not use it
uniform sampler2D bgl_DepthTexture;

// access to 16bit luminance, simulates infrared
uniform sampler2D bgl_LuminanceTexture;

// uniform to sample the 9 pixels around the current screen location
// not used in this version
//uniform vec2 bgl_TextureCoordinateOffset[9];

// near and far plane. Needed to convert z_depth into millimeter distance
uniform float near;
uniform float far;

// the application should pass the current time at each frame to produce seed for random generation
uniform float time;

// This assumes that the frame buffer is 610x510
// The size of the frame buffer is computed to match the field of view of the kinect and \
// the pixel resolution at the center. The difference in size comes from the lens distortion
const float kw = 512.0;
const float kh = 424.0;
const float fw = 610.0;
const float fh = 510.0;
// border size around central kinect zone
const float bw = (fw-kw)*0.5;
const float bh = (fh-kh)*0.5;
// convert screen UV coordinate to kinect UV coordinate
// UVk = mb2k * UV + vb2k
const mat2 mb2k = mat2(fw/kw , 0.0,
		       0.0, fh/kh);
const vec2 vb2k = vec2(-bw/kw, -bh/kh);
// the lens distortion can only be reproduced with a lookup table: it converts
// kinect UVk (=point of the final render) to GL UV (=point where to get pixel).
// This table is precomputed and converted to EXR floating point texture.
// To be available here, it then must be assigned to texture channel 0 of the
// first material of the object on which the 2D filter is enabled.
uniform sampler2D bgl_ObjectTexture0;
// whether we want the ground truth or noise image
uniform int ground_truth;

// UV from vertex shader
in vec2 gl_TexCoord[];
// the pixel color in which we will encode depth and luminance
out vec4 fragment;


// A single iteration of Bob Jenkins' One-At-A-Time hashing algorithm.
uint hash( uint x ) {
    x += ( x << 10u );
    x ^= ( x >>  6u );
    x += ( x <<  3u );
    x ^= ( x >> 11u );
    x += ( x << 15u );
    return x;
}

// 3 component hash
uint hash( uvec2 v, uint seed ) {
   return hash(v.x ^ hash(v.y) ^ hash(seed));
}

// Construct a float with half-open range [0:1[ from low 23 bits of uint
// All zeroes yields 0.0, all ones yields the next smallest representable value below 1.0.
float floatConstruct( uint m ) {
    const uint ieeeMantissa = 0x007FFFFFu; // binary32 mantissa bitmask
    const uint ieeeOne      = 0x3F800000u; // 1.0 in IEEE binary32

    m &= ieeeMantissa;                     // Keep only mantissa bits (fractional part)
    m |= ieeeOne;                          // Add fractional part to 1.0

    return uintBitsToFloat( m ) - 1.0;       	   // Range [0:1]
}

// return a random float equally distributed between [0:1[ 
// and negate delta randomly with 50% chance
float random(inout float delta)
{
   uint rand = hash(floatBitsToUint(gl_TexCoord[0].st), floatBitsToUint(time));
   // use low bit as sign indicator
   if ((rand & 1U) == 1U)
      delta *= -1.0;
   return floatConstruct(rand);
}

// screen = UVk (UV coordinates relative to kinect zone centered on the frame buffer)
// return true if screen falls in the kinect zone.
bool test_kinect(vec2 screen)
{
   if (screen.x >= 0.0 &&
       screen.x < 1.0   &&
       screen.y >= 0.0 &&
       screen.y < 1.0)
      return true;
   return false;
}

// screen=UV in blender frame buffer
bool lens_distortion(inout vec2 screen)
{
   // convert UV to UVk
   vec2 kinect = mb2k * screen + vb2k;
   // exclude border around the kinect zone
   if (!test_kinect(kinect))
      return false;
   // convert back UVk tyo UV but with lens distortion
   screen = texture(bgl_ObjectTexture0, kinect).st;
   return true;
}

// convert a depth value to actual distance in millimeter from the camier
float zdist(float z_b)
{
   // convert z_buffer to distance from camera plane
   float z_n = 2.0 * z_b - 1.0;
   float z_e = 2.0 * near * far / (far + near - z_n * (far - near));
   // convert to millimeter, then to 16 bits
   return z_e*1000.0/65536.0;   
}

// return a gaussian noise in units of 1/65536 with a variance of sigma units
float normal_noise(float sigma)
{
   // normalize to the sigma of our reference gaussian and to 16 bit unit
   // 0.000003052 = 1/5/65536.0
   float delta = sigma*0.000003052;
   // get random value between [0,1[
   float x = random(delta);
   // approximation of inverse PHI function
   // 39.2699081 = PI*5^2/2
   return delta*sqrt(-39.2699081*log(1.0-x*x));
}

// add gaussian noise to distance call
void kinect_noise(inout float dist, inout float luminance)
{
   if (dist == 0.0)
      return;
   // Made up formula to make level of noise depend on luminance
   // TBD: insert here actual noise model
   float sigma = 1.0-log2(luminance)*0.5;
   // limit sigma to 5 bits
   if (sigma > 5.0)
      sigma = 5.0;
   dist += normal_noise(sigma);
   // TBD: noise on luminance
}

void main(void)
{
   float dist, luminance;
   vec2 screen = gl_TexCoord[0].st;

   if (!lens_distortion(screen)) {
      fragment = vec4(0.0, 1.0, 0.0, 1.0);
   } else {
      luminance = texture2D(bgl_LuminanceTexture, screen).r;
      dist = zdist(texture2D(bgl_DepthTexture, screen).r);
      if (ground_truth == 0) {
	 // process shadow
	 if (luminance < 0.001)
	    dist = 0.0;
	 // TBD: filter to detect object border and create random empty pixel
	 // TBD: flying pixel
	 // Add noise
	 kinect_noise(dist, luminance);
      }
      
      // encode distance in red and green channels
      // and luminance in blue and alpha
      // low byte first to match intel byte order
      fragment = vec4(fract(dist*256.0), 
		      dist, 
		      fract(luminance*256.0), 
		      luminance);
      
   }
}
