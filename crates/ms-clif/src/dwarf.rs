//! Minimal DWARF4: source attribution, and a DIE for every Manuscript type (`debug_types`) so a
//! debugger can print a `String`, list, map, record, enum or optional at an address, a DIE per
//! named parameter and local with a location list, and a frame DIE per inlined callee.
//! The runtime's independent fault/profile tables remain unchanged.

use crate::Error;
use crate::cg::{FuncDbg, VarDbg, VarLoc};
use cranelift_object::ObjectProduct;
use cranelift_object::object::{
    BinaryFormat, RelocationEncoding, RelocationFlags, RelocationKind, SectionKind,
    write::{Relocation, StandardSegment},
};
use gimli::write::{
    Address, AttributeValue, DwarfUnit, EndianVec, Expression, LineProgram, LineString, Location,
    LocationList, Range, RangeList, RelocateWriter, Relocation as DwarfRelocation,
    RelocationTarget, Sections,
};
use gimli::{Encoding, Format, LineEncoding, RunTimeEndian};
use ms_mir::ir::{Module, Scope};
use std::collections::{BTreeMap, HashMap};

#[derive(Clone)]
struct Section {
    bytes: EndianVec<RunTimeEndian>,
    relocations: Vec<DwarfRelocation>,
}

impl RelocateWriter for Section {
    type Writer = EndianVec<RunTimeEndian>;
    fn writer(&self) -> &Self::Writer {
        &self.bytes
    }
    fn writer_mut(&mut self) -> &mut Self::Writer {
        &mut self.bytes
    }
    fn relocate(&mut self, r: DwarfRelocation) {
        self.relocations.push(r);
    }
}

/// One DIE per [`ms_mir::debug_types::DebugType`], referring to each other as the list does.
/// Returns the DIE of each MIR type, by `Ty` index.
fn emit_types(
    dwarf: &mut DwarfUnit,
    root: gimli::write::UnitEntryId,
    m: &Module,
) -> Vec<gimli::write::UnitEntryId> {
    use ms_mir::debug_types::{DebugKind, Encoding as Enc, debug_types_by_ty};
    let (types, of_ty) = debug_types_by_ty(m);
    let tags = |t: &ms_mir::debug_types::DebugType| match &t.kind {
        DebugKind::Base(_) => gimli::DW_TAG_base_type,
        DebugKind::Struct(_) => gimli::DW_TAG_structure_type,
        DebugKind::Union(_) => gimli::DW_TAG_union_type,
        DebugKind::Pointer(_) => gimli::DW_TAG_pointer_type,
    };
    let ids: Vec<_> = types
        .iter()
        .map(|t| dwarf.unit.add(root, tags(t)))
        .collect();
    for (t, &id) in types.iter().zip(&ids) {
        let entry = dwarf.unit.get_mut(id);
        entry.set(
            gimli::DW_AT_byte_size,
            AttributeValue::Udata(u64::from(t.size)),
        );
        match &t.kind {
            DebugKind::Base(e) => {
                entry.set(
                    gimli::DW_AT_name,
                    AttributeValue::String(t.name.clone().into_bytes()),
                );
                let enc = match e {
                    Enc::Bool => gimli::DW_ATE_boolean,
                    Enc::Signed => gimli::DW_ATE_signed,
                    Enc::Unsigned => gimli::DW_ATE_unsigned,
                    Enc::Float => gimli::DW_ATE_float,
                };
                entry.set(gimli::DW_AT_encoding, AttributeValue::Encoding(enc));
            }
            DebugKind::Pointer(target) => {
                entry.set(
                    gimli::DW_AT_name,
                    AttributeValue::String(t.name.clone().into_bytes()),
                );
                if let Some(target) = target {
                    entry.set(gimli::DW_AT_type, AttributeValue::UnitRef(ids[*target]));
                }
            }
            DebugKind::Struct(members) | DebugKind::Union(members) => {
                entry.set(
                    gimli::DW_AT_name,
                    AttributeValue::String(t.name.clone().into_bytes()),
                );
                for member in members {
                    let child = dwarf.unit.add(id, gimli::DW_TAG_member);
                    let child = dwarf.unit.get_mut(child);
                    child.set(
                        gimli::DW_AT_name,
                        AttributeValue::String(member.name.clone().into_bytes()),
                    );
                    child.set(gimli::DW_AT_type, AttributeValue::UnitRef(ids[member.ty]));
                    child.set(
                        gimli::DW_AT_data_member_location,
                        AttributeValue::Udata(u64::from(member.offset)),
                    );
                }
            }
        }
    }
    of_ty.into_iter().map(|i| ids[i]).collect()
}

