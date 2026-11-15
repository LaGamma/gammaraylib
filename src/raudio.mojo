from std.ffi import OwnedDLHandle, c_int, c_uint, c_char, external_call
from std.origin import MutUntrackedOrigin, ImmutAnyOrigin
from std.memory import Pointer
from std.memory.alloc import unsafe_alloc
from std.math import sin, exp
from std.pathlib import Path
from std.memory import bitcast
from std.sys.defines import is_defined

comptime VoidPtr    = Pointer[NoneType, MutUntrackedOrigin]
comptime OptVoidPtr = Optional[VoidPtr]
comptime CharPtr    = Pointer[UInt8, MutUntrackedOrigin]
comptime CStrPtr    = Pointer[c_char, ImmutAnyOrigin]
comptime IntPtr     = Pointer[c_int, MutUntrackedOrigin]
comptime PthreadPtr = Pointer[UInt64, MutUntrackedOrigin]

comptime PA_STREAM_PLAYBACK: c_int = 1
comptime PA_SAMPLE_U8: c_int       = 0
comptime PA_SAMPLE_S16LE: c_int    = 3

@fieldwise_init
struct SoundState(TrivialRegisterPassable):
    var volume: Float32
    var playing: Int32  # 0 = stopped, 1 = playing

struct SoundJob(TrivialRegisterPassable):
    var data: Pointer[UInt8, MutUntrackedOrigin]
    var byte_length: Int
    var sample_rate: Int
    var channels: Int
    var bits_per_sample: Int
    var state: Pointer[SoundState, MutUntrackedOrigin]

    def __init__(
        out self,
        data: Pointer[UInt8, MutUntrackedOrigin],
        byte_length: Int,
        sample_rate: Int,
        channels: Int,
        bits_per_sample: Int,
        state: Pointer[SoundState, MutUntrackedOrigin],
    ):
        self.data = data
        self.byte_length = byte_length
        self.sample_rate = sample_rate
        self.channels = channels
        self.bits_per_sample = bits_per_sample
        self.state = state

