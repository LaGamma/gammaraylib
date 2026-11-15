from std.ffi import OwnedDLHandle, c_int, c_uint, c_float
from std.origin import MutUntrackedOrigin
from std.memory import Pointer
from std.collections import Array
from std.memory.alloc import unsafe_alloc, dealloc
from std.math import sin, cos
from std.sys.defines import is_defined

from raymath import Vector3, Matrix, Vec2f, Vec4f

comptime VoidPtr    = Pointer[NoneType, MutUntrackedOrigin]
comptime CharPtr    = Pointer[UInt8, MutUntrackedOrigin]
comptime CharPtrPtr = Pointer[CharPtr, MutUntrackedOrigin]
comptime UIntPtr    = Pointer[c_uint, MutUntrackedOrigin]
comptime IntPtr     = Pointer[c_int, MutUntrackedOrigin]
comptime FloatPtr   = Pointer[c_float, MutUntrackedOrigin]
comptime OptVoidPtr = Optional[VoidPtr]
comptime OptIntPtr  = Optional[IntPtr]

# OpenGL Constants
comptime GL_LINES: c_uint     = 0x0001
comptime GL_TRIANGLES: c_uint = 0x0004
comptime GL_ARRAY_BUFFER: c_uint     = 0x8892
comptime GL_DYNAMIC_DRAW: c_uint     = 0x88E8
comptime GL_FLOAT: c_uint            = 0x1406
comptime GL_FRAGMENT_SHADER: c_uint  = 0x8B30
comptime GL_VERTEX_SHADER: c_uint    = 0x8B31
comptime GL_DEPTH_BUFFER_BIT: c_uint = 0x00000100
comptime GL_DEPTH_TEST: c_uint       = 0x0B71
comptime GL_TEXTURE_2D: c_uint         = 0x0DE1
comptime GL_TEXTURE_MIN_FILTER: c_uint = 0x2801
comptime GL_TEXTURE_MAG_FILTER: c_uint = 0x2800
comptime GL_NEAREST: c_int             = 0x2600
comptime GL_LINEAR: c_int              = 0x2601
comptime GL_RGBA: c_uint               = 0x1908
comptime GL_UNSIGNED_BYTE: c_uint      = 0x1401
comptime GL_BLEND: c_uint              = 0x0BE2
comptime GL_SRC_ALPHA: c_uint          = 0x0302
comptime GL_ONE_MINUS_SRC_ALPHA: c_uint = 0x0303

comptime FLOATS_PER_VERTEX: Int = 12  # x, y, z, r, g, b, a, u, v, nx, ny, nz
comptime MAX_BATCH_VERTICES: Int = 8192

struct Camera3D(Copyable, Movable):
    var position: Vector3
    var target: Vector3
    var up: Vector3
    var fovy: Float32
    var yaw: Float32
    var pitch: Float32

    def __init__(
        out self,
        position: Vector3 = Vector3(0.0, 2.0, 6.0),
        target: Vector3 = Vector3(0.0, 2.0, 0.0),
        up: Vector3 = Vector3(0.0, 1.0, 0.0),
        fovy: Float32 = 45.0,
    ):
        self.position = position
        self.target = target
        self.up = up
        self.fovy = fovy
        self.yaw = -1.5707963  # -90 deg (looking down -Z)
        self.pitch = 0.0

    def update_first_person(
        mut self,
        mouse_dx: Float32,
        mouse_dy: Float32,
        move_forward: Float32,
        move_right: Float32,
        move_up: Float32,
        dt: Float32,
    ):
        var sensitivity: Float32 = 0.0025
        var speed: Float32 = 6.0 * dt

        # 1. Update Yaw & Pitch from mouse delta
        self.yaw += mouse_dx * sensitivity
        self.pitch -= mouse_dy * sensitivity

        # Clamp pitch to [-89 deg, +89 deg] to prevent gimbal flip
        var max_pitch: Float32 = 1.5533
        if self.pitch > max_pitch:
            self.pitch = max_pitch
        elif self.pitch < -max_pitch:
            self.pitch = -max_pitch

        # 2. Compute 3D forward look vector from yaw & pitch
        var cos_pitch = cos(self.pitch)
        var forward = Vector3(
            cos(self.yaw) * cos_pitch,
            sin(self.pitch),
            sin(self.yaw) * cos_pitch,
        ).normalize()

        # 3. Compute horizontal plane movement vectors (so looking up/down doesn't fly)
        var flat_forward = Vector3(cos(self.yaw), 0.0, sin(self.yaw)).normalize()
        var right = flat_forward.cross(self.up).normalize()

        # 4. Apply WASD + Space/Shift movement
        self.position = self.position + (flat_forward * (move_forward * speed))
        self.position = self.position + (right * (move_right * speed))
        self.position = self.position + (self.up * (move_up * speed))

        # 5. Update look target ahead of eye position
        self.target = self.position + forward