/// Describes each inlined callee of `f` as a frame nested in the one that called it, located by
/// the code ranges its lines occupy. Returns the frame DIE of each scope that kept code.
fn emit_inlined(
    dwarf: &mut DwarfUnit,
    subprogram: gimli::write::UnitEntryId,
    symbol: usize,
    f: &FuncDbg,
    scopes: &[Scope],
    files: &[Option<gimli::write::FileId>],
    origins: &mut HashMap<String, gimli::write::UnitEntryId>,
) -> HashMap<u32, gimli::write::UnitEntryId> {
    // Every address belongs to one scope, the innermost whose lines cover it, so sibling frames
    // never overlap even when two line ranges do. A span of a scope is also a span of every
    // scope that called it.
    let mut spans: BTreeMap<u32, Vec<(u32, u32)>> = BTreeMap::new();
    let mut cuts: Vec<u32> = f.dwarf_ranges.iter().flat_map(|r| [r.0, r.1]).collect();
    cuts.sort_unstable();
    cuts.dedup();
    let mut covering: Vec<(u32, u32, u32)> = Vec::new();
    let mut next = 0;
    for w in cuts.windows(2) {
        let (begin, end) = (w[0], w[1]);
        while let Some(r) = f.dwarf_ranges.get(next)
            && r.0 <= begin
        {
            covering.push((r.0, r.1, r.4));
            next += 1;
        }
        covering.retain(|c| c.1 > begin);
        // The latest-starting range is the innermost.
        let Some(&(_, _, scope)) = covering.last() else {
            continue;
        };
        let mut s = scope;
        while s != 0 {
            let list = spans.entry(s).or_default();
            match list.last_mut() {
                Some(last) if last.1 == begin => last.1 = end,
                _ => list.push((begin, end)),
            }
            s = scopes[s as usize - 1].parent;
        }
    }
    let at = |offset: u32| Address::Symbol {
        symbol,
        addend: i64::from(offset),
    };
    let mut frames: HashMap<u32, gimli::write::UnitEntryId> = HashMap::new();
    // A caller's scope number is lower than its callee's, so it already has its frame.
    for (&s, list) in &spans {
        let scope = &scopes[s as usize - 1];
        let (parent, call_file) = match frames.get(&scope.parent) {
            Some(&p) => (p, scopes[scope.parent as usize - 1].file),
            None => (subprogram, f.file),
        };
        let origin = *origins.entry(scope.name.clone()).or_insert_with(|| {
            let root = dwarf.unit.root();
            let id = dwarf.unit.add(root, gimli::DW_TAG_subprogram);
            let die = dwarf.unit.get_mut(id);
            die.set(
                gimli::DW_AT_name,
                AttributeValue::String(scope.name.clone().into_bytes()),
            );
            die.set(
                gimli::DW_AT_inline,
                AttributeValue::Inline(gimli::DW_INL_inlined),
            );
            id
        });
        let ranges = dwarf.unit.ranges.add(RangeList(
            list.iter()
                .map(|&(begin, end)| Range::StartEnd {
                    begin: at(begin),
                    end: at(end),
                })
                .collect(),
        ));
        let id = dwarf.unit.add(parent, gimli::DW_TAG_inlined_subroutine);
        let die = dwarf.unit.get_mut(id);
        die.set(
            gimli::DW_AT_abstract_origin,
            AttributeValue::UnitRef(origin),
        );
        die.set(gimli::DW_AT_ranges, AttributeValue::RangeListRef(ranges));
        if let Some(Some(file)) = files.get(call_file as usize) {
            die.set(
                gimli::DW_AT_call_file,
                AttributeValue::FileIndex(Some(*file)),
            );
        }
        die.set(
            gimli::DW_AT_call_line,
            AttributeValue::Udata(u64::from(scope.call_line)),
        );
        frames.insert(s, id);
    }
    frames
}

