import bge
from bge import logic
from bge import texture as vt
import numpy as np
import time

# target of offscreen render. Other choice is RAS_OFS_RENDER_TEXTURE
# alway use RAS_OFS_RENDER_BUFFER when rendering to a buffer, it's faster
t=bge.render.RAS_OFS_RENDER_BUFFER

# size of the render
w = 512
h = 424
# number of MSAA, 0 to disable
s = 0

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


def init_fbo(cont):
    obj = cont.owner
    scene = logic.getCurrentScene()
    detector = scene.cameras['detector']
    fbo = bge.render.offScreenCreate(w, h, s, t)
    ir = vt.ImageRender(scene, detector, fbo)
    # extract the alpha channel too, for best efficiency
    ir.alpha = True
    obj['ir'] = ir
    obj['depth'] = np.zeros((w*h), dtype=np.float32)
    obj['img'] = np.zeros((w*h*4), dtype=np.uint8)
    # to stop after x frames
    obj['fc'] = 0
    # we don't need the normal BGE render, disable it so that we can compute many frames
    bge.logic.setRender(False)
    # on next frame execute run()
    cont.script = __name__+'.run_fbo'

def run_fbo(cont):
    obj = cont.owner
    ir = obj['ir']
    depth = obj['depth']
    img = obj['img']
    # get the depth buffer as float
    ir.depth = True
    ir.refresh(depth)
    # now get the color
    ir.depth = False
    ir.refresh(img, "RGBA")
    # process image buffers here...
    data = write_png(img, w, h)
    with open(bge.logic.expandPath("//tof_img_{0}.png".format(obj['fc'])), 'wb') as fb:
        fb.write(data)
    obj['fc'] += 1
    if obj['fc'] == 10:
        bge.logic.endGame()


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
    obj['ref'] = time.perf_counter();
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
    cont.activate("postproc")
    # on next frame execute run_2df()
    cont.script = __name__+'.run_noop'

def run_noop(cont):
    obj = cont.owner;
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



