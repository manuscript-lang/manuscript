//! The C back end: the lowered module goes to libms as MIR text (`compiler/include/ms/build_object.h`, linked
//! into this crate by `build.rs`), which runs the optimizer and finishing passes, writes LLVM IR, compiles it with
//! the pinned LLVM tools (`opt`, `llc`) and appends the fault tables, so no C toolchain and no helper program is
//! needed. A program the emitter cannot write fails with the reason; the corpus diff
//! (`compiler/tests/build-diff.sh`) counts the gaps.

// The calls into libms are the only unsafe code of this crate.
#![allow(unsafe_code)]

use std::ffi::{CString, c_char};
use std::path::PathBuf;

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
struct Backend {
    speed: bool,
    checks: bool,
    verify: bool,
    tables: bool,
    count_ops: bool,
    poison_slots: bool,
    cancel_edges: bool,
    copy_probe: u8,
}

/// `MsLinkOptions`.
#[repr(C)]
struct LinkOptions {
    lld: *const c_char,
    llc: *const c_char,
    files: *const c_char,
    strip: bool,
    musl: bool,
}

/// `MsObjectOptions`.
#[repr(C)]
struct ObjectOptions {
    backend: Backend,
    tools: *const c_char,
    vectorize: bool,
    llvm_verify: bool,
    keep_ll: *const c_char,
}

unsafe extern "C" {
    fn ms_build_object(
        mir: *const c_char,
        mir_len: usize,
        shown: *const c_char,
        shown_len: usize,
        options: *const ObjectOptions,
        object: *mut Text,
        why: *mut Text,
    ) -> bool;
    fn ms_backend_optimized(
        mir: *const c_char,
        mir_len: usize,
        name: *const c_char,
        optimize: bool,
        out: *mut Text,
        why: *mut Text,
    ) -> bool;
    fn ms_build_link(
        object: *const c_char,
        inputs: *const *const c_char,
        ninputs: usize,
        out: *const c_char,
        options: *const LinkOptions,
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

/// The MIR of `module` after elaboration, and after the optimizer at its speed level when `optimize`,
/// as text (`ms emit`, `MS_EMIT_OPT=1 ms emit`).
pub fn emitted_mir(module: &Module, optimize: bool) -> Result<String, String> {
    let mir = ms_mir::print::print_module_unique(module);
    let (mut out, mut why) = (Text::empty(), Text::empty());
    // SAFETY: the text is passed with its length, the name is NUL-terminated, and the outputs are
    // empty texts libms fills.
    let ok = unsafe {
        ms_backend_optimized(
            mir.as_ptr().cast(),
            mir.len(),
            c"program.mir".as_ptr(),
            optimize,
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

/// Compiles `module` to an object file with the C pipeline.
pub fn compile(
    module: &Module,
    speed: bool,
    checks: bool,
    build: &BuildOptions,
) -> Result<Vec<u8>, String> {
    let tools: PathBuf = llvm_tools(build).map_err(|e| e.to_string())?.ok_or(
        "no LLVM tools are available for this platform; set MS_LLVM_TOOLS to a directory with opt and llc",
    )?;
    let tools = CString::new(tools.to_string_lossy().as_bytes())
        .map_err(|_| "the LLVM tools path holds a NUL".to_string())?;
    let keep_ll = c"ms-keep.ll";
    let options = ObjectOptions {
        backend: Backend {
            speed,
            checks,
            verify: true,
            tables: true,
            count_ops: build.count_ops,
            poison_slots: build.poison_slots,
            cancel_edges: std::env::var_os("MS_CANCEL_EDGES").is_some(),
            copy_probe: match build.copy_probe {
                crate::CopyProbe::Off => 0,
                crate::CopyProbe::Report => 1,
                crate::CopyProbe::Strict => 2,
            },
        },
        tools: tools.as_ptr(),
        vectorize: build.vectorize,
        llvm_verify: build.llvm_verify,
        keep_ll: if build.keep_ll {
            keep_ll.as_ptr()
        } else {
            std::ptr::null()
        },
    };
    let mir = ms_mir::print::print_module_unique(module);
    let shown = ms_mir::print::display_names(module);
    let (mut object, mut why) = (Text::empty(), Text::empty());
    // SAFETY: the texts are passed with their lengths, `options` and the strings it points to outlive the call, and
    // the outputs are empty texts libms fills.
    let ok = unsafe {
        ms_build_object(
            mir.as_ptr().cast(),
            mir.len(),
            shown.as_ptr().cast(),
            shown.len(),
            &raw const options,
            &raw mut object,
            &raw mut why,
        )
    };
    if ok {
        Ok(object.take())
    } else {
        Err(reason(why))
    }
}

/// What a link names: the `lld` and `llc` executables (`llc` only for the glibc stubs of a dynamic Linux link) and the
/// directory of bundled startup files.
pub struct LinkFiles<'a> {
    pub lld: &'a CString,
    pub llc: Option<&'a CString>,
    pub files: &'a CString,
    pub strip: bool,
    pub musl: bool,
}

/// Links `object` and `inputs` into the executable `out` with libms (`compiler/src/build/link.c`).
pub fn build_link(
    object: &CString,
    inputs: &[CString],
    out: &CString,
    files: &LinkFiles,
) -> Result<(), String> {
    let pointers: Vec<*const c_char> = inputs.iter().map(|path| path.as_ptr()).collect();
    let options = LinkOptions {
        lld: files.lld.as_ptr(),
        llc: files.llc.map_or(std::ptr::null(), |path| path.as_ptr()),
        files: files.files.as_ptr(),
        strip: files.strip,
        musl: files.musl,
    };
    let mut why = Text::empty();
    // SAFETY: every string is NUL-terminated and outlives the call, `pointers` holds one pointer per input, and `why`
    // is an empty text libms fills.
    let linked = unsafe {
        ms_build_link(
            object.as_ptr(),
            pointers.as_ptr(),
            pointers.len(),
            out.as_ptr(),
            &raw const options,
            &raw mut why,
        )
    };
    if linked { Ok(()) } else { Err(reason(why)) }
}