/// Describes the named values of `f` as parameter and variable DIEs, each located by a list over the function.
fn emit_vars(
    dwarf: &mut DwarfUnit,
    subprogram: gimli::write::UnitEntryId,
    symbol: usize,
    size: u32,
    vars: &[VarDbg],
    frames: &HashMap<u32, gimli::write::UnitEntryId>,
    type_dies: &[gimli::write::UnitEntryId],
) {
    let mut frame = Expression::new();
    frame.op(gimli::DW_OP_call_frame_cfa);
    dwarf
        .unit
        .get_mut(subprogram)
        .set(gimli::DW_AT_frame_base, AttributeValue::Exprloc(frame));
    let at = |offset: u32| Address::Symbol {
        symbol,
        addend: i64::from(offset),
    };
    for v in vars {
        // A value of an inlined callee belongs to that callee's frame, when the code kept one.
        let parent = if v.scope == 0 {
            subprogram
        } else if let Some(&frame) = frames.get(&v.scope) {
            frame
        } else {
            continue;
        };
        // Split the code at every point where any leaf changes place, so each segment's
        // expression names one place per leaf.
        let mut cuts: Vec<u32> = v
            .pieces
            .iter()
            .flat_map(|p| p.ranges.iter().flat_map(|r| [r.0, r.1]))
            .filter(|&c| c <= size)
            .collect();
        cuts.sort_unstable();
        cuts.dedup();
        // Each leaf's ranges are in code order, so one cursor per leaf finds its place in a
        // segment without searching. A cut another leaf made does not change this one, so equal
        // neighbouring segments join before any expression is built.
        let mut cursor = vec![0usize; v.pieces.len()];
        let mut segments: Vec<(u32, u32, Vec<Option<VarLoc>>)> = Vec::new();
        for w in cuts.windows(2) {
            let (begin, end) = (w[0], w[1]);
            let places: Vec<Option<VarLoc>> = v
                .pieces
                .iter()
                .zip(&mut cursor)
                .map(|(p, at_range)| {
                    while p.ranges.get(*at_range).is_some_and(|r| r.1 <= begin) {
                        *at_range += 1;
                    }
                    p.ranges
                        .get(*at_range)
                        .filter(|r| r.0 <= begin && end <= r.1)
                        .map(|r| r.2)
                })
                .collect();
            if places.iter().all(Option::is_none) {
                continue;
            }
            match segments.last_mut() {
                Some(last) if last.1 == begin && last.2 == places => last.1 = end,
                _ => segments.push((begin, end, places)),
            }
        }
        let list: Vec<Location> = segments
            .into_iter()
            .map(|(begin, end, places)| {
                let mut expr = Expression::new();
                let mut next = 0;
                for (p, place) in v.pieces.iter().zip(places) {
                    if p.offset > next {
                        expr.op_piece(u64::from(p.offset - next));
                    }
                    match place {
                        Some(VarLoc::Reg(r)) => expr.op_reg(gimli::Register(r)),
                        Some(VarLoc::Cfa(o)) => expr.op_fbreg(o),
                        None => {}
                    }
                    expr.op_piece(u64::from(p.size));
                    next = p.offset + p.size;
                }
                Location::StartEnd {
                    begin: at(begin),
                    end: at(end),
                    data: expr,
                }
            })
            .collect();
        let tag = if v.param {
            gimli::DW_TAG_formal_parameter
        } else {
            gimli::DW_TAG_variable
        };
        let param_id = dwarf.unit.add(parent, tag);
        let param = dwarf.unit.get_mut(param_id);
        param.set(
            gimli::DW_AT_name,
            AttributeValue::String(v.name.clone().into_bytes()),
        );
        param.set(
            gimli::DW_AT_type,
            AttributeValue::UnitRef(type_dies[v.ty.0 as usize]),
        );
        if !list.is_empty() {
            let id = dwarf.unit.locations.add(LocationList(list));
            dwarf
                .unit
                .get_mut(param_id)
                .set(gimli::DW_AT_location, AttributeValue::LocationListRef(id));
        }
    }
}

