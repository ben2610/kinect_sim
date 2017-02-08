
uniform sampler2D bgl_RenderedTexture;
uniform sampler2D bgl_DepthTexture;
uniform sampler2D bgl_LuminanceTexture;
// The noise model is given by a 2D texture of size 256*512
// where the y coordinate encodes the distance (16 linear steps) and the infrared light level (16 logarithmic steps)
//   as y = (q_dist*16+q_infrared)
// and the x coordinate encodes the normal angle (16 linear steps) and the distribution of the error (32 steps -16 to +15)
//   as x = (q_angle*32+error+16)
uniform sampler2D noice_model;
uniform vec2 bgl_TextureCoordinateOffset[9];
uniform float near;
uniform float far;
// field of view expressed as x opening at 1 unit distance = 2*tg(fovx_angle/2)
uniform float fov_x;
// field of view expressed as y opening at 1 unit distance = 2*tg(fovx_angle/2)
uniform float fov_y;

const float width = 680.0;
const float heigh = 520.0;

vec2 spherical_distortion(vec2 screen)
{
   // compute the position where to sample the framebuffer
   vec2 world = screen;
   return world;
}

float zdist(float z_b)
{
   // convert z_buffer to distance from camera plane
   float z_n = 2.0 * z_b - 1.0;
   float z_e = 2.0 * near * far / (far + near - z_n * (far - near));
   // convert to millimeter, then to 16 bits
   return z_e*1000.0/65535.0;   
}

vec3 get_3D(vec2 screen)
{
   float dist = zdist(texture2D(bgl_DepthTexture, screen).r);
   return vec3(fov_x*(screen.x-0.5)*dist, fov_y*(screen.y-0.5)*dist, dist);
}

float normal_estimate();

void main(void)
{
   float dist, luminance;
   vec3 point;
   vec3 neighbours[4];
   vec2 screen;


   screen = spherical_distortion(gl_TexCoord[0].st);
   luminance = texture2D(bgl_LuminanceTexture, screen).r;

   dist = zdist(texture2D(bgl_DepthTexture, screen).r);
   // how to sample 4 samples around the screen position
   for (int i = 0; i < 9; i++) {
      sample[i] = texture2D(bgl_RenderedTexture,
			    screen + bgl_TextureCoordinateOffset[i]);
   }
   // detect shadow
   if (luminance < 0.001)
      dist = 0.0;
   // encode distance in red and green channels
   // and luminance in blue and alphs
   // low byte first to match intel byte order
   gl_FragColor = vec4(fract(dist*256.0), 
		       dist, 
		       fract(luminance*256.0), 
		       luminance);
}
