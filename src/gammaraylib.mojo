from std.ffi import OwnedDLHandle, c_int, c_uint, c_float, c_double
from std.origin import MutUntrackedOrigin
from std.memory import Pointer

from raymath import Vec2f, Vector3, Vec4f, Matrix
from rlgl import RLGL, Camera3D, GL_DEPTH_BUFFER_BIT
from rshapes import *
from rtextures import Texture2D, gen_texture_checked, load_texture, unload_texture, draw_texture, draw_texture_pro, WHITE
from rtext import Font, load_font_default, load_font, draw_text, measure_text
from rcollisions import BoundingBox, Ray, RayCollision, check_collision_boxes, get_ray_collision_box
from rmaterials import Material, MaterialMap, MATERIAL_MAP_DIFFUSE, MATERIAL_MAP_SPECULAR, MATERIAL_MAP_NORMAL, load_material_default
from rmodels import Mesh, Model, load_model, draw_model
from raudio import AudioDevice, Sound, load_sound, gen_sound_click, gen_sound_laser, gen_sound_explosion, gen_sound_powerup
from rgui import Rectangle, gui_panel, gui_button, gui_checkbox, gui_slider

comptime VoidPtr    = Pointer[NoneType, MutUntrackedOrigin]
comptime OptVoidPtr = Optional[VoidPtr]
comptime IntPtr     = Pointer[c_int, MutUntrackedOrigin]
comptime DoublePtr  = Pointer[c_double, MutUntrackedOrigin]

# --- Number Keys (0–9) ---
comptime KEY_0: c_int = 48
comptime KEY_1: c_int = 49
comptime KEY_2: c_int = 50
comptime KEY_3: c_int = 51
comptime KEY_4: c_int = 52
comptime KEY_5: c_int = 53
comptime KEY_6: c_int = 54
comptime KEY_7: c_int = 55
comptime KEY_8: c_int = 56
comptime KEY_9: c_int = 57
# --- Alphabet Keys (A–Z) ---
comptime KEY_A: c_int = 65
comptime KEY_B: c_int = 66
comptime KEY_C: c_int = 67
comptime KEY_D: c_int = 68
comptime KEY_E: c_int = 69
comptime KEY_F: c_int = 70
comptime KEY_G: c_int = 71
comptime KEY_H: c_int = 72
comptime KEY_I: c_int = 73
comptime KEY_J: c_int = 74
comptime KEY_K: c_int = 75
comptime KEY_L: c_int = 76
comptime KEY_M: c_int = 77
comptime KEY_N: c_int = 78
comptime KEY_O: c_int = 79
comptime KEY_P: c_int = 80
comptime KEY_Q: c_int = 81
comptime KEY_R: c_int = 82
comptime KEY_S: c_int = 83
comptime KEY_T: c_int = 84
comptime KEY_U: c_int = 85
comptime KEY_V: c_int = 86
comptime KEY_W: c_int = 87
comptime KEY_X: c_int = 88
comptime KEY_Y: c_int = 89
comptime KEY_Z: c_int = 90
# --- Special & Navigation Keys ---
comptime KEY_SPACE: c_int       = 32
comptime KEY_GRAVE: c_int       = 96
comptime KEY_ESCAPE: c_int      = 256
comptime KEY_ENTER: c_int       = 257
comptime KEY_TAB: c_int         = 258
comptime KEY_BACKSPACE: c_int   = 259
comptime KEY_RIGHT: c_int       = 262
comptime KEY_LEFT: c_int        = 263
comptime KEY_DOWN: c_int        = 264
comptime KEY_UP: c_int          = 265
comptime KEY_LEFT_SHIFT: c_int  = 340
comptime KEY_RIGHT_SHIFT: c_int = 344

comptime MAX_KEYS: Int          = 350
comptime MAX_MOUSE_BUTTONS: Int = 8

comptime MOUSE_BUTTON_LEFT: c_int  = 0
comptime MOUSE_BUTTON_RIGHT: c_int = 1

