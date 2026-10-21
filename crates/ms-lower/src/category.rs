//! `@std/core.ms` `category`: the shared category of a standard error case. Each standard
//! error type that has been turned into an `Error` value gets a test; a case answers with the
//! category of its own name.

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncId, Imm, Mode, Module, Op, Param};
use ms_mir::types::{Ty as MTy, TyKind};

impl Cx {
    /// The function answering `category` for an `Error` value, reserved on first use.
    pub(crate) fn category_fn(&mut self, m: &mut Module, cause: MTy, result: MTy) -> FuncId {
        let key = format!("category:{}:{}", cause.0, result.0);
        if let Some(f) = self.helpers.get(&key) {
            return *f;
        }
        let f = ms_mir::ir::Func::new(
            "category",
            vec![Param {
                ty: cause,
                mode: Mode::Borrow,
            }],
            result,
        );
        let id = m.add_func(f);
        self.helpers.insert(key, id);
        self.queue.push(Job {
            func: id,
            kind: JobKind::Category(cause),
        });
        id
    }
}

/// Lowers the category query: the tag of each standard error value picks the category.
pub(crate) fn build_category(
    cx: &Cx,
    m: &mut Module,
    func: FuncId,
    cause: MTy,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let TyKind::Iface(iface) = m.types.kind(cause).clone() else {
        return Err(Error::new("category of a non-interface value"));
    };
    let TyKind::Opt(inner) = m.types.kind(proto.ret).clone() else {
        return Err(Error::new("category without an Optional result"));
    };
    let TyKind::Alt(cat) = m.types.kind(inner).clone() else {
        return Err(Error::new("category without an ErrorCategory"));
    };
    let categories: Vec<String> = m.alts[cat.index()]
        .cases
        .iter()
        .map(|c| c.name.clone())
        .collect();
    // (table, data type, [(case tag, category tag)])
    let mut tables = Vec::new();
    for (i, v) in m.vtables.iter().enumerate() {
        if v.iface != iface {
            continue;
        }
        let TyKind::Alt(a) = m.types.kind(v.data_ty).clone() else {
            continue;
        };
        let def = &m.alts[a.index()];
        if !cx.std_alts.contains(&a.index()) {
            continue;
        }
        let pairs: Vec<(i64, u32)> = def
            .cases
            .iter()
            .enumerate()
            .filter_map(|(tag, c)| {
                categories
                    .iter()
                    .position(|n| *n == c.name)
                    .map(|k| (tag as i64, k as u32))
            })
            .collect();
        if !pairs.is_empty() {
            tables.push((ms_mir::ir::VtableId(i as u32), v.data_ty, pairs));
        }
    }
    let mut b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    let x = b.params()[0];
    for (vt, data_ty, pairs) in tables {
        let hit = b
            .emit(Op::IfaceIs, &[x], Imm::Vtable(vt), Some(MTy::BOOL))
            .expect("test");
        let (yes, next) = (b.new_block(), b.new_block());
        b.br_if(hit, yes, &[], next, &[]);
        b.seal_block(yes);
        b.seal_block(next);
        b.switch_to(yes);
        let data = b
            .emit(Op::IfaceData, &[x], Imm::None, Some(MTy::PTR))
            .expect("data");
        let v = b
            .emit(Op::Load, &[data], Imm::Ty(data_ty), Some(data_ty))
            .expect("load");
        let tag = b.alt_tag(v);
        for (case, category) in pairs {
            let want = b.iconst(case);
            let is = b.icmp(Cc::Eq, tag, want);
            let (found, more) = (b.new_block(), b.new_block());
            b.br_if(is, found, &[], more, &[]);
            b.seal_block(found);
            b.seal_block(more);
            b.switch_to(found);
            let c = b.alt_new(cat, category, &[]);
            let some = b.opt_some(c);
            b.ret(Some(some));
            b.switch_to(more);
        }
        let none = b.opt_none(proto.ret);
        b.ret(Some(none));
        b.switch_to(next);
    }
    let none = b.opt_none(proto.ret);
    b.ret(Some(none));
    let mut f = b.into_func();
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}
