//! The C back end: the lowered module goes to libms as MIR text
//! (`compiler/include/ms/emit_program.h`, linked into this crate by `build.rs`), which runs the
//! optimizer and finishing passes and returns LLVM IR. The pinned LLVM tools (`opt`, `llc`) turn
//! that into assembly, libms appends the fault tables to it, and `llc` assembles the result, so
//! no C toolchain and no helper program is needed. A program the emitter cannot write fails with the
//! reason; the corpus diff (`compiler/tests/build-diff.sh`) counts the gaps.

// The calls into libms are the only unsafe code of this crate.
#![allow(unsafe_code)]

use std::ffi::{CString, c_char};
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::BuildOptions;
use crate::link::llvm_tools;
use ms_mir::ir::Module;

/// `MsBackendText`: bytes libms allocated, freed with `ms_backend_free`.
#[repr(C)]
struct Text {
    ptr: *mut c_char,
    len: usize,
}

/// `MsBackendOptions`.
#[repr(C)]
struct Options {
    speed: bool,
    checks: bool,
    verify: bool,
    tables: bool,
    count_ops: bool,
    poison_slots: bool,
}

unsafe extern "C" {
    fn ms_backend_ir(
        mir: *const c_char,
        mir_len: usize,
        name: *const c_char,
        shown: *const c_char,
        shown_len: usize,
        options: *const Options,
        ir: *mut Text,
        meta: *mut Text,
        why: *mut Text,
    ) -> bool;
    fn ms_backend_optimized(
        mir: *const c_char,
        mir_len: usize,
        name: *const c_char,
        out: *mut Text,
        why: *mut Text,
    ) -> bool;
    fn ms_backend_tables(
        meta: *const c_char,
        meta_len: usize,
        asm_text: *const c_char,
        asm_len: usize,
        prefix: *const c_char,
        out: *mut Text,
        why: *mut Text,
    ) -> bool;
    fn ms_backend_free(text: *mut Text);
}

impl Text {
    const fn empty() -> Self {
        Self {
            ptr: std::ptr::null_mut(),
            len: 0,
        }
    }

    /// Copies the bytes out and frees them.
    fn take(mut self) -> Vec<u8> {
        let bytes = if self.ptr.is_null() {
            Vec::new()
        } else {
            // SAFETY: libms returned `len` initialized bytes at `ptr`, which this value owns.
            unsafe { std::slice::from_raw_parts(self.ptr.cast::<u8>(), self.len) }.to_vec()
        };
        // SAFETY: the text came from libms and is freed once; the call leaves it empty.
        unsafe { ms_backend_free(&raw mut self) };
        bytes
    }
}

/// The reason libms gave, as an error message.
fn reason(why: Text) -> String {
    String::from_utf8_lossy(&why.take()).trim_end().to_string()
}

/// The LLVM IR of `mir` and the description its fault tables are built from. `shown` names the
/// functions as a fault trace shows them (`ms_mir::print::display_names`).
fn ir_of(
    mir: &str,
    shown: &str,
    speed: bool,
    checks: bool,
    build: &BuildOptions,
) -> Result<(Vec<u8>, Vec<u8>), String> {
    let options = Options {
        speed,
        checks,
        verify: true,
        tables: true,
        count_ops: build.count_ops,
        poison_slots: build.poison_slots,
    };
    let (mut ir, mut meta, mut why) = (Text::empty(), Text::empty(), Text::empty());
    // SAFETY: every pointer is valid for the call, both texts are passed with their lengths, the
    // name is NUL-terminated, and the three outputs are empty texts libms fills.
    let ok = unsafe {
        ms_backend_ir(
            mir.as_ptr().cast(),
            mir.len(),
            c"program.mir".as_ptr(),
            shown.as_ptr().cast(),
            shown.len(),
            &raw const options,
            &raw mut ir,
            &raw mut meta,
            &raw mut why,
        )
    };
    if ok {
        Ok((ir.take(), meta.take()))
    } else {
        Err(reason(why))
    }
}

/// The MIR of `module` after the optimizer at its speed level, as text (`MS_EMIT_OPT=1 ms emit`).
pub fn optimized_mir(module: &Module) -> Result<String, String> {
    let mir = ms_mir::print::print_module_unique(module);
    let (mut out, mut why) = (Text::empty(), Text::empty());
    // SAFETY: the text is passed with its length, the name is NUL-terminated, and the outputs are
    // empty texts libms fills.
    let ok = unsafe {
        ms_backend_optimized(
            mir.as_ptr().cast(),
            mir.len(),
            c"program.mir".as_ptr(),
            &raw mut out,
            &raw mut why,
        )
    };
    if ok {
        Ok(String::from_utf8_lossy(&out.take()).into_owned())
    } else {
        Err(reason(why))
    }
}

