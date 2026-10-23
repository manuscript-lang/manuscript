//! Runtime fault and profile tables for LLVM-built functions.
//!
//! The runtime resolves a program counter to `function, line, inlined scopes` through the
//! `ms.tables` blob (`crates/ms-rt/ABI.md`). Cranelift reports code offsets while compiling;
//! with LLVM the code layout is only known after optimization, so the tables are rebuilt from
//! the DWARF line program and inlined-subroutine DIEs that LLVM emits for the debug metadata
//! in [`crate::llvm_ir`]. LLVM's own inlining appears as inlined scopes, exactly like the
//! scopes the MIR inliner records, so fault traces keep every source frame.

use crate::Error;
use crate::cg::{FuncDbg, LlvmFn};
use crate::llvm_ir::TEXT_ANCHOR;
use cranelift_object::object::{
    BinaryFormat, File, Object as _, ObjectSection as _, ObjectSymbol as _, RelocationKind,
    RelocationTarget, SectionIndex, SectionKind,
};
use gimli::{EndianSlice, RunTimeEndian};
use ms_mir::ir::Scope;
use std::collections::HashMap;
use std::path::Path;

type R<'a> = EndianSlice<'a, RunTimeEndian>;

fn err(what: &str, e: impl std::fmt::Display) -> Error {
    Error(format!("LLVM debug tables: {what}: {e}"))
}

/// One inlined-callee DIE: address ranges and its scope id.
struct Inlined {
    ranges: Vec<(u64, u64)>,
    id: u32,
    depth: u32,
}

/// The tables rebuilt from the LLVM object.
pub struct Tables {
    pub dbg: Vec<FuncDbg>,
    pub scopes: Vec<Scope>,
}

/// Code addresses for an unlinked object: its code sections laid end to end, so every function
/// and every address the DWARF names get the same offsets the final link keeps within the
/// object's own code.
struct Layout {
    delta: HashMap<SectionIndex, u64>,
}

impl Layout {
    fn new(obj: &File) -> Self {
        let mut delta = HashMap::new();
        let mut next = 0u64;
        for s in obj.sections().filter(|s| s.kind() == SectionKind::Text) {
            let align = s.align().max(1);
            next = next.div_ceil(align) * align;
            delta.insert(s.index(), next.wrapping_sub(s.address()));
            next += s.size();
        }
        Layout { delta }
    }

    fn place(&self, section: Option<SectionIndex>, address: u64) -> u64 {
        let delta = section.and_then(|s| self.delta.get(&s)).copied();
        address.wrapping_add(delta.unwrap_or(0))
    }
}

