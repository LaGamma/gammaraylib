from raymath import Vector3, Vec4f

struct BoundingBox(TrivialRegisterPassable):
    var min: Vector3
    var max: Vector3

    def __init__(out self, min: Vector3, max: Vector3):
        self.min = min
        self.max = max

    @staticmethod
    def from_center_size(center: Vector3, w: Float32, h: Float32, length: Float32) -> Self:
        var half = Vector3(w * 0.5, h * 0.5, length * 0.5)
        return Self(center - half, center + half)

struct Ray(TrivialRegisterPassable):
    var position: Vector3
    var direction: Vector3

    def __init__(out self, position: Vector3, direction: Vector3):
        self.position = position
        self.direction = direction.normalize()

struct RayCollision(TrivialRegisterPassable):
    var hit: Bool
    var distance: Float32
    var point: Vector3
    var normal: Vector3

    def __init__(
        out self,
        hit: Bool = False,
        distance: Float32 = 0.0,
        point: Vector3 = Vector3(),
        normal: Vector3 = Vector3(),
    ):
        self.hit = hit
        self.distance = distance
        self.point = point
        self.normal = normal

def check_collision_boxes(box1: BoundingBox, box2: BoundingBox) -> Bool:
    # SIMD lane comparison across X, Y, Z simultaneously (lane 3 is 0.0 <= 0.0 -> True)
    var overlap_a = box1.min.data.le(box2.max.data)
    var overlap_b = box1.max.data.ge(box2.min.data)
    return overlap_a.reduce_and() and overlap_b.reduce_and()

def get_ray_collision_box(ray: Ray, box: BoundingBox) -> RayCollision:
    # Slab method for Ray vs AABB intersection
    var t_min: Float32 = -1e30
    var t_max: Float32 =  1e30
    var hit_axis: Int = -1
    var hit_sign: Float32 = 1.0

    for i in range(3):
        var origin = ray.position.data[i]
        var dir    = ray.direction.data[i]
        var b_min  = box.min.data[i]
        var b_max  = box.max.data[i]

        if dir == 0.0:
            if origin < b_min or origin > b_max:
                return RayCollision(hit=False)
        else:
            var inv_d = 1.0 / dir
            var t1 = (b_min - origin) * inv_d
            var t2 = (b_max - origin) * inv_d
            var sign: Float32 = -1.0

            if t1 > t2:
                var tmp = t1
                t1 = t2
                t2 = tmp
                sign = 1.0

            if t1 > t_min:
                t_min = t1
                hit_axis = i
                hit_sign = sign
            if t2 < t_max:
                t_max = t2

            if t_min > t_max:
                return RayCollision(hit=False)

    if t_max < 0.0:
        return RayCollision(hit=False)

    var dist = t_min if t_min >= 0.0 else t_max
    var point = ray.position + (ray.direction * dist)
    var normal = Vector3(
        hit_sign if hit_axis == 0 else 0.0,
        hit_sign if hit_axis == 1 else 0.0,
        hit_sign if hit_axis == 2 else 0.0,
    )
    return RayCollision(hit=True, distance=dist, point=point, normal=normal)