comptime GLFW_CONTEXT_VERSION_MAJOR: c_int = 0x00022002
comptime GLFW_CONTEXT_VERSION_MINOR: c_int = 0x00022003
comptime GLFW_OPENGL_PROFILE: c_int        = 0x00022008
comptime GLFW_OPENGL_CORE_PROFILE: c_int   = 0x00032001
comptime GLFW_RED_BITS: c_int              = 0x00021001
comptime GLFW_GREEN_BITS: c_int            = 0x00021002
comptime GLFW_BLUE_BITS: c_int             = 0x00021003
comptime GLFW_REFRESH_RATE: c_int          = 0x0002100F
comptime GLFW_WAYLAND_APP_ID: c_int        = 0x00026001
comptime GLFW_CURSOR: c_int                = 0x00033001
comptime GLFW_CURSOR_DISABLED: c_int       = 0x00034003
comptime GLFW_CURSOR_NORMAL: c_int         = 0x00034001
comptime GLFW_PRESS: c_int                 = 1
comptime GL_COLOR_BUFFER_BIT: c_uint       = 0x00004000

struct Raylib:
    var glfw: OwnedDLHandle
    var gl: OwnedDLHandle
    var win: OptVoidPtr
    var rl: RLGL
    var default_font: Font

    var screen_width: Float32
    var screen_height: Float32
    var design_width: Float32
    var design_height: Float32

    var delta_time: Float32
    var last_time: c_double
    var last_mouse_x: Float32
    var last_mouse_y: Float32
    var mouse_dx: Float32
    var mouse_dy: Float32
    var audio: AudioDevice
    var prev_keys: Array[Bool, MAX_KEYS]
    var curr_keys: Array[Bool, MAX_KEYS]
    var prev_mouse: Array[Bool, MAX_MOUSE_BUTTONS]
    var curr_mouse: Array[Bool, MAX_MOUSE_BUTTONS]

    var mouse_x: Float32
    var mouse_y: Float32
    var cursor_locked: Bool

    def __init__(out self, width: Int, height: Int, title: String, fullscreen: Bool = True) raises:
        self.glfw = OwnedDLHandle("libglfw.so")
        self.gl   = OwnedDLHandle("libGL.so.1")

        var glfwInit               = self.glfw.get_function[c_int]("glfwInit")
        var glfwWindowHint         = self.glfw.get_function("glfwWindowHint")
        var glfwWindowHintString   = self.glfw.get_function("glfwWindowHintString")
        var glfwGetPrimaryMonitor  = self.glfw.get_function[OptVoidPtr]("glfwGetPrimaryMonitor")
        var glfwGetVideoMode       = self.glfw.get_function[IntPtr]("glfwGetVideoMode")
        var glfwCreateWindow       = self.glfw.get_function[OptVoidPtr]("glfwCreateWindow")
        var glfwMakeContextCurrent = self.glfw.get_function("glfwMakeContextCurrent")
        var glfwGetTime            = self.glfw.get_function[c_double]("glfwGetTime")
        var glfwGetCursorPos       = self.glfw.get_function("glfwGetCursorPos")

        if glfwInit() == 0:
            raise Error("Failed to initialize GLFW")

        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, c_int(4))
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, c_int(6))
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE)

        var app_id = "gammaraylib\x00"
        glfwWindowHintString(GLFW_WAYLAND_APP_ID, app_id.unsafe_ptr())
        _ = app_id

        var win_w = c_int(width)
        var win_h = c_int(height)
        var monitor: OptVoidPtr = None

        if fullscreen:
            monitor = glfwGetPrimaryMonitor()
            if monitor:
                var mode = glfwGetVideoMode(monitor)
                win_w = mode[unsafe_offset=0]
                win_h = mode[unsafe_offset=1]
                glfwWindowHint(GLFW_RED_BITS, mode[unsafe_offset=2])
                glfwWindowHint(GLFW_GREEN_BITS, mode[unsafe_offset=3])
                glfwWindowHint(GLFW_BLUE_BITS, mode[unsafe_offset=4])
                glfwWindowHint(GLFW_REFRESH_RATE, mode[unsafe_offset=5])

        var c_title = title + "\x00"
        var null_ptr: OptVoidPtr = None
        self.win = glfwCreateWindow(win_w, win_h, c_title.unsafe_ptr(), monitor, null_ptr)
        _ = c_title

        if not self.win:
            var glfwTerminate = self.glfw.get_function("glfwTerminate")
            glfwTerminate()
            raise Error("Failed to create GLFW window")

        glfwMakeContextCurrent(self.win)

        self.rl = RLGL(self.gl)
        self.default_font = load_font_default(self.gl)
        #self.default_font = load_font(self.gl, "assets/font/menuFont.ttf")
        self.audio = AudioDevice()
        self.screen_width = Float32(width)
        self.screen_height = Float32(height)
        self.design_width = Float32(width)
        self.design_height = Float32(height)
        self.delta_time = 0.016
        self.last_time = glfwGetTime()

        var mx = c_double(0.0)
        var my = c_double(0.0)
        glfwGetCursorPos(
            self.win,
            DoublePtr(unsafe_from_address=Int(Pointer(to=mx))),
            DoublePtr(unsafe_from_address=Int(Pointer(to=my))),
        )
        self.last_mouse_x = Float32(mx)
        self.last_mouse_y = Float32(my)
        self.mouse_dx = 0.0
        self.mouse_dy = 0.0
        self.prev_keys  = Array[Bool, MAX_KEYS](fill=False)
        self.curr_keys  = Array[Bool, MAX_KEYS](fill=False)
        self.prev_mouse = Array[Bool, MAX_MOUSE_BUTTONS](fill=False)
        self.curr_mouse = Array[Bool, MAX_MOUSE_BUTTONS](fill=False)
        self.mouse_x = Float32(mx)
        self.mouse_y = Float32(my)
        self.cursor_locked = False

    def close(mut self) raises:
        var glfwTerminate = self.glfw.get_function("glfwTerminate")
        glfwTerminate()

    def window_should_close(self) raises -> Bool:
        var glfwWindowShouldClose = self.glfw.get_function[c_int]("glfwWindowShouldClose")
        return glfwWindowShouldClose(self.win) != 0

    def disable_cursor(mut self) raises:
        var glfwSetInputMode = self.glfw.get_function("glfwSetInputMode")
        glfwSetInputMode(self.win, GLFW_CURSOR, GLFW_CURSOR_DISABLED)
        self.cursor_locked = True

    def enable_cursor(mut self) raises:
        var glfwSetInputMode = self.glfw.get_function("glfwSetInputMode")
        glfwSetInputMode(self.win, GLFW_CURSOR, GLFW_CURSOR_NORMAL)
        self.cursor_locked = False

    def toggle_cursor(mut self) raises:
        if self.cursor_locked:
            self.enable_cursor()
        else:
            self.disable_cursor()

    def is_key_down(self, key: c_int) -> Bool:
        var idx = Int(key)
        if idx < 0 or idx >= MAX_KEYS:
            return False
        return self.curr_keys[idx]

    def is_key_pressed(self, key: c_int) -> Bool:
        var idx = Int(key)
        if idx < 0 or idx >= MAX_KEYS:
            return False
        return self.curr_keys[idx] and not self.prev_keys[idx]

    def is_mouse_button_down(self, button: c_int) -> Bool:
        var idx = Int(button)
        if idx < 0 or idx >= MAX_MOUSE_BUTTONS:
            return False
        return self.curr_mouse[idx]

    def is_mouse_button_pressed(self, button: c_int) -> Bool:
        var idx = Int(button)
        if idx < 0 or idx >= MAX_MOUSE_BUTTONS:
            return False
        return self.curr_mouse[idx] and not self.prev_mouse[idx]

    def get_frame_time(self) -> Float32:
        return self.delta_time

    def get_fps(self) -> Int:
        return Int(1.0 / self.delta_time) if self.delta_time > 0.0 else 0

    def update_camera_first_person(self, mut camera: Camera3D):
        if not self.cursor_locked: return
        var fwd: Float32 = 0.0
        var right: Float32 = 0.0
        var up: Float32 = 0.0
        if self.is_key_down(KEY_W): fwd += 1.0
        if self.is_key_down(KEY_S): fwd -= 1.0
        if self.is_key_down(KEY_D): right += 1.0
        if self.is_key_down(KEY_A): right -= 1.0
        if self.is_key_down(KEY_SPACE): up += 1.0
        if self.is_key_down(KEY_LEFT_SHIFT): up -= 1.0
        camera.update_first_person(self.mouse_dx, self.mouse_dy, fwd, right, up, self.delta_time)

    # --- Frame Lifecycle ---
    def begin_drawing(mut self) raises:
        var glfwGetTime            = self.glfw.get_function[c_double]("glfwGetTime")
        var glfwGetFramebufferSize = self.glfw.get_function("glfwGetFramebufferSize")
        var glfwGetCursorPos       = self.glfw.get_function("glfwGetCursorPos")
        var glViewport             = self.gl.get_function("glViewport")
        var glfwGetKey             = self.glfw.get_function[c_int]("glfwGetKey")
        var glfwGetMouseButton     = self.glfw.get_function[c_int]("glfwGetMouseButton")
        var glfwGetWindowSize      = self.glfw.get_function("glfwGetWindowSize")
        var glScissor    = self.gl.get_function("glScissor")
        var glEnable     = self.gl.get_function("glEnable")
        var glDisable    = self.gl.get_function("glDisable")
        var glClearColor = self.gl.get_function("glClearColor")
        var glClear      = self.gl.get_function("glClear")
        var GL_SCISSOR_TEST: c_uint = 0x0C11
        var GL_COLOR_BUFFER_BIT: c_uint = 0x00004000

        var win_w = c_int(0)
        var win_h = c_int(0)
        glfwGetWindowSize(
            self.win,
            IntPtr(unsafe_from_address=Int(Pointer(to=win_w))),
            IntPtr(unsafe_from_address=Int(Pointer(to=win_h))),
        )

        for k in range(MAX_KEYS):
            self.prev_keys[k] = self.curr_keys[k]
            self.curr_keys[k] = glfwGetKey(self.win, c_int(k)) == GLFW_PRESS

        for b in range(MAX_MOUSE_BUTTONS):
            self.prev_mouse[b] = self.curr_mouse[b]
            self.curr_mouse[b] = glfwGetMouseButton(self.win, c_int(b)) == GLFW_PRESS

        var now = glfwGetTime()
        self.delta_time = Float32(now - self.last_time)
        self.last_time = now

        var mx = c_double(0.0)
        var my = c_double(0.0)
        glfwGetCursorPos(
            self.win,
            DoublePtr(unsafe_from_address=Int(Pointer(to=mx))),
            DoublePtr(unsafe_from_address=Int(Pointer(to=my))),
        )
        var cur_mx = Float32(mx)
        var cur_my = Float32(my)
        self.mouse_dx = cur_mx - self.last_mouse_x
        self.mouse_dy = cur_my - self.last_mouse_y
        self.last_mouse_x = cur_mx
        self.last_mouse_y = cur_my

        var fb_w = c_int(0)
        var fb_h = c_int(0)
        glfwGetFramebufferSize(
            self.win,
            IntPtr(unsafe_from_address=Int(Pointer(to=fb_w))),
            IntPtr(unsafe_from_address=Int(Pointer(to=fb_h))),
        )
        if fb_w > 0 and fb_h > 0:
            var target_aspect = self.design_width / self.design_height if self.design_height > 0.0 else Float32(1.0)
            var fb_aspect = Float32(fb_w) / Float32(fb_h)
            var vp_w = Int(fb_w)
            var vp_h = Int(fb_h)
            var vp_x = 0
            var vp_y = 0

            if fb_aspect > target_aspect:
                vp_w = Int(Float32(fb_h) * target_aspect)
                vp_x = (Int(fb_w) - vp_w) // 2
            elif fb_aspect < target_aspect:
                vp_h = Int(Float32(fb_w) / target_aspect)
                vp_y = (Int(fb_h) - vp_h) // 2

            glDisable(GL_SCISSOR_TEST)
            glViewport(c_int(0), c_int(0), fb_w, fb_h)
            glClearColor(c_float(0.0), c_float(0.0), c_float(0.0), c_float(1.0))
            glClear(GL_COLOR_BUFFER_BIT)

            glEnable(GL_SCISSOR_TEST)
            glScissor(c_int(vp_x), c_int(vp_y), c_int(vp_w), c_int(vp_h))
            glViewport(c_int(vp_x), c_int(vp_y), c_int(vp_w), c_int(vp_h))
            self.screen_width = self.design_width
            self.screen_height = self.design_height

            var win_aspect = Float32(win_w) / Float32(win_h) if win_h > 0 else target_aspect
            var win_vp_w = Float32(win_w)
            var win_vp_h = Float32(win_h)
            var win_vp_x: Float32 = 0.0
            var win_vp_y: Float32 = 0.0
            if win_aspect > target_aspect:
                win_vp_w = Float32(win_h) * target_aspect
                win_vp_x = (Float32(win_w) - win_vp_w) * 0.5
            elif win_aspect < target_aspect:
                win_vp_h = Float32(win_w) / target_aspect
                win_vp_y = (Float32(win_h) - win_vp_h) * 0.5

            self.mouse_x = ((cur_mx - win_vp_x) / win_vp_w) * self.design_width if win_vp_w > 0.0 else cur_mx
            self.mouse_y = ((cur_my - win_vp_y) / win_vp_h) * self.design_height if win_vp_h > 0.0 else cur_my

        self.rl.projection = Matrix.ortho(0.0, self.design_width, self.design_height, 0.0, -1.0, 1.0)
        self.rl.modelview = Matrix.identity()

    def clear_background(self, color: Vec4f) raises:
        var glClearColor = self.gl.get_function("glClearColor")
        var glClear      = self.gl.get_function("glClear")
        glClearColor(c_float(color[0]), c_float(color[1]), c_float(color[2]), c_float(color[3]))
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

    def end_drawing(mut self) raises:
        var glfwSwapBuffers          = self.glfw.get_function("glfwSwapBuffers")
        var glfwPollEvents           = self.glfw.get_function("glfwPollEvents")
        var glfwSetWindowShouldClose = self.glfw.get_function("glfwSetWindowShouldClose")

        if self.is_key_down(KEY_ESCAPE):
            glfwSetWindowShouldClose(self.win, c_int(1))

        self.rl.flush(self.gl)
        glfwSwapBuffers(self.win)
        glfwPollEvents()

    def get_camera_ray(self, camera: Camera3D) -> Ray:
        # Center crosshair ray shoots straight from camera.position toward camera.target
        return Ray(camera.position, camera.target - camera.position)

    # --- 3D Mode ---
    def begin_mode_3d(mut self, camera: Camera3D) raises:
        self.rl.begin_mode_3d(self.gl, camera, self.screen_width / self.screen_height)

    def end_mode_3d(mut self) raises:
        self.rl.end_mode_3d(self.gl, self.screen_width, self.screen_height)

    # --- High-Level Drawing Wrappers ---
    def draw_plane(mut self, center: Vector3, width: Float32, length: Float32, color: Vec4f) raises:
        draw_plane(self.rl, self.gl, center, width, length, color)

    def draw_sphere(mut self, center: Vector3, radius: Float32, color: Vec4f, rings: Int = 16, slices: Int = 24) raises:
        draw_sphere(self.rl, self.gl, center, radius, rings, slices, color)

    def draw_line(mut self, start_x: Float32, start_y: Float32, end_x: Float32, end_y: Float32, color: Vec4f) raises:
        draw_line(self.rl, self.gl, start_x, start_y, end_x, end_y, color)
    def draw_rectangle(mut self, x: Float32, y: Float32, w: Float32, h: Float32, color: Vec4f) raises:
        draw_rectangle(self.rl, self.gl, x, y, w, h, color)
    def draw_rectangle_lines(mut self, x: Float32, y: Float32, w: Float32, h: Float32, color: Vec4f) raises:
        draw_rectangle_lines(self.rl, self.gl, x, y, w, h, color)
    def draw_texture_pro(mut self, tex: Texture2D, source: Rectangle, dest: Rectangle, origin: Vec2f, rotation: Float32, tint: Vec4f = WHITE) raises:
        draw_texture_pro(self.rl, self.gl, tex, source, dest, origin, rotation, tint)
    def draw_circle(mut self, center_x: Float32, center_y: Float32, radius: Float32, color: Vec4f):
        draw_circle(self.rl, center_x, center_y, radius, color)
    def draw_cube(mut self, pos: Vector3, w: Float32, h: Float32, length: Float32, color: Vec4f) raises:
        draw_cube(self.rl, self.gl, pos, w, h, length, color)
    def draw_grid(mut self, slices: Int, spacing: Float32):
        draw_grid(self.rl, slices, spacing)
    def gen_texture_checked(self, w: Int, h: Int, cx: Int, cy: Int) raises -> Texture2D:
        return gen_texture_checked(self.gl, w, h, cx, cy)
    def draw_texture(mut self, tex: Texture2D, x: Float32, y: Float32, tint: Vec4f = WHITE) raises:
        draw_texture(self.rl, self.gl, tex, x, y, tint)
    def draw_text(mut self, text: String, x: Float32, y: Float32, font_size: Float32, color: Vec4f) raises:
        draw_text(self.rl, self.gl, self.default_font, text, x, y, font_size, color)
    def draw_fps(mut self, x: Float32, y: Float32) raises:
        self.draw_text("FPS: " + String(self.get_fps()), x, y, 20.0, DARKGRAY)
    def draw_line_3d(mut self, start: Vector3, end: Vector3, color: Vec4f) raises:
        draw_line_3d(self.rl, self.gl, start, end, color)
    def draw_cube_wires(mut self, pos: Vector3, w: Float32, h: Float32, length: Float32, color: Vec4f) raises:
        draw_cube_wires(self.rl, self.gl, pos, w, h, length, color)
    def draw_bounding_box(mut self, box: BoundingBox, color: Vec4f) raises:
        draw_bounding_box(self.rl, self.gl, box, color)
    def load_texture(self, path: String, smooth: Bool = False) raises -> Texture2D:
        return load_texture(self.gl, path, smooth)
    def unload_texture(self, tex: Texture2D) raises:
        unload_texture(self.gl, tex)

    def draw_cube_texture(mut self, tex: Texture2D, pos: Vector3, w: Float32, h: Float32, length: Float32, color: Vec4f = WHITE) raises:
        draw_cube_texture(self.rl, self.gl, tex, pos, w, h, length, color)
    def draw_cube_material(mut self, mat: Material, pos: Vector3, w: Float32, h: Float32, length: Float32) raises:
        draw_cube_material(self.rl, self.gl, mat, pos, w, h, length)
    def draw_plane_material(mut self, mat: Material, center: Vector3, width: Float32, length: Float32, uv_scale: Float32 = 1.0) raises:
        draw_plane_material(self.rl, self.gl, mat, center, width, length, uv_scale)
    def load_model(self, path: String) raises -> Model:
        return load_model(path)
    def draw_model(mut self, model: Model, position: Vector3, scale: Float32 = 1.0, tint: Vec4f = WHITE) raises:
        draw_model(self.rl, self.gl, model, position, scale, tint)
    def load_sound(self, path: String) raises -> Sound:
        return load_sound(path)
    def play_sound(self, sound: Sound) raises:
        self.audio.play_sound(sound)
    def gen_sound_click(self, freq: Float32 = 880.0, duration_sec: Float32 = 0.04) -> Sound:
        return gen_sound_click(freq, duration_sec)
    def gen_sound_laser(self, start_freq: Float32 = 960.0, end_freq: Float32 = 180.0, duration_sec: Float32 = 0.14) -> Sound:
        return gen_sound_laser(start_freq, end_freq, duration_sec)
    def gen_sound_explosion(self, duration_sec: Float32 = 0.35) -> Sound:
        return gen_sound_explosion(duration_sec)
    def gen_sound_powerup(self, duration_sec: Float32 = 0.24) -> Sound:
        return gen_sound_powerup(duration_sec)
    def gui_panel(mut self, bounds: Rectangle, title: String) raises:
        gui_panel(self.rl, self.gl, self.default_font, bounds, title)
    def gui_button(mut self, bounds: Rectangle, text: String) raises -> Bool:
        return gui_button(
            self.rl, self.gl, self.default_font, bounds, text,
            self.mouse_x, self.mouse_y,
            self.is_mouse_button_down(MOUSE_BUTTON_LEFT),
            self.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
        )
    def gui_checkbox(mut self, bounds: Rectangle, text: String, mut checked: Bool) raises -> Bool:
        return gui_checkbox(
            self.rl, self.gl, self.default_font, bounds, text, checked,
            self.mouse_x, self.mouse_y,
            self.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
        )
    def gui_slider(mut self, bounds: Rectangle, label: String, mut value: Float32, min_val: Float32, max_val: Float32) raises:
        gui_slider(
            self.rl, self.gl, self.default_font, bounds, label, value, min_val, max_val,
            self.mouse_x, self.mouse_y,
            self.is_mouse_button_down(MOUSE_BUTTON_LEFT),
        )
    def set_sound_volume(self, sound: Sound, volume: Float32):
        sound.set_volume(volume)
    def is_sound_playing(self, sound: Sound) -> Bool:
        return sound.is_playing()
    def stop_sound(self, sound: Sound):
        sound.stop()
    #def load_font(self, path: String, pixel_size: Int = 48) raises -> Font:
    #    return load_font(self.gl, path, pixel_size)
    def load_font(self, path: String, pixel_size: Int = 48) raises -> Font:
        return load_font(self.gl, path)
    def measure_text(self, text: String, font_size: Float32) -> Float32:
        return measure_text(self.default_font, text, font_size)
