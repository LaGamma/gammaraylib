from std.ffi import OwnedDLHandle
from std.math import pi, cos, sin
from rlgl import RLGL, GL_LINES, GL_TRIANGLES
from rcollisions import BoundingBox
from raymath import Vector3, Vec2f, Vec4f
from rtextures import Texture2D, WHITE
from rmaterials import Material, MATERIAL_MAP_DIFFUSE

# Classic Raylib Color Constants
comptime RAYWHITE = Vec4f(0.96, 0.96, 0.96, 1.0)
comptime MAROON   = Vec4f(0.75, 0.13, 0.22, 1.0)
comptime SKYBLUE  = Vec4f(0.40, 0.75, 1.00, 1.0)
comptime RED      = Vec4f(0.90, 0.16, 0.22, 1.0)
comptime DARKGRAY = Vec4f(0.31, 0.31, 0.31, 1.0)
comptime LIGHTGRAY = Vec4f(0.78, 0.78, 0.78, 1.0)
comptime Color = Vec4f

struct Rectangle(TrivialRegisterPassable):
    var x: Float32
    var y: Float32
    var width: Float32
    var height: Float32

    def __init__(out self, x: Float32, y: Float32, width: Float32, height: Float32):
        self.x = x
        self.y = y
        self.width = width
        self.height = height

    def contains(self, px: Float32, py: Float32) -> Bool:
        return (
            px >= self.x
            and px <= (self.x + self.width)
            and py >= self.y
            and py <= (self.y + self.height)
        )


def draw_circle(
    mut rl: RLGL,
    center_x: Float32,
    center_y: Float32,
    radius: Float32,
    color: Vec4f,
):
    if radius <= 0.0:
        return

    rl.draw_mode = GL_TRIANGLES
    rl.current_color = color

    comptime SEGMENTS = 36
    comptime STEP: Float32 = 6.28318530718 / Float32(SEGMENTS)

    for i in range(SEGMENTS):
        var a0 = Float32(i) * STEP
        var a1 = Float32(i + 1) * STEP

        var x0 = center_x + cos(a0) * radius
        var y0 = center_y + sin(a0) * radius
        var x1 = center_x + cos(a1) * radius
        var y1 = center_y + sin(a1) * radius

        # Counter-clockwise winding in 2D screen space (+Y down)
        rl.vertex3f(center_x, center_y, 0.0)
        rl.vertex3f(x0, y0, 0.0)
        rl.vertex3f(x1, y1, 0.0)

def draw_line(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    start_x: Float32,
    start_y: Float32,
    end_x: Float32,
    end_y: Float32,
    color: Vec4f,
) raises:
    rl.begin_mode(gl, GL_LINES)
    rl.current_color = color
    rl.vertex3f(start_x + 0.5, start_y + 0.5, 0.0)
    rl.vertex3f(end_x + 0.5, end_y + 0.5, 0.0)

def draw_rectangle_lines(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    x: Float32,
    y: Float32,
    w: Float32,
    h: Float32,
    color: Vec4f,
) raises:
    rl.begin_mode(gl, GL_LINES)
    rl.current_color = color

    var x0 = x + 0.5
    var y0 = y + 0.5
    var x1 = x + w - 0.5
    var y1 = y + h - 0.5

    # Top
    rl.vertex3f(x0, y0, 0.0)
    rl.vertex3f(x1, y0, 0.0)
    # Right
    rl.vertex3f(x1, y0, 0.0)
    rl.vertex3f(x1, y1, 0.0)
    # Bottom
    rl.vertex3f(x1, y1, 0.0)
    rl.vertex3f(x0, y1, 0.0)
    # Left
    rl.vertex3f(x0, y1, 0.0)
    rl.vertex3f(x0, y0, 0.0)

