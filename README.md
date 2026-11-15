# gammaraylib

[![Live Wasm Demo](https://lagamma.github.io/gammaraylib)](https://lagamma.github.io/gammaraylib/)

A lightweight, raylib-inspired 2D/3D game library for **Mojo** targeting **Native Linux** (GLFW + OpenGL 4.6) and **WebAssembly** (Emscripten + WebGL 2 + WebAudio).

> **Try it online:** [Launch the WebAssembly Demo](https://lagamma.github.io/gammaraylib/)

## Features
* **2D & 3D Rendering**: Batched OpenGL/WebGL2 renderer (`rlgl`), shapes, textures, procedural checked textures, and 3D primitives/models.
* **Text & Immediate-Mode GUI**: Built-in 8×8 bitmap font (`load_font_default`), baked TTF atlas support (`load_font`), panels, buttons, checkboxes, and sliders.
* **Audio**: Native ALSA/PulseAudio and browser WebAudio playback with procedural synth sound generators.
* **Single-Command Builds**: Unified `build.py` script for both native binaries and standalone WebAssembly bundles.

## Prerequisites
* [uv](https://astral.sh) (manages the Mojo toolchain)
* **Native Linux**: `libglfw3`, `libGL`, `libpng16`, `libturbojpeg`
* **WebAssembly**: [Emscripten SDK (`emcc`)](https://emscripten.org)

## Quick Start

1. **Install dependencies:**
   ```bash
   uv sync
   ```

2. **Build & run the standalone demo (Native):**
   ```bash
   python3 build.py native --run
   ```

3. **Build & serve the standalone demo (WebAssembly):**
   ```bash
   python3 build.py wasm --title "gammaraylib Demo" --run
   ```
   Then open `http://localhost:8000` in your browser.

4. **Run the engine test suite:**
   ```bash
   python3 build.py test
   ```

## Using in Your Own Project

Add `gammaraylib` as a Git submodule (e.g. `libs/gammaraylib`) and build your game using the unified builder:

```bash
# Native build
python3 libs/gammaraylib/build.py native --src src/main.mojo -I src --run

# WebAssembly build with assets
python3 libs/gammaraylib/build.py wasm --src src/main_wasm.mojo -I src --assets assets --title "My Game" --run
```
