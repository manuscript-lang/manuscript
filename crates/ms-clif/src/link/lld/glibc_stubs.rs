//! Link-time stand-ins for glibc's shared libraries. Linking against the build machine's `libc.so.6`
//! would make its glibc the program's minimum, so programs link against stubs generated from glibc
//! 2.28's ABI (`toolchain/glibc/<arch>.symbols`) instead: each stub exports every symbol of its library
//! at the newest version 2.28 has, so the program asks the loader for nothing newer. At run time the
//! loader binds those names and versions in the real glibc, which keeps old versions forever.

use crate::Error;
use object::write::{Object, StandardSection, Symbol, SymbolSection};
use object::{Architecture, BinaryFormat, Endianness, SymbolFlags, SymbolKind, SymbolScope};
use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The libraries in the order the program lists them: libpthread comes first so that, on glibc
/// before 2.34, its definitions of names libc also exports win, as with `cc -lpthread`.
pub fn libraries() -> [&'static str; 6] {
    [
        "libpthread.so.0",
        "libc.so.6",
        "libm.so.6",
        "libdl.so.2",
        "librt.so.1",
        loader_name(),
    ]
}

/// The file name of glibc's dynamic loader, which exports a few symbols of its own.
fn loader_name() -> &'static str {
    if cfg!(target_arch = "aarch64") {
        "ld-linux-aarch64.so.1"
    } else {
        "ld-linux-x86-64.so.2"
    }
}

/// The loader's absolute path, recorded in the program.
pub fn loader() -> &'static str {
    if cfg!(target_arch = "aarch64") {
        "/lib/ld-linux-aarch64.so.1"
    } else {
        "/lib64/ld-linux-x86-64.so.2"
    }
}

/// One exported symbol: its version, and its size when it is data (copy relocations need it).
struct Export<'a> {
    version: &'a str,
    name: &'a str,
    data: Option<u64>,
}

/// The stub directory under the unpacked linker `dir`, generated with `lld` on first use.
pub fn stubs(dir: &Path, lld: &Path) -> Result<PathBuf, Error> {
    let out = dir.join("glibc");
    if out.join(".ok").is_file() {
        return Ok(out);
    }
    let failed = |what: &str, e: &dyn std::fmt::Display| {
        Error(format!(
            "cannot {what} the glibc stubs in {}: {e}",
            out.display()
        ))
    };
    let table = std::fs::read_to_string(dir.join("glibc.symbols"))
        .map_err(|e| failed("read the symbol table for", &e))?;
    let mut libraries: BTreeMap<&str, Vec<Export>> = BTreeMap::new();
    for line in table
        .lines()
        .filter(|l| !l.starts_with('#') && !l.is_empty())
    {
        let fields: Vec<&str> = line.split_whitespace().collect();
        let [soname, version, name, kind, rest @ ..] = fields.as_slice() else {
            return Err(failed("parse", &format!("bad line {line:?}")));
        };
        let data = match (*kind, rest) {
            ("D", [size]) => Some(
                u64::from_str_radix(size.trim_start_matches("0x"), 16)
                    .map_err(|e| failed("parse", &e))?,
            ),
            _ => None,
        };
        libraries.entry(soname).or_default().push(Export {
            version,
            name,
            data,
        });
    }
    // Staged beside the destination so concurrent builds never see a partial set.
    let stage = dir.join(format!(".glibc-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&stage);
    std::fs::create_dir_all(&stage).map_err(|e| failed("create", &e))?;
    let result = (|| {
        for (soname, exports) in &libraries {
            build(&stage, lld, soname, exports)?;
        }
        std::fs::write(stage.join(".ok"), b"").map_err(|e| failed("finish", &e))
    })();
    if result.is_ok() && std::fs::rename(&stage, &out).is_err() && !out.join(".ok").is_file() {
        let _ = std::fs::remove_dir_all(&stage);
        return Err(failed(
            "install",
            &"the directory could not be moved into place",
        ));
    }
    let _ = std::fs::remove_dir_all(&stage);
    result.map(|()| out)
}

/// Links one stub library: an object defining every export, versioned by a version script.
fn build(stage: &Path, lld: &Path, soname: &str, exports: &[Export]) -> Result<(), Error> {
    let arch = if cfg!(target_arch = "aarch64") {
        Architecture::Aarch64
    } else {
        Architecture::X86_64
    };
    let mut object = Object::new(BinaryFormat::Elf, arch, Endianness::Little);
    let text = object.section_id(StandardSection::Text);
    let data = object.section_id(StandardSection::Data);
    let mut versions: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    for export in exports {
        let (section, kind, size) = match export.data {
            Some(size) => (data, SymbolKind::Data, size.max(1)),
            None => (text, SymbolKind::Text, 1),
        };
        let offset = object.append_section_data(section, &vec![0; size as usize], 8);
        object.add_symbol(Symbol {
            name: export.name.as_bytes().to_vec(),
            value: offset,
            size: export.data.unwrap_or(0),
            kind,
            scope: SymbolScope::Dynamic,
            weak: false,
            section: SymbolSection::Section(section),
            flags: SymbolFlags::None,
        });
        versions
            .entry(export.version)
            .or_default()
            .push(export.name);
    }
    let io = |e: &dyn std::fmt::Display| Error(format!("cannot write the {soname} stub: {e}"));
    let bytes = object.write().map_err(|e| io(&e))?;
    let input = stage.join(format!("{soname}.o"));
    std::fs::write(&input, bytes).map_err(|e| io(&e))?;
    let mut script = String::new();
    for (version, names) in &versions {
        let _ = writeln!(script, "{version} {{ global: {}; }};", names.join("; "));
    }
    let script_path = stage.join(format!("{soname}.map"));
    std::fs::write(&script_path, script).map_err(|e| io(&e))?;
    let output = Command::new(lld)
        .args(["-flavor", "gnu", "-shared", "-soname", soname])
        .arg("--version-script")
        .arg(&script_path)
        .arg("-o")
        .arg(stage.join(soname))
        .arg(&input)
        .output()
        .map_err(|e| io(&e))?;
    let _ = std::fs::remove_file(&input);
    let _ = std::fs::remove_file(&script_path);
    if !output.status.success() {
        return Err(io(&String::from_utf8_lossy(&output.stderr).trim_end()));
    }
    Ok(())
}
