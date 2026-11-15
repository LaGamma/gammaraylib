from std.ffi import OwnedDLHandle, c_int, c_uint, c_size_t
from std.origin import MutUntrackedOrigin
from std.memory import Pointer
from std.memory.alloc import unsafe_alloc
from std.pathlib import Path
from rshapes import Rectangle

from raymath import Vec2f, Vec4f
from rlgl import RLGL, VoidPtr, CharPtr, IntPtr, UIntPtr, GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_TEXTURE_MAG_FILTER, GL_NEAREST, GL_LINEAR, GL_RGBA, GL_UNSIGNED_BYTE, GL_TRIANGLES

comptime WHITE = Vec4f(1.0, 1.0, 1.0, 1.0)
comptime BytePtrPtr = Pointer[Pointer[UInt8, MutUntrackedOrigin], MutUntrackedOrigin]

struct Image(Movable):
    var data: Pointer[UInt32, MutUntrackedOrigin]
    var width: Int
    var height: Int

    def __init__(out self, data: Pointer[UInt32, MutUntrackedOrigin], width: Int, height: Int):
        self.data = data
        self.width = width
        self.height = height

    def unload(mut self):
        self.data.unsafe_free()

struct Texture2D(TrivialRegisterPassable):
    var id: c_uint
    var width: Int
    var height: Int

    def __init__(out self, id: c_uint, width: Int, height: Int):
        self.id = id
        self.width = width
        self.height = height

def _read_u16_le(bytes: Span[UInt8, _], offset: Int) -> Int:
    return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)

def _read_u32_le(bytes: Span[UInt8, _], offset: Int) -> Int:
    return (
        Int(bytes[offset])
        | (Int(bytes[offset + 1]) << 8)
        | (Int(bytes[offset + 2]) << 16)
        | (Int(bytes[offset + 3]) << 24)
    )

