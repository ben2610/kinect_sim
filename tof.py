import bge
import math
from bge import logic
from bge import texture as vt
import numpy as np
import time
import terrain


# size of the render
w = 512
h = 424

def write_png(buf, width, height):
    import zlib, struct

    # reverse the vertical line order and add null bytes at the start
    width_byte_4 = width * 4
    raw_data = b"".join(b'\x00' + buf[span:span + width_byte_4].tobytes() for span in range((height - 1) * width * 4, -1, - width_byte_4))

    def png_pack(png_tag, data):
        chunk_head = png_tag + data
        return struct.pack("!I", len(data)) + chunk_head + struct.pack("!I", 0xFFFFFFFF & zlib.crc32(chunk_head))

    return b"".join([
        b'\x89PNG\r\n\x1a\n',
        png_pack(b'IHDR', struct.pack("!2I5B", width, height, 8, 6, 0, 0, 0)),
        png_pack(b'IDAT', zlib.compress(raw_data, 9)),
        png_pack(b'IEND', b'')])


def init_2df(cont):
    obj = cont.owner
    scene = logic.getCurrentScene()
    cam = scene.cameras['Camera']
    iv = vt.ImageViewport()
    iv.whole = True
    iv.alpha = True
    # we only capture the central part of the image
    iv.capsize = (w,h)
    obj['iv'] = iv
    obj['ref'] = time.perf_counter()
    # transfer camera near and far value to object properties so that the shader can use them
    obj['near'] = cam.near
    obj['far'] = cam.far
    obj['time'] = 0.0
    # Here we should really use np.zeros((w,h,2), dtype=np.uint16)
    # to directly assemble the depth and luminance channel that are computed by the 2D filter.
    # But in this example the frame buffer is just saved as an image, so keep byte array format
    obj['img'] = np.zeros((w*h*4), dtype=np.uint8)
    # to stop after x frames
    obj['fc'] = 0
    # we need to activate just once the 2D filter
    try:
        cont.activate("noise")
        cont.activate("filter")
    except:
        pass
    # on next frame execute run_2df()
    cont.script = __name__+'.run_noop'

def run_noop(cont):
    obj = cont.owner
    obj['time'] = time.perf_counter() - obj['ref']

def run_2df(cont):
    obj = cont.owner
    iv = obj['iv']
    img = obj['img']
    iv.refresh(img, "RGBA")
    # process and save the image here ...
    data = write_png(img, w, h)
    with open(bge.logic.expandPath("//tof_2df_{0}.png".format(obj['fc'])), 'wb') as fb:
        fb.write(data)
    obj['fc'] += 1
    obj['time'] = time.perf_counter() - obj['ref']
    if obj['fc'] == 10:
        bge.logic.endGame()

def init_cylinder(cont):
    obj = cont.owner
    mesh = obj.meshes[0]
    vlen = mesh.getVertexArrayLength(0)
    varr = []   # array of (vertex pos,vertex ref,idx)
    xquant = 2.0*math.pi/32.0
    yquant = 0.1
    for i in range(vlen):
        v = mesh.getVertex(0, i)
        p = v.getXYZ()
        r =  p.length
        if r > 0.5:
            ro = math.atan2(p.x, p.y)+math.pi;
            x = ro // xquant
            y = p.z // yquant
            varr.append((p,v,(x,y)))
    obj['varray'] = varr
    obj['ref'] = time.perf_counter()
    cont.script = __name__+'.run_cylinder'

def run_cylinder(cont):
    if not cont.sensors["pause"].positive:
        obj = cont.owner
        t = time.perf_counter() - obj['ref']
        ter = terrain.generateTerrain(32,23,0.7)
        for v in obj['varray']:
            pos = v[0].copy()
            #k = 1.0+0.2*math.sin(3.0*(pos.z+2.0*t))
            k = 1.0+ter[v[2][1],v[2][0]]
            pos.xy *= k
            v[1].setXYZ(pos)


    
