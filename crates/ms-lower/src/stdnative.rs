//! The standard-library externs that lowering handles itself, in one table.
//!
//! Every other extern is a plain runtime call marshalled from its signature. An entry here is keyed by
//! the runtime symbol the `.ms` declaration names and gives the native identity the lowering arms in
//! `native.rs` and `closure.rs` match on. A function that returns an interface over a runtime handle
//! also names the handle; `natiface` builds its value.

/// The runtime call that makes the handle behind an interface value, and the interface's module.
pub(crate) struct Handle {
    pub module: &'static str,
    /// The runtime symbol that returns the handle; empty when the value carries nothing and its
    /// operations open handles.
    pub make: &'static str,
    /// The constant argument of `make`.
    pub constant: i64,
}

pub(crate) struct HandLowered {
    pub symbol: &'static str,
    pub identity: &'static str,
    pub handle: Option<Handle>,
}

const fn plain(symbol: &'static str, identity: &'static str) -> HandLowered {
    HandLowered {
        symbol,
        identity,
        handle: None,
    }
}

const fn handle(
    symbol: &'static str,
    identity: &'static str,
    module: &'static str,
    make: &'static str,
) -> HandLowered {
    HandLowered {
        symbol,
        identity,
        handle: Some(Handle {
            module,
            make,
            constant: 0,
        }),
    }
}

const HAND_LOWERED: &[HandLowered] = &[
    plain("msstd_html_parse", "html/parse"),
    handle("msstd_net_network", "net/network", "net", "msstd_net_network"),
    handle("msstd_fs_filesystem", "fs/filesystem", "fs", ""),
    // The rules are the table: `path_win` forwards with the Windows flag set.
    handle("msstd_fs_posix", "fs/posix", "path", ""),
    handle("msstd_fs_win32", "fs/win32", "path_win", ""),
    plain("msstd_io_copy", "io/copy"),
    handle("msstd_io_files", "io/files", "io", ""),
    plain("msstd_io_read_all", "io/read_all"),
    plain("msstd_io_read_line", "io/read_line"),
    plain("msstd_io_stderr", "io/stderr"),
    handle("msstd_io_stdin", "io/stdin", "io", "msstd_io_standard"),
    plain("msstd_io_stdout", "io/stdout"),
    handle("msstd_io_terminal", "io/terminal", "terminal", ""),
    handle("msstd_process_commands", "process/commands", "process", ""),
    plain("msstd_random_draw_choice", "random/draw_choice"),
    plain("msstd_random_draw_float", "random/draw_float"),
    plain("msstd_random_draw_int", "random/draw_int"),
    plain("msstd_random_draw_shuffle", "random/draw_shuffle"),
    plain("msstd_random_draw_uuid", "random/draw_uuid"),
    handle("msstd_random_entropy", "random/host_entropy", "random", ""),
    handle("msstd_process_control", "process/control", "process", ""),
    handle("msstd_process_system", "process/system", "system", ""),
    handle("msstd_time_clock", "time/clock", "time", ""),
    handle("msstd_time_wall_clock", "time/wall_clock", "time", ""),
];

pub(crate) fn by_symbol(symbol: &str) -> Option<&'static HandLowered> {
    HAND_LOWERED.iter().find(|h| h.symbol == symbol)
}

/// The handle behind the interface that the native function `identity` returns.
pub(crate) fn handle_of(identity: &str) -> Option<&'static Handle> {
    HAND_LOWERED
        .iter()
        .find(|h| h.identity == identity)
        .and_then(|h| h.handle.as_ref())
}

#[cfg(test)]
mod tests {
    use super::HAND_LOWERED;
    use std::path::Path;

    fn collect(dir: &Path, text: &mut String) {
        for entry in std::fs::read_dir(dir).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                collect(&path, text);
            } else if path.extension().is_some_and(|e| e == "ms") {
                text.push_str(&std::fs::read_to_string(&path).unwrap());
            }
        }
    }

    /// A renamed symbol would silently fall back to a plain runtime call.
    #[test]
    fn every_entry_names_a_declared_extern() {
        let mut stdlib = String::new();
        collect(
            &Path::new(env!("CARGO_MANIFEST_DIR")).join("../../stdlib"),
            &mut stdlib,
        );
        for h in HAND_LOWERED {
            let declared = ["(", "["]
                .iter()
                .any(|open| stdlib.contains(&format!("extern fn {}{open}", h.symbol)));
            assert!(
                declared,
                "{} is not declared by any stdlib extern",
                h.symbol
            );
        }
    }

    #[test]
    fn symbols_and_identities_are_unique() {
        for (i, a) in HAND_LOWERED.iter().enumerate() {
            for b in &HAND_LOWERED[i + 1..] {
                assert_ne!(a.symbol, b.symbol);
                assert_ne!(a.identity, b.identity);
            }
        }
    }
}
