from std.ffi import OwnedDLHandle, c_int, c_uint, c_long, external_call
from std.memory import Pointer
from std.memory.alloc import unsafe_alloc
from std.pathlib import Path
from std.sys.defines import is_defined
from rlgl import (
    RLGL, VoidPtr, UIntPtr, GL_TRIANGLES, GL_TEXTURE_2D,
    GL_TEXTURE_MIN_FILTER, GL_TEXTURE_MAG_FILTER, GL_NEAREST, GL_LINEAR,
    GL_RGBA, GL_UNSIGNED_BYTE
)
from raymath import Vec4f
from rtextures import Texture2D, load_texture

comptime OptVoidPtr = Optional[VoidPtr]
comptime FloatPtr = Pointer[Float32, MutUntrackedOrigin]
comptime VoidPtrPtr = Pointer[OptVoidPtr, MutUntrackedOrigin]


struct Font(TrivialRegisterPassable):
    var texture: Texture2D
    var base_size: Int
    var advances: FloatPtr  # 96 entries for ASCII 32..127 (advance / base_size)

    def __init__(out self,
                 texture: Texture2D,
                 base_size: Int = 8,
                 advances: FloatPtr = FloatPtr(unsafe_from_address=0)):
        self.texture = texture
        self.base_size = base_size
        self.advances = advances


def _upload_atlas(gl: OwnedDLHandle, pixels: Pointer[UInt32, MutUntrackedOrigin], w: Int, h: Int, smooth: Bool) raises -> c_uint:
    var glGenTextures = gl.get_function("glGenTextures")
    var glBindTexture = gl.get_function("glBindTexture")
    var glTexParameteri = gl.get_function("glTexParameteri")
    var glTexImage2D = gl.get_function("glTexImage2D")

    var tex_id = c_uint(0)
    glGenTextures(c_int(1), UIntPtr(unsafe_from_address=Int(Pointer(to=tex_id))))
    glBindTexture(GL_TEXTURE_2D, tex_id)
    var filt = GL_LINEAR if smooth else GL_NEAREST
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filt)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filt)

    glTexImage2D(
        GL_TEXTURE_2D, c_int(0), c_int(GL_RGBA), c_int(w), c_int(h), c_int(0),
        GL_RGBA, GL_UNSIGNED_BYTE, VoidPtr(unsafe_from_address=Int(pixels))
    )
    return tex_id


