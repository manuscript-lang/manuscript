//! Link-time stand-ins for the macOS system libraries. Apple's SDK is not redistributable and is
//! absent without Xcode tools, so the stubs (`.tbd` text files, which `lld` reads like the real
//! ones) are generated: they export exactly the symbols the program and runtime import but do not
//! define. At run time dyld binds those names in the real libSystem, Security and CoreFoundation.

use crate::Error;
use object::read::archive::ArchiveFile;
use object::{Object as _, ObjectSymbol as _};
use std::collections::BTreeSet;
use std::path::Path;

/// Writes `usr/lib/libSystem.tbd` and the two framework stubs under `sdk`.
pub fn write(sdk: &Path, arch: &str, object: &Path, inputs: &[&Path]) -> Result<(), Error> {
    let mut defined = BTreeSet::new();
    let mut undefined = BTreeSet::new();
    for path in std::iter::once(&object).chain(inputs) {
        let bytes = std::fs::read(path)
            .map_err(|e| Error(format!("cannot read {}: {e}", path.display())))?;
        if let Ok(archive) = ArchiveFile::parse(bytes.as_slice()) {
            for member in archive.members().flatten() {
                if let Ok(data) = member.data(bytes.as_slice()) {
                    collect(data, &mut defined, &mut undefined);
                }
            }
        } else {
            collect(&bytes, &mut defined, &mut undefined);
        }
    }
    let target = format!("{arch}-macos");
    let mut system = Vec::new();
    let mut security = Vec::new();
    let mut core_foundation = Vec::new();
    for name in undefined.difference(&defined) {
        match name.as_str() {
            n if n.starts_with("_Sec") || n.starts_with("_kSec") => security.push(n),
            n if n.starts_with("_CF") || n.starts_with("_kCF") => core_foundation.push(n),
            n => system.push(n),
        }
    }
    let io = |e: std::io::Error| Error(format!("cannot write the SDK stubs: {e}"));
    let framework = |name: &str| sdk.join(format!("System/Library/Frameworks/{name}.framework"));
    std::fs::create_dir_all(sdk.join("usr/lib")).map_err(io)?;
    std::fs::create_dir_all(framework("Security")).map_err(io)?;
    std::fs::create_dir_all(framework("CoreFoundation")).map_err(io)?;
    std::fs::write(
        sdk.join("usr/lib/libSystem.tbd"),
        tbd(&target, "/usr/lib/libSystem.B.dylib", &system),
    )
    .map_err(io)?;
    for (name, symbols) in [
        ("Security", &security),
        ("CoreFoundation", &core_foundation),
    ] {
        let install = format!("/System/Library/Frameworks/{name}.framework/Versions/A/{name}");
        std::fs::write(
            framework(name).join(format!("{name}.tbd")),
            tbd(&target, &install, symbols),
        )
        .map_err(io)?;
    }
    Ok(())
}

fn collect(data: &[u8], defined: &mut BTreeSet<String>, undefined: &mut BTreeSet<String>) {
    let Ok(file) = object::File::parse(data) else {
        return;
    };
    for symbol in file.symbols() {
        let Ok(name) = symbol.name() else { continue };
        if name.is_empty() || !symbol.is_global() {
            continue;
        }
        if symbol.is_undefined() {
            undefined.insert(name.to_string());
        } else {
            defined.insert(name.to_string());
        }
    }
}

/// One text-based dylib stub (TAPI v4) exporting `symbols`.
fn tbd(target: &str, install_name: &str, symbols: &[&str]) -> String {
    let mut text = format!(
        "--- !tapi-tbd\ntbd-version: 4\ntargets: [ {target} ]\ninstall-name: '{install_name}'\ncurrent-version: 1\nexports:\n  - targets: [ {target} ]\n    symbols: ["
    );
    for (index, symbol) in symbols.iter().enumerate() {
        text.push_str(if index == 0 {
            "\n      '"
        } else {
            ",\n      '"
        });
        text.push_str(symbol);
        text.push('\'');
    }
    text.push_str(" ]\n...\n");
    text
}
