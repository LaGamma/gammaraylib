from std.ffi import c_int
from std.sys import is_defined
from std.memory import Pointer, alloc, Layout
from std.origin import MutUntrackedOrigin
from gammaraylib import *

struct DemoState(Movable):
    var rl: Raylib
    var checker: Texture2D
    var sfx_bounce: Sound
    var sfx_boost: Sound
    var px: Float32
    var py: Float32
    var vx: Float32
    var vy: Float32
    var radius: Float32
    var paused: Bool

    def __init__(out self) raises:
        self.rl = Raylib(800, 600, "gammaraylib - Standalone Example", fullscreen=False)
        self.checker = self.rl.gen_texture_checked(64, 64, 4, 4)
        self.sfx_bounce = self.rl.gen_sound_click(660.0, 0.05)
        self.sfx_boost = self.rl.gen_sound_powerup(0.22)
        self.px = 400.0
        self.py = 300.0
        self.vx = 220.0
        self.vy = 175.0
        self.radius = 28.0
        self.paused = False

    def step(mut self) raises:
        var dt = self.rl.get_frame_time()

        if self.rl.is_key_pressed(KEY_SPACE):
            self.paused = not self.paused
            self.rl.play_sound(self.sfx_boost)

        if not self.paused:
            var accel: Float32 = 420.0
            if self.rl.is_key_down(KEY_LEFT) or self.rl.is_key_down(KEY_A):
                self.vx -= accel * dt
            if self.rl.is_key_down(KEY_RIGHT) or self.rl.is_key_down(KEY_D):
                self.vx += accel * dt
            if self.rl.is_key_down(KEY_UP) or self.rl.is_key_down(KEY_W):
                self.vy -= accel * dt
            if self.rl.is_key_down(KEY_DOWN) or self.rl.is_key_down(KEY_S):
                self.vy += accel * dt

            self.px += self.vx * dt
            self.py += self.vy * dt

            if self.px - self.radius < 24.0:
                self.px = 24.0 + self.radius
                self.vx = -self.vx
                self.rl.play_sound(self.sfx_bounce)
            elif self.px + self.radius > 776.0:
                self.px = 776.0 - self.radius
                self.vx = -self.vx
                self.rl.play_sound(self.sfx_bounce)

            if self.py - self.radius < 24.0:
                self.py = 24.0 + self.radius
                self.vy = -self.vy
                self.rl.play_sound(self.sfx_bounce)
            elif self.py + self.radius > 576.0:
                self.py = 576.0 - self.radius
                self.vy = -self.vy
                self.rl.play_sound(self.sfx_bounce)

        var bg_color     = Vec4f(0.06, 0.09, 0.14, 1.0)
        var puck_color   = Vec4f(0.20, 0.78, 0.96, 1.0)
        var border_color = Vec4f(0.25, 0.45, 0.70, 1.0)
        var text_color   = Vec4f(0.92, 0.96, 1.00, 1.0)

        self.rl.begin_drawing()
        self.rl.clear_background(bg_color)

        self.rl.draw_rectangle_lines(24.0, 24.0, 752.0, 552.0, border_color)
        self.rl.draw_texture(self.checker, 40.0, 40.0)
        self.rl.draw_circle(self.px, self.py, self.radius, puck_color)

        self.rl.draw_text("gammaraylib Standalone Demo", 120.0, 44.0, 22.0, text_color)
        self.rl.draw_text("WASD / Arrows: Steer   |   SPACE: Pause", 120.0, 76.0, 16.0, text_color)
        self.rl.draw_fps(345.0, 150.0)


        if self.rl.gui_button(Rectangle(40.0, 516.0, 180.0, 38.0), "Boost Puck"):
            self.vx *= 1.25
            self.vy *= 1.25
            self.rl.play_sound(self.sfx_boost)

        self.rl.end_drawing()

@export("init_game")
def init_game() abi("C") -> Pointer[DemoState, MutUntrackedOrigin]:
    var allocation = alloc(Layout[DemoState](count=1))
    var ptr = allocation^.unsafe_leak()
    try:
        ptr[] = DemoState()
    except e:
        print("Failed to init demo:", e)
    return ptr

@export("update_game")
def update_game(state: Pointer[DemoState, MutUntrackedOrigin]) abi("C"):
    try:
        state[].step()
    except e:
        print("Demo frame error:", e)

def main() raises:
    var state = DemoState()
    while not state.rl.window_should_close():
        state.step()
    state.rl.unload_texture(state.checker)
    state.rl.close()