def draw_plane(mut rl: RLGL, gl: OwnedDLHandle, center: Vector3, width: Float32, length: Float32, color: Vec4f) raises:
    rl.set_lighting(gl, True)
    var x = center.data[0]
    var y = center.data[1]
    var z = center.data[2]
    var hw = width * 0.5
    var hl = length * 0.5

    var v0 = Vector3(x - hw, y, z + hl)
    var v1 = Vector3(x + hw, y, z + hl)
    var v2 = Vector3(x + hw, y, z - hl)
    var v3 = Vector3(x - hw, y, z - hl)

    # Normal points straight up (+Y)
    _quad3d_lit(rl, v0, v1, v2, v3, Vector3(0.0, 1.0, 0.0), color)
    rl.set_lighting(gl, False)

def draw_plane_material(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    mat: Material,
    center: Vector3,
    width: Float32,
    length: Float32,
    uv_scale: Float32 = 1.0,
) raises:
    var tex = mat.get_diffuse_texture()
    var color = mat.get_diffuse_color()

    rl.set_texture(gl, tex.id)
    rl.set_lighting(gl, True)

    var x = center.data[0]; var y = center.data[1]; var z = center.data[2]
    var hw = width * 0.5; var hl = length * 0.5

    var v0 = Vector3(x - hw, y, z + hl)
    var v1 = Vector3(x + hw, y, z + hl)
    var v2 = Vector3(x + hw, y, z - hl)
    var v3 = Vector3(x - hw, y, z - hl)

    _quad3d_textured_lit(
        rl, v0, v1, v2, v3,
        Vec2f(0.0, uv_scale), Vec2f(uv_scale, uv_scale), Vec2f(uv_scale, 0.0), Vec2f(0.0, 0.0),
        Vector3(0.0, 1.0, 0.0), color
    )

    rl.set_lighting(gl, False)
    rl.set_texture(gl, 0)

def draw_sphere(mut rl: RLGL, gl: OwnedDLHandle, center: Vector3, radius: Float32, rings: Int, slices: Int, color: Vec4f) raises:
    rl.set_lighting(gl, True)
    rl.current_color = color

    var cx = center.data[0]
    var cy = center.data[1]
    var cz = center.data[2]

    for i in range(rings):
        var theta0 = (Float32(i) / Float32(rings)) * pi
        var theta1 = (Float32(i + 1) / Float32(rings)) * pi

        var sin_t0 = sin(theta0); var cos_t0 = cos(theta0)
        var sin_t1 = sin(theta1); var cos_t1 = cos(theta1)

        for j in range(slices):
            var phi0 = (Float32(j) / Float32(slices)) * 2.0 * pi
            var phi1 = (Float32(j + 1) / Float32(slices)) * 2.0 * pi

            var sin_p0 = sin(phi0); var cos_p0 = cos(phi0)
            var sin_p1 = sin(phi1); var cos_p1 = cos(phi1)

            # Unit normals on the sphere surface
            var nx00 = sin_t0 * cos_p0; var ny00 = cos_t0; var nz00 = sin_t0 * sin_p0
            var nx10 = sin_t1 * cos_p0; var ny10 = cos_t1; var nz10 = sin_t1 * sin_p0
            var nx11 = sin_t1 * cos_p1; var ny11 = cos_t1; var nz11 = sin_t1 * sin_p1
            var nx01 = sin_t0 * cos_p1; var ny01 = cos_t0; var nz01 = sin_t0 * sin_p1

            # Triangle 1 (v00 -> v10 -> v11)
            rl.normal3f(nx00, ny00, nz00)
            rl.vertex3f(cx + radius * nx00, cy + radius * ny00, cz + radius * nz00)

            rl.normal3f(nx10, ny10, nz10)
            rl.vertex3f(cx + radius * nx10, cy + radius * ny10, cz + radius * nz10)

            rl.normal3f(nx11, ny11, nz11)
            rl.vertex3f(cx + radius * nx11, cy + radius * ny11, cz + radius * nz11)

            # Triangle 2 (v00 -> v11 -> v01)
            rl.normal3f(nx00, ny00, nz00)
            rl.vertex3f(cx + radius * nx00, cy + radius * ny00, cz + radius * nz00)

            rl.normal3f(nx11, ny11, nz11)
            rl.vertex3f(cx + radius * nx11, cy + radius * ny11, cz + radius * nz11)

            rl.normal3f(nx01, ny01, nz01)
            rl.vertex3f(cx + radius * nx01, cy + radius * ny01, cz + radius * nz01)

    rl.set_lighting(gl, False)