/// `asm` with the fault tables `meta` describes appended and its `.loc` lines removed.
fn with_tables(meta: &[u8], asm: &[u8]) -> Result<Vec<u8>, String> {
    let prefix = CString::new(if cfg!(target_os = "macos") { "_" } else { "" }).expect("no NUL");
    let (mut out, mut why) = (Text::empty(), Text::empty());
    // SAFETY: both texts are passed with their lengths, the prefix is NUL-terminated, and the
    // outputs are empty texts libms fills.
    let ok = unsafe {
        ms_backend_tables(
            meta.as_ptr().cast(),
            meta.len(),
            asm.as_ptr().cast(),
            asm.len(),
            prefix.as_ptr(),
            &raw mut out,
            &raw mut why,
        )
    };
    if ok { Ok(out.take()) } else { Err(reason(why)) }
}

/// The LLVM target triple of this host. Windows executables link over the mingw-w64 CRT, so the
/// code follows its conventions rather than MSVC's.
fn host_triple() -> Result<String, String> {
    let arch = std::env::consts::ARCH;
    match std::env::consts::OS {
        "linux" => Ok(format!("{arch}-unknown-linux-gnu")),
        "macos" => Ok(format!("{arch}-apple-darwin")),
        "windows" => Ok(format!("{arch}-w64-windows-gnu")),
        os => Err(format!("no LLVM target for {os}")),
    }
}

/// Assembly as an LLVM module that holds nothing else, which `llc` assembles: the pinned tools
/// have no assembler of their own.
///
/// A COFF object carries one `@feat.00` symbol, which `llc` writes for every module. The assembly
/// already defines it, and so would the wrapping module, so the copy in the assembly is left out.
fn asm_module(asm: &[u8]) -> Vec<u8> {
    const FEATURES: &[u8] = b"@feat.00";
    let names_features = |line: &[u8]| line.windows(FEATURES.len()).any(|w| w == FEATURES);
    let mut module = Vec::with_capacity(asm.len() + asm.len() / 2);
    let mut in_features_def = false;
    for line in asm.split(|&b| b == b'\n') {
        if in_features_def {
            in_features_def = !line.windows(6).any(|w| w == b".endef");
            continue;
        }
        if names_features(line) {
            in_features_def = line.trim_ascii_start().starts_with(b".def");
            continue;
        }
        module.extend_from_slice(b"module asm \"");
        for &byte in line {
            if (0x20..0x7f).contains(&byte) && byte != b'"' && byte != b'\\' {
                module.push(byte);
            } else {
                module.extend_from_slice(format!("\\{byte:02X}").as_bytes());
            }
        }
        module.extend_from_slice(b"\"\n");
    }
    module
}

/// Prints how long a build stage took to stderr when `MS_TIMINGS` is set, so a slow platform shows
/// which stage grows (the scaling gate reports only the total).
fn timed<T>(what: &str, stage: impl FnOnce() -> T) -> T {
    let start = std::time::Instant::now();
    let result = stage();
    if std::env::var_os("MS_TIMINGS").is_some() {
        eprintln!("timing {what}: {:.3}s", start.elapsed().as_secs_f64());
    }
    result
}

fn run(command: &mut Command, what: &str) -> Result<(), String> {
    let output = timed(what, || command.output()).map_err(|e| format!("cannot run {what}: {e}"))?;
    if output.status.success() {
        Ok(())
    } else {
        Err(format!(
            "{what} failed: {}",
            String::from_utf8_lossy(&output.stderr).trim_end()
        ))
    }
}

fn write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    std::fs::write(path, bytes).map_err(|e| format!("cannot write {}: {e}", path.display()))
}

