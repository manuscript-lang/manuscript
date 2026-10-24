//! The files `ms build` links with, embedded by `build.rs`, which reruns only when the bundled tools change.

macro_rules! bundled {
    ($($name:literal),*) => {
        /// The linker and its startup files and libraries, by file name.
        pub(super) const FILES: &[(&str, &[u8])] = &[
            $(($name, include_bytes!(concat!(env!("OUT_DIR"), "/linker/", $name)))),*
        ];
    };
}
#[cfg(target_os = "linux")]
bundled!("crt1.o", "crti.o", "crtn.o", "libc.a", "libunwind.a");
#[cfg(target_os = "windows")]
bundled!(
    "crt2.o",
    "libmingw32.a",
    "libmingwex.a",
    "libmoldname.a",
    "libunwind.a",
    "libucrt.a",
    "libmsvcrt.a",
    "libkernel32.a",
    "libadvapi32.a",
    "libbcrypt.a",
    "libcrypt32.a",
    "libdbghelp.a",
    "libntdll.a",
    "libsecur32.a",
    "libuserenv.a",
    "libws2_32.a",
    "libuser32.a",
    "libshell32.a"
);
#[cfg(target_os = "macos")]
bundled!();

/// The embedded `lld`, gzipped: raw it is the largest thing in `ms`.
pub(super) const LLD: (&str, &[u8]) = (
    concat!("lld", env!("MS_EXE_SUFFIX")),
    include_bytes!(concat!(env!("OUT_DIR"), "/linker/lld.gz")),
);

/// Where `ms` fetches the LLVM tools (`opt`, `llc`, `llvm-link`) on the first release build, and the
/// SHA-256 of that archive, both from `scripts/lld.lock`. Empty on targets without a published archive.
pub(super) const LLVM_TOOLS_URL: &str = env!("MS_LLVM_TOOLS_URL");
pub(super) const LLVM_TOOLS_SHA256: &str = env!("MS_LLVM_TOOLS_SHA256");

/// LLVM IR of the runtime's pure helpers (`ms-rt-hot`), linked into release programs before they
/// are optimized so the helpers inline; empty when the runtime was not built with `cargo xtask runtime`.
pub(crate) const RUNTIME_HOT_IR: &str =
    include_str!(concat!(env!("OUT_DIR"), "/linker/ms_rt_hot.ll"));

/// A hash of every bundled file; names the cache directory the files are unpacked into.
pub(super) const LINKER_ID: &str = env!("MS_LINKER_ID");
