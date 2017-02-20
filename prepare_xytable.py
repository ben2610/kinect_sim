import numpy as np
import imageio
import math

kshape = (424,512)
kw=512.0
kh=424.0

bw=610.0
bh=510.0

# center of lens distortion in kinect pixel unit
# (this should be loaded from external file)
cx = (bw-kw)*0.5+258.7
cy = (bh-kh)*0.5+206.4

fov=math.pi*40.0/180.0
f=0.5*bw/math.tan(fov)

def prepare():
    xy_table = np.loadtxt("xy_table.dat", dtype=np.float32)
    x_table = (np.reshape(xy_table[:, 0], kshape)*f + cx)/bw
    y_table = (np.reshape(xy_table[:, 1], kshape)*f + cy)/bh
    z_table = np.zeros(kshape, dtype=np.float32)
    im = np.dstack((x_table, y_table, z_table))
    imageio.imwrite("image/xytable.exr", im, flags=1)
    

if __name__ == "__main__":
    prepare()