def _audio_worker(arg: VoidPtr) -> VoidPtr:
    var job_ptr = Pointer[SoundJob, MutUntrackedOrigin](unsafe_from_address=Int(arg))
    var job = job_ptr[]
    job_ptr.unsafe_free()

    try:
        var pa = OwnedDLHandle("libpulse-simple.so.0")
        var pa_simple_new   = pa.get_function[OptVoidPtr]("pa_simple_new")
        var pa_simple_write = pa.get_function[c_int]("pa_simple_write")
        var pa_simple_drain = pa.get_function[c_int]("pa_simple_drain")
        var pa_simple_free  = pa.get_function("pa_simple_free")

        var spec = unsafe_alloc[UInt32](3)
        var fmt = PA_SAMPLE_S16LE
        if job.bits_per_sample == 8:
            fmt = PA_SAMPLE_U8
        elif job.bits_per_sample == 24:
            fmt = 9  # PA_SAMPLE_S24LE
        spec[unsafe_offset=0] = UInt32(fmt)
        spec[unsafe_offset=1] = UInt32(job.sample_rate)
        spec[unsafe_offset=2] = UInt32(job.channels)

        var app_cstr = unsafe_alloc[UInt8](4)
        app_cstr[unsafe_offset=0] = 103 # 'g'
        app_cstr[unsafe_offset=1] = 114 # 'r'
        app_cstr[unsafe_offset=2] = 108 # 'l'
        app_cstr[unsafe_offset=3] = 0

        var stream_cstr = unsafe_alloc[UInt8](4)
        stream_cstr[unsafe_offset=0] = 115 # 's'
        stream_cstr[unsafe_offset=1] = 102 # 'f'
        stream_cstr[unsafe_offset=2] = 120 # 'x'
        stream_cstr[unsafe_offset=3] = 0

        var err = c_int(0)
        var null_ptr: OptVoidPtr = None

        var s = pa_simple_new(
            null_ptr,
            app_cstr,
            PA_STREAM_PLAYBACK,
            null_ptr,
            stream_cstr,
            VoidPtr(unsafe_from_address=Int(spec)),
            null_ptr,
            null_ptr,
            IntPtr(unsafe_from_address=Int(Pointer(to=err))),
        )
        spec.unsafe_free()
        app_cstr.unsafe_free()
        stream_cstr.unsafe_free()

        if s:
            # 16380 is divisible by 6 (aligns both 2-byte 16-bit and 3-byte 24-bit stereo frames)
            var chunk_size = 16380
            var scratch = unsafe_alloc[UInt8](chunk_size)
            var offset = 0

            while offset < job.byte_length:
                if job.state[unsafe_offset=0].playing == 0:
                    break

                var vol = job.state[unsafe_offset=0].volume
                var n = job.byte_length - offset
                if n > chunk_size:
                    n = chunk_size

                if job.bits_per_sample == 16:
                    var count = n // 2
                    for i in range(count):
                        var lo = Int32(job.data[unsafe_offset=offset + i * 2 + 0])
                        var hi = Int32(job.data[unsafe_offset=offset + i * 2 + 1])
                        var raw = (hi << 8) | lo
                        if raw >= 32768:
                            raw -= 65536
                        var scaled = Int32(Float32(raw) * vol)
                        scratch[unsafe_offset=i * 2 + 0] = UInt8(scaled & 0xFF)
                        scratch[unsafe_offset=i * 2 + 1] = UInt8((scaled >> 8) & 0xFF)
                elif job.bits_per_sample == 24:
                    var count = n // 3
                    for i in range(count):
                        var b0 = Int32(job.data[unsafe_offset=offset + i * 3 + 0])
                        var b1 = Int32(job.data[unsafe_offset=offset + i * 3 + 1])
                        var b2 = Int32(job.data[unsafe_offset=offset + i * 3 + 2])
                        var raw = (b2 << 16) | (b1 << 8) | b0
                        if raw >= 8388608:
                            raw -= 16777216
                        var scaled = Int32(Float32(raw) * vol)
                        scratch[unsafe_offset=i * 3 + 0] = UInt8(scaled & 0xFF)
                        scratch[unsafe_offset=i * 3 + 1] = UInt8((scaled >> 8) & 0xFF)
                        scratch[unsafe_offset=i * 3 + 2] = UInt8((scaled >> 16) & 0xFF)
                else:
                    for i in range(n):
                        var centered = Float32(Int(job.data[unsafe_offset=offset + i]) - 128) * vol
                        scratch[unsafe_offset=i] = UInt8(Int(centered) + 128)

                _ = pa_simple_write(
                    s,
                    VoidPtr(unsafe_from_address=Int(scratch)),
                    Int(n),
                    IntPtr(unsafe_from_address=Int(Pointer(to=err))),
                )
                offset += n

            scratch.unsafe_free()
            if job.state[unsafe_offset=0].playing != 0:
                _ = pa_simple_drain(s, IntPtr(unsafe_from_address=Int(Pointer(to=err))))
            pa_simple_free(s)

        job.state[unsafe_offset=0].playing = 0
        _ = pa^
    except:
        job.state[unsafe_offset=0].playing = 0

    return arg

struct Sound(Copyable, Movable):
    var data: Pointer[UInt8, MutUntrackedOrigin]
    var byte_length: Int
    var sample_rate: Int
    var channels: Int
    var bits_per_sample: Int
    var state: Pointer[SoundState, MutUntrackedOrigin]

    def __init__(
        out self,
        data: Pointer[UInt8, MutUntrackedOrigin],
        byte_length: Int,
        sample_rate: Int,
        channels: Int,
        bits_per_sample: Int,
    ):
        self.data = data
        self.byte_length = byte_length
        self.sample_rate = sample_rate
        self.channels = channels
        self.bits_per_sample = bits_per_sample
        self.state = unsafe_alloc[SoundState](1)
        self.state[unsafe_offset=0] = SoundState(1.0, 0)

    def set_volume(self, volume: Float32):
        var clamped = volume
        if clamped < 0.0:
            clamped = 0.0
        elif clamped > 1.0:
            clamped = 1.0
        self.state[unsafe_offset=0].volume = clamped

    def is_playing(self) -> Bool:
        return self.state[unsafe_offset=0].playing != 0

    def stop(self):
        self.state[unsafe_offset=0].playing = 0

    def unload(mut self):
        self.stop()
        self.data.unsafe_free()
        self.state.unsafe_free()

def set_sound_volume(sound: Sound, volume: Float32):
    sound.set_volume(volume)
def is_sound_playing(sound: Sound) -> Bool:
    return sound.is_playing()
def stop_sound(sound: Sound):
    sound.stop()

def _read_u16_le(bytes: Span[UInt8, _], offset: Int) -> Int:
    return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)

