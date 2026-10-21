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
use cranelift_object::object::{Object as _, ObjectSection as _, ObjectSymbol as _};
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

/// The tables rebuilt from the linked image `image`.
pub struct Tables {
    pub dbg: Vec<FuncDbg>,
    pub scopes: Vec<Scope>,
}

pub fn read(image: &Path, funcs: &[LlvmFn], files: &[String]) -> Result<Tables, Error> {
    let bytes = std::fs::read(image).map_err(|e| err("read image", e))?;
    let obj =
        cranelift_object::object::File::parse(bytes.as_slice()).map_err(|e| err("parse", e))?;
    let endian = if obj.is_little_endian() {
        RunTimeEndian::Little
    } else {
        RunTimeEndian::Big
    };
    // Function address ranges by symbol.
    let by_symbol: HashMap<&str, usize> = funcs
        .iter()
        .enumerate()
        .map(|(i, f)| (f.symbol.as_str(), i))
        .collect();
    let mut placed: Vec<Option<(u64, u64)>> = vec![None; funcs.len()];
    for s in obj.symbols() {
        let Ok(name) = s.name() else { continue };
        if let Some(&i) = by_symbol.get(name)
            && s.size() > 0
        {
            placed[i] = Some((s.address(), s.size()));
        }
    }
    let load = |id: gimli::SectionId| -> Result<R<'_>, gimli::Error> {
        let data = obj
            .section_by_name(id.name())
            .and_then(|s| s.data().ok())
            .unwrap_or(&[]);
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
    // Assemble per-function range lists.
    let mut dbg: Vec<FuncDbg> = funcs
        .iter()
        .enumerate()
        .filter_map(|(i, f)| {
            placed[i].map(|(_, size)| FuncDbg {
                id: f.id,
                name: f.name.clone(),
                file: f.file,
                line: f.line,
                size: size as u32,
                ranges: Vec::new(),
                dwarf_ranges: Vec::new(),
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
