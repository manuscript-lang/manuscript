//! Minimal DWARF4 source attribution. No variables, types, or inline frame DIEs.
//! The runtime's independent fault/profile tables remain unchanged.

use crate::Error;
use crate::cg::FuncDbg;
use cranelift_object::ObjectProduct;
use cranelift_object::object::{
    BinaryFormat, RelocationEncoding, RelocationFlags, RelocationKind, SectionKind,
    write::{Relocation, StandardSegment},
};
use gimli::write::{
    Address, AttributeValue, DwarfUnit, EndianVec, LineProgram, LineString, Range, RangeList,
    RelocateWriter, Relocation as DwarfRelocation, RelocationTarget, Sections,
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
    if product.object.format() == BinaryFormat::MachO {
        // dsymutil needs an explicit original CU base to relocate its range
        // list into the linked image, even when that original base is zero.
        dwarf.unit.get_mut(root).set(
            gimli::DW_AT_low_pc,
            AttributeValue::Address(Address::Constant(0)),
        );
    }
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
