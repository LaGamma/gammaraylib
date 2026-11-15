from std.ffi import OwnedDLHandle
from raymath import Vec4f
from rlgl import RLGL
from rshapes import draw_rectangle, Rectangle, DARKGRAY, LIGHTGRAY, MAROON, RED, SKYBLUE
from rtext import Font, draw_text, measure_text

comptime UI_BG         = Vec4f(0.92, 0.92, 0.92, 0.92)
comptime UI_BORDER     = Vec4f(0.45, 0.45, 0.45, 1.00)
comptime UI_HOVER      = Vec4f(0.78, 0.88, 0.96, 1.00)
comptime UI_ACTIVE     = Vec4f(0.55, 0.78, 0.95, 1.00)
comptime UI_TEXT       = Vec4f(0.15, 0.15, 0.15, 1.00)
comptime UI_HEADER     = Vec4f(0.25, 0.25, 0.28, 1.00)
comptime UI_WHITE      = Vec4f(0.98, 0.98, 0.98, 1.00)

def _draw_bordered_box(mut rl: RLGL, gl: OwnedDLHandle, bounds: Rectangle, border_col: Vec4f, fill_col: Vec4f, border: Float32 = 2.0) raises:
    draw_rectangle(rl, gl, bounds.x, bounds.y, bounds.width, bounds.height, border_col)
    draw_rectangle(
        rl, gl,
        bounds.x + border,
        bounds.y + border,
        bounds.width - border * 2.0,
        bounds.height - border * 2.0,
        fill_col,
    )

def gui_panel(mut rl: RLGL, gl: OwnedDLHandle, font: Font, bounds: Rectangle, title: String) raises:
    _draw_bordered_box(rl, gl, bounds, UI_BORDER, UI_BG)
    var header_h: Float32 = 26.0
    draw_rectangle(rl, gl, bounds.x, bounds.y, bounds.width, header_h, UI_HEADER)
    draw_text(rl, gl, font, title, bounds.x + 8.0, bounds.y + 6.0, 14.0, UI_WHITE)

def gui_button(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    font: Font,
    bounds: Rectangle,
    text: String,
    mouse_x: Float32,
    mouse_y: Float32,
    mouse_down: Bool,
    mouse_pressed: Bool,
) raises -> Bool:
    var hovered = bounds.contains(mouse_x, mouse_y)
    var fill = UI_ACTIVE if (hovered and mouse_down) else (UI_HOVER if hovered else LIGHTGRAY)
    var border = SKYBLUE if hovered else UI_BORDER

    _draw_bordered_box(rl, gl, bounds, border, fill)

    var font_size: Float32 = 16.0
    #var text_w = Float32(text.byte_length()) * (font_size + 2.0)
    var text_w = measure_text(font, text, font_size)
    var tx = bounds.x + (bounds.width - text_w) * 0.5
    var ty = bounds.y + (bounds.height - font_size) * 0.5
    draw_text(rl, gl, font, text, tx, ty, font_size, UI_TEXT)

    return hovered and mouse_pressed

def gui_checkbox(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    font: Font,
    bounds: Rectangle,
    text: String,
    mut checked: Bool,
    mouse_x: Float32,
    mouse_y: Float32,
    mouse_pressed: Bool,
) raises -> Bool:
    var hovered = bounds.contains(mouse_x, mouse_y)
    if hovered and mouse_pressed:
        checked = not checked

    _draw_bordered_box(rl, gl, bounds, SKYBLUE if hovered else UI_BORDER, UI_WHITE)
    if checked:
        draw_rectangle(rl, gl, bounds.x + 4.0, bounds.y + 4.0, bounds.width - 8.0, bounds.height - 8.0, MAROON)

    draw_text(rl, gl, font, text, bounds.x + bounds.width + 8.0, bounds.y + (bounds.height - 16.0) * 0.5, 16.0, UI_TEXT)
    return hovered and mouse_pressed

def gui_slider(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    font: Font,
    bounds: Rectangle,
    label: String,
    mut value: Float32,
    min_val: Float32,
    max_val: Float32,
    mouse_x: Float32,
    mouse_y: Float32,
    mouse_down: Bool,
) raises:
    var hovered = bounds.contains(mouse_x, mouse_y)
    if hovered and mouse_down:
        var t = (mouse_x - bounds.x) / bounds.width
        if t < 0.0:
            t = 0.0
        elif t > 1.0:
            t = 1.0
        value = min_val + t * (max_val - min_val)

    _draw_bordered_box(rl, gl, bounds, SKYBLUE if hovered else UI_BORDER, UI_WHITE)

    var ratio = (value - min_val) / (max_val - min_val)
    var fill_w = (bounds.width - 4.0) * ratio
    draw_rectangle(rl, gl, bounds.x + 2.0, bounds.y + 2.0, fill_w, bounds.height - 4.0, SKYBLUE)
    draw_text(rl, gl, font, label, bounds.x, bounds.y - 18.0, 14.0, UI_TEXT)

