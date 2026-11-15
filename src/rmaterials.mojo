from std.collections import Array
from raymath import Vec4f
from rtextures import Texture2D, WHITE

comptime MATERIAL_MAP_DIFFUSE: Int  = 0
comptime MATERIAL_MAP_SPECULAR: Int = 1
comptime MATERIAL_MAP_NORMAL: Int   = 2
comptime MAX_MATERIAL_MAPS: Int     = 4

struct MaterialMap(TrivialRegisterPassable):
    var texture: Texture2D
    var color: Vec4f
    var value: Float32

    def __init__(
        out self,
        texture: Texture2D = Texture2D(0, 1, 1),
        color: Vec4f = WHITE,
        value: Float32 = 0.0,
    ):
        self.texture = texture
        self.color = color
        self.value = value

struct Material(Copyable, Movable):
    var maps: Array[MaterialMap, MAX_MATERIAL_MAPS]

    def __init__(out self):
        self.maps = Array[MaterialMap, MAX_MATERIAL_MAPS](fill=MaterialMap())

    def set_texture(mut self, map_type: Int, texture: Texture2D):
        if map_type >= 0 and map_type < MAX_MATERIAL_MAPS:
            self.maps[map_type].texture = texture

    def set_color(mut self, map_type: Int, color: Vec4f):
        if map_type >= 0 and map_type < MAX_MATERIAL_MAPS:
            self.maps[map_type].color = color

    def get_diffuse_texture(self) -> Texture2D:
        return self.maps[MATERIAL_MAP_DIFFUSE].texture

    def get_diffuse_color(self) -> Vec4f:
        return self.maps[MATERIAL_MAP_DIFFUSE].color

def load_material_default() -> Material:
    return Material()

