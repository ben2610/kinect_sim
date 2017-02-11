#version 330 core

uniform sampler2D bgl_DepthTexture;
uniform sampler2D bgl_LuminanceTexture;
// The noise model is a gaussian with 0 centered and sigma that depends mostly
// on the infrared level and to a lesser extend on the distance.
uniform vec2 bgl_TextureCoordinateOffset[9];
// frustrum near and far plane
uniform float near;
uniform float far;
// the application should pass the time to produce seed
uniform float time;
// The frame buffer should be 640x480
// The actual Kinect render is 512x424
// The difference is to adress spherical deformation:
// The pixel in the kinect central zone may be sampled from the border outside this zone.
const float kw = 512.0;
const float kh = 424.0;
const float fw = 532.0;
const float fh = 444.0;
// border size around central kinect zone
const float bw = (fw-kw)*0.5;
const float bh = (fh-kh)*0.5;
// transform to convert from blender to kinect coordinates
const mat2 mb2k = mat2(fw , 0.0,
		       0.0, fh);
const vec2 vb2k = vec2(-bw, -bh);
// reverse transform
const mat2 mk2b = mat2(1.0/fw, 0.0   ,
		       0.0   , 1.0/fh);
const vec2 vk2b = vec2( bw/fw,  bh/fh);

// focal length in pixels
uniform float k_fx;
uniform float k_fy;
// principal point in kinect coordinate
uniform float k_cx;
uniform float k_cy;
// lens distortion coefficients
uniform float k_r2;
uniform float k_r4;
uniform float k_r6;
// whether we want the ground truth or noise image
uniform int ground_truth;

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

uint hash( uvec2 v, uint seed ) {
   return hash(v.x ^ hash(v.y) ^ hash(seed));
}

// Construct a float with half-open range [0:1] using low 23 bits.
// All zeroes yields 0.0, all ones yields the next smallest representable value below 1.0.
float floatConstruct( uint m ) {
    const uint ieeeMantissa = 0x007FFFFFu; // binary32 mantissa bitmask
    const uint ieeeOne      = 0x3F800000u; // 1.0 in IEEE binary32

    m &= ieeeMantissa;                     // Keep only mantissa bits (fractional part)
    m |= ieeeOne;                          // Add fractional part to 1.0

    return uintBitsToFloat( m ) - 1.0;       	   // Range [0:1]
}

float random(inout float delta)
{
   uint rand = hash(floatBitsToUint(gl_TexCoord[0].st), floatBitsToUint(time));
   // use low bit as sign indicator
   if ((rand & 1U) == 1U)
      delta *= -1.0;
   return floatConstruct(rand);
}

bool test_kinect(vec2 screen)
{
   if (screen.x >= 0.0 &&
       screen.x < kw   &&
       screen.y >= 0.0 &&
       screen.y < kh)
      return true;
   return false;
}

// screen must be the (u,v) normalized coordinates in the blender frame buffer
bool spherical_distortion(inout vec2 screen)
{
   // compute the position where to sample the framebuffer
   vec2 kinect = mb2k * screen + vb2k;
   if (!test_kinect(kinect))
      return false;
   vec2 focal = vec2(k_fx, k_fy);
   vec2 center = vec2(k_cx, k_cy);
   vec2 norm = (kinect-center)/focal;
   float r2 = dot(norm, norm);
   float dist = 1.0+r2*(k_r2+r2*(k_r4+r2*k_r6));
   vec2 rel = (norm*dist)*focal+center;
   screen = mk2b * rel + vk2b;
   return true;
}

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
   
void kinect_noise(inout float dist, inout float luminance)
{
   if (dist == 0.0)
      return;
   // TBD: formula to compute sigma from dist and luminance
   float sigma = 1.0-log2(luminance)*0.5;
   if (sigma > 5.0)
      sigma = 5.0;
   dist += normal_noise(sigma);
   // TBD: noise on luminance
}

void main(void)
{
   float dist, luminance;
   vec2 screen = gl_TexCoord[0].st;

   if (!spherical_distortion(screen)) {
      fragment = vec4(0.0, 0.0, 0.0, 1.0);
   } else {
      luminance = texture2D(bgl_LuminanceTexture, screen).r;
      dist = zdist(texture2D(bgl_DepthTexture, screen).r);
      if (ground_truth == 0) {
	 // process shadow
	 if (luminance < 0.001)
	    dist = 0.0;
	 // TBD: filter to detect object border and create random empty pixel
	 // TBD: flying pixel
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