# Compact 8x8 bitmaps for fallback default font
def _glyph_bits(code: Int) -> UInt64:
    if code == 32:  return 0x0000000000000000 # ' ' (Space)
    if code == 33:  return 0x1818181818001800 # '!'
    if code == 34:  return 0x6666660000000000 # '"'
    if code == 35:  return 0x6666FF66FF666600 # '#'
    if code == 36:  return 0x183E603C067C1800 # '$'
    if code == 37:  return 0x62660C1830664600 # '%'
    if code == 38:  return 0x386C3876DCCC7600 # '&'
    if code == 39:  return 0x1818180000000000 # '''
    if code == 40:  return 0x0C18303030180C00 # '('
    if code == 41:  return 0x30180C0C0C183000 # ')'
    if code == 42:  return 0x00663CFF3C660000 # '*'
    if code == 43:  return 0x0018187E18180000 # '+'
    if code == 44:  return 0x0000000000181830 # ','
    if code == 45:  return 0x0000007E00000000 # '-'
    if code == 46:  return 0x0000000000181800 # '.'
    if code == 47:  return 0x060C183060C00000 # '/'
    # Digits 0-9 (ASCII 48..57)
    if code == 48:  return 0x3C666E76663C0000 # '0'
    if code == 49:  return 0x18381818187E0000 # '1'
    if code == 50:  return 0x3C660C18307E0000 # '2'
    if code == 51:  return 0x3C660C1C06663C00 # '3'
    if code == 52:  return 0x0C1C3C6C7E0C0000 # '4'
    if code == 53:  return 0x7E607C0606663C00 # '5'
    if code == 54:  return 0x3C607C66663C0000 # '6'
    if code == 55:  return 0x7E060C1830300000 # '7'
    if code == 56:  return 0x3C663C66663C0000 # '8'
    if code == 57:  return 0x3C663E060C380000 # '9'
    # Punctuation & Symbols (ASCII 58..64)
    if code == 58:  return 0x0018180018180000 # ':'
    if code == 59:  return 0x0018180000181830 # ';'
    if code == 60:  return 0x0C18306030180C00 # '<'
    if code == 61:  return 0x00007E007E000000 # '='
    if code == 62:  return 0x30180C060C183000 # '>'
    if code == 63:  return 0x3C660C1818001800 # '?'
    if code == 64:  return 0x3C666E6A6E603C00 # '@'
    # Uppercase A-Z (ASCII 65..90)
    if code == 65:  return 0x183C667E66660000 # 'A'
    if code == 66:  return 0x7C667C66667C0000 # 'B'
    if code == 67:  return 0x3C666060663C0000 # 'C'
    if code == 68:  return 0x786C66666C780000 # 'D'
    if code == 69:  return 0x7E607C60607E0000 # 'E'
    if code == 70:  return 0x7E607C6060600000 # 'F'
    if code == 71:  return 0x3C66606E663E0000 # 'G'
    if code == 72:  return 0x66667E6666660000 # 'H'
    if code == 73:  return 0x3C181818183C0000 # 'I'
    if code == 74:  return 0x1E0C0C0C6C380000 # 'J'
    if code == 75:  return 0x666C78786C660000 # 'K'
    if code == 76:  return 0x60606060607E0000 # 'L'
    if code == 77:  return 0x63777F6B63630000 # 'M'
    if code == 78:  return 0x66767E6E66660000 # 'N'
    if code == 79:  return 0x3C666666663C0000 # 'O'
    if code == 80:  return 0x7C667C6060600000 # 'P'
    if code == 81:  return 0x3C66666E3C060000 # 'Q'
    if code == 82:  return 0x7C667C6C66660000 # 'R'
    if code == 83:  return 0x3C603C06063C0000 # 'S'
    if code == 84:  return 0x7E18181818180000 # 'T'
    if code == 85:  return 0x66666666663C0000 # 'U'
    if code == 86:  return 0x666666663C180000 # 'V'
    if code == 87:  return 0x63636B7F77630000 # 'W'
    if code == 88:  return 0x663C183C66660000 # 'X'
    if code == 89:  return 0x66663C1818180000 # 'Y'
    if code == 90:  return 0x7E0C1830607E0000 # 'Z'
    # Brackets & Symbols (ASCII 91..96)
    if code == 91:  return 0x3C30303030303C00 # '['
    if code == 92:  return 0xC06030180C060000 # '\'
    if code == 93:  return 0x3C0C0C0C0C0C3C00 # ']'
    if code == 94:  return 0x183C660000000000 # '^'
    if code == 95:  return 0x000000000000FF00 # '_'
    if code == 96:  return 0x30180C0000000000 # '`'
    # Lowercase a-z (ASCII 97..122) -> maps to uppercase A-Z
    if code >= 97 and code <= 122:
        return _glyph_bits(code - 32)
    # Braces, Pipe, Tilde (ASCII 123..126)
    if code == 123: return 0x0E18187018180E00 # '{'
    if code == 124: return 0x1818181818181800 # '|'
    if code == 125: return 0x7018180E18187000 # '}'
    if code == 126: return 0x76DC000000000000 # '~'
    return 0x7E424242427E0000

def load_font_default(gl: OwnedDLHandle) raises -> Font:
    comptime ATLAS_W = 128
    comptime ATLAS_H = 48
    var pixels = unsafe_alloc[UInt32](ATLAS_W * ATLAS_H)
    var advances = unsafe_alloc[Float32](96)

    for idx in range(96):
        advances[unsafe_offset=idx] = 0.65
        var code = 32 + idx
        var lookup_code = code - 32 if (code >= 97 and code <= 122) else code
        var bits = _glyph_bits(lookup_code)
        var col = idx % 16
        var row = idx // 16
        var base_x = col * 8
        var base_y = row * 8

        for gy in range(8):
            var row_byte = (bits >> UInt64((7 - gy) * 8)) & 0xFF
            for gx in range(8):
                var bit_on = ((row_byte >> UInt64(7 - gx)) & 1) == 1
                var px = base_x + gx
                var py = base_y + gy
                pixels[unsafe_offset=py * ATLAS_W + px] = UInt32(0xFFFFFFFF) if bit_on else UInt32(0x00000000)

    var tex_id = _upload_atlas(gl, pixels, ATLAS_W, ATLAS_H, False)
    pixels.unsafe_free()
    return Font(Texture2D(tex_id, ATLAS_W, ATLAS_H), 8, advances)