/// Emits relocatable source lines and enough CU/range metadata for addr2line.
pub fn emit(
    product: &mut ObjectProduct,
    m: &Module,
    funcs: &[FuncDbg],
    scopes: &[Scope],
    endian: cranelift_codegen::ir::Endianness,
) -> Result<(), Error> {
    let valid_path = |s: &str| !s.is_empty() && !s.contains('\0');
    let Some(first_file) = m.files.iter().find(|p| valid_path(p)) else {
        return Ok(());
    };
    let encoding = Encoding {
        format: Format::Dwarf32,
        version: 4,
        address_size: 8,
    };
    let cwd = std::env::current_dir().map_err(|e| Error(format!("DWARF source directory: {e}")))?;
    let cwd = cwd.to_string_lossy();
    let mut dwarf = DwarfUnit::new(encoding);
    let mut lines = LineProgram::new(
        encoding,
        LineEncoding::default(),
        LineString::String(cwd.as_bytes().to_vec()),
        None,
        LineString::String(first_file.as_bytes().to_vec()),
        None,
    );
    let dir = lines.default_directory();
    // Keep the exact MIR file identity, including directories and logical @std
    // paths. Invalid/unknown paths get no rows, rather than a misleading file 1.
    let files: Vec<_> = m
        .files
        .iter()
        .map(|p| {
            valid_path(p)
                .then(|| lines.add_file(LineString::String(p.as_bytes().to_vec()), dir, None))
        })
        .collect();
    let mut symbols = Vec::new();
    let mut ranges = Vec::new();
    let root = dwarf.unit.root();
    // Range and location lists hold absolute addresses, so the base is zero. dsymutil needs the
    // explicit original CU base to relocate its range list into the linked image.
    dwarf.unit.get_mut(root).set(
        gimli::DW_AT_low_pc,
        AttributeValue::Address(Address::Constant(0)),
    );
    dwarf.unit.get_mut(root).set(
        gimli::DW_AT_name,
        AttributeValue::String(first_file.as_bytes().to_vec()),
    );
    dwarf.unit.get_mut(root).set(
        gimli::DW_AT_comp_dir,
        AttributeValue::String(cwd.as_bytes().to_vec()),
    );
    dwarf.unit.get_mut(root).set(
        gimli::DW_AT_producer,
        AttributeValue::String(b"Manuscript Cranelift".to_vec()),
    );
    let type_dies = emit_types(&mut dwarf, root, m);
    let mut origins = HashMap::new();
    for f in funcs {
        if f.dwarf_ranges.is_empty() {
            continue;
        }
        let symbol = symbols.len();
        symbols.push(product.function_symbol(f.id));
        let address = Address::Symbol { symbol, addend: 0 };
        ranges.push(Range::StartLength {
            begin: address,
            length: u64::from(f.size),
        });
        let entry = dwarf.unit.add(root, gimli::DW_TAG_subprogram);
        dwarf.unit.get_mut(entry).set(
            gimli::DW_AT_name,
            AttributeValue::String(f.name.as_bytes().to_vec()),
        );
        dwarf
            .unit
            .get_mut(entry)
            .set(gimli::DW_AT_low_pc, AttributeValue::Address(address));
        dwarf.unit.get_mut(entry).set(
            gimli::DW_AT_high_pc,
            AttributeValue::Udata(u64::from(f.size)),
        );
        let frames = emit_inlined(&mut dwarf, entry, symbol, f, scopes, &files, &mut origins);
        emit_vars(
            &mut dwarf, entry, symbol, f.size, &f.vars, &frames, &type_dies,
        );
        let mut end = None;
        for &(start, stop, file, line, _) in &f.dwarf_ranges {
            let Some(Some(file)) = files.get(file as usize) else {
                continue;
            };
            // A gap or an unknown source location must not inherit the previous
            // row. Separate sequences also give every function its own end PC.
            if end != Some(start) {
                if let Some(end) = end {
                    lines.end_sequence(u64::from(end));
                }
                lines.begin_sequence(Some(address));
            }
            lines.row().address_offset = u64::from(start);
            lines.row().file = *file;
            lines.row().line = u64::from(line);
            lines.generate_row();
            end = Some(stop);
        }
        if let Some(end) = end {
            lines.end_sequence(u64::from(end));
        }
    }
    if ranges.is_empty() {
        return Ok(());
    }
    let ranges = dwarf.unit.ranges.add(RangeList(ranges));
    dwarf
        .unit
        .get_mut(root)
        .set(gimli::DW_AT_ranges, AttributeValue::RangeListRef(ranges));
    dwarf.unit.line_program = lines;
    let endian = if endian == cranelift_codegen::ir::Endianness::Little {
        RunTimeEndian::Little
    } else {
        RunTimeEndian::Big
    };
    let mut sections = Sections::new(Section {
        bytes: EndianVec::new(endian),
        relocations: Vec::new(),
    });
    dwarf
        .write(&mut sections)
        .map_err(|e| Error(format!("DWARF: {e}")))?;
    let mut ids = HashMap::new();
    sections.for_each(|id, s| -> Result<(), Error> {
        if s.bytes.slice().is_empty() {
            return Ok(());
        }
        let name = if product.object.format() == BinaryFormat::MachO {
            id.name().replacen('.', "__", 1)
        } else {
            id.name().to_string()
        };
        let segment = product.object.segment_name(StandardSegment::Debug).to_vec();
        let section = product
            .object
            .add_section(segment, name.into_bytes(), SectionKind::Debug);
        product
            .object
            .section_mut(section)
            .set_data(s.bytes.slice().to_vec(), 1);
        ids.insert(id, section);
        Ok(())
    })?;
    sections.for_each(|id, s| -> Result<(), Error> {
        let Some(&section) = ids.get(&id) else {
            return Ok(());
        };
        for r in &s.relocations {
            let (symbol, kind, addend) = match r.target {
                RelocationTarget::Symbol(i) if product.object.format() == BinaryFormat::MachO => {
                    // Mach-O DWARF consumers read section-relative addresses
                    // from the object before linking. Use the same local
                    // section relocation and baked function offset as llvm-mc.
                    let function = product.object.symbol(symbols[i]);
                    let section = function.section.id().ok_or_else(|| {
                        Error("DWARF function is not defined in a section".into())
                    })?;
                    let offset = i64::try_from(function.value)
                        .ok()
                        .and_then(|v| v.checked_add(r.addend))
                        .ok_or_else(|| Error("DWARF function offset is too large".into()))?;
                    (
                        product.object.section_symbol(section),
                        RelocationKind::Absolute,
                        offset,
                    )
                }
                RelocationTarget::Symbol(i) => (symbols[i], RelocationKind::Absolute, r.addend),
                // dsymutil reads a location list offset as it stands: a section relocation would
                // add the section's address to it, past the end of the list data. (Offsets into
                // the other debug sections are rebased by dsymutil, so they keep theirs.)
                RelocationTarget::Section(id)
                    if product.object.format() == BinaryFormat::MachO
                        && id.name() == ".debug_loc" =>
                {
                    return Ok(());
                }
                RelocationTarget::Section(id) => {
                    let target = ids
                        .get(&id)
                        .ok_or_else(|| Error(format!("DWARF missing {}", id.name())))?;
                    let kind = if product.object.format() == BinaryFormat::Coff {
                        RelocationKind::SectionOffset
                    } else {
                        RelocationKind::Absolute
                    };
                    (product.object.section_symbol(*target), kind, r.addend)
                }
            };
            product
                .object
                .add_relocation(
                    section,
                    Relocation {
                        offset: r.offset as u64,
                        symbol,
                        addend,
                        flags: RelocationFlags::Generic {
                            kind,
                            encoding: RelocationEncoding::Generic,
                            size: r.size * 8,
                        },
                    },
                )
                .map_err(|e| Error(format!("DWARF relocation: {e}")))?;
        }
        Ok(())
    })
}