def load_image_bmp(path: String) raises -> Image:
    var raw = Path(path).read_bytes()
    var bytes = Span(raw)
    if len(bytes) < 54 or bytes[0] != 0x42 or bytes[1] != 0x4D: # 'B', 'M'
        raise Error("Invalid BMP header: " + path)

    var pixel_offset = _read_u32_le(bytes, 10)
    var width        = _read_u32_le(bytes, 18)
    var raw_height   = _read_u32_le(bytes, 22)
    var bpp          = _read_u16_le(bytes, 28)

    var top_down = False
    var height = raw_height
    if raw_height < 0:
        top_down = True
        height = -raw_height

    if bpp != 24 and bpp != 32:
        raise Error("Unsupported BMP bit depth (expected 24 or 32): " + String(bpp))

    var bytes_per_px = bpp // 8
    var row_stride = ((width * bytes_per_px + 3) // 4) * 4
    var pixels = unsafe_alloc[UInt32](width * height)

    for y in range(height):
        var src_y = y if top_down else (height - 1 - y)
        var row_start = pixel_offset + src_y * row_stride
        for x in range(width):
            var p = row_start + x * bytes_per_px
            var b = UInt32(bytes[p + 0])
            var g = UInt32(bytes[p + 1])
            var r = UInt32(bytes[p + 2])
            var a = UInt32(bytes[p + 3]) if bytes_per_px == 4 else UInt32(255)
            # Pack RGBA8888 in little-endian memory order (R at byte 0, G at 1, B at 2, A at 3)
            pixels[unsafe_offset=y * width + x] = r | (g << 8) | (b << 16) | (a << 24)

    return Image(pixels, width, height)

def load_image_png(path: String) raises -> Image:
    if not Path(path).exists():
        raise Error("PNG file not found on disk: " + path)

    var libpng = OwnedDLHandle("libpng16.so")
    var png_image_begin_read_from_file = libpng.get_function[c_int]("png_image_begin_read_from_file")
    var png_image_finish_read          = libpng.get_function[c_int]("png_image_finish_read")

    # png_image struct (104 bytes on 64-bit Linux):
    # [0..1] opaque (void*), [2] version (1), [3] width, [4] height, [5] format, [10..25] message[64]
    var img_struct = unsafe_alloc[UInt32](32)
    for i in range(32):
        img_struct[unsafe_offset=i] = 0
    img_struct[unsafe_offset=2] = 1  # PNG_IMAGE_VERSION = 1

    var c_path = path + "\x00"
    var path_ptr = CharPtr(unsafe_from_address=Int(c_path.unsafe_ptr()))
    var ok = png_image_begin_read_from_file(
        VoidPtr(unsafe_from_address=Int(img_struct)),
        path_ptr,
    )
    _ = path_ptr
    _ = c_path

    if ok == 0:
        # Read libpng's error string starting at byte offset 40 (UInt32 index 10)
        var msg_ptr = CharPtr(unsafe_from_address=Int(img_struct) + 40)
        var err_msg = String()
        for i in range(64):
            var ch = msg_ptr[unsafe_offset=i]
            if ch == 0:
                break
            err_msg += chr(Int(ch))
        img_struct.unsafe_free()
        raise Error("libpng error (" + path + "): " + err_msg)

    var width  = Int(img_struct[unsafe_offset=3])
    var height = Int(img_struct[unsafe_offset=4])
    img_struct[unsafe_offset=5] = 3  # PNG_FORMAT_RGBA

    var pixels = unsafe_alloc[UInt32](width * height)
    var read_ok = png_image_finish_read(
        VoidPtr(unsafe_from_address=Int(img_struct)),
        Optional[VoidPtr](None),
        VoidPtr(unsafe_from_address=Int(pixels)),
        c_int(width * 4),
        Optional[VoidPtr](None),
    )
    img_struct.unsafe_free()
    _ = libpng^

    if read_ok == 0:
        pixels.unsafe_free()
        raise Error("libpng failed to decode RGBA pixels: " + path)

    return Image(pixels, width, height)

def load_image_jpg(path: String) raises -> Image:
    if not Path(path).exists():
        raise Error("JPG file not found on disk: " + path)

    var raw = Path(path).read_bytes()
    var jpeg_size = len(raw)

    var tj = OwnedDLHandle("libturbojpeg.so.0")
    var tjInitDecompress   = tj.get_function[VoidPtr]("tjInitDecompress")
    var tjDecompressHeader = tj.get_function[c_int]("tjDecompressHeader3")
    var tjDecompress2      = tj.get_function[c_int]("tjDecompress2")
    var tjDestroy          = tj.get_function[c_int]("tjDestroy")

    var handle = tjInitDecompress()
    var width     = c_int(0)
    var height    = c_int(0)
    var subsamp   = c_int(0)
    var colorspace = c_int(0)

    var src_ptr = CharPtr(unsafe_from_address=Int(raw.unsafe_ptr()))
    var hdr_ok = tjDecompressHeader(
        handle,
        src_ptr,
        UInt64(jpeg_size),
        IntPtr(unsafe_from_address=Int(Pointer(to=width))),
        IntPtr(unsafe_from_address=Int(Pointer(to=height))),
        IntPtr(unsafe_from_address=Int(Pointer(to=subsamp))),
        IntPtr(unsafe_from_address=Int(Pointer(to=colorspace))),
    )
    if hdr_ok != 0:
        _ = tjDestroy(handle)
        raise Error("TurboJPEG failed to read header: " + path)

    var w = Int(width)
    var h = Int(height)
    var pixels = unsafe_alloc[UInt32](w * h)

    # TJPF_RGBA = 7 (outputs 4 bytes per pixel: R, G, B, 255)
    var dec_ok = tjDecompress2(
        handle,
        src_ptr,
        UInt64(jpeg_size),
        CharPtr(unsafe_from_address=Int(pixels)),
        width,
        c_int(w * 4),
        height,
        c_int(7),
        c_int(0),
    )
    _ = raw^
    _ = tjDestroy(handle)
    _ = tj^

    if dec_ok != 0:
        pixels.unsafe_free()
        raise Error("TurboJPEG failed to decode pixels: " + path)

    return Image(pixels, w, h)


def load_image(path: String) raises -> Image:
    if path.endswith(".bmp") or path.endswith(".BMP"):
        return load_image_bmp(path)
    if path.endswith(".png") or path.endswith(".PNG"):
        return load_image_png(path)
    if path.endswith(".jpg") or path.endswith(".jpeg") or path.endswith(".JPG") or path.endswith(".JPEG"):
        return load_image_jpg(path)
    raise Error("Unsupported image format (use .bmp or .png): " + path)

def load_texture_from_image(gl: OwnedDLHandle, image: Image, smooth: Bool = False) raises -> Texture2D:
    var glGenTextures   = gl.get_function("glGenTextures")
    var glBindTexture   = gl.get_function("glBindTexture")
    var glTexParameteri = gl.get_function("glTexParameteri")
    var glTexImage2D    = gl.get_function("glTexImage2D")

    var tex_id = c_uint(0)
    glGenTextures(c_int(1), UIntPtr(unsafe_from_address=Int(Pointer(to=tex_id))))
    glBindTexture(GL_TEXTURE_2D, tex_id)

    var filter = GL_LINEAR if smooth else GL_NEAREST
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter)

    glTexImage2D(
        GL_TEXTURE_2D, c_int(0), c_int(GL_RGBA), c_int(image.width), c_int(image.height), c_int(0),
        GL_RGBA, GL_UNSIGNED_BYTE, VoidPtr(unsafe_from_address=Int(image.data))
    )
    return Texture2D(tex_id, image.width, image.height)