/// The DWARF sections of `obj` by their ELF names, with the object's relocations applied so
/// code addresses are final within the object (the linker would otherwise do this).
fn dwarf_sections(obj: &File, layout: &Layout) -> Result<HashMap<String, Vec<u8>>, Error> {
    let little = obj.is_little_endian();
    let mut out = HashMap::new();
    for section in obj.sections() {
        let Ok(name) = section.name() else { continue };
        let name = match name.strip_prefix("__debug_") {
            Some(rest) => format!(".debug_{rest}"),
            None => name.to_string(),
        };
        if !name.starts_with(".debug_") {
            continue;
        }
        let mut data = section
            .uncompressed_data()
            .map_err(|e| err("section data", e))?
            .into_owned();
        for (offset, rel) in section.relocations() {
            let size = usize::from(rel.size() / 8);
            let at = offset as usize;
            if !matches!(
                rel.kind(),
                RelocationKind::Absolute | RelocationKind::SectionOffset
            ) || !matches!(size, 4 | 8)
            {
                return Err(err(
                    "relocation",
                    format!(
                        "{name}: unsupported {:?} of {} bits",
                        rel.kind(),
                        rel.size()
                    ),
                ));
            }
            let field = data
                .get_mut(at..at + size)
                .ok_or_else(|| err("relocation", format!("{name}: offset out of range")))?;
            let mut raw = [0u8; 8];
            let addend = if rel.has_implicit_addend() {
                raw[..size].copy_from_slice(field);
                let v = if little {
                    u64::from_le_bytes(raw)
                } else {
                    u64::from_be_bytes(raw) >> (8 * (8 - size))
                };
                // Sign-extend the in-place value.
                let shift = 64 - 8 * size as u32;
                (((v << shift) as i64) >> shift) as u64
            } else {
                rel.addend() as u64
            };
            // An absolute field takes the target's final address; a section offset (COFF
            // `SECREL`) its offset within its own section.
            let section_offset = rel.kind() == RelocationKind::SectionOffset;
            let target = match rel.target() {
                RelocationTarget::Symbol(i) => {
                    let sym = obj
                        .symbol_by_index(i)
                        .map_err(|e| err("relocation symbol", e))?;
                    match sym.section_index() {
                        Some(sec) if section_offset => {
                            let base = obj
                                .section_by_index(sec)
                                .map_err(|e| err("section", e))?
                                .address();
                            sym.address().wrapping_sub(base)
                        }
                        sec => layout.place(sec, sym.address()),
                    }
                }
                RelocationTarget::Section(i) if section_offset => {
                    let _ = i;
                    0
                }
                RelocationTarget::Section(i) => {
                    let sec = obj.section_by_index(i).map_err(|e| err("section", e))?;
                    layout.place(Some(i), sec.address())
                }
                _ => 0,
            };
            let value = target.wrapping_add(addend);
            if little {
                field.copy_from_slice(&value.to_le_bytes()[..size]);
            } else {
                field.copy_from_slice(&value.to_be_bytes()[8 - size..]);
            }
        }
        out.insert(name, data);
    }
    Ok(out)
}

