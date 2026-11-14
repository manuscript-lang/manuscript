//! The program's `main` and the symbol and line tables it hands to `msrt_start`, as one more LLVM
//! module. The tables describe code that exists only after LLVM has compiled the others, so the
//! caller reads each function's size and line ranges from the compiled objects and then asks for
//! this module.

use crate::llvm_ir::Unit;
use crate::{ENTRY_SYMBOL, TEXT_ANCHOR};
use ms_mir::fault_tables::{self, FuncTable};
use ms_mir::ir::{Module, Scope};
use std::collections::BTreeSet;
use std::fmt::Write as _;

/// What the tables record about one function the other modules define.
#[derive(Clone, Debug, Default)]
pub struct TableFn {
    /// Linkage symbol (unused when the code is addressed from the anchor).
    pub symbol: String,
    pub name: String,
    pub file: u32,
    pub line: u32,
    /// Bytes of code.
    pub size: u32,
    /// `(code offset, file, line, scope)` ranges, sorted by offset.
    pub ranges: Vec<(u32, u32, u32, u32)>,
    /// Offset of the function from [`TEXT_ANCHOR`], when the code is addressed from it.
    pub text: u64,
}

/// The module that holds `main` and the tables, or `None` for a program without an entry
/// function. `anchored`: the functions have no visible symbol and are addressed from
/// [`TEXT_ANCHOR`].
pub fn tables_unit(
    m: &Module,
    funcs: &[TableFn],
    scopes: &[Scope],
    anchored: bool,
    triple: &str,
) -> Option<Unit> {
    m.entry?;
    let table: Vec<FuncTable> = funcs
        .iter()
        .map(|f| FuncTable {
            name: &f.name,
            file: f.file,
            line: f.line,
            size: f.size,
            ranges: &f.ranges,
        })
        .collect();
    let built = fault_tables::build(&m.files, &table, scopes);
    let own = |target: usize| {
        format!("ptrtoint (ptr getelementptr (i8, ptr @\"ms.tables\", i64 {target}) to i64)")
    };
    // Every 8 bytes that hold an address, by offset in the blob.
    let mut words: Vec<(usize, String)> = built
        .pointers
        .iter()
        .map(|&(at, target)| (at, own(target)))
        .collect();
    let mut symbols = BTreeSet::new();
    for &(at, n, off) in &built.pcs {
        let (sym, base) = if anchored {
            (TEXT_ANCHOR, funcs[n].text)
        } else {
            (funcs[n].symbol.as_str(), 0)
        };
        symbols.insert(sym.to_string());
        let at_off = base + u64::from(off);
        words.push((
            at,
            format!("ptrtoint (ptr getelementptr (i8, ptr @\"{sym}\", i64 {at_off}) to i64)"),
        ));
    }
    words.sort_by_key(|w| w.0);
    let mut fields = Vec::new();
    let mut at = 0;
    for (offset, value) in &words {
        if *offset > at {
            fields.push(bytes(&built.blob[at..*offset]));
        }
        fields.push(("i64".to_string(), value.clone()));
        at = offset + 8;
    }
    if at < built.blob.len() {
        fields.push(bytes(&built.blob[at..]));
    }
    let types: Vec<&str> = fields.iter().map(|f| f.0.as_str()).collect();
    let values: Vec<String> = fields.iter().map(|f| format!("{} {}", f.0, f.1)).collect();
    let mut ir = String::new();
    let _ = writeln!(ir, "target triple = \"{triple}\"");
    symbols.insert(ENTRY_SYMBOL.to_string());
    for sym in &symbols {
        let _ = writeln!(ir, "declare void @\"{sym}\"()");
    }
    let _ = writeln!(ir, "declare i64 @msrt_start(i64, i64, i64, i64)");
    let _ = writeln!(
        ir,
        "@\"ms.tables\" = internal constant <{{ {} }}> <{{ {} }}>, align 8",
        types.join(", "),
        values.join(", ")
    );
    let _ = writeln!(
        ir,
        "define i32 @main(i32 %argc, ptr %argv) #0 {{\n\
         entry:\n  \
         %n = sext i32 %argc to i64\n  \
         %v = ptrtoint ptr %argv to i64\n  \
         %r = call i64 @msrt_start(i64 ptrtoint (ptr @\"{ENTRY_SYMBOL}\" to i64), i64 ptrtoint (ptr @\"ms.tables\" to i64), i64 %n, i64 %v)\n  \
         %c = trunc i64 %r to i32\n  \
         ret i32 %c\n}}\n\
         attributes #0 = {{ \"frame-pointer\"=\"all\" nounwind }}"
    );
    Some(Unit {
        ir,
        unoptimized: false,
    })
}

/// A run of bytes as an LLVM array constant: its type and value.
fn bytes(run: &[u8]) -> (String, String) {
    let mut s = String::with_capacity(run.len() * 3 + 4);
    s.push_str("c\"");
    for b in run {
        let _ = write!(s, "\\{b:02X}");
    }
    s.push('"');
    (format!("[{} x i8]", run.len()), s)
}
