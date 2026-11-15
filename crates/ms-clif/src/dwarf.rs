//! Minimal DWARF4: source attribution, and a DIE for every Manuscript type (`debug_types`) so a
//! debugger can print a `String`, list, map, record, enum or optional at an address, and a
//! parameter DIE per named function parameter with a location list. No inline frame DIEs.
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
use ms_mir::ir::Module;
use std::collections::HashMap;

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

/// Describes the named values of `f` as parameter DIEs, each located by a list over the function.
fn emit_vars(
    dwarf: &mut DwarfUnit,
    subprogram: gimli::write::UnitEntryId,
    symbol: usize,
    size: u32,
    vars: &[VarDbg],
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
        let mut list = Vec::new();
        for w in cuts.windows(2) {
            let (begin, end) = (w[0], w[1]);
            let mut expr = Expression::new();
            let mut known = false;
            let mut next = 0;
            for p in &v.pieces {
                if p.offset > next {
                    expr.op_piece(u64::from(p.offset - next));
                }
                match p.ranges.iter().find(|r| r.0 <= begin && end <= r.1) {
                    Some((_, _, VarLoc::Reg(r))) => {
                        expr.op_reg(gimli::Register(*r));
                        known = true;
                    }
                    Some((_, _, VarLoc::Cfa(o))) => {
                        expr.op_fbreg(*o);
                        known = true;
                    }
                    None => {}
                }
                expr.op_piece(u64::from(p.size));
                next = p.offset + p.size;
            }
            if known {
                list.push(Location::StartEnd {
                    begin: at(begin),
                    end: at(end),
                    data: expr,
                });
            }
        }
        let param_id = dwarf.unit.add(subprogram, gimli::DW_TAG_formal_parameter);
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
        emit_vars(&mut dwarf, entry, symbol, f.size, &f.vars, &type_dies);
        let mut end = None;
        for &(start, stop, file, line) in &f.dwarf_ranges {
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
                // clang writes a reference from one debug section to another as a plain offset on
                // Darwin, and dsymutil reads loclist and range offsets as such (a section
                // relocation would add the section's address to them, past the end of the data).
                RelocationTarget::Section(_) if product.object.format() == BinaryFormat::MachO => {
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
