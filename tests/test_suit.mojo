from std.math import abs, sqrt
from std.memory.alloc import unsafe_alloc
from std.pathlib import Path
from std.os import remove

from raymath import Vector3, Vec2f, Vec4f, Quaternion, Matrix
from rcollisions import BoundingBox, Ray, check_collision_boxes, get_ray_collision_box
from rmaterials import Material, MATERIAL_MAP_DIFFUSE, load_material_default
from rtextures import Texture2D, load_image_bmp
from rmodels import load_model
from raudio import load_sound, gen_sound_click, gen_sound_laser, gen_sound_explosion, gen_sound_powerup
from rgui import Rectangle

def assert_true(cond: Bool, msg: String) raises:
    if not cond:
        raise Error("ASSERT FAILED: " + msg)

def assert_near(actual: Float32, expected: Float32, eps: Float32, msg: String) raises:
    if abs(actual - expected) > eps:
        raise Error("ASSERT NEAR FAILED (" + msg + "): got " + String(actual) + ", expected " + String(expected))

def test_raymath() raises:
    print("[1/7] Testing raymath (Vector3, Quaternion, Matrix)...")

    var a = Vector3(1.0, 2.0, 3.0)
    var b = Vector3(4.0, 5.0, 6.0)
    var c = a + b
    assert_near(c.data[0], 5.0, 1e-5, "Vector3 add x")
    assert_near(c.data[1], 7.0, 1e-5, "Vector3 add y")
    assert_near(c.data[2], 9.0, 1e-5, "Vector3 add z")

    assert_near(a.dot(b), 32.0, 1e-5, "Vector3 dot")

    var x_axis = Vector3(1.0, 0.0, 0.0)
    var y_axis = Vector3(0.0, 1.0, 0.0)
    var z_axis = x_axis.cross(y_axis)
    assert_near(z_axis.data[0], 0.0, 1e-5, "Cross x")
    assert_near(z_axis.data[1], 0.0, 1e-5, "Cross y")
    assert_near(z_axis.data[2], 1.0, 1e-5, "Cross z")

    var norm = Vector3(3.0, 0.0, 4.0).normalize()
    assert_near(sqrt(norm.dot(norm)), 1.0, 1e-5, "Normalize length")
    assert_near(norm.data[0], 0.6, 1e-5, "Normalize x")
    assert_near(norm.data[2], 0.8, 1e-5, "Normalize z")

    # Matrix translation & look_at
    var t_mat = Matrix.translate(10.0, -5.0, 2.0)
    var p = t_mat.transform_vec4(Vec4f(1.0, 2.0, 3.0, 1.0))
    assert_near(p[0], 11.0, 1e-5, "Matrix translate x")
    assert_near(p[1], -3.0, 1e-5, "Matrix translate y")
    assert_near(p[2], 5.0, 1e-5, "Matrix translate z")

    var view = Matrix.look_at(Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0))
    var origin_in_view = view.transform_vec4(Vec4f(0.0, 0.0, 0.0, 1.0))
    assert_near(origin_in_view[2], -5.0, 1e-4, "look_at origin z in camera space")

def test_rcollisions() raises:
    print("[2/7] Testing rcollisions (AABB & Ray Slab Picking)...")

    var box1 = BoundingBox.from_center_size(Vector3(0.0, 0.0, 0.0), 2.0, 2.0, 2.0)
    var box2 = BoundingBox.from_center_size(Vector3(1.5, 0.0, 0.0), 2.0, 2.0, 2.0)
    var box3 = BoundingBox.from_center_size(Vector3(5.0, 0.0, 0.0), 2.0, 2.0, 2.0)

    assert_true(check_collision_boxes(box1, box2), "Overlapping boxes should collide")
    assert_true(not check_collision_boxes(box1, box3), "Separated boxes should not collide")

    var hit_ray = Ray(Vector3(0.0, 0.0, 10.0), Vector3(0.0, 0.0, -1.0))
    var hit = get_ray_collision_box(hit_ray, box1)
    assert_true(hit.hit, "Ray aimed at box1 should hit")
    assert_near(hit.distance, 9.0, 1e-4, "Ray hit distance")
    assert_near(hit.point.data[2], 1.0, 1e-4, "Ray hit point z")
    assert_near(hit.normal.data[2], 1.0, 1e-4, "Ray hit normal z (+Z face)")

    var miss_ray = Ray(Vector3(0.0, 5.0, 10.0), Vector3(0.0, 0.0, -1.0))
    var miss = get_ray_collision_box(miss_ray, box1)
    assert_true(not miss.hit, "Ray above box1 should miss")

