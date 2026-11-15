from std.ffi import OwnedDLHandle
from std.collections import List, Array
from std.pathlib import Path

from raymath import Vector3, Vec2f, Vec4f, Matrix
from rlgl import RLGL
from rmaterials import Material, load_material_default

struct Mesh(Copyable, Movable):
    var vertices: List[Vector3]
    var texcoords: List[Vec2f]
    var normals: List[Vector3]
    var triangle_count: Int

    def __init__(out self):
        self.vertices = List[Vector3]()
        self.texcoords = List[Vec2f]()
        self.normals = List[Vector3]()
        self.triangle_count = 0

struct Model(Copyable, Movable):
    var mesh: Mesh
    var material: Material
    var transform: Matrix

    def __init__(out self, var mesh: Mesh):
        self.mesh = mesh^
        self.material = load_material_default()
        self.transform = Matrix.identity()

def _parse_obj_index(token: String, count: Int) raises -> Int:
    if token.byte_length() == 0:
        return -1
    var idx = Int(token)
    # OBJ indices are 1-based (or negative relative to current list length)
    return (count + idx) if idx < 0 else (idx - 1)

def load_model(path: String) raises -> Model:
    var content = Path(path).read_text()
    var raw_pos  = List[Vector3]()
    var raw_uv   = List[Vec2f]()
    var raw_norm = List[Vector3]()

    var mesh = Mesh()
    var lines = content.split("\n")

    for i in range(len(lines)):
        var line = lines[i].strip()
        if line.byte_length() == 0 or line.startswith("#"):
            continue

        var parts = line.split(" ")
        var tokens = List[String]()
        for j in range(len(parts)):
            if parts[j].byte_length() > 0:
                tokens.append(String(parts[j]))
        if len(tokens) < 2:
            continue

        var tag = tokens[0]
        if tag == "v" and len(tokens) >= 4:
            raw_pos.append(Vector3(
                Float32(atof(tokens[1])),
                Float32(atof(tokens[2])),
                Float32(atof(tokens[3])),
            ))
        elif tag == "vt" and len(tokens) >= 3:
            raw_uv.append(Vec2f(
                Float32(atof(tokens[1])),
                1.0 - Float32(atof(tokens[2])),
            ))
        elif tag == "vn" and len(tokens) >= 4:
            raw_norm.append(Vector3(
                Float32(atof(tokens[1])),
                Float32(atof(tokens[2])),
                Float32(atof(tokens[3])),
            ).normalize())
        elif tag == "f" and len(tokens) >= 4:
            var face_count = len(tokens) - 1
            for k in range(1, face_count - 1):
                var tri_tokens = List[String]()
                tri_tokens.append(tokens[1])
                tri_tokens.append(tokens[k + 1])
                tri_tokens.append(tokens[k + 2])
                for corner in range(3):
                    var sub = tri_tokens[corner].split("/")
                    var v_idx  = _parse_obj_index(String(sub[0]), len(raw_pos))
                    var vt_idx = _parse_obj_index(String(sub[1]), len(raw_uv)) if len(sub) > 1 else -1
                    var vn_idx = _parse_obj_index(String(sub[2]), len(raw_norm)) if len(sub) > 2 else -1

                    mesh.vertices.append(raw_pos[v_idx] if v_idx >= 0 and v_idx < len(raw_pos) else Vector3())
                    mesh.texcoords.append(raw_uv[vt_idx] if vt_idx >= 0 and vt_idx < len(raw_uv) else Vec2f(0.0, 0.0))
                    mesh.normals.append(raw_norm[vn_idx] if vn_idx >= 0 and vn_idx < len(raw_norm) else Vector3(0.0, 1.0, 0.0))
                mesh.triangle_count += 1

    return Model(mesh^)

def draw_model(
    mut rl: RLGL,
    gl: OwnedDLHandle,
    model: Model,
    position: Vector3,
    scale: Float32 = 1.0,
    tint: Vec4f = Vec4f(1.0, 1.0, 1.0, 1.0),
) raises:
    var tex = model.material.get_diffuse_texture()
    var mat_col = model.material.get_diffuse_color()
    var final_col = mat_col * tint

    rl.set_texture(gl, tex.id)
    rl.set_lighting(gl, True)
    rl.current_color = final_col

    rl.push_matrix()
    rl.translatef(position.data[0], position.data[1], position.data[2])

    var total_verts = model.mesh.triangle_count * 3
    for i in range(total_verts):
        if rl.vertex_count >= 8190:
            rl.flush(gl)

        var v  = model.mesh.vertices[i]
        var uv = model.mesh.texcoords[i]
        var n  = model.mesh.normals[i]

        rl.normal3f(n.data[0], n.data[1], n.data[2])
        rl.texcoord2f(uv[0], uv[1])
        rl.vertex3f(v.data[0] * scale, v.data[1] * scale, v.data[2] * scale)

    rl.pop_matrix()
    rl.set_lighting(gl, False)
    rl.set_texture(gl, 0)