struct RLGL:
    var vao: c_uint
    var vbo: c_uint
    var shader_program: c_uint
    var mvp_loc: c_int

    var vertices: FloatPtr
    var vertex_count: Int

    var current_color: Vec4f
    var modelview: Matrix
    var projection: Matrix
    var stack: Array[Matrix, 32]
    var stack_ptr: Int

    var current_uv: Vec2f
    var default_texture_id: c_uint
    var active_texture_id: c_uint
    var draw_mode: c_uint

    var current_normal: Vec4f
    var light_dir: Vector3
    var light_enabled: Bool
    var light_enabled_loc: c_int
    var light_dir_loc: c_int

    def __init__(out self, gl: OwnedDLHandle) raises:
        self.vertices = unsafe_alloc[c_float](MAX_BATCH_VERTICES * FLOATS_PER_VERTEX)
        self.vertex_count = 0
        self.current_color = Vec4f(1.0, 1.0, 1.0, 1.0)
        self.modelview = Matrix.identity()
        self.projection = Matrix.identity()
        self.stack = Array[Matrix, 32](fill=Matrix.identity())
        self.stack_ptr = 0
        self.draw_mode = GL_TRIANGLES

        var vs_src = """#version 460 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec4 aColor;
layout (location = 2) in vec2 aUV;
layout (location = 3) in vec3 aNormal;
out vec4 vColor;
out vec2 vUV;
out vec3 vNormal;
uniform mat4 uMVP;
void main() {
    gl_Position = uMVP * vec4(aPos, 1.0);
    vColor = aColor;
    vUV = aUV;
    vNormal = aNormal;
}\x00"""

        var fs_src = """#version 460 core
precision mediump float;
in vec4 vColor;
in vec2 vUV;
in vec3 vNormal;
out vec4 FragColor;
uniform sampler2D uTex;
uniform int uLightEnabled;
uniform vec3 uLightDir;
void main() {
    vec4 base = vColor * texture(uTex, vUV);
    if (uLightEnabled == 1) {
        vec3 n = normalize(vNormal);
        float diff = max(dot(n, normalize(-uLightDir)), 0.0);
        float ambient = 0.25;
        FragColor = vec4(base.rgb * (ambient + diff * 0.75), base.a);
    } else {
        FragColor = base;
    }
}\x00"""

        var null_void_ptr: OptVoidPtr = None
        var glCreateShader = gl.get_function[c_uint]("glCreateShader")
        var glShaderSource = gl.get_function("glShaderSource")
        var glCompileShader = gl.get_function("glCompileShader")
        var glCreateProgram = gl.get_function[c_uint]("glCreateProgram")
        var glAttachShader = gl.get_function("glAttachShader")
        var glLinkProgram = gl.get_function("glLinkProgram")
        var glGetUniformLocation = gl.get_function[c_int]("glGetUniformLocation")

        var vs_span = vs_src.as_c_string_span()
        var vs_ptr = CharPtr(unsafe_from_address=Int(vs_span.ptr()))
        var vs_len = c_int(len(vs_span))
        var vs = glCreateShader(GL_VERTEX_SHADER)
        glShaderSource(
            vs,
            c_int(1),
            CharPtrPtr(unsafe_from_address=Int(Pointer(to=vs_ptr))),
            IntPtr(unsafe_from_address=Int(Pointer(to=vs_len))),
        )
        glCompileShader(vs)
        _ = vs_ptr
        _ = vs_len
        _ = vs_src

        var fs_span = fs_src.as_c_string_span()
        var fs_ptr = CharPtr(unsafe_from_address=Int(fs_span.ptr()))
        var fs_len = c_int(len(fs_span))
        var fs = glCreateShader(GL_FRAGMENT_SHADER)
        glShaderSource(
            fs,
            c_int(1),
            CharPtrPtr(unsafe_from_address=Int(Pointer(to=fs_ptr))),
            IntPtr(unsafe_from_address=Int(Pointer(to=fs_len))),
        )
        glCompileShader(fs)
        _ = fs_ptr
        _ = fs_len
        _ = fs_src

        self.shader_program = glCreateProgram()
        glAttachShader(self.shader_program, vs)
        glAttachShader(self.shader_program, fs)
        glLinkProgram(self.shader_program)

        var u_mvp_name = "uMVP\x00"
        var u_mvp_span = u_mvp_name.as_c_string_span()
        self.mvp_loc = glGetUniformLocation(
            self.shader_program,
            CharPtr(unsafe_from_address=Int(u_mvp_span.ptr())),
        )
        _ = u_mvp_name
        _ = vs_src
        _ = fs_src
        _ = u_mvp_name

        var glGenVertexArrays = gl.get_function("glGenVertexArrays")
        var glBindVertexArray = gl.get_function("glBindVertexArray")
        var glGenBuffers = gl.get_function("glGenBuffers")
        var glBindBuffer = gl.get_function("glBindBuffer")
        var glBufferData = gl.get_function("glBufferData")
        var glVertexAttribPointer = gl.get_function("glVertexAttribPointer")
        var glEnableVertexAttribArray = gl.get_function("glEnableVertexAttribArray")

        self.vao = c_uint(0)
        self.vbo = c_uint(0)
        glGenVertexArrays(c_int(1), UIntPtr(unsafe_from_address=Int(Pointer(to=self.vao))))
        glGenBuffers(c_int(1), UIntPtr(unsafe_from_address=Int(Pointer(to=self.vbo))))

        glBindVertexArray(self.vao)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        var buffer_bytes = MAX_BATCH_VERTICES * FLOATS_PER_VERTEX * 4
        glBufferData(GL_ARRAY_BUFFER, buffer_bytes, null_void_ptr, GL_DYNAMIC_DRAW)

        var stride = c_int(FLOATS_PER_VERTEX * 4)
        glVertexAttribPointer(c_uint(0), c_int(3), GL_FLOAT, UInt8(0), stride, null_void_ptr)
        glEnableVertexAttribArray(c_uint(0))
        glVertexAttribPointer(c_uint(1), c_int(4), GL_FLOAT, UInt8(0), stride, VoidPtr(unsafe_from_address=12))
        glEnableVertexAttribArray(c_uint(1))

        # Location 2: UV (vec2) at byte offset 28 (7 floats * 4 bytes)
        glVertexAttribPointer(c_uint(2), c_int(2), GL_FLOAT, UInt8(0), stride, VoidPtr(unsafe_from_address=28))
        glEnableVertexAttribArray(c_uint(2))

        # Enable alpha blending for transparent sprites
        var glEnable = gl.get_function("glEnable")
        var glBlendFunc = gl.get_function("glBlendFunc")
        glEnable(GL_BLEND)
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

        # Create 1x1 white default texture
        var glGenTextures = gl.get_function("glGenTextures")
        var glBindTexture = gl.get_function("glBindTexture")
        var glTexParameteri = gl.get_function("glTexParameteri")
        var glTexImage2D = gl.get_function("glTexImage2D")

        self.default_texture_id = c_uint(0)
        glGenTextures(c_int(1), UIntPtr(unsafe_from_address=Int(Pointer(to=self.default_texture_id))))
        glBindTexture(GL_TEXTURE_2D, self.default_texture_id)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)

        var white_pixel = UInt32(0xFFFFFFFF)
        glTexImage2D(
            GL_TEXTURE_2D, c_int(0), c_int(GL_RGBA), c_int(1), c_int(1), c_int(0),
            GL_RGBA, GL_UNSIGNED_BYTE, VoidPtr(unsafe_from_address=Int(Pointer(to=white_pixel)))
        )
        _ = white_pixel
        self.active_texture_id = self.default_texture_id
        self.current_uv = Vec2f(0.0, 0.0)

        # Normal / lighting
        glVertexAttribPointer(c_uint(3), c_int(3), GL_FLOAT, UInt8(0), stride, VoidPtr(unsafe_from_address=36))
        glEnableVertexAttribArray(c_uint(3))
        var u_le_name = "uLightEnabled\x00"
        var u_ld_name = "uLightDir\x00"
        self.light_enabled_loc = glGetUniformLocation(self.shader_program, u_le_name.as_c_string_span().ptr())
        self.light_dir_loc     = glGetUniformLocation(self.shader_program, u_ld_name.as_c_string_span().ptr())
        _ = u_le_name
        _ = u_ld_name
        self.current_normal = Vec4f(0.0, 1.0, 0.0, 0.0)
        self.light_dir      = Vector3(-0.5, -1.0, -0.4).normalize()
        self.light_enabled  = False

    def push_matrix(mut self):
        if self.stack_ptr < 32:
            self.stack[self.stack_ptr] = self.modelview
            self.stack_ptr += 1

    def pop_matrix(mut self):
        if self.stack_ptr > 0:
            self.stack_ptr -= 1
            self.modelview = self.stack[self.stack_ptr]

    def translatef(mut self, x: Float32, y: Float32, z: Float32):
        self.modelview = self.modelview * Matrix.translate(x, y, z)

    def rotatef(mut self, angle_rad: Float32):
        self.modelview = self.modelview * Matrix.rotate_z(angle_rad)

    def color4f(mut self, r: Float32, g: Float32, b: Float32, a: Float32 = 1.0):
        self.current_color = Vec4f(r, g, b, a)

    def set_texture(mut self, gl: OwnedDLHandle, tex_id: c_uint) raises:
        var target_id = tex_id if tex_id != 0 else self.default_texture_id
        if self.active_texture_id != target_id:
            self.flush(gl)
            self.active_texture_id = target_id

    def texcoord2f(mut self, u: Float32, v: Float32):
        self.current_uv = Vec2f(u, v)

    def set_lighting(mut self, gl: OwnedDLHandle, enabled: Bool) raises:
        if self.light_enabled != enabled:
            self.flush(gl)
            self.light_enabled = enabled

    def normal3f(mut self, nx: Float32, ny: Float32, nz: Float32):
        # w = 0.0 rotates normal without translating it
        var world_n = self.modelview.transform_vec4(Vec4f(nx, ny, nz, 0.0))
        self.current_normal = world_n

    def vertex3f(mut self, x: Float32, y: Float32, z: Float32):
        if self.vertex_count >= MAX_BATCH_VERTICES:
            return
        var world_pos = self.modelview.transform_vec4(Vec4f(x, y, z, 1.0))
        var base = self.vertex_count * FLOATS_PER_VERTEX
        self.vertices[unsafe_offset=base + 0]  = world_pos[0]
        self.vertices[unsafe_offset=base + 1]  = world_pos[1]
        self.vertices[unsafe_offset=base + 2]  = world_pos[2]
        self.vertices[unsafe_offset=base + 3]  = self.current_color[0]
        self.vertices[unsafe_offset=base + 4]  = self.current_color[1]
        self.vertices[unsafe_offset=base + 5]  = self.current_color[2]
        self.vertices[unsafe_offset=base + 6]  = self.current_color[3]
        self.vertices[unsafe_offset=base + 7]  = self.current_uv[0]
        self.vertices[unsafe_offset=base + 8]  = self.current_uv[1]
        self.vertices[unsafe_offset=base + 9]  = self.current_normal[0]
        self.vertices[unsafe_offset=base + 10] = self.current_normal[1]
        self.vertices[unsafe_offset=base + 11] = self.current_normal[2]
        self.vertex_count += 1

    def flush(mut self, gl: OwnedDLHandle) raises:
        if self.vertex_count == 0:
            return

        var glUseProgram = gl.get_function("glUseProgram")
        var glUniformMatrix4fv = gl.get_function("glUniformMatrix4fv")
        var glBindVertexArray = gl.get_function("glBindVertexArray")
        var glBindBuffer = gl.get_function("glBindBuffer")
        var glBufferSubData = gl.get_function("glBufferSubData")
        var glDrawArrays = gl.get_function("glDrawArrays")
        var glBindTexture = gl.get_function("glBindTexture")

        glUseProgram(self.shader_program)

        var m = Array[c_float, 16](uninitialized=True)
        m[0]  = self.projection.c0[0]; m[1]  = self.projection.c0[1]; m[2]  = self.projection.c0[2]; m[3]  = self.projection.c0[3]
        m[4]  = self.projection.c1[0]; m[5]  = self.projection.c1[1]; m[6]  = self.projection.c1[2]; m[7]  = self.projection.c1[3]
        m[8]  = self.projection.c2[0]; m[9]  = self.projection.c2[1]; m[10] = self.projection.c2[2]; m[11] = self.projection.c2[3]
        m[12] = self.projection.c3[0]; m[13] = self.projection.c3[1]; m[14] = self.projection.c3[2]; m[15] = self.projection.c3[3]

        var proj_ptr = FloatPtr(unsafe_from_address=Int(Pointer(to=m)))
        glUniformMatrix4fv(self.mvp_loc, c_int(1), UInt8(0), proj_ptr)
        _ = m

        glBindVertexArray(self.vao)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        var byte_size = self.vertex_count * FLOATS_PER_VERTEX * 4
        glBufferSubData(GL_ARRAY_BUFFER, 0, byte_size, VoidPtr(unsafe_from_address=Int(self.vertices)))

        glBindTexture(GL_TEXTURE_2D, self.active_texture_id)

        glDrawArrays(self.draw_mode, c_int(0), c_int(self.vertex_count))
        self.vertex_count = 0

        var glUniform1i  = gl.get_function("glUniform1i")
        var glUniform3f  = gl.get_function("glUniform3f")
        glUniform1i(self.light_enabled_loc, c_int(1 if self.light_enabled else 0))
        glUniform3f(self.light_dir_loc,
                    c_float(self.light_dir.data[0]),
                    c_float(self.light_dir.data[1]),
                    c_float(self.light_dir.data[2]),
        )


    def rotate_yf(mut self, angle_rad: Float32):
        self.modelview = self.modelview * Matrix.rotate_y(angle_rad)

    def begin_mode(mut self, gl: OwnedDLHandle, mode: c_uint) raises:
        if self.draw_mode != mode:
            self.flush(gl)
            self.draw_mode = mode

    def begin_mode_3d(mut self, gl: OwnedDLHandle, camera: Camera3D, aspect: Float32) raises:
        # 1. Flush any 2D geometry drawn before entering 3D mode
        self.flush(gl)

        # 2. Enable depth testing so front faces occlude back faces
        var glEnable = gl.get_function("glEnable")
        glEnable(GL_DEPTH_TEST)

        # 3. Switch to perspective projection & camera view matrix
        var fov_rad = camera.fovy * (3.14159265 / 180.0)
        self.projection = Matrix.perspective(fov_rad, aspect, 0.01, 1000.0)
        self.modelview = Matrix.look_at(camera.position, camera.target, camera.up)

    def end_mode_3d(mut self, gl: OwnedDLHandle, screen_w: Float32, screen_h: Float32) raises:
        # 1. Flush all 3D geometry while depth test & perspective are active
        self.flush(gl)

        # 2. Disable depth test and restore 2D screen-space orthographic matrix
        var glDisable = gl.get_function("glDisable")
        glDisable(GL_DEPTH_TEST)

        self.projection = Matrix.ortho(0.0, screen_w, screen_h, 0.0, -1.0, 1.0)
        self.modelview = Matrix.identity()

        self.set_lighting(gl, False)