/// Rebuilds the tables from the DWARF in the object file `object`.
pub fn read(
    object: &Path,
    funcs: &[LlvmFn],
    files: &[String],
    anchored: bool,
) -> Result<Tables, Error> {
    let bytes = std::fs::read(object).map_err(|e| err("read object", e))?;
    let obj = File::parse(bytes.as_slice()).map_err(|e| err("parse", e))?;
    let endian = if obj.is_little_endian() {
        RunTimeEndian::Little
    } else {
        RunTimeEndian::Big
    };
    let layout = Layout::new(&obj);
    let sections = dwarf_sections(&obj, &layout)?;
    // Function address ranges by symbol.
    let by_symbol: HashMap<&str, usize> = funcs
        .iter()
        .enumerate()
        .map(|(i, f)| (f.symbol.as_str(), i))
        .collect();
    let mut placed: Vec<Option<(u64, u64)>> = vec![None; funcs.len()];
    let mut section_of: Vec<Option<SectionIndex>> = vec![None; funcs.len()];
    let mut anchor: Option<(SectionIndex, u64)> = None;
    // Mach-O symbols carry no size: a function runs to the next symbol of its section.
    let mut starts: HashMap<SectionIndex, Vec<u64>> = HashMap::new();
    for s in obj.symbols() {
        if let Some(sec) = s.section_index() {
            starts.entry(sec).or_default().push(s.address());
        }
    }
    for v in starts.values_mut() {
        v.sort_unstable();
        v.dedup();
    }
    for s in obj.symbols() {
        let Ok(name) = s.name() else { continue };
        // Mach-O prefixes C symbols with an underscore.
        let name = match name.strip_prefix('_') {
            Some(rest) if obj.format() == BinaryFormat::MachO => rest,
            _ => name,
        };
        if name == TEXT_ANCHOR {
            anchor = s
                .section_index()
                .map(|sec| (sec, layout.place(Some(sec), s.address())));
        }
        let (Some(&i), Some(sec)) = (by_symbol.get(name), s.section_index()) else {
            continue;
        };
        let size = if s.size() > 0 {
            s.size()
        } else {
            let end = starts
                .get(&sec)
                .and_then(|v| v.get(v.partition_point(|a| *a <= s.address())).copied());
            let section = obj.section_by_index(sec).map_err(|e| err("section", e))?;
            end.unwrap_or(section.address() + section.size()) - s.address()
        };
        if size > 0 {
            placed[i] = Some((layout.place(Some(sec), s.address()), size));
            section_of[i] = Some(sec);
        }
    }
    let load = |id: gimli::SectionId| -> Result<R<'_>, gimli::Error> {
        let data = sections.get(id.name()).map_or(&[][..], Vec::as_slice);
        Ok(EndianSlice::new(data, endian))
    };
    let dwarf = gimli::Dwarf::load(load).map_err(|e| err("sections", e))?;
    let file_index = |path: &str| -> u32 {
        files
            .iter()
            .position(|f| f == path)
            .map_or(u32::MAX, |i| i as u32)
    };
    let mut scopes: Vec<Scope> = Vec::new();
    let mut inlined: Vec<Inlined> = Vec::new();
    let mut rows: Vec<(u64, u32, u32)> = Vec::new();
    let mut units = dwarf.units();
    while let Some(header) = units.next().map_err(|e| err("units", e))? {
        let unit = dwarf.unit(header).map_err(|e| err("unit", e))?;
        let line_program = unit.line_program.clone();
        let full_path = |header: &gimli::LineProgramHeader<R>, index: u64| -> Option<String> {
            let entry = header.file(index)?;
            let name = dwarf.attr_string(&unit, entry.path_name()).ok()?;
            let name = name.to_string_lossy().into_owned();
            // LLVM splits `dir/name` into a directory entry and a base name (index 0 is the
            // compilation directory, which the source names are relative to).
            match entry.directory(header) {
                Some(d) if entry.directory_index() != 0 => {
                    let dir = dwarf.attr_string(&unit, d).ok()?;
                    Some(format!("{}/{name}", dir.to_string_lossy()))
                }
                _ => Some(name),
            }
        };
        let path_of = |index: u64| -> u32 {
            let Some(lp) = &line_program else {
                return u32::MAX;
            };
            full_path(lp.header(), index).map_or(u32::MAX, |p| file_index(&p))
        };
        // Walk the DIE tree: subprograms are physical functions; inlined subroutines nest.
        let mut stack: Vec<(isize, u32)> = Vec::new(); // (depth, scope id; 0 = function)
        let mut cursor = unit.entries();
        while let Some(entry) = cursor.next_dfs().map_err(|e| err("entries", e))? {
            let depth = entry.depth();
            while stack.last().is_some_and(|(d, _)| *d >= depth) {
                stack.pop();
            }
            match entry.tag() {
                gimli::DW_TAG_subprogram => stack.push((depth, 0)),
                gimli::DW_TAG_inlined_subroutine => {
                    let parent = stack.last().map_or(0, |s| s.1);
                    let origin = entry.attr_value(gimli::DW_AT_abstract_origin);
                    let (mut name, mut file) = (String::new(), u32::MAX);
                    if let Some(gimli::AttributeValue::UnitRef(off)) = origin {
                        let o = unit.entry(off).map_err(|e| err("origin entry", e))?;
                        if let Some(n) = o.attr_value(gimli::DW_AT_name)
                            && let Ok(s) = dwarf.attr_string(&unit, n)
                        {
                            name = s.to_string_lossy().into_owned();
                        }
                        if let Some(gimli::AttributeValue::FileIndex(i)) =
                            o.attr_value(gimli::DW_AT_decl_file)
                        {
                            file = path_of(i);
                        }
                    }
                    let call_line = match entry.attr_value(gimli::DW_AT_call_line) {
                        Some(gimli::AttributeValue::Udata(l)) => l as u32,
                        _ => 0,
                    };
                    scopes.push(Scope {
                        name,
                        file,
                        parent,
                        call_line,
                    });
                    let id = scopes.len() as u32;
                    let mut ranges = Vec::new();
                    let mut it = dwarf
                        .die_ranges(&unit, entry)
                        .map_err(|e| err("ranges", e))?;
                    while let Some(r) = it.next().map_err(|e| err("range", e))? {
                        if r.begin < r.end {
                            ranges.push((r.begin, r.end));
                        }
                    }
                    inlined.push(Inlined {
                        ranges,
                        id,
                        depth: stack.len() as u32,
                    });
                    stack.push((depth, id));
                }
                _ => {}
            }
        }
        // Line rows: (address, line, file) in program order, 0 line ends nothing useful.
        if let Some(lp) = line_program {
            let mut r = lp.rows();
            while let Some((header, row)) = r.next_row().map_err(|e| err("rows", e))? {
                if row.end_sequence() {
                    rows.push((row.address(), 0, u32::MAX));
                    continue;
                }
                let line = row.line().map_or(0, |l| l.get() as u32);
                let file = full_path(header, row.file_index()).map_or(u32::MAX, |p| file_index(&p));
                rows.push((row.address(), line, file));
            }
        }
    }
    // Functions are addressed from the anchor, which only works inside its own code section.
    let (anchor_sec, anchor_at) = match anchor {
        Some(a) => a,
        None if anchored => {
            return Err(err("anchor", format!("{TEXT_ANCHOR} is not in the object")));
        }
        None => (SectionIndex(0), 0),
    };
    if anchored
        && let Some(i) = section_of
            .iter()
            .position(|s| s.is_some_and(|s| s != anchor_sec))
    {
        return Err(err(
            "layout",
            format!(
                "{} is in another code section than {TEXT_ANCHOR}",
                funcs[i].name
            ),
        ));
    }
    // Assemble per-function range lists.
    let mut dbg: Vec<FuncDbg> = funcs
        .iter()
        .enumerate()
        .filter_map(|(i, f)| {
            placed[i].map(|(addr, size)| FuncDbg {
                id: f.id,
                name: f.name.clone(),
                file: f.file,
                line: f.line,
                size: size as u32,
                ranges: Vec::new(),
                dwarf_ranges: Vec::new(),
                text: if anchored {
                    addr.wrapping_sub(anchor_at)
                } else {
                    0
                },
            })
        })
        .collect();
    let mut dbg_of: Vec<Option<usize>> = Vec::with_capacity(funcs.len());
    let mut n = 0;
    for p in &placed {
        dbg_of.push(p.map(|_| {
            n += 1;
            n - 1
        }));
    }
    let mut spans: Vec<(u64, u64, usize)> = placed
        .iter()
        .enumerate()
        .filter_map(|(i, p)| p.map(|(a, s)| (a, a + s, dbg_of[i].expect("placed"))))
        .collect();
    spans.sort();
    let function_at = |addr: u64| -> Option<(u64, usize)> {
        let i = spans.partition_point(|s| s.0 <= addr);
        let s = spans.get(i.checked_sub(1)?)?;
        (addr < s.1).then_some((s.0, s.2))
    };
    let scope_at = |addr: u64| -> u32 {
        inlined
            .iter()
            .filter(|s| s.ranges.iter().any(|r| r.0 <= addr && addr < r.1))
            .max_by_key(|s| s.depth)
            .map_or(0, |s| s.id)
    };
    // Cut points: every row start and every inlined-range boundary, so a range never spans a
    // change of scope. A point takes its line from the row covering it.
    let mut points: Vec<u64> = rows.iter().map(|r| r.0).collect();
    for s in &inlined {
        for r in &s.ranges {
            points.push(r.0);
            points.push(r.1);
        }
    }
    points.sort_unstable();
    points.dedup();
    // Rows are in program order per sequence; a sequence's end row has file `u32::MAX`.
    let mut sorted_rows = rows.clone();
    sorted_rows.sort_by_key(|r| r.0);
    for addr in points {
        let Some((start, d)) = function_at(addr) else {
            continue;
        };
        let i = sorted_rows.partition_point(|r| r.0 <= addr);
        let Some(&(_, mut line, mut file)) = i.checked_sub(1).and_then(|i| sorted_rows.get(i))
        else {
            continue;
        };
        let mut scope = scope_at(addr);
        // Code without a position inside an inlined callee (a thunk, glue) belongs to the
        // call site that gave it a position.
        while line == 0 && scope != 0 {
            let sc = &scopes[scope as usize - 1];
            line = sc.call_line;
            scope = sc.parent;
        }
        if line == 0 {
            continue;
        }
        let ranges = &mut dbg[d].ranges;
        let off = (addr - start) as u32;
        if file == u32::MAX {
            file = ranges.last().map_or(u32::MAX, |l| l.1);
        }
        if ranges
            .last()
            .is_none_or(|l| (l.1, l.2, l.3) != (file, line, scope))
        {
            ranges.push((off, file, line, scope));
        }
    }
    for d in &mut dbg {
        // A function without a position of its own borrows the first file its lines name.
        if d.file == u32::MAX {
            let first = d.ranges.iter().map(|r| r.1).find(|f| *f != u32::MAX);
            d.file = first.unwrap_or(u32::MAX);
            d.line = 0;
        }
        d.ranges.sort_by_key(|r| r.0);
        d.ranges.dedup_by(|b, a| (a.1, a.2, a.3) == (b.1, b.2, b.3));
    }
    if std::env::var_os("MS_DEBUG_TABLES").is_some() {
        for (i, sc) in scopes.iter().enumerate() {
            eprintln!("scope {} {:?}", i + 1, sc);
        }
        for d in &dbg {
            eprintln!(
                "fn {} file={} line={} size={} ranges={:?}",
                d.name, d.file, d.line, d.size, d.ranges
            );
        }
    }
    Ok(Tables { dbg, scopes })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::link::llvm_tools;
    use cranelift_module::FuncId;
    use std::collections::BTreeSet;
    use std::process::Command;

    fn lines_for(triple: &str) -> Option<(BTreeSet<u32>, usize)> {
        let tools = llvm_tools().ok()??;
        let dir = std::env::temp_dir().join(format!("ms-tables-{}-{triple}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let object = dir.join("m.o");
        let fixture = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/data/tables.ll");
        let status = Command::new(tools.join("llc"))
            .args(["-O2", "-filetype=obj", "-relocation-model=pic"])
            .arg(format!("-mtriple={triple}"))
            .arg(fixture)
            .arg("-o")
            .arg(&object)
            .output()
            .unwrap();
        assert!(status.status.success(), "llc {triple}: {status:?}");
        let funcs: Vec<LlvmFn> = ["ms_entry", "sum_squares#1"]
            .iter()
            .enumerate()
            .map(|(i, symbol)| LlvmFn {
                id: FuncId::from_u32(i as u32),
                symbol: (*symbol).into(),
                name: (*symbol).into(),
                file: 0,
                line: 0,
            })
            .collect();
        let tables = read(&object, &funcs, &["src/main.ms".to_string()], true)
            .unwrap_or_else(|e| panic!("{triple}: {e:?}"));
        let _ = std::fs::remove_dir_all(&dir);
        let mut lines = BTreeSet::new();
        for d in &tables.dbg {
            assert!(!d.ranges.is_empty(), "{triple}: {} has no lines", d.name);
            for r in &d.ranges {
                assert!(r.0 < d.size, "{triple}: {} range past its end", d.name);
                assert_eq!(r.1, 0, "{triple}: file");
                lines.insert(r.2);
            }
        }
        Some((lines, tables.scopes.len()))
    }

    /// The line tables come out the same from ELF, Mach-O and COFF objects: relocations are
    /// applied and symbols placed the way the linker would.
    #[test]
    fn tables_agree_across_object_formats() {
        // The bundled tools only carry the backend of the machine they run on.
        let arch = std::env::consts::ARCH;
        let Some(elf) = lines_for(&format!("{arch}-unknown-linux-gnu")) else {
            return;
        };
        assert!(elf.0.contains(&4) && elf.0.contains(&21), "{:?}", elf.0);
        assert!(elf.1 > 0, "inlined scopes");
        for triple in [
            format!("{arch}-apple-darwin"),
            format!("{arch}-w64-windows-gnu"),
        ] {
            let got = lines_for(&triple).unwrap();
            assert_eq!(got.0, elf.0, "{triple}: lines");
            assert_eq!(got.1, elf.1, "{triple}: scopes");
        }
    }
}
