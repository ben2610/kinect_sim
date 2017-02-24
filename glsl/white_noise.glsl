#version 330 core

// the application should pass the current time at each frame to produce seed for random generation
uniform float time;

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
float random(out float sign)
{
   uint rand = hash(floatBitsToUint(gl_TexCoord[0].st), floatBitsToUint(time));
   // use low bit as sign indicator
   sign = ((rand & 1U) == 1U) ? 1.0 : -1.0;
   return floatConstruct(rand);
}

// return a gaussian noise in units of 1/256 with a variance of 50 units
// 50 is computed such that even if random produces the highest possible value, the formula returns less than 1
float normal_noise(out float sign)
{
   // get random value from [0,1[
   float x = random(sign);
   // approximation of inverse PHI function
   // 0.1953125 = 50/256.0
   // 1.570796327 = PI/2
   return 0.1953125*sqrt(-1.570796327*log(1.0-x*x));
}

void main(void)
{
   float sign;
   float noise = normal_noise(sign);

   if (sign > 0.0) {
      fragment = vec4(noise, 0.0, 0.0, 1.0);
   } else {
      fragment = vec4(0.0, 0.0, noise, 1.0);
   }
}