def _read_u32_le(bytes: Span[UInt8, _], offset: Int) -> Int:
    return (
        Int(bytes[offset])
        | (Int(bytes[offset + 1]) << 8)
        | (Int(bytes[offset + 2]) << 16)
        | (Int(bytes[offset + 3]) << 24)
    )

def load_sound(path: String) raises -> Sound:
    var raw = Path(path).read_bytes()
    var bytes = Span(raw)

    if len(bytes) < 44 or bytes[0] != 0x52 or bytes[1] != 0x49 or bytes[2] != 0x46 or bytes[3] != 0x46:
        raise Error("Invalid WAV RIFF header: " + path)
    if bytes[8] != 0x57 or bytes[9] != 0x41 or bytes[10] != 0x56 or bytes[11] != 0x45:
        raise Error("Invalid WAVE format marker: " + path)

    var channels = 1
    var sample_rate = 44100
    var bits_per_sample = 16
    var data_offset = -1
    var data_size = 0

    var pos = 12
    while pos + 8 <= len(bytes):
        var c0 = bytes[pos + 0]
        var c1 = bytes[pos + 1]
        var c2 = bytes[pos + 2]
        var c3 = bytes[pos + 3]
        var chunk_size = _read_u32_le(bytes, pos + 4)

        if c0 == 0x66 and c1 == 0x6D and c2 == 0x74 and c3 == 0x20:
            var audio_format = _read_u16_le(bytes, pos + 8)
            if audio_format != 1:
                raise Error("Only uncompressed PCM WAV is supported: " + path)
            channels = _read_u16_le(bytes, pos + 10)
            sample_rate = _read_u32_le(bytes, pos + 12)
            bits_per_sample = _read_u16_le(bytes, pos + 22)
        elif c0 == 0x64 and c1 == 0x61 and c2 == 0x74 and c3 == 0x61:
            data_offset = pos + 8
            data_size = chunk_size
            break

        pos += 8 + chunk_size
        if chunk_size % 2 == 1:
            pos += 1

    if data_offset < 0 or data_offset + data_size > len(bytes):
        raise Error("Missing or truncated WAV data chunk: " + path)

    var pcm_buf = unsafe_alloc[UInt8](data_size)
    for i in range(data_size):
        pcm_buf[unsafe_offset=i] = bytes[data_offset + i]

    _ = raw^
    return Sound(pcm_buf, data_size, sample_rate, channels, bits_per_sample)

def gen_sound_click(freq: Float32 = 880.0, duration_sec: Float32 = 0.04) -> Sound:
    var sample_rate = 44100
    var num_samples = Int(Float32(sample_rate) * duration_sec)
    var byte_length = num_samples * 2
    var pcm_buf = unsafe_alloc[UInt8](byte_length)

    for i in range(num_samples):
        var t = Float32(i) / Float32(sample_rate)
        var env = exp(-t * 140.0)
        var wave_val = sin(2.0 * 3.14159265 * freq * t) * env
        var sample_i16 = Int16(wave_val * 28000.0)
        var u16 = UInt16(sample_i16)
        pcm_buf[unsafe_offset=i * 2 + 0] = UInt8(u16 & 0xFF)
        pcm_buf[unsafe_offset=i * 2 + 1] = UInt8((u16 >> 8) & 0xFF)

    return Sound(pcm_buf, byte_length, sample_rate, 1, 16)

def _write_sample_i16(buf: Pointer[UInt8, MutUntrackedOrigin], sample_idx: Int, val: Float32):
    var clamped = val
    if clamped > 1.0:
        clamped = 1.0
    elif clamped < -1.0:
        clamped = -1.0
    var sample_i16 = Int16(clamped * 28000.0)
    var u16 = UInt16(sample_i16)
    buf[unsafe_offset=sample_idx * 2 + 0] = UInt8(u16 & 0xFF)
    buf[unsafe_offset=sample_idx * 2 + 1] = UInt8((u16 >> 8) & 0xFF)

