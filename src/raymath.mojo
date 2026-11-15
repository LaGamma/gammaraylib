from std.math import sin, cos, tan, sqrt

comptime Vec2f = SIMD[DType.float32, 2]
comptime Vec4f = SIMD[DType.float32, 4]

struct Vector3(TrivialRegisterPassable):
    var data: Vec4f

    def __init__(out self, x: Float32 = 0.0, y: Float32 = 0.0, z: Float32 = 0.0):
        self.data = Vec4f(x, y, z, 0.0)

    def __init__(out self, data: Vec4f):
        self.data = data

    def __add__(self, other: Self) -> Self:
        return Self(self.data + other.data)

    def __sub__(self, other: Self) -> Self:
        return Self(self.data - other.data)

    def __mul__(self, scalar: Float32) -> Self:
        return Self(self.data * scalar)

    def dot(self, other: Self) -> Float32:
        return (self.data * other.data).reduce_add()

    def cross(self, other: Self) -> Self:
        var a = self.data.shuffle[1, 2, 0, 3]() * other.data.shuffle[2, 0, 1, 3]()
        var b = self.data.shuffle[2, 0, 1, 3]() * other.data.shuffle[1, 2, 0, 3]()
        return Self(a - b)

    def normalize(self) -> Self:
        var len_sq = self.dot(self)
        if len_sq == 0.0:
            return Self()
        return self * (1.0 / sqrt(len_sq))

struct Matrix(TrivialRegisterPassable):
    var c0: Vec4f
    var c1: Vec4f
    var c2: Vec4f
    var c3: Vec4f

    def __init__(out self, c0: Vec4f, c1: Vec4f, c2: Vec4f, c3: Vec4f):
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3

    @staticmethod
    def identity() -> Self:
        return Self(
            Vec4f(1.0, 0.0, 0.0, 0.0),
            Vec4f(0.0, 1.0, 0.0, 0.0),
            Vec4f(0.0, 0.0, 1.0, 0.0),
            Vec4f(0.0, 0.0, 0.0, 1.0),
        )

    def transform_vec4(self, v: Vec4f) -> Vec4f:
        return (self.c0 * v[0]) + (self.c1 * v[1]) + (self.c2 * v[2]) + (self.c3 * v[3])

    def __mul__(self, rhs: Self) -> Self:
        return Self(
            self.transform_vec4(rhs.c0),
            self.transform_vec4(rhs.c1),
            self.transform_vec4(rhs.c2),
            self.transform_vec4(rhs.c3),
        )

    @staticmethod
    def translate(x: Float32, y: Float32, z: Float32) -> Self:
        var m = Self.identity()
        m.c3 = Vec4f(x, y, z, 1.0)
        return m

    @staticmethod
    def rotate_z(angle_rad: Float32) -> Self:
        var c = cos(angle_rad)
        var s = sin(angle_rad)
        return Self(
            Vec4f(c, s, 0.0, 0.0),
            Vec4f(-s, c, 0.0, 0.0),
            Vec4f(0.0, 0.0, 1.0, 0.0),
            Vec4f(0.0, 0.0, 0.0, 1.0),
        )

    @staticmethod
    def ortho(left: Float32, right: Float32, bottom: Float32, top: Float32, near: Float32, far: Float32) -> Self:
        var rl = right - left
        var tb = top - bottom
        var fn_val = far - near
        return Self(
            Vec4f(2.0 / rl, 0.0, 0.0, 0.0),
            Vec4f(0.0, 2.0 / tb, 0.0, 0.0),
            Vec4f(0.0, 0.0, -2.0 / fn_val, 0.0),
            Vec4f(-(right + left) / rl, -(top + bottom) / tb, -(far + near) / fn_val, 1.0),
        )

    @staticmethod
    def perspective(fov_y_rad: Float32, aspect: Float32, near: Float32, far: Float32) -> Self:
        var f = 1.0 / tan(fov_y_rad * 0.5)
        var nf = 1.0 / (near - far)
        return Self(
            Vec4f(f / aspect, 0.0, 0.0, 0.0),
            Vec4f(0.0, f, 0.0, 0.0),
            Vec4f(0.0, 0.0, (far + near) * nf, -1.0),
            Vec4f(0.0, 0.0, (2.0 * far * near) * nf, 0.0),
        )

    @staticmethod
    def look_at(eye: Vector3, target: Vector3, up: Vector3) -> Self:
        var f = (target - eye).normalize()
        var s = f.cross(up).normalize()
        var u = s.cross(f)

        return Self(
            Vec4f(s.data[0], u.data[0], -f.data[0], 0.0),
            Vec4f(s.data[1], u.data[1], -f.data[1], 0.0),
            Vec4f(s.data[2], u.data[2], -f.data[2], 0.0),
            Vec4f(-s.dot(eye), -u.dot(eye), f.dot(eye), 1.0),
        )

    @staticmethod
    def rotate_y(angle_rad: Float32) -> Self:
        var c = cos(angle_rad)
        var s = sin(angle_rad)
        return Self(
            Vec4f(c, 0.0, -s, 0.0),
            Vec4f(0.0, 1.0, 0.0, 0.0),
            Vec4f(s, 0.0, c, 0.0),
            Vec4f(0.0, 0.0, 0.0, 1.0),
        )


struct Quaternion(TrivialRegisterPassable):
    var data: Vec4f

    def __init__(out self, x: Float32 = 0.0, y: Float32 = 0.0, z: Float32 = 0.0, w: Float32 = 1.0):
        self.data = Vec4f(x, y, z, w)

    @staticmethod
    def from_axis_angle(axis: Vector3, angle_rad: Float32) -> Self:
        var half = angle_rad * 0.5
        var s = sin(half)
        var n = axis.normalize()
        return Self(n.data[0] * s, n.data[1] * s, n.data[2] * s, cos(half))

    def to_matrix(self) -> Matrix:
        var x = self.data[0]
        var y = self.data[1]
        var z = self.data[2]
        var w = self.data[3]
        var xx = x * x; var yy = y * y; var zz = z * z
        var xy = x * y; var xz = x * z; var yz = y * z
        var wx = w * x; var wy = w * y; var wz = w * z

        return Matrix(
            Vec4f(1.0 - 2.0 * (yy + zz), 2.0 * (xy + wz), 2.0 * (xz - wy), 0.0),
            Vec4f(2.0 * (xy - wz), 1.0 - 2.0 * (xx + zz), 2.0 * (yz + wx), 0.0),
            Vec4f(2.0 * (xz + wy), 2.0 * (yz - wx), 1.0 - 2.0 * (xx + yy), 0.0),
            Vec4f(0.0, 0.0, 0.0, 1.0),
        )

