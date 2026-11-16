#!/usr/bin/env python3
import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ENGINE_ROOT = Path(__file__).resolve().parent
WASM_DIR = ENGINE_ROOT / "wasm"

DEFAULT_MOJO_FILE = ENGINE_ROOT / "examples/hello_gammaraylib.mojo"
DEFAULT_TEST_FILE = ENGINE_ROOT / "tests/test_suit.mojo"
DEFAULT_INCLUDE_DIR = ENGINE_ROOT / "src"
RUNTIME_C = WASM_DIR / "runtime.c"
SHELL_HTML = WASM_DIR / "shell.html"

DEFAULT_EXPORTS = ["_init_game", "_update_game", "_webaudio_set_music_gain", "_main"]


def run(cmd: list[str], cwd: Path) -> None:
    print(f"[build] {' '.join(cmd)}")
    subprocess.run(cmd, cwd=cwd, check=True)

def run_tests(work_dir: Path, test_path: Path, include_flags: list[str]) -> None:
    if not test_path.is_file():
        sys.exit(f"[error] Test suite not found: {test_path}")
    run(["uv", "run", "mojo", *include_flags, str(test_path)], cwd=work_dir)
    print(f"[done] All tests passed ({test_path})")

def sub_checked(pattern: str, repl: str, text: str, label: str, required: bool = True) -> str:
    new_text, count = re.subn(pattern, repl, text)
    if required and count == 0:
        print(f"[warning] Regex patch '{label}' matched 0 times!", file=sys.stderr)
    return new_text


def patch_llvm_ir(ir: str) -> str:
    wasm_datalayout = 'target datalayout = "e-m:e-p:64:64-p10:8:8-p20:8:8-i64:64-i128:128-f128:64-n32:64-S128-ni:1:10:20"'
    wasm_triple = 'target triple = "wasm64-unknown-emscripten"'

    ir = sub_checked(r'target datalayout = "[^"]+"', wasm_datalayout, ir, "datalayout")
    ir = sub_checked(r'target triple = "[^"]+"', wasm_triple, ir, "triple")
    ir = sub_checked(r'"target-cpu"="[^"]+"', '"target-cpu"="generic"', ir, "target-cpu")
    ir = re.sub(r'"target-features"="[^"]+"', '', ir)
    ir = re.sub(r'(?m)^define\s+([^\n@]+?)\s+@main\(', r'define \1 @mojo_main(', ir)
    ir = ir.replace("@dlopen(", "@mojo_dlopen(").replace("@dlsym(", "@mojo_dlsym(")

    ir = re.sub(
        r'\b(call|invoke)\s+([^\(\n]+?)\s+\(([^\)]*?)\b\.\.\.\)\s+(%[A-Za-z0-9_.]+)\(',
        lambda m: f"{m.group(1)} {m.group(2)} ({m.group(3).rstrip(', ')}) {m.group(4)}(",
        ir,
    )

    ir = re.sub(
        r'store \{\} undef, ptr (%[A-Za-z0-9_.]+), align \d+\s+(%[A-Za-z0-9_.]+) = load i32, ptr \1, align \d+\s+(%[A-Za-z0-9_.]+) = call ([^\(\n]+?) (%[A-Za-z0-9_.]+)\(i32 \2\)',
        r'\3 = call \4 \5()',
        ir,
    )
    ir = re.sub(
        r'(%[A-Za-z0-9_.]+) = load i32, ptr (%[A-Za-z0-9_.]+), align \d+\s+call void (%[A-Za-z0-9_.]+)\(i32 \1\)',
        r'call void \3()',
        ir,
    )

    ir = sub_checked(r'#version \d{3} core', '#version 300 es  ', ir, "webgl2-shader-version")

    def stub_kgen_decl(match: re.Match) -> str:
        full_decl, ret_type, fn_name, args = match.group(0), match.group(1).strip(), match.group(2), match.group(3)
        if fn_name in ("KGEN_CompilerRT_AlignedAlloc", "KGEN_CompilerRT_AlignedFree"):
            return full_decl
        ret_clean = ret_type.split()[-1]
        body = "  ret void\n" if ret_clean == "void" else f"  ret {ret_clean} zeroinitializer\n"
        return f"define {ret_clean} @{fn_name}({args}) {{\n{body}}}\n"

    ir = re.sub(
        r'^declare\s+([^\n@]+?)\s+@(KGEN_CompilerRT_[A-Za-z0-9_]*)\(([^\)]*)\)[^\n]*',
        stub_kgen_decl,
        ir,
        flags=re.MULTILINE,
    )
    return ir