def gen_sound_laser(
    start_freq: Float32 = 960.0,
    end_freq: Float32 = 180.0,
    duration_sec: Float32 = 0.14,
) -> Sound:
    var sample_rate = 44100
    var num_samples = Int(Float32(sample_rate) * duration_sec)
    var byte_length = num_samples * 2
    var pcm_buf = unsafe_alloc[UInt8](byte_length)

    var phase: Float32 = 0.0
    var dt = 1.0 / Float32(sample_rate)

    for i in range(num_samples):
        var progress = Float32(i) / Float32(num_samples)
        # Rapid downward pitch sweep
        var freq = start_freq + (end_freq - start_freq) * progress
        phase += freq * dt
        if phase >= 1.0:
            phase -= 1.0

        # Retro 50% duty cycle square wave with fast decay envelope
        var square: Float32 = 0.65 if phase < 0.5 else -0.65
        var env = exp(-progress * 4.5)
        _write_sample_i16(pcm_buf, i, square * env)

    return Sound(pcm_buf, byte_length, sample_rate, 1, 16)

def gen_sound_explosion(duration_sec: Float32 = 0.35) -> Sound:
    var sample_rate = 44100
    var num_samples = Int(Float32(sample_rate) * duration_sec)
    var byte_length = num_samples * 2
    var pcm_buf = unsafe_alloc[UInt8](byte_length)

    # 16-bit LFSR pseudo-random noise generator (classic NES/GameBoy noise channel)
    var lfsr = UInt32(0xACE1)
    var held_noise: Float32 = 0.0

    for i in range(num_samples):
        var progress = Float32(i) / Float32(num_samples)
        # Step down sample-and-hold rate over time for low-end rumble
        var hold_step = 4 + Int(progress * 24.0)
        if i % hold_step == 0:
            var bit = ((lfsr >> 0) ^ (lfsr >> 2) ^ (lfsr >> 3) ^ (lfsr >> 5)) & 1
            lfsr = (lfsr >> 1) | (bit << 15)
            held_noise = 0.85 if (lfsr & 1) == 1 else -0.85

        var env = exp(-progress * 5.5)
        _write_sample_i16(pcm_buf, i, held_noise * env)

    return Sound(pcm_buf, byte_length, sample_rate, 1, 16)

def gen_sound_powerup(duration_sec: Float32 = 0.24) -> Sound:
    var sample_rate = 44100
    var num_samples = Int(Float32(sample_rate) * duration_sec)
    var byte_length = num_samples * 2
    var pcm_buf = unsafe_alloc[UInt8](byte_length)

    var phase: Float32 = 0.0
    var dt = 1.0 / Float32(sample_rate)

    for i in range(num_samples):
        var progress = Float32(i) / Float32(num_samples)
        # 4-step ascending arpeggio (C5 -> E5 -> G5 -> C6)
        var freq: Float32 = 523.25
        if progress >= 0.75:
            freq = 1046.50
        elif progress >= 0.50:
            freq = 783.99
        elif progress >= 0.25:
            freq = 659.25

        phase += freq * dt
        if phase >= 1.0:
            phase -= 1.0

        # 25% pulse wave for crisp chiptune chime
        var pulse: Float32 = 0.6 if phase < 0.25 else -0.6
        var env = 1.0 - (progress * 0.4)
        _write_sample_i16(pcm_buf, i, pulse * env)

    return Sound(pcm_buf, byte_length, sample_rate, 1, 16)


struct AudioDevice:
    var libc: OwnedDLHandle

    def __init__(out self) raises:
        self.libc = OwnedDLHandle("libc.so.6")

    def play_sound(self, sound: Sound) raises:
        if sound.byte_length <= 0:
            return

        sound.state[unsafe_offset=0].playing = 1

        comptime if is_defined["WASM"]():
            external_call["wasm_play_sound", NoneType](
                sound.data,
                sound.byte_length,
                sound.sample_rate,
                sound.channels,
                sound.bits_per_sample,
                sound.state,
            )
        else:
            var pthread_create = self.libc.get_function[c_int]("pthread_create")
            var pthread_detach = self.libc.get_function[c_int]("pthread_detach")

            var job_ptr = unsafe_alloc[SoundJob](1)
            job_ptr[unsafe_offset=0] = SoundJob(
                sound.data,
                sound.byte_length,
                sound.sample_rate,
                sound.channels,
                sound.bits_per_sample,
                sound.state,
            )

            var thread_id = UInt64(0)
            var res = pthread_create(
                PthreadPtr(unsafe_from_address=Int(Pointer(to=thread_id))),
                Optional[VoidPtr](None),
                _audio_worker,
                VoidPtr(unsafe_from_address=Int(job_ptr)),
            )
            if res == 0:
                _ = pthread_detach(thread_id)
            else:
                sound.state[unsafe_offset=0].playing = 0
                job_ptr.unsafe_free()
