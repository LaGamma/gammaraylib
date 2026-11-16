// C runtime allocator, dlopen/dlsym wrappers, Web Audio PulseAudio shim, and main loop
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <emscripten.h>

// --- Zero-Overhead Virtual & Right-Modifier Key Buffer ---
extern int glfwGetKey(void* window, int key);

static uint8_t wasm_virtual_keys[512] = {0};

EM_JS(void, wasm_init_virtual_keys, (uintptr_t ptr), {
    window._wasmKeyBufPtr = Number(ptr);
    if (window._virtualKeys && typeof HEAPU8 !== 'undefined') {
        for (const [k, v] of Object.entries(window._virtualKeys)) {
            const idx = Number(k);
            if (idx >= 0 && idx < 512) HEAPU8[window._wasmKeyBufPtr + idx] = v ? 1 : 0;
        }
    }
});

static int mojo_glfwGetKey(void* win, int key) {
    static int inited = 0;
    if (!inited) {
        wasm_init_virtual_keys((uintptr_t)wasm_virtual_keys);
        inited = 1;
    }
    if (key >= 0 && key < 512 && wasm_virtual_keys[key]) {
        return 1;
    }
    return glfwGetKey(win, key);
}

// --- Web Audio API Bridge (Replaces libpulse-simple.so.0) ---
EM_JS(void, webaudio_play_pcm, (uintptr_t data_ptr, size_t byte_len, int sample_rate, int channels, int format), {
    if (!window._mojoAudioCtx) {
        const AudioCtx = window.AudioContext || window.webkitAudioContext;
        if (!AudioCtx) return;
        window._mojoAudioCtx = new AudioCtx();
    }
    const ctx = window._mojoAudioCtx;
    if (ctx.state === 'suspended') ctx.resume();

    if (channels <= 0 || sample_rate <= 0) return;
    const bytesPerSample = (format === 0) ? 1 : (format === 9) ? 3 : 2;
    const blockAlign = channels * bytesPerSample;
    const frames = Math.floor(Number(byte_len) / blockAlign);
    if (frames <= 0) return;

    const audioBuf = ctx.createBuffer(channels, frames, sample_rate);
    const byteOffset = Number(data_ptr);
    const u8 = new Uint8Array(HEAPU8.buffer, byteOffset, frames * blockAlign);

    if (format === 0) {
        for (let ch = 0; ch < channels; ch++) {
            const dst = audioBuf.getChannelData(ch);
            for (let i = 0; i < frames; i++) {
                dst[i] = (u8[i * channels + ch] - 128) / 128.0;
            }
        }
    } else if (format === 9) {
        for (let ch = 0; ch < channels; ch++) {
            const dst = audioBuf.getChannelData(ch);
            for (let i = 0; i < frames; i++) {
                const idx = (i * channels + ch) * 3;
                const b0 = u8[idx];
                const b1 = u8[idx + 1];
                const b2 = u8[idx + 2];
                const val = ((b2 << 24) | (u8[idx + 1] << 16) | (b0 << 8)) >> 8;
                dst[i] = val / 8388608.0;
            }
        }
    } else {
        const view = new DataView(HEAPU8.buffer, byteOffset, frames * blockAlign);
        for (let ch = 0; ch < channels; ch++) {
            const dst = audioBuf.getChannelData(ch);
            for (let i = 0; i < frames; i++) {
                dst[i] = view.getInt16((i * channels + ch) * 2, true) / 32768.0;
            }
        }
    }

    const gainNode = ctx.createGain();
    gainNode.gain.value = 0.25;
    gainNode.connect(ctx.destination);

    const source = ctx.createBufferSource();
    source.buffer = audioBuf;
    source.connect(gainNode);

    if (frames > sample_rate * 5) {
        if (window._mojoCurrentMusic) {
            try { window._mojoCurrentMusic.stop(); } catch (e) {}
        }
        source.loop = true;
        window._mojoCurrentMusic = source;
        window._mojoMusicGain = gainNode;
        window._mojoMusicBaseVol = window._mojoLastRequestedVol || 0.5;
    }

    source.start();
});

