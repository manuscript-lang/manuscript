//! Selects Rust or C for whole native modules. `cargo xtask runtime` sets `MS_C_CRYPTO` (and later `MS_C_REGEX`)
//! when the archive also holds the C version in `runtime/std`; `src/lib.rs` then leaves the Rust crate out.

fn main() {
    for (var, cfg) in [("MS_C_CRYPTO", "ms_c_crypto")] {
        println!("cargo::rustc-check-cfg=cfg({cfg})");
        println!("cargo::rerun-if-env-changed={var}");
        if std::env::var_os(var).is_some() {
            println!("cargo::rustc-cfg={cfg}");
        }
    }
}
