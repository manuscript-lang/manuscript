//! The symbol and line tables handed to `msrt_start` (`crates/ms-rt/ABI.md`), shared by the
//! backends. Code addresses are left zero: the backend relocates the entries listed in
//! [`Built::pcs`] and the table's own pointers ([`Built::pointers`]).

use crate::ir::Scope;

const TABLES_HEADER: usize = 80;
const SCOPE_ENTRY: usize = 16;
const FUNC_ENTRY: usize = 24;
const LINE_ENTRY: usize = 16;

/// What the tables record about one compiled function.
pub struct FuncTable<'a> {
    pub name: &'a str,
    /// Index into the module's files, `u32::MAX` when unknown.
    pub file: u32,
    pub line: u32,
    /// Bytes of code.
    pub size: u32,
    /// `(code offset, file, line, scope)` ranges, sorted by offset.
    pub ranges: &'a [(u32, u32, u32, u32)],
}

/// A finished blob and where its absolute addresses go.
pub struct Built {
    pub blob: Vec<u8>,
    /// `(offset in the blob, offset of the target in the blob)` of each pointer into the blob.
    pub pointers: Vec<(usize, usize)>,
    /// `(entry offset in the blob, function index, code offset)`: each is the address of that
    /// function's code plus the offset.
    pub pcs: Vec<(usize, usize, u32)>,
}

/// Builds the tables of `funcs` (in order) and `scopes`.
pub fn build(files: &[String], funcs: &[FuncTable], scopes: &[Scope]) -> Built {
    let mut strings: Vec<u8> = Vec::new();
    let mut intern = |s: &str| -> u32 {
        let at = strings.len() as u32;
        strings.extend_from_slice(s.as_bytes());
        strings.push(0);
        at
    };
    let files: Vec<u32> = files.iter().map(|f| intern(f)).collect();
    let file_off = |f: u32| files.get(f as usize).copied().unwrap_or(u32::MAX);
    let names: Vec<u32> = funcs.iter().map(|d| intern(d.name)).collect();
    let scope_names: Vec<u32> = scopes.iter().map(|sc| intern(&sc.name)).collect();
    let nlines: usize = funcs.iter().map(|d| d.ranges.len()).sum();
    let funcs_at = TABLES_HEADER;
    let lines_at = funcs_at + funcs.len() * FUNC_ENTRY;
    let line_scopes_at = lines_at + nlines * LINE_ENTRY;
    let scopes_at = (line_scopes_at + nlines * 4).next_multiple_of(8);
    let strings_at = scopes_at + scopes.len() * SCOPE_ENTRY;
    let mut blob = vec![0u8; strings_at + strings.len()];
    blob[0..4].copy_from_slice(&3u32.to_le_bytes()); // ms-rt ABI_VERSION
    blob[72..80].copy_from_slice(&(scopes.len() as u64).to_le_bytes());
    blob[16..24].copy_from_slice(&(funcs.len() as u64).to_le_bytes());
    blob[32..40].copy_from_slice(&(nlines as u64).to_le_bytes());
    blob[48..56].copy_from_slice(&(strings.len() as u64).to_le_bytes());
    for (n, sc) in scopes.iter().enumerate() {
        let at = scopes_at + n * SCOPE_ENTRY;
        blob[at..at + 4].copy_from_slice(&scope_names[n].to_le_bytes());
        blob[at + 4..at + 8].copy_from_slice(&file_off(sc.file).to_le_bytes());
        blob[at + 8..at + 12].copy_from_slice(&sc.parent.to_le_bytes());
        blob[at + 12..at + 16].copy_from_slice(&sc.call_line.to_le_bytes());
    }
    blob[strings_at..].copy_from_slice(&strings);
    let mut pcs = Vec::new();
    let mut at_line = lines_at;
    for (n, d) in funcs.iter().enumerate() {
        let at = funcs_at + n * FUNC_ENTRY;
        pcs.push((at, n, 0));
        blob[at + 8..at + 12].copy_from_slice(&d.size.to_le_bytes());
        blob[at + 12..at + 16].copy_from_slice(&names[n].to_le_bytes());
        blob[at + 16..at + 20].copy_from_slice(&file_off(d.file).to_le_bytes());
        blob[at + 20..at + 24].copy_from_slice(&d.line.to_le_bytes());
        for &(off, file, line, scope) in d.ranges {
            // The runtime resolves a pc to the last entry at or before it.
            pcs.push((at_line, n, off));
            blob[at_line + 8..at_line + 12].copy_from_slice(&line.to_le_bytes());
            blob[at_line + 12..at_line + 16].copy_from_slice(&file_off(file).to_le_bytes());
            let ls = line_scopes_at + (at_line - lines_at) / LINE_ENTRY * 4;
            blob[ls..ls + 4].copy_from_slice(&scope.to_le_bytes());
            at_line += LINE_ENTRY;
        }
    }
    let pointers = vec![
        (8, funcs_at),
        (24, lines_at),
        (40, strings_at),
        (56, line_scopes_at),
        (64, scopes_at),
    ];
    Built {
        blob,
        pointers,
        pcs,
    }
}
