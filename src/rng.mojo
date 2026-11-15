from std.random.philox import Random

struct GameRng(Copyable, Movable):
    var rng: Random[]
    var cache: SIMD[DType.float32, 4]
    var lane: Int

    def __init__(out self, seed_val: UInt64 = 12345):
        self.rng = Random[](seed=seed_val, subsequence=0)
        self.cache = self.rng.step_uniform()
        self.lane = 0

    def next_float(mut self) -> Float32:
        if self.lane >= 4:
            self.cache = self.rng.step_uniform()
            self.lane = 0
        var val = self.cache[self.lane]
        self.lane += 1
        return val

    def next_int(mut self, min_val: Int, max_val: Int) -> Int:
        if max_val <= min_val:
            return min_val
        var u = self.next_float()
        var span = Float32(max_val - min_val + 1)
        var offset = Int(u * span)
        if offset >= (max_val - min_val + 1):
            offset = max_val - min_val
        return min_val + offset

