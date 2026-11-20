//! Selects Rust or C for whole native modules. `cargo xtask runtime` sets `MS_C_CRYPTO` when the archive also holds
//! the C version in `runtime/std`; `src/lib.rs` then leaves the Rust crate out.

fn main() {
    println!("cargo::rustc-check-cfg=cfg(ms_c_crypto)");
    println!("cargo::rerun-if-env-changed=MS_C_CRYPTO");
    if std::env::var_os("MS_C_CRYPTO").is_some() {
        println!("cargo::rustc-cfg=ms_c_crypto");
    }
}