def build_native(
    work_dir: Path,
    src_path: Path,
    include_flags: list[str],
    out_path: Path,
    debug: bool,
    run_after: bool,
) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    opt_flags = ["-O0", "-g"] if debug else ["-O3"]
    engine_dir = Path(__file__).resolve().parent
    ws_c = engine_dir / "native" / "ws_native2.c"
    if ws_c.is_file():
        ws_so = out_path.parent / "libgrl_ws.so"
        run(["cc", "-O2", "-shared", "-fPIC", str(ws_c), "-lcurl", "-o", str(ws_so)], cwd=work_dir)

    run(
        [
            "uv", "run", "mojo", "build",
            *opt_flags,
            *include_flags,
            str(src_path),
            "-o", str(out_path),
        ],
        cwd=work_dir,
    )
    subprocess.run(["llvm-strip", "--strip-debug", str(out_path)], check=False)
    print(f"[done] Built native binary at {out_path}")
    if run_after:
        run([str(out_path)], cwd=work_dir)


def build_wasm(
    work_dir: Path,
    src_path: Path,
    include_flags: list[str],
    assets_dir: Path | None,
    title: str,
    dist_dir: Path,
    exports: list[str],
    debug: bool,
    run_after: bool,
    port: int,
) -> None:
    if not RUNTIME_C.is_file() or not SHELL_HTML.is_file():
        sys.exit(f"[error] Missing {RUNTIME_C.name} or {SHELL_HTML.name} in {WASM_DIR}")

    build_dir = work_dir / "build" / "wasm"
    stage_dir = build_dir / "dist"

    shutil.rmtree(build_dir, ignore_errors=True)
    stage_dir.mkdir(parents=True, exist_ok=True)

    raw_ll = build_dir / "raw.ll"
    patched_ll = build_dir / "patched.ll"
    staged_shell = build_dir / "shell.html"

    shell_text = SHELL_HTML.read_text(encoding="utf-8").replace("{{TITLE}}", title)
    staged_shell.write_text(shell_text, encoding="utf-8")

    # 1. Emit LLVM IR from Mojo
    run(
        [
            "uv", "run", "mojo", "build",
            "-D", "WASM=1",
            "--target-cpu=x86-64",
            "-O1",
            "--emit", "llvm",
            *include_flags,
            str(src_path),
            "-o", str(raw_ll),
        ],
        cwd=work_dir,
    )

    # 2. Patch IR for wasm64 + WebGL 2
    patched_ir = patch_llvm_ir(raw_ll.read_text(encoding="utf-8"))
    patched_ll.write_text(patched_ir, encoding="utf-8")

    # 3. Compile & link with Emscripten
    opt_flags = ["-O1", "-g2", "-sASSERTIONS=2"] if debug else ["-O3"]
    exports_arg = f"-sEXPORTED_FUNCTIONS={exports}".replace("'", '"').replace(" ", "")

    emcc_cmd = [
        "emcc",
        str(patched_ll),
        str(RUNTIME_C),
        *opt_flags,
        "-msimd128",
        "-m64",
        "-sMEMORY64=2",
        "-sALLOW_MEMORY_GROWTH=1",
        "-sINITIAL_MEMORY=128MB",
        "-sMAXIMUM_MEMORY=512MB",
        "-sMIN_SAFARI_VERSION=150000",
        "-sUSE_GLFW=3",
        "-sFULL_ES3=1",
        "-sMAIN_MODULE=1",
        "-sINVOKE_RUN=0",
        '-sEXPORTED_RUNTIME_METHODS=["callMain"]',
        "-O3",
        "-g0",
        "-Wl,--strip-debug",
        "--shell-file", str(staged_shell),
        exports_arg,
        "-o", "index.html",
    ]

    if assets_dir is not None:
        if not assets_dir.is_dir():
            sys.exit(f"[error] Assets directory not found: {assets_dir}")
        emcc_cmd.extend(["--preload-file", f"{assets_dir}@assets"])

    run(emcc_cmd, cwd=stage_dir)

    # 4. Swap into dist/ and clean up build/wasm
    shutil.rmtree(dist_dir, ignore_errors=True)
    shutil.move(str(stage_dir), str(dist_dir))
    shutil.rmtree(build_dir, ignore_errors=True)

    # 5. Strip debug symbols & local paths
    bin_path = dist_dir / "index.wasm"
    subprocess.run(["llvm-strip", "--strip-debug", str(bin_path)], check=False)
    if bin_path.is_file():
        data = bin_path.read_bytes()
        cleaned = re.sub(
            rb'/(?:home|Users|tmp|var|opt|usr)/[A-Za-z0-9_./-]+',
            lambda m: b' ' * len(m.group(0)),
            data,
        )
        if cleaned != data:
            bin_path.write_bytes(cleaned)

    print(f"[done] Built WebAssembly bundle at {dist_dir}/")

    if run_after:
        print(f"[serve] Serving {dist_dir}/ at http://127.0.0.1:{port} (Press Ctrl+C to stop)")
        try:
            run([sys.executable, "-m", "http.server", str(port)], cwd=dist_dir)
        except KeyboardInterrupt:
            print("\n[serve] Stopped HTTP server.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Unified Native & WebAssembly builder for gammaraylib projects.")
    parser.add_argument("target", nargs="?", choices=["native", "wasm", "test"], default="native", help="Build target (native, wasm, or test)")
    parser.add_argument("--src", type=Path, default=DEFAULT_MOJO_FILE, help="Path to entry .mojo file")
    parser.add_argument("-I", "--include", type=Path, action="append", default=[], help="Extra Mojo import paths")
    parser.add_argument("--assets", type=Path, default=None, help="Optional path to assets directory (for wasm)")
    parser.add_argument("--title", type=str, default="gammaraylib App", help="HTML page title (for wasm)")
    parser.add_argument("--out", type=Path, default=None, help="Output binary path (native) or dist folder (wasm)")
    parser.add_argument("--export", type=str, action="append", default=[], help="Extra exported C/Mojo symbols (wasm)")
    parser.add_argument("--debug", action="store_true", help="Enable debug symbols / assertions")
    parser.add_argument("--run", "--serve", dest="run_after", action="store_true", help="Run binary or start HTTP server after building")
    parser.add_argument("--port", type=int, default=8000, help="HTTP server port when using --run/--serve on wasm")
    args = parser.parse_args()

    src_path = args.src.resolve()
    if not src_path.is_file():
        sys.exit(f"[error] Mojo source file not found: {src_path}")

    work_dir = Path.cwd()
    include_flags = ["-I", str(DEFAULT_INCLUDE_DIR)]
    for inc in args.include:
        include_flags.extend(["-I", str(inc.resolve())])

    if args.target == "test":
        test_path = args.src.resolve() if args.src != DEFAULT_MOJO_FILE else DEFAULT_TEST_FILE
        run_tests(work_dir, test_path, include_flags)
    elif args.target == "native":
        out_path = (args.out or (work_dir / "build" / "native" / src_path.stem)).resolve()
        build_native(work_dir, src_path, include_flags, out_path, args.debug, args.run_after)
    else:
        dist_dir = (args.out or (work_dir / "dist")).resolve()
        assets_dir = args.assets.resolve() if args.assets is not None else None
        build_wasm(
            work_dir,
            src_path,
            include_flags,
            assets_dir,
            args.title,
            dist_dir,
            DEFAULT_EXPORTS + args.export,
            args.debug,
            args.run_after,
            args.port,
        )


if __name__ == "__main__":
    main()
