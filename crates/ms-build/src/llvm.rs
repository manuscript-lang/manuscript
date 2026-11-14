//! Release builds: `ms-mir-llvm` writes the program as LLVM IR, the pinned LLVM tools compile it, the
//! fault and profile tables are rebuilt from the objects' DWARF, and one more module holds `main`
//! and those tables. Cranelift takes no part.

pub(crate) mod obj;
mod tables;

pub use obj::available;

use ms_clif::{BuildOptions, Error};
use ms_mir::ir::Module;

/// The LLVM target triple of this host. Windows executables link over the mingw-w64 CRT, so the
/// code must follow its conventions rather than MSVC's.
fn host_triple() -> Result<String, Error> {
    let arch = std::env::consts::ARCH;
    match std::env::consts::OS {
        "linux" => Ok(format!("{arch}-unknown-linux-gnu")),
        "macos" => Ok(format!("{arch}-apple-darwin")),
        "windows" => Ok(format!("{arch}-w64-windows-gnu")),
        os => Err(Error(format!("no LLVM target for {os}"))),
    }
}

/// Compiles `m` to relocatable objects at LLVM level `level` (`"3"` or `"s"`).
pub fn compile(
    m: &Module,
    checks: bool,
    level: &str,
    build: &BuildOptions,
) -> Result<Vec<Vec<u8>>, Error> {
    let triple = host_triple()?;
    let program = ms_mir_llvm::emit(
        m,
        &ms_mir_llvm::Options {
            checks,
            heap_facts: build.heap_facts,
            units: build.llvm_units,
            triple: triple.clone(),
            // Mach-O links with `-dead_strip` and one atom per function, so offsets within the
            // object's code do not survive the link; COFF linkers reject the undefined symbol
            // that an object declares for each function it never references. Both keep a visible
            // symbol per function, which only ELF can do without.
            anchor: std::env::consts::OS == "linux",
        },
    )
    .map_err(|e| Error(e.0))?;
    let objects = obj::compile_all(&program.units, level, build)?;
    let mut dbg = Vec::new();
    let mut scopes: Vec<ms_mir::ir::Scope> = Vec::new();
    for object in &objects {
        let t = tables::read(object.path(), &program.funcs, &m.files, program.anchored)?;
        // Scope ids count from one within an object.
        let base = scopes.len() as u32;
        for mut d in t.dbg {
            if base != 0 {
                for r in &mut d.ranges {
                    if r.3 != 0 {
                        r.3 += base;
                    }
                }
            }
            dbg.push(d);
        }
        scopes.extend(t.scopes.into_iter().map(|mut sc| {
            if sc.parent != 0 {
                sc.parent += base;
            }
            sc
        }));
    }
    let mut out = objects
        .iter()
        .map(obj::LlvmObject::bytes)
        .collect::<Result<Vec<_>, _>>()?;
    drop(objects);
    if let Some(unit) = ms_mir_llvm::tables_unit(m, &dbg, &scopes, program.anchored, &triple) {
        let main = obj::compile_numbered(
            std::slice::from_ref(&unit),
            level,
            build,
            program.units.len(),
        )?;
        out.push(main[0].bytes()?);
    }
    Ok(out)
}