def load_font(gl: OwnedDLHandle, path: String) raises -> Font:
    comptime CELL = 48

    # Derive sibling atlas PNG and advances binary paths (e.g. menuFont.ttf -> menuFont_atlas.png)
    var base_path = String(path.removesuffix(".ttf")) if path.endswith(".ttf") else path
    var atlas_path = base_path + "_atlas.png"
    var adv_path = base_path + "_advances.bin"

    var tex = load_texture(gl, atlas_path)
    if tex.id == 0:
        print("Font atlas missing, falling back to default:", atlas_path)
        return load_font_default(gl)

    # Ensure smooth GL_LINEAR filtering on the pre-baked atlas
    var glBindTexture = gl.get_function("glBindTexture")
    var glTexParameteri = gl.get_function("glTexParameteri")
    glBindTexture(GL_TEXTURE_2D, tex.id)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glBindTexture(GL_TEXTURE_2D, c_uint(0))

    # Load 96 x Float32 character advance ratios (384 bytes)
    var advances = unsafe_alloc[Float32](96)
    for i in range(96):
        advances[unsafe_offset=i] = 0.52

    try:
        with open(adv_path, "r") as f:
            var raw = f.read_bytes()
            if len(raw) >= 96 * 4:
                var src_ptr = Pointer[Float32, MutUntrackedOrigin](unsafe_from_address=Int(raw.unsafe_ptr()))
                for i in range(96):
                    advances[unsafe_offset=i] = src_ptr[unsafe_offset=i]
            _ = raw
    except e:
        print("Font advances missing, using uniform fallback:", adv_path, e)

    return Font(tex, CELL, advances)

def draw_text(mut rl: RLGL, gl: OwnedDLHandle, font: Font, text: String, x: Float32, y: Float32, font_size: Float32, color: Vec4f) raises:
    var is_default = font.base_size <= 8
    var sz = font_size if is_default else (font_size * 1.28)
    var glyph_w = (sz * 0.75) if is_default else (sz * 1.17)
    var glyph_h = (sz * 0.90) if is_default else (sz * 1.17)
    var cursor_x = x
    var cursor_y = y if is_default else (y - (sz * 0.24))

    rl.begin_mode(gl, GL_TRIANGLES)
    rl.set_texture(gl, font.texture.id)
    rl.current_color = color

    var bytes = text.as_bytes()
    for i in range(len(bytes)):
        var code = Int(bytes[i])
        if code == 10:  # '\n'
            cursor_x = x
            cursor_y += sz * 1.05
            continue
        if code < 32 or code > 127:
            code = 63  # '?'

        var idx = code - 32
        var col = Float32(idx % 16)
        var row = Float32(idx // 16)

        var pad_u: Float32 = 0.0 if is_default else (0.5 / 768.0)
        var pad_v: Float32 = 0.0 if is_default else (1.5 / 288.0)
        var u0 = (col / 16.0) + pad_u
        var v0 = (row / 6.0) + pad_v
        var u1 = ((col + 1.0) / 16.0) - pad_u
        var v1 = ((row + 1.0) / 6.0) - pad_v

        rl.texcoord2f(u0, v0); rl.vertex3f(cursor_x, cursor_y, 0.0)
        rl.texcoord2f(u0, v1); rl.vertex3f(cursor_x, cursor_y + glyph_h, 0.0)
        rl.texcoord2f(u1, v1); rl.vertex3f(cursor_x + glyph_w, cursor_y + glyph_h, 0.0)

        rl.texcoord2f(u0, v0); rl.vertex3f(cursor_x, cursor_y, 0.0)
        rl.texcoord2f(u1, v1); rl.vertex3f(cursor_x + glyph_w, cursor_y + glyph_h, 0.0)
        rl.texcoord2f(u1, v0); rl.vertex3f(cursor_x + glyph_w, cursor_y, 0.0)

        var adv = Float32(0.85) if is_default else (font.advances[unsafe_offset=idx] if Int(font.advances) != 0 else Float32(0.52))
        cursor_x += sz * adv

    rl.set_texture(gl, 0)

def measure_text(font: Font, text: String, font_size: Float32) -> Float32:
    var is_default = font.base_size <= 8
    var sz = font_size if is_default else (font_size * 1.28)
    var max_w: Float32 = 0.0
    var cur_w: Float32 = 0.0
    var bytes = text.as_bytes()
    for i in range(len(bytes)):
        var code = Int(bytes[i])
        if code == 10:  # '\n'
            if cur_w > max_w:
                max_w = cur_w
            cur_w = 0.0
            continue
        if code < 32 or code > 127:
            code = 63
        var idx = code - 32
        var adv = Float32(0.85) if is_default else (font.advances[unsafe_offset=idx] if Int(font.advances) != 0 else Float32(0.52))
        cur_w += sz * adv
    return max(max_w, cur_w)