/// Compiles `module` to an object file with the C pipeline.
pub fn compile(
    module: &Module,
    speed: bool,
    checks: bool,
    build: &BuildOptions,
) -> Result<Vec<u8>, String> {
    // One folder per build: a process may build several programs at once (the test runner does).
    static BUILDS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    let build_number = BUILDS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let dir =
        std::env::temp_dir().join(format!("ms-cbackend-{}-{build_number}", std::process::id()));
    std::fs::create_dir_all(&dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    let result = compile_in(&dir, module, speed, checks, build);
    let _ = std::fs::remove_dir_all(&dir);
    result
}

fn compile_in(
    dir: &Path,
    module: &Module,
    speed: bool,
    checks: bool,
    build: &BuildOptions,
) -> Result<Vec<u8>, String> {
    let (ir_text, meta) = timed("front end (print, optimize, emit IR)", || {
        ir_of(
            &ms_mir::print::print_module_unique(module),
            &ms_mir::print::display_names(module),
            speed,
            checks,
            build,
        )
    })?;
    let tools: PathBuf = llvm_tools(build).map_err(|e| e.to_string())?.ok_or(
        "no LLVM tools are available for this platform; set MS_LLVM_TOOLS to a directory with opt and llc",
    )?;
    let tool =
        |name: &str| Command::new(tools.join(format!("{name}{}", std::env::consts::EXE_SUFFIX)));
    let triple = format!("-mtriple={}", host_triple()?);
    let ir = dir.join("program.ll");
    write(&ir, &ir_text)?;
    if build.keep_ll {
        let _ = std::fs::copy(&ir, "ms-keep.ll");
    }
    // What `clang -O3` does for IR input: the default pipeline, then code generation.
    let mut input = ir;
    if speed {
        let optimized = dir.join("program.bc");
        let mut opt = tool("opt");
        if !build.vectorize {
            opt.args(["-vectorize-loops=false", "-vectorize-slp=false"]);
        }
        if build.llvm_verify {
            opt.arg("-verify-each");
        }
        opt.args([&triple, "-passes=default<O3>"])
            .arg(&input)
            .arg("-o")
            .arg(&optimized);
        run(&mut opt, "opt (LLVM optimizer)")?;
        input = optimized;
    }
    let plain = dir.join("program.plain.s");
    let mut llc = tool("llc");
    // A module with a function the emitter marked `optnone` (a size tier, #3928) goes through the
    // fast code generator: llc's -O3 two-address and register-allocation passes are superlinear in
    // one function's size even when the function is optnone, and `opt` already ran the IR passes.
    let size_tiered = ir_text.windows(8).any(|w| w == b" optnone");
    llc.args([
        if speed && !size_tiered { "-O3" } else { "-O0" },
        "-filetype=asm",
        "-relocation-model=pic",
        &triple,
    ]);
    if cfg!(target_arch = "x86_64") {
        // Loops start on a 32-byte boundary and the CPU is the portable baseline, as the Rust LLVM
        // path set them (#1871): a small loop must not straddle a cache line by link order, and the
        // unnamed "generic" CPU lacks the cheap 32-bit divide guard.
        llc.args(["-align-loops=32", "-mcpu=x86-64"]);
    }
    llc.arg(&input).arg("-o").arg(&plain);
    run(&mut llc, "llc (LLVM code generator)")?;
    // The fault tables: libms labels the assembly and appends them (no debug info is read). The
    // `.loc` lines are dropped, so the object carries no line tables.
    let asm = std::fs::read(&plain).map_err(|e| format!("cannot read {}: {e}", plain.display()))?;
    let wrapped = dir.join("program.asm.ll");
    write(
        &wrapped,
        &asm_module(&timed("fault tables", || with_tables(&meta, &asm))?),
    )?;
    let object = dir.join("program.o");
    run(
        tool("llc")
            .args(["-filetype=obj", "-relocation-model=pic", &triple])
            .arg(&wrapped)
            .arg("-o")
            .arg(&object),
        "llc (assembler)",
    )?;
    std::fs::read(&object).map_err(|e| format!("cannot read {}: {e}", object.display()))
}

#[cfg(test)]
mod tests {
    use super::asm_module;

    #[test]
    fn the_coff_feature_symbol_is_left_to_the_wrapping_module() {
        let asm =
            b"\t.def\t@feat.00;\n\t.scl\t3;\n\t.endef\n\t.globl\t@feat.00\n@feat.00 = 0\nmain:";
        assert_eq!(
            String::from_utf8(asm_module(asm)).unwrap(),
            "module asm \"main:\"\n"
        );
    }

    #[test]
    fn assembly_is_quoted_line_by_line() {
        let module = asm_module(b"\t.ascii \"a\\n\"\nmain:");
        assert_eq!(
            String::from_utf8(module).unwrap(),
            "module asm \"\\09.ascii \\22a\\5Cn\\22\"\nmodule asm \"main:\"\n"
        );
    }
}
