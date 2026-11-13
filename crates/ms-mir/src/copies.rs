//! Implicit copies of object values. A value whose type holds a closure, interface or runtime
//! object leaf has one owner, so a program duplicates it only through a written `.clone()`
//! (`copy 1`); any other `copy` of such a value is lowering duplicating what it should have
//! moved or borrowed. This pass lists every such `copy` so the build can report them
//! (`MS_COPY_PROBE`) or fail on them (`MS_COPY_PROBE=strict`, see `make copy-check`). A copy of a
//! `none` is exempt: it touches no object.

use crate::ir::{Func, Imm, Module, Op, Value};
use crate::print::ty_str;
use crate::types::{Native, Ty, TyKind};
use std::collections::HashSet;

/// One copy of an object value.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CopySite {
    /// The function holding the copy.
    pub func: String,
    /// The copied type, printed.
    pub ty: String,
    /// The source file, empty when unknown.
    pub file: String,
    /// The 1-based source line, 0 when unknown.
    pub line: u32,
}

impl std::fmt::Display for CopySite {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}\t{}\t{}:{}", self.func, self.ty, self.file, self.line)
    }
}

/// Whether a value of `t` holds a closure, interface or runtime object, directly or in a field,
/// element or payload. `Map` and `Set` are copied by the runtime, so only their arguments count.
pub fn holds_object(m: &Module, t: Ty) -> bool {
    holds_object_in(m, t, &mut Vec::new())
}

fn holds_object_in(m: &Module, t: Ty, seen: &mut Vec<Ty>) -> bool {
    if seen.contains(&t) {
        return false;
    }
    seen.push(t);
    let held = match m.types.kind(t) {
        TyKind::Obj(Native::Map | Native::Set, args) => {
            args.iter().any(|a| holds_object_in(m, *a, seen))
        }
        TyKind::Obj(..) | TyKind::Fn(..) | TyKind::Iface(_) => true,
        TyKind::Opt(i) | TyKind::List(i) => holds_object_in(m, *i, seen),
        TyKind::Type(r) => m.type_defs[r.index()]
            .fields
            .iter()
            .any(|(_, f)| holds_object_in(m, *f, seen)),
        TyKind::Alt(a) => m.alts[a.index()]
            .cases
            .iter()
            .any(|c| c.fields.iter().any(|(_, f)| holds_object_in(m, *f, seen))),
        _ => false,
    };
    seen.pop();
    held
}

/// Every implicit `copy` of an object value in `m`, in function and instruction order.
pub fn object_copies(m: &Module) -> Vec<CopySite> {
    let mut sites = Vec::new();
    for f in &m.funcs {
        let nones = none_values(f);
        for b in &f.blocks {
            for inst in &b.insts {
                if inst.op != Op::Clone || inst.imm == Imm::Int(1) || nones.contains(&inst.args[0])
                {
                    continue;
                }
                let t = f.ty(inst.args[0]);
                if !holds_object(m, t) {
                    continue;
                }
                let file = m
                    .files
                    .get(inst.loc.file as usize)
                    .cloned()
                    .unwrap_or_default();
                sites.push(CopySite {
                    func: f.name.clone(),
                    ty: ty_str(m, t),
                    file,
                    line: inst.loc.line,
                });
            }
        }
    }
    sites
}

/// The values `f` defines as a bare `none`.
fn none_values(f: &Func) -> HashSet<Value> {
    f.blocks
        .iter()
        .flat_map(|b| b.insts.iter())
        .filter(|i| i.op == Op::OptNone)
        .filter_map(|i| i.res)
        .collect()
}