def load_texture(gl: OwnedDLHandle, path: String, smooth: Bool = False) raises -> Texture2D:
    var img = load_image(path)
    var tex = load_texture_from_image(gl, img, smooth)
    img.unload()
    return tex

def unload_texture(gl: OwnedDLHandle, tex: Texture2D) raises:
    var glDeleteTextures = gl.get_function("glDeleteTextures")
    var id = tex.id
    glDeleteTextures(c_int(1), UIntPtr(unsafe_from_address=Int(Pointer(to=id))))

def gen_texture_checked(gl: OwnedDLHandle, width: Int, height: Int, checks_x: Int, checks_y: Int) raises -> Texture2D:
    var pixels = unsafe_alloc[UInt32](width * height)
    var cw = width // checks_x
    var ch = height // checks_y

    for y in range(height):
        for x in range(width):
            var is_even = ((x // cw) + (y // ch)) % 2 == 0
            # Little-endian ABGR: 0xFFFFFFFF (white) vs 0xFF5533CC (crimson/purple)
            pixels[unsafe_offset=y * width + x] = UInt32(0xFFFFFFFF) if is_even else UInt32(0xFF5533CC)

    var glGenTextures = gl.get_function("glGenTextures")
    var glBindTexture = gl.get_function("glBindTexture")
    var glTexParameteri = gl.get_function("glTexParameteri")
    var glTexImage2D = gl.get_function("glTexImage2D")

    var tex_id = c_uint(0)
    glGenTextures(c_int(1), UIntPtr(unsafe_from_address=Int(Pointer(to=tex_id))))
    glBindTexture(GL_TEXTURE_2D, tex_id)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)

    glTexImage2D(
        GL_TEXTURE_2D, c_int(0), c_int(GL_RGBA), c_int(width), c_int(height), c_int(0),
        GL_RGBA, GL_UNSIGNED_BYTE, VoidPtr(unsafe_from_address=Int(pixels))
    )
    pixels.unsafe_free()
    return Texture2D(tex_id, width, height)

def draw_texture(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    tex: Texture2D,
    x: Float32,
    y: Float32,
    tint: Vec4f = WHITE,
) raises:
    var w = Float32(tex.width)
    var h = Float32(tex.height)

    rl.begin_mode(gl, GL_TRIANGLES)
    rl.set_texture(gl, tex.id)
    rl.current_color = tint

    rl.texcoord2f(0.0, 0.0); rl.vertex3f(x, y, 0.0)
    rl.texcoord2f(0.0, 1.0); rl.vertex3f(x, y + h, 0.0)
    rl.texcoord2f(1.0, 1.0); rl.vertex3f(x + w, y + h, 0.0)

    rl.texcoord2f(0.0, 0.0); rl.vertex3f(x, y, 0.0)
    rl.texcoord2f(1.0, 1.0); rl.vertex3f(x + w, y + h, 0.0)
    rl.texcoord2f(1.0, 0.0); rl.vertex3f(x + w, y, 0.0)

    rl.set_texture(gl, 0)

def draw_texture_pro(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    tex: Texture2D,
    source: Rectangle,
    dest: Rectangle,
    origin: Vec2f,
    rotation: Float32,
    tint: Vec4f = WHITE,
) raises:
    var tw = Float32(tex.width) if tex.width > 0 else 1.0
    var th = Float32(tex.height) if tex.height > 0 else 1.0

    var u0 = source.x / tw
    var v0 = source.y / th
    var u1 = (source.x + source.width) / tw
    var v1 = (source.y + source.height) / th

    var x0 = dest.x - origin[0]
    var y0 = dest.y - origin[1]
    var x1 = x0 + dest.width
    var y1 = y0 + dest.height

    rl.begin_mode(gl, GL_TRIANGLES)
    rl.set_texture(gl, tex.id)
    rl.current_color = tint

    rl.texcoord2f(u0, v0); rl.vertex3f(x0, y0, 0.0)
    rl.texcoord2f(u0, v1); rl.vertex3f(x0, y1, 0.0)
    rl.texcoord2f(u1, v1); rl.vertex3f(x1, y1, 0.0)

    rl.texcoord2f(u0, v0); rl.vertex3f(x0, y0, 0.0)
    rl.texcoord2f(u1, v1); rl.vertex3f(x1, y1, 0.0)
    rl.texcoord2f(u1, v0); rl.vertex3f(x1, y0, 0.0)

    rl.set_texture(gl, 0)
