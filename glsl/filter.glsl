#version 330 core

// access to RGB color, we will not use it
uniform sampler2D bgl_DepthTexture;

// access to 16bit luminance, simulates infrared
uniform sampler2D bgl_LuminanceTexture;

// frame buffer contains while noise computed in first pass
uniform sampler2D bgl_RenderedTexture;

// to sample surrounding pixels
uniform vec2 bgl_TextureCoordinateOffset[9];

// the lens distortion can only be reproduced with a lookup table: it converts
// kinect UVk (=point of the final render) to GL UV (=point where to get pixel).
// This table is precomputed and converted to EXR floating point texture.
// To be available here, it then must be assigned to texture channel 0 of the
// first material of the object on which the 2D filter is enabled.
uniform sampler2D bgl_ObjectTexture0;
// whether we want the ground truth or noise image
uniform int ground_truth;

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
const float invfw = 1.0/610.0;
const float invfh = 1.0/510.0;
// border size around central kinect zone
const float bw = (fw-kw)*0.5;
const float bh = (fh-kh)*0.5;
// convert screen UV coordinate to kinect UV coordinate
// UVk = mb2k * UV + vb2k
const mat2 mb2k = mat2(fw/kw , 0.0,
		       0.0, fh/kh);
const vec2 vb2k = vec2(-bw/kw, -bh/kh);

// UV from vertex shader
in vec2 gl_TexCoord[];
// the pixel color in which we will encode depth and luminance
out vec4 fragment;

const float convCoef[9] = float[9](
   0.2, 0.3, 0.2,
   0.3, 0.69282, 0.3,
   0.2, 0.3, 0.2
   );

// A single iteration of Bob Jenkins' One-At-A-Time hashing algorithm.
uint hash( uint x ) {
    x += ( x << 10u );
    x ^= ( x >>  6u );
    x += ( x <<  3u );
    x ^= ( x >> 11u );
    x += ( x << 15u );
    return x;
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

float uni_to_normal(uint urand, float sigma)
{
   float x = floatConstruct(urand);
   // 1.570796327 = PI/2
   return sigma*sqrt(-1.570796327*log(1.0-x*x));
}

// return random UV offset with variance sigma expressed in pixels
vec2 offset_noise(float sigma)
{
   // get random value from [0,1[
   uvec2 v = floatBitsToUint(gl_TexCoord[0].st);
   uint texhash = v.x ^ hash(v.y);
   uint seed = floatBitsToUint(time) ^ 0xDE871035U;
   uint urand = hash(texhash ^ hash(seed));
   float xoffset = uni_to_normal(urand, sigma*invfw);
   if ((urand & 1U) == 1U)
      xoffset = -xoffset;
   seed ^= 0xB0E251D2U;
   urand = hash(texhash ^ hash(seed));
   float yoffset = uni_to_normal(urand, sigma*invfh);
   if ((urand & 1U) == 1U)
      yoffset = -yoffset;
   return vec2(xoffset, yoffset);
}


/* produce a filtered noise of variance sigma expressed in pixels */
float filter(vec2 screen, float sigma)
{
   vec4 sample;
   float result = 0.0;
   int i;
   
   for (i = 0; i < 9; i++) {
      sample = texture2D(bgl_RenderedTexture, screen + bgl_TextureCoordinateOffset[i]);
      if (sample.b > sample.r) {
	 result -= sample.b * convCoef[i];
      } else {
	 result += sample.r * convCoef[i];
      }
   }
   // result is a random noise or variance 50/256, convert to depth units of 1/65536
   // 0.000078125 = 256/50/65536;
   return result*sigma*0.000078125;
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

// input: screen=fragment UV
// output: screen=UV where to sample frame buffer to take lens distortion into account
// return true if fragment is inside kinect render area, false otherwise.
// A random offset gaussian noise is added to the resulting UV to simulate flying pixels
// and random black pixels: as the depth texture is setup for linear interpolation, the
// combination of random sampling point and large depth variations for adjacent pixels
// on border of objects will produce large depth variation from frame to frame.
// The variance in sampling noise must be determined experimentally.
bool lens_distortion(inout vec2 screen, out vec2 kinect)
{
   // convert UV to UVk
   kinect = mb2k * screen + vb2k;
   // exclude border around the kinect zone
   if (!test_kinect(kinect))
      return false;
   // convert back UVk to UV but with lens distortion
   // and add a small variance to produce flying pixels
   screen = texture(bgl_ObjectTexture0, kinect).st;
   if (ground_truth != 1)
      screen += offset_noise(0.6);
   return true;
}

// convert a depth value to actual distance in millimeter from the camera
float zdist(float z_b)
{
   // convert z_buffer to distance from camera plane
   float z_n = 2.0 * z_b - 1.0;
   float z_e = 2.0 * near * far / (far + near - z_n * (far - near));
   // convert to millimeter, then to 16 bits
   return z_e*1000.0/65536.0;   
}

float calc_sigma(float dist, float luminance, vec2 kinect)
{
   if (dist == 0.0)
      return 0.0;
   // Made up formula to make level of noise depend on luminance
   // TBD: insert here actual noise model
   float sigma = 1.0-log2(luminance)*0.5;
   // limit sigma to 5 bits
   if (sigma > 5.0)
      sigma = 5.0;
   return sigma;
}

void main(void)
{
   float noise, sigma, dist, luminance;
   vec2 screen = gl_TexCoord[0].st;
   vec2 kinect;

   if (!lens_distortion(screen, kinect)) {
      fragment = vec4(0.0, 0.0, 0.0, 1.0);
   } else {
      if (ground_truth == 2) {
	 noise = filter(screen, 50.0*256.0);
	 if (noise > 0.0) {
	    fragment = vec4(noise, 0.0, 0.0, 1.0);
	 } else {
	    fragment = vec4(0.0, 0.0, -noise, 1.0);
	 }
      } else {
	 luminance = texture2D(bgl_LuminanceTexture, screen).r;
	 dist = zdist(texture2D(bgl_DepthTexture, screen).r);
	 if (ground_truth == 0) {
	    // process shadow
	    // TBD: put here correct luminance threshold for black pixels.
	    if (luminance < 0.001)
	       dist = 0.0;
	    // Add noise
	    sigma = calc_sigma(dist, luminance, kinect);
	    noise = filter(screen, sigma);
	    dist += noise;
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
}