def draw_rectangle(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    x: Float32,
    y: Float32,
    w: Float32,
    h: Float32,
    color: Vec4f,
) raises:
    rl.begin_mode(gl, GL_TRIANGLES)
    rl.current_color = color

    rl.vertex3f(x, y, 0.0)
    rl.vertex3f(x, y + h, 0.0)
    rl.vertex3f(x + w, y + h, 0.0)

    rl.vertex3f(x, y, 0.0)
    rl.vertex3f(x + w, y + h, 0.0)
    rl.vertex3f(x + w, y, 0.0)

def _quad3d(mut rl: RLGL, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, color: Vec4f):
    rl.draw_mode = GL_TRIANGLES
    rl.current_color = color
    rl.vertex3f(p0.data[0], p0.data[1], p0.data[2])
    rl.vertex3f(p1.data[0], p1.data[1], p1.data[2])
    rl.vertex3f(p2.data[0], p2.data[1], p2.data[2])

    rl.vertex3f(p0.data[0], p0.data[1], p0.data[2])
    rl.vertex3f(p2.data[0], p2.data[1], p2.data[2])
    rl.vertex3f(p3.data[0], p3.data[1], p3.data[2])


def _quad3d_lit(mut rl: RLGL, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, normal: Vector3, color: Vec4f):
    rl.current_color = color
    rl.normal3f(normal.data[0], normal.data[1], normal.data[2])

    rl.vertex3f(p0.data[0], p0.data[1], p0.data[2])
    rl.vertex3f(p1.data[0], p1.data[1], p1.data[2])
    rl.vertex3f(p2.data[0], p2.data[1], p2.data[2])

    rl.vertex3f(p0.data[0], p0.data[1], p0.data[2])
    rl.vertex3f(p2.data[0], p2.data[1], p2.data[2])
    rl.vertex3f(p3.data[0], p3.data[1], p3.data[2])

def _quad3d_textured_lit(
    mut rl: RLGL,
    p0: Vector3,
    p1: Vector3,
    p2: Vector3,
    p3: Vector3,
    uv0: Vec2f,
    uv1: Vec2f,
    uv2: Vec2f,
    uv3: Vec2f,
    normal: Vector3,
    color: Vec4f,
):
    rl.current_color = color
    rl.normal3f(normal.data[0], normal.data[1], normal.data[2])

    rl.texcoord2f(uv0[0], uv0[1]); rl.vertex3f(p0.data[0], p0.data[1], p0.data[2])
    rl.texcoord2f(uv1[0], uv1[1]); rl.vertex3f(p1.data[0], p1.data[1], p1.data[2])
    rl.texcoord2f(uv2[0], uv2[1]); rl.vertex3f(p2.data[0], p2.data[1], p2.data[2])

    rl.texcoord2f(uv0[0], uv0[1]); rl.vertex3f(p0.data[0], p0.data[1], p0.data[2])
    rl.texcoord2f(uv2[0], uv2[1]); rl.vertex3f(p2.data[0], p2.data[1], p2.data[2])
    rl.texcoord2f(uv3[0], uv3[1]); rl.vertex3f(p3.data[0], p3.data[1], p3.data[2])