EM_JS(void, wasm_play_sound, (uintptr_t data_ptr, size_t byte_len, int64_t sample_rate_bi, int64_t channels_bi, int64_t bits_bi, uintptr_t state_ptr), {
    if (!window._mojoAudioCtx) {
        const AudioCtx = window.AudioContext || window.webkitAudioContext;
        if (!AudioCtx) return;
        window._mojoAudioCtx = new AudioCtx();
        const resumeAudio = () => {
            if (window._mojoAudioCtx && window._mojoAudioCtx.state === 'suspended') {
                window._mojoAudioCtx.resume();
            }
        };
        window.addEventListener('touchstart', resumeAudio, { passive: true });
        window.addEventListener('touchend', resumeAudio, { passive: true });
        window.addEventListener('pointerdown', resumeAudio);
        window.addEventListener('keydown', resumeAudio);
    }
    const ctx = window._mojoAudioCtx;
    if (ctx.state === 'suspended') ctx.resume();

    const sample_rate = Number(sample_rate_bi);
    const channels = Number(channels_bi);
    const bits_per_sample = Number(bits_bi);
    const byteOffset = Number(data_ptr);
    const totalBytes = Number(byte_len);
    const sBase = Number(state_ptr);

    if (channels <= 0 || sample_rate <= 0) return;
    const bytesPerSample = (bits_per_sample === 8) ? 1 : (bits_per_sample === 24) ? 3 : 2;
    const blockAlign = channels * bytesPerSample;
    const frames = Math.floor(totalBytes / blockAlign);
    if (frames <= 0) return;

    const audioBuf = ctx.createBuffer(channels, frames, sample_rate);
    const u8 = new Uint8Array(HEAPU8.buffer, byteOffset, frames * blockAlign);

    if (bits_per_sample === 8) {
        for (let ch = 0; ch < channels; ch++) {
            const dst = audioBuf.getChannelData(ch);
            for (let i = 0; i < frames; i++) {
                dst[i] = (u8[i * channels + ch] - 128) / 128.0;
            }
        }
    } else if (bits_per_sample === 24) {
        for (let ch = 0; ch < channels; ch++) {
            const dst = audioBuf.getChannelData(ch);
            for (let i = 0; i < frames; i++) {
                const idx = (i * channels + ch) * 3;
                const val = ((u8[idx + 2] << 24) | (u8[idx + 1] << 16) | (u8[idx] << 8)) >> 8;
                dst[i] = val / 8388608.0;
            }
        }
    } else {
        const view = new DataView(HEAPU8.buffer, byteOffset, frames * blockAlign);
        for (let ch = 0; ch < channels; ch++) {
            const dst = audioBuf.getChannelData(ch);
            for (let i = 0; i < frames; i++) {
                dst[i] = view.getInt16((i * channels + ch) * 2, true) / 32768.0;
            }
        }
    }

    const gainNode = ctx.createGain();
    const initialVol = HEAPF32[sBase >> 2];
    gainNode.gain.value = Math.min(Math.max(initialVol, 0.0), 1.0) * 0.25;
    gainNode.connect(ctx.destination);

    const source = ctx.createBufferSource();
    source.buffer = audioBuf;
    source.connect(gainNode);

    if (frames > sample_rate * 5) {
        if (window._mojoCurrentMusic) {
            try { window._mojoCurrentMusic.stop(); } catch (e) {}
        }
        source.loop = true;
        window._mojoCurrentMusic = source;
    }

    const syncTimer = setInterval(() => {
        const vol = HEAPF32[sBase >> 2];
        const playing = HEAP32[(sBase + 4) >> 2];
        if (playing === 0) {
            try { source.stop(); } catch (e) {}
            clearInterval(syncTimer);
            return;
        }
        gainNode.gain.setValueAtTime(Math.min(Math.max(vol, 0.0), 1.0) * 0.25, ctx.currentTime);
    }, 50);

    source.onended = () => {
        clearInterval(syncTimer);
        HEAP32[(sBase + 4) >> 2] = 0;
    };

    source.start();
});

EM_JS(void, webaudio_set_music_gain, (float volume), {
    window._mojoLastRequestedVol = volume;
    if (window._mojoMusicGain && window._mojoAudioCtx) {
        const base = window._mojoMusicBaseVol || 0.5;
        const scale = (base > 0.001) ? (volume / base) : 0.0;
        window._mojoMusicGain.gain.setValueAtTime(
            Math.max(scale, 0.0) * 0.25,
            window._mojoAudioCtx.currentTime
        );
    }
});

// --- Pre-decoded Browser PNG Image Bridge (Replaces libpng16) ---
EM_JS(int, js_png_begin, (uintptr_t img_ptr, const char* path_ptr), {
    let path = UTF8ToString(Number(path_ptr));
    if (path.startsWith('/')) path = path.slice(1);
    const entry = window._decodedPngs && window._decodedPngs[path];
    if (!entry) return 0;
    const base = Number(img_ptr);
    HEAPU32[(base + 12) >> 2] = entry.width;
    HEAPU32[(base + 16) >> 2] = entry.height;
    if (!window._activePngReads) window._activePngReads = {};
    window._activePngReads[base] = entry;
    return 1;
});

EM_JS(int, js_png_finish, (uintptr_t img_ptr, uintptr_t buf_ptr), {
    const base = Number(img_ptr);
    const entry = window._activePngReads && window._activePngReads[base];
    if (!entry) return 0;
    delete window._activePngReads[base];
    new Uint8Array(HEAPU8.buffer, Number(buf_ptr), entry.rgba.length).set(entry.rgba);
    return 1;
});

int png_image_begin_read_from_file(void* image, const char* file_name) {
    return js_png_begin((uintptr_t)image, file_name);
}

int png_image_finish_read(void* image, const void* background, void* buffer, int32_t row_stride, void* colormap) {
    return js_png_finish((uintptr_t)image, (uintptr_t)buffer);
}

