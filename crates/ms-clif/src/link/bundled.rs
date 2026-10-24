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
bundled!("lld", "crt1.o", "crti.o", "crtn.o", "libc.a", "libunwind.a");
#[cfg(target_os = "windows")]
bundled!(
    "lld.exe",
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
bundled!("lld");

/// The embedded `opt` and `llc`, gzipped; empty when `ms` was built without the LLVM tools.
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub(super) const TOOLS: [(&str, &[u8]); 2] = [
    (
        concat!("opt", env!("MS_EXE_SUFFIX")),
        include_bytes!(concat!(env!("OUT_DIR"), "/linker/opt.gz")),
    ),
    (
        concat!("llc", env!("MS_EXE_SUFFIX")),
        include_bytes!(concat!(env!("OUT_DIR"), "/linker/llc.gz")),
    ),
];

/// A hash of every bundled file; names the cache directory the files are unpacked into.
pub(super) const LINKER_ID: &str = env!("MS_LINKER_ID");