def draw_cube(mut rl: RLGL, gl: OwnedDLHandle, pos: Vector3, w: Float32, h: Float32, length: Float32, color: Vec4f) raises:
    rl.set_lighting(gl, True)
    var x = pos.data[0]
    var y = pos.data[1]
    var z = pos.data[2]
    var hw = w * 0.5
    var hh = h * 0.5
    var hl = length * 0.5

    var v0 = Vector3(x - hw, y - hh, z + hl)
    var v1 = Vector3(x + hw, y - hh, z + hl)
    var v2 = Vector3(x + hw, y + hh, z + hl)
    var v3 = Vector3(x - hw, y + hh, z + hl)
    var v4 = Vector3(x - hw, y - hh, z - hl)
    var v5 = Vector3(x + hw, y - hh, z - hl)
    var v6 = Vector3(x + hw, y + hh, z - hl)
    var v7 = Vector3(x - hw, y + hh, z - hl)

    _quad3d_lit(rl, v0, v1, v2, v3, Vector3( 0.0,  0.0,  1.0), color) # Front (+Z)
    _quad3d_lit(rl, v5, v4, v7, v6, Vector3( 0.0,  0.0, -1.0), color) # Back (-Z)
    _quad3d_lit(rl, v3, v2, v6, v7, Vector3( 0.0,  1.0,  0.0), color) # Top (+Y)
    _quad3d_lit(rl, v4, v5, v1, v0, Vector3( 0.0, -1.0,  0.0), color) # Bottom (-Y)
    _quad3d_lit(rl, v1, v5, v6, v2, Vector3( 1.0,  0.0,  0.0), color) # Right (+X)
    _quad3d_lit(rl, v4, v0, v3, v7, Vector3(-1.0,  0.0,  0.0), color) # Left (-X)

    rl.set_lighting(gl, False)


def draw_cube_material(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    mat: Material,
    pos: Vector3,
    w: Float32,
    h: Float32,
    length: Float32,
) raises:
    var tex = mat.get_diffuse_texture()
    var color = mat.get_diffuse_color()

    rl.set_texture(gl, tex.id)
    rl.set_lighting(gl, True)

    var x = pos.data[0]; var y = pos.data[1]; var z = pos.data[2]
    var hw = w * 0.5; var hh = h * 0.5; var hl = length * 0.5

    var v0 = Vector3(x - hw, y - hh, z + hl)
    var v1 = Vector3(x + hw, y - hh, z + hl)
    var v2 = Vector3(x + hw, y + hh, z + hl)
    var v3 = Vector3(x - hw, y + hh, z + hl)
    var v4 = Vector3(x - hw, y - hh, z - hl)
    var v5 = Vector3(x + hw, y - hh, z - hl)
    var v6 = Vector3(x + hw, y + hh, z - hl)
    var v7 = Vector3(x - hw, y + hh, z - hl)

    var uv_bl = Vec2f(0.0, 1.0)
    var uv_br = Vec2f(1.0, 1.0)
    var uv_tr = Vec2f(1.0, 0.0)
    var uv_tl = Vec2f(0.0, 0.0)

    _quad3d_textured_lit(rl, v0, v1, v2, v3, uv_bl, uv_br, uv_tr, uv_tl, Vector3( 0.0,  0.0,  1.0), color) # Front
    _quad3d_textured_lit(rl, v5, v4, v7, v6, uv_bl, uv_br, uv_tr, uv_tl, Vector3( 0.0,  0.0, -1.0), color) # Back
    _quad3d_textured_lit(rl, v3, v2, v6, v7, uv_bl, uv_br, uv_tr, uv_tl, Vector3( 0.0,  1.0,  0.0), color) # Top
    _quad3d_textured_lit(rl, v4, v5, v1, v0, uv_bl, uv_br, uv_tr, uv_tl, Vector3( 0.0, -1.0,  0.0), color) # Bottom
    _quad3d_textured_lit(rl, v1, v5, v6, v2, uv_bl, uv_br, uv_tr, uv_tl, Vector3( 1.0,  0.0,  0.0), color) # Right
    _quad3d_textured_lit(rl, v4, v0, v3, v7, uv_bl, uv_br, uv_tr, uv_tl, Vector3(-1.0,  0.0,  0.0), color) # Left

    rl.set_lighting(gl, False)
    rl.set_texture(gl, 0)


