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
const float fw = 640.0;
const float fh = 480.0;
// border size around central kinect zone
const float bw = (w-kw)*0.5;
const float bh = (h-kh)*0.5;
// transform to convert from blender to kinect coordinates
const mat2 mb2k = mat2(fw/kw, 0.0,
		       0.0  , fh/kh);
const vec2 vb2k = vec2(-bw/kw, -bh/kh);
// reverse transform
const mat2 mk2b = mat2(kw/fw, 0.0  ,
		       0.0  , kh/fh);
const vec2 vk2b = vec2( bw/fw,  bh/fh);

// spherical coefficient
uniform float k_cx;	// x coordinates of the lens center expressed in kinect coordinates
uniform float k_cy;     // y coordinates of the lens center expressed in kinect coordinates
// polynomial coefficients of square of distance to center
uniform float k_r2;
uniform float k_r4;
uniform float k_r6;

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

uint hash( uvec2 v ) {
   return hash( v.x ^ hash(v.y));
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

    float  f = uintBitsToFloat( m );       // Range [1:2]
    return f - 1.0;                        // Range [0:1]
}

float random(vec2  v)
{
   return floatConstruct(hash(floatBitsToUint(v), floatBitsToUint(time)));
}

bool outside_kinect(vec2 screen)
{
   if (screen.x < 0.0 ||
       screen.x >= 1.0 ||
       screen.y < 0.0 ||
       screen.y >= 1.0)
      return false;
   return true;
}

// screen must be the (u,v) normalized coordinates in the blender frame buffer
bool spherical_distortion(inout vec2 screen)
{
   // compute the position where to sample the framebuffer
   vec2 kinect = mb2k * screen + vb2k;
   if (outside_kinect(kinect))
      return false;
   vec2 center = vec2(k_cx, k_cy);
   vec2 rel = kinect-center;
   float r2 = dot(rel, rel);
   float rk = sqrt(k_r2+r2*(k_r4+r2*k_r6));
   screen = mk2b * (rk*rel+center) + vk2b;
   return true;
}

float zdist(float z_b)
{
   // convert z_buffer to distance from camera plane
   float z_n = 2.0 * z_b - 1.0;
   float z_e = 2.0 * near * far / (far + near - z_n * (far - near));
   // convert to millimeter, then to 16 bits
   return z_e*1000.0/65535.0;   
}

// rand is uniform random value [0,1]
// return a gaussian value [-16,+15] with variance = 5
float normal_noise(float rand)
{
   // cumulative probability in the [-16,+15] interval of a guassian with variance=5
   const float cumul_gaussian[32] = { };
   
}
   
void kinect_noice(inout float dist, inout float luminance)
{
   if (dist == 0.0)
      return;
}

void main(void)
{
   float dist, luminance;
   vec2 screen = gl_TexCoord[0].st;

   if (!spherical_distortion(screen)) {
      fragment = vec4(0.0, 0.0, 0.0, 0.0);
   } else {
      luminance = texture2D(bgl_LuminanceTexture, screen).r;
      dist = zdist(texture2D(bgl_DepthTexture, screen).r);
      // TBD: filter to detect object border and create random empty pixel
      // TBD: flying pixel
      kinect_noise(dist, luminance);
      
      // encode distance in red and green channels
      // and luminance in blue and alphs
      // low byte first to match intel byte order
      fragment = vec4(fract(dist*256.0), 
		      dist, 
		      fract(luminance*256.0), 
		      luminance);
   }
}