def test_rmaterials() raises:
    print("[3/7] Testing rmaterials (Material & MaterialMap)...")

    var mat = load_material_default()
    assert_near(mat.get_diffuse_color()[3], 1.0, 1e-5, "Default material alpha is 1.0")

    var dummy_tex = Texture2D(42, 64, 64)
    mat.set_texture(MATERIAL_MAP_DIFFUSE, dummy_tex)
    assert_true(mat.get_diffuse_texture().id == 42, "Material diffuse texture ID updated")

def test_rmodels() raises:
    print("[4/7] Testing rmodels (Wavefront .obj parser & fan triangulation)...")

    var tmp_obj = "/tmp/gammaraylib_test.obj"
    var obj_src = (
        "# Test Quad + Triangle\n"
        + "v 0.0 0.0 0.0\n"
        + "v 1.0 0.0 0.0\n"
        + "v 1.0 1.0 0.0\n"
        + "v 0.0 1.0 0.0\n"
        + "vt 0.0 0.0\n"
        + "vt 1.0 1.0\n"
        + "vn 0.0 0.0 1.0\n"
        + "f 1/1/1 2/2/1 3/2/1 4/1/1\n"
    )
    Path(tmp_obj).write_text(obj_src)

    var model = load_model(tmp_obj)
    assert_true(model.mesh.triangle_count == 2, "Quad face should triangulate into 2 triangles")
    assert_true(len(model.mesh.vertices) == 6, "2 triangles = 6 unpacked vertices")
    assert_near(model.mesh.vertices[2].data[0], 1.0, 1e-5, "Parsed vertex 3 x")
    assert_near(model.mesh.vertices[2].data[1], 1.0, 1e-5, "Parsed vertex 3 y")
    assert_near(model.mesh.normals[0].data[2], 1.0, 1e-5, "Parsed normal z")

    remove(tmp_obj)

def test_rtextures_bmp() raises:
    print("[5/7] Testing rtextures (Pure-Mojo 24-bit BMP decoder)...")

    # Write a minimal valid 2x1 24-bit uncompressed BMP file (62 bytes total)
    var tmp_bmp = "/tmp/gammaraylib_test.bmp"
    var bmp_bytes = List[UInt8]()
    # 14-byte BITMAPFILEHEADER: "BM", size=62, reserved=0, offset=54
    var hdr = Array[UInt8, 54](fill=0)
    hdr[0] = 0x42; hdr[1] = 0x4D # 'BM'
    hdr[2] = 62                  # file size
    hdr[10] = 54                 # pixel offset
    hdr[14] = 40                 # DIB header size
    hdr[18] = 2                  # width = 2
    hdr[22] = 1                  # height = 1
    hdr[26] = 1                  # planes = 1
    hdr[28] = 24                 # bpp = 24
    for i in range(54):
        bmp_bytes.append(hdr[i])

    # Row 0 (2 pixels BGR + 2 bytes padding = 8 bytes):
    # Pixel 0 = Red (B=0, G=0, R=255), Pixel 1 = Blue (B=255, G=0, R=0)
    bmp_bytes.append(0); bmp_bytes.append(0); bmp_bytes.append(255)
    bmp_bytes.append(255); bmp_bytes.append(0); bmp_bytes.append(0)
    bmp_bytes.append(0); bmp_bytes.append(0) # 4-byte row padding

    Path(tmp_bmp).write_bytes(bmp_bytes)

    var img = load_image_bmp(tmp_bmp)
    assert_true(img.width == 2 and img.height == 1, "BMP dimensions 2x1")
    # Packed RGBA8888 little-endian: Red = 0xFF0000FF, Blue = 0xFFFF0000
    assert_true(img.data[unsafe_offset=0] == UInt32(0xFF0000FF), "BMP pixel 0 is RGBA Red")
    assert_true(img.data[unsafe_offset=1] == UInt32(0xFFFF0000), "BMP pixel 1 is RGBA Blue")
    img.unload()
    remove(tmp_bmp)