def draw_cube_texture(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    tex: Texture2D,
    pos: Vector3,
    w: Float32,
    h: Float32,
    length: Float32,
    color: Vec4f = WHITE,
) raises:
    var mat = load_material_default()
    mat.set_texture(MATERIAL_MAP_DIFFUSE, tex)
    mat.set_color(MATERIAL_MAP_DIFFUSE, color)
    draw_cube_material(rl, gl, mat, pos, w, h, length)


def draw_grid(mut rl: RLGL, slices: Int, spacing: Float32):
    var half = Float32(slices) * spacing * 0.5
    var t: Float32 = 0.02
    for i in range(-slices // 2, slices // 2 + 1):
        var p = Float32(i) * spacing
        var col = DARKGRAY if i == 0 else LIGHTGRAY
        _quad3d(rl, Vector3(p - t, 0.0, -half), Vector3(p + t, 0.0, -half), Vector3(p + t, 0.0, half), Vector3(p - t, 0.0, half), col)
        _quad3d(rl, Vector3(-half, 0.0, p - t), Vector3(half, 0.0, p - t), Vector3(half, 0.0, p + t), Vector3(-half, 0.0, p + t), col)


def draw_line_3d(mut rl: RLGL, gl: OwnedDLHandle, start: Vector3, end: Vector3, color: Vec4f) raises:
    rl.begin_mode(gl, GL_LINES)
    rl.set_texture(gl, 0)
    rl.current_color = color
    rl.vertex3f(start.data[0], start.data[1], start.data[2])
    rl.vertex3f(end.data[0], end.data[1], end.data[2])

def draw_bounding_box(mut rl: RLGL, gl: OwnedDLHandle, box: BoundingBox, color: Vec4f) raises:
    var x0 = box.min.data[0]; var y0 = box.min.data[1]; var z0 = box.min.data[2]
    var x1 = box.max.data[0]; var y1 = box.max.data[1]; var z1 = box.max.data[2]

    var v0 = Vector3(x0, y0, z1) # Front-bottom-left
    var v1 = Vector3(x1, y0, z1) # Front-bottom-right
    var v2 = Vector3(x1, y1, z1) # Front-top-right
    var v3 = Vector3(x0, y1, z1) # Front-top-left
    var v4 = Vector3(x0, y0, z0) # Back-bottom-left
    var v5 = Vector3(x1, y0, z0) # Back-bottom-right
    var v6 = Vector3(x1, y1, z0) # Back-top-right
    var v7 = Vector3(x0, y1, z0) # Back-top-left

    # Front face edges
    draw_line_3d(rl, gl, v0, v1, color)
    draw_line_3d(rl, gl, v1, v2, color)
    draw_line_3d(rl, gl, v2, v3, color)
    draw_line_3d(rl, gl, v3, v0, color)

    # Back face edges
    draw_line_3d(rl, gl, v4, v5, color)
    draw_line_3d(rl, gl, v5, v6, color)
    draw_line_3d(rl, gl, v6, v7, color)
    draw_line_3d(rl, gl, v7, v4, color)

    # Connecting side edges
    draw_line_3d(rl, gl, v0, v4, color)
    draw_line_3d(rl, gl, v1, v5, color)
    draw_line_3d(rl, gl, v2, v6, color)
    draw_line_3d(rl, gl, v3, v7, color)

    # Restore triangle mode for subsequent solid shapes
    rl.begin_mode(gl, GL_TRIANGLES)

def draw_cube_wires(mut rl: RLGL, gl: OwnedDLHandle, pos: Vector3, w: Float32, h: Float32, length: Float32, color: Vec4f) raises:
    var box = BoundingBox.from_center_size(pos, w, h, length)
    draw_bounding_box(rl, gl, box, color)