// --- Cross-Platform WebSocket Bridge (Browser WebSocket API) ---
EM_JS(int32_t, grl_ws_connect, (const char* url_ptr), {
    let base = Number(url_ptr);
    const bytes = Array.of();
    while (HEAPU8[base] !== 0) {
        bytes.push(HEAPU8[base++]);
    }
    const rawUrl = new TextDecoder().decode(new Uint8Array(bytes));
    const queryWs = new URLSearchParams(window.location.search).get('ws');
    const url = (queryWs && rawUrl.startsWith('ws://127.0.0.1')) ? queryWs : rawUrl;
    if (window._grlWs) {
        try { window._grlWs.close(); } catch (_) {}
    }
    window._grlWsState = 1;
    window._grlWsInbox = Array.of();
    try {
        const ws = new WebSocket(url);
        ws.onopen = () => { window._grlWsState = 2; };
        ws.onerror = () => { window._grlWsState = 3; };
        ws.onclose = () => { window._grlWsState = 0; };
        ws.onmessage = (ev) => {
            if (typeof ev.data === 'string') {
                window._grlWsInbox.push(ev.data);
            }
        };
        window._grlWs = ws;
        return 0;
    } catch (_) {
        window._grlWsState = 3;
        return -1;
    }
});

EM_JS(int32_t, grl_ws_state, (void), {
    return window._grlWsState || 0;
});

EM_JS(int32_t, grl_ws_send, (const char* data_ptr, int32_t len), {
    if (!window._grlWs || window._grlWs.readyState !== WebSocket.OPEN) return -1;
    const base = Number(data_ptr);
    const n = Number(len);
    let msg = "";
    for (let i = 0; i < n; i++) {
        msg += String.fromCharCode(HEAPU8[base + i]);
    }
    window._grlWs.send(msg);
    return n;
});

EM_JS(int32_t, grl_ws_poll, (char* out_buf, int32_t max_len), {
    if (!window._grlWsInbox || window._grlWsInbox.length === 0) return 0;
    const msg = window._grlWsInbox.shift();
    const limit = Math.min(msg.length, Number(max_len) - 1);
    const base = Number(out_buf);
    for (let i = 0; i < limit; i++) {
        HEAPU8[base + i] = msg.charCodeAt(i) & 0xFF;
    }
    HEAPU8[base + limit] = 0;
    return limit;
});

EM_JS(int32_t, grl_ws_close, (void), {
    if (window._grlWs) {
        try { window._grlWs.close(); } catch (_) {}
        window._grlWs = null;
    }
    window._grlWsState = 0;
    window._grlWsInbox = Array.of();
    return 0;
});

// --- dlopen / dlsym Wrappers ---
int64_t mojo_dlopen(int64_t filename, int32_t flags) {
    return 1; // Always return valid non-zero handle immediately without calling JS dlopen
}

int64_t mojo_dlsym(int64_t handle, const char* symbol) {
    if (symbol) {
        if (strcmp(symbol, "png_image_begin_read_from_file") == 0) return (int64_t)(uintptr_t)png_image_begin_read_from_file;
        if (strcmp(symbol, "png_image_finish_read") == 0) return (int64_t)(uintptr_t)png_image_finish_read;
        if (strcmp(symbol, "glfwGetKey") == 0) return (int64_t)(uintptr_t)mojo_glfwGetKey;
        if (strcmp(symbol, "grl_ws_connect") == 0) return (int64_t)(uintptr_t)grl_ws_connect;
        if (strcmp(symbol, "grl_ws_state") == 0)   return (int64_t)(uintptr_t)grl_ws_state;
        if (strcmp(symbol, "grl_ws_send") == 0)    return (int64_t)(uintptr_t)grl_ws_send;
        if (strcmp(symbol, "grl_ws_poll") == 0)    return (int64_t)(uintptr_t)grl_ws_poll;
        if (strcmp(symbol, "grl_ws_close") == 0)   return (int64_t)(uintptr_t)grl_ws_close;
    }
    // In Emscripten, NULL (0) is RTLD_DEFAULT for the main module!
    void* res = dlsym(NULL, symbol);
    if (!res) {
        printf("[dlsym MISSING] %s\n", symbol ? symbol : "(null)");
        fflush(stdout);
    }
    return (int64_t)(uintptr_t)res;
}

// --- Mojo Runtime Allocator ---
void* KGEN_CompilerRT_AlignedAlloc(size_t alignment, size_t size) {
    if (alignment < sizeof(void*)) alignment = sizeof(void*);
    size_t padded = (size + alignment - 1) & ~(alignment - 1);
    return aligned_alloc(alignment, padded ? padded : alignment);
}

void KGEN_CompilerRT_AlignedFree(void* ptr) {
    free(ptr);
}

// --- Pointer Lock & Main Loop ---
extern void* init_game(void);
extern void update_game(void* state);

EM_JS(void, focus_canvas_on_click, (void), {
    const canvas = document.getElementById('canvas');
    if (canvas) {
        canvas.focus();
        canvas.addEventListener('click', () => canvas.focus());
    }
});

int main(void) {
    void* game_state = init_game();
    focus_canvas_on_click();
    emscripten_set_main_loop_arg(update_game, game_state, 0, 1);
    return 0;
}