def test_raudio() raises:
    print("[6/7] Testing raudio (Chiptune synthesizers & WAV parser)...")

    var s_click = gen_sound_click(880.0, 0.05)
    assert_true(s_click.sample_rate == 44100, "Click sample rate")
    assert_true(s_click.byte_length == Int(Float32(44100.0) * Float32(0.05)) * 2, "Click PCM byte length")
    s_click.unload()

    var s_laser = gen_sound_laser()
    var s_boom  = gen_sound_explosion()
    var s_pow   = gen_sound_powerup()
    assert_true(s_laser.byte_length > 0 and s_boom.byte_length > 0 and s_pow.byte_length > 0, "Chiptune buffers non-empty")
    s_laser.unload()
    s_boom.unload()
    s_pow.unload()

    # Write a minimal valid 44-byte + 4-byte PCM WAV file and parse it back
    var tmp_wav = "/tmp/gammaraylib_test.wav"
    var wav = List[UInt8]()
    var wh = Array[UInt8, 44](fill=0)
    # "RIFF" + size(40) + "WAVE"
    wh[0]=0x52; wh[1]=0x49; wh[2]=0x46; wh[3]=0x46
    wh[4]=40
    wh[8]=0x57; wh[9]=0x41; wh[10]=0x56; wh[11]=0x45
    # "fmt " + size(16) + PCM(1) + mono(1) + 44100Hz (0xAC44) + 16-bit
    wh[12]=0x66; wh[13]=0x6D; wh[14]=0x74; wh[15]=0x20
    wh[16]=16; wh[20]=1; wh[22]=1
    wh[24]=0x44; wh[25]=0xAC # 44100 LE
    wh[34]=16
    # "data" + size(4)
    wh[36]=0x64; wh[37]=0x61; wh[38]=0x74; wh[39]=0x61
    wh[40]=4
    for i in range(44):
        wav.append(wh[i])
    wav.append(0x10); wav.append(0x20); wav.append(0x30); wav.append(0x40)

    Path(tmp_wav).write_bytes(wav)
    var loaded_wav = load_sound(tmp_wav)
    assert_true(loaded_wav.sample_rate == 44100, "WAV parsed sample rate")
    assert_true(loaded_wav.byte_length == 4, "WAV parsed data size")
    assert_true(loaded_wav.data[unsafe_offset=2] == 0x30, "WAV parsed sample byte")
    loaded_wav.unload()
    remove(tmp_wav)

def test_rgui() raises:
    print("[7/7] Testing rgui (Rectangle hit-testing)...")

    var rect = Rectangle(100.0, 200.0, 150.0, 40.0)
    assert_true(rect.contains(150.0, 220.0), "Point inside rectangle")
    assert_true(not rect.contains(99.0, 220.0), "Point left of rectangle")
    assert_true(not rect.contains(150.0, 241.0), "Point below rectangle")

def main() raises:
    print("=== Running gammaraylib Unit Test Suite ===")
    test_raymath()
    test_rcollisions()
    test_rmaterials()
    test_rmodels()
    test_rtextures_bmp()
    test_raudio()
    test_rgui()
    print("=== ALL 7 TEST SUITES PASSED! ===")
