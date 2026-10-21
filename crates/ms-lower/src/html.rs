//! `@std/html.ms` `parse`: the runtime parses into a tree handle (`msrt_html_*`, see
//! `ms-std-html`) and one generated function per `HtmlNode` type copies it into the sum type.
//! `escape` and `unescape` are plain runtime functions.

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use crate::native::NArg;
use ms_check::hir::ModuleHir;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncId, Mode, Module, Op, Param, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use std::rc::Rc;

/// Node kinds returned by `msrt_html_kind`.
const KIND_DOCUMENT: i64 = 0;
const KIND_ELEMENT: i64 = 1;
const KIND_TEXT: i64 = 2;
const KIND_COMMENT: i64 = 3;
const KIND_DOCTYPE: i64 = 4;

/// What `msrt_html_first_child` / `msrt_html_next_sibling` answer for no node.
const NO_NODE: i64 = 0xffff_ffff;

/// A queued tree-to-`HtmlNode` copy.
pub struct HtmlJob {
    /// The `HtmlNode` type.
    pub ty: ct::Ty,
    /// Module of the use.
    pub hir: Rc<ModuleHir>,
}

impl Cx {
    /// The function copying a node of a parse tree into an `HtmlNode`, reserved on first use.
    pub(crate) fn html_node_fn(
        &mut self,
        m: &mut Module,
        hir: &Rc<ModuleHir>,
        t: &ct::Ty,
    ) -> Result<FuncId, Error> {
        let key = format!("html-node:{}", ct::type_key(t));
        if let Some(f) = self.helpers.get(&key) {
            return Ok(*f);
        }
        let mt = self.lower_ty(m, t)?;
        let tree = m.types.obj("HtmlTree", Vec::new());
        let borrowed = |ty| Param {
            ty,
            mode: Mode::Borrow,
        };
        let id = m.add_func(ms_mir::ir::Func::new(
            "html_node",
            vec![borrowed(tree), borrowed(MTy::INT)],
            mt,
        ));
        self.helpers.insert(key, id);
        self.queue.push(Job {
            func: id,
            kind: JobKind::Html(Rc::new(HtmlJob {
                ty: t.clone(),
                hir: hir.clone(),
            })),
        });
        Ok(id)
    }
}

/// Lowers the body of a queued node copy.
pub(crate) fn build_html(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &HtmlJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let file = m.add_file(job.hir.data.file.as_str());
    let b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    let mut fl = FnLower::new(cx, b, job.hir.clone(), ct::Subst::new(), file, proto.ret);
    let result = fl.lower_html_node(&job.ty);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

impl FnLower<'_> {
    fn hstr(&mut self, sym: &str, tree: Value, id: Value) -> Result<Value, Error> {
        self.call_runtime(sym, &[tree, id], MTy::STR)
    }

    /// The node reached by `sym` from `id`, or `NO_NODE`.
    fn hlink(&mut self, sym: &str, tree: Value, id: Value) -> Result<Value, Error> {
        self.jcall_masked(sym, &[tree, id], NO_NODE)
    }

    fn lower_html_node(&mut self, t: &ct::Ty) -> Result<(), Error> {
        let p = self.b.params();
        let (tree, id) = (p[0], p[1]);
        let mt = self.jmty(t)?;
        let TyKind::Alt(a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("HtmlNode is an alternative"));
        };
        let cases = ct::cases(t);
        let index = |name: &str| {
            cases
                .iter()
                .position(|c| c.name.as_str() == name)
                .ok_or_else(|| Error::new(format!("HtmlNode lacks {name}")))
        };
        let kind = self.jcall_masked("msrt_html_kind", &[tree, id], 0xff)?;
        let blocks: Vec<_> = (0..5).map(|_| self.b.new_block()).collect();
        let other = self.b.new_block();
        let arms: Vec<(i64, _)> = blocks
            .iter()
            .enumerate()
            .map(|(i, b)| (i as i64, *b))
            .collect();
        self.b.switch(kind, &arms, other);
        self.b.seal_block(other);
        self.b.switch_to(other);
        self.b.unreachable();
        for (k, block) in blocks.iter().enumerate() {
            self.b.seal_block(*block);
            self.b.switch_to(*block);
            let v = match k as i64 {
                KIND_DOCUMENT => {
                    let c = index("Document")?;
                    let kids = self.html_children(&cases[c].fields[0].ty, tree, id)?;
                    self.b.alt_new(a, c as u32, &[kids])
                }
                KIND_ELEMENT => {
                    let c = index("Element")?;
                    let tag = self.hstr("msrt_html_data", tree, id)?;
                    let ns = self.hstr("msrt_html_namespace", tree, id)?;
                    let attrs = self.html_attributes(&cases[c].fields[2].ty, tree, id)?;
                    let kids = self.html_children(&cases[c].fields[3].ty, tree, id)?;
                    self.b.alt_new(a, c as u32, &[tag, ns, attrs, kids])
                }
                KIND_TEXT => {
                    let c = index("Text")?;
                    let s = self.hstr("msrt_html_data", tree, id)?;
                    self.b.alt_new(a, c as u32, &[s])
                }
                KIND_COMMENT => {
                    let c = index("Comment")?;
                    let s = self.hstr("msrt_html_data", tree, id)?;
                    self.b.alt_new(a, c as u32, &[s])
                }
                KIND_DOCTYPE => {
                    let c = index("Doctype")?;
                    let name = self.hstr("msrt_html_data", tree, id)?;
                    let mut ids = Vec::new();
                    for which in 0..2 {
                        let w = self.b.iconst(which);
                        ids.push(self.call_runtime(
                            "msrt_html_doctype_id",
                            &[tree, id, w],
                            MTy::STR,
                        )?);
                    }
                    self.b.alt_new(a, c as u32, &[name, ids[0], ids[1]])
                }
                _ => unreachable!("five kinds"),
            };
            self.b.ret(Some(v));
        }
        Ok(())
    }

    /// An owned list of the nodes under `id`, in order.
    fn html_children(&mut self, list: &ct::Ty, tree: Value, id: Value) -> Result<Value, Error> {
        let lt = self.jmty(list)?;
        let elem = list
            .args
            .first()
            .ok_or_else(|| Error::new("children are a list"))?;
        let et = self.jmty(elem)?;
        let hir = self.hir.clone();
        let node_fn = self.cx.html_node_fn(self.b.m, &hir, elem)?;
        let acc = self.jvar(lt);
        let zero = self.b.iconst(0);
        let empty = self.b.list_new(et, zero);
        self.b.def_var(acc, empty);
        let cur = self.b.declare_var(MTy::INT, Mode::Borrow);
        let first = self.hlink("msrt_html_first_child", tree, id)?;
        self.b.def_var(cur, first);
        let (head, body, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(head, &[]);
        self.b.switch_to(head);
        let c = self.b.use_var(cur);
        let none = self.b.iconst(NO_NODE);
        let more = self.b.icmp(Cc::Ne, c, none);
        self.b.br_if(more, body, &[], exit, &[]);
        self.b.seal_block(body);
        self.b.switch_to(body);
        let c = self.b.use_var(cur);
        let node = self.b.call(node_fn, &[tree, c]);
        let l = self.b.use_var(acc);
        let l2 = self.b.list_push(l, node);
        self.b.def_var(acc, l2);
        let c = self.b.use_var(cur);
        let next = self.hlink("msrt_html_next_sibling", tree, c)?;
        self.b.def_var(cur, next);
        self.b.br(head, &[]);
        self.b.seal_block(head);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(self.b.use_var(acc))
    }

    /// An owned list of the `HtmlAttribute` records of element `id`.
    fn html_attributes(&mut self, list: &ct::Ty, tree: Value, id: Value) -> Result<Value, Error> {
        let lt = self.jmty(list)?;
        let elem = list
            .args
            .first()
            .ok_or_else(|| Error::new("attributes are a list"))?;
        let et = self.jmty(elem)?;
        let TyKind::Rec(rec) = self.b.m.types.kind(et).clone() else {
            return Err(Error::new("HtmlAttribute is a record"));
        };
        let n = self.call_runtime("msrt_html_attr_count", &[tree, id], MTy::INT)?;
        let acc = self.jvar(lt);
        let zero = self.b.iconst(0);
        let empty = self.b.list_new(et, zero);
        self.b.def_var(acc, empty);
        let i = self.b.declare_var(MTy::INT, Mode::Borrow);
        self.b.def_var(i, zero);
        let (head, body, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(head, &[]);
        self.b.switch_to(head);
        let iv = self.b.use_var(i);
        let more = self.b.icmp(Cc::Lt, iv, n);
        self.b.br_if(more, body, &[], exit, &[]);
        self.b.seal_block(body);
        self.b.switch_to(body);
        let iv = self.b.use_var(i);
        let mut fields = Vec::new();
        for which in 0..3 {
            let w = self.b.iconst(which);
            fields.push(self.call_runtime("msrt_html_attr", &[tree, id, iv, w], MTy::STR)?);
        }
        let attr = self.b.rec_new(rec, &fields);
        let l = self.b.use_var(acc);
        let l2 = self.b.list_push(l, attr);
        self.b.def_var(acc, l2);
        let iv = self.b.use_var(i);
        let one = self.b.iconst(1);
        let next = self.b.binop(Op::IAdd, iv, one);
        self.b.def_var(i, next);
        self.b.br(head, &[]);
        self.b.seal_block(head);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(self.b.use_var(acc))
    }

    /// `parse(text, limits)`: the tree copied into an `HtmlNode`, or the runtime's error.
    pub(crate) fn html_parse(
        &mut self,
        e: &ms_syntax::ast::Expr,
        rty: MTy,
        args: &[NArg],
    ) -> Result<Val, Error> {
        let TyKind::Alt(ra) = self.b.m.types.kind(rty).clone() else {
            return Err(Error::new("parse returns a Result"));
        };
        let ok = self.ok_case_index(ra)?;
        let err = self.b.m.alts[ra.index()]
            .cases
            .iter()
            .position(|c| c.name == "error")
            .ok_or_else(|| Error::new("not a Result"))?;
        let node = self
            .ety(e)
            .args
            .first()
            .cloned()
            .ok_or_else(|| Error::new("parse without a node type"))?;
        let text = self.jarg(args, "text")?;
        let text = self.borrow(text);
        let limits = args
            .iter()
            .find(|a| a.name.as_str() == "limits")
            .map(|a| a.val);
        // Whether a limits record was supplied: absent limits get the runtime's defaults.
        let has_limits = match limits {
            None => self.b.bconst(false),
            Some(l) => {
                let lv = self.borrow(l);
                if matches!(self.b.m.types.kind(self.ty_of(lv)), TyKind::Opt(_)) {
                    self.b.opt_is_some(lv)
                } else {
                    self.b.bconst(true)
                }
            }
        };
        let flat = self.jlimits(limits)?;
        let tree_ty = self.b.m.types.obj("HtmlTree", Vec::new());
        let tree_slot = self.jslot(tree_ty);
        let root_slot = self.jslot(MTy::INT);
        let mut vals = vec![text, has_limits];
        vals.extend(flat);
        vals.push(tree_slot);
        vals.push(root_slot);
        let code = self.status_code("msrt_html_parse", &vals)?;
        let zero = self.b.iconst(0);
        let good = self.b.icmp(Cc::Eq, code, zero);
        let hir = self.hir.clone();
        let node_fn = self.cx.html_node_fn(self.b.m, &hir, &node)?;
        self.two_ways(
            good,
            rty,
            &mut |s| {
                let tree = s.take_slot(tree_slot, tree_ty);
                let raw = s.take_slot(root_slot, MTy::INT);
                let m = s.b.iconst(NO_NODE);
                let root = s.b.binop(Op::And, raw, m);
                let v = s.b.call(node_fn, &[tree, root]);
                s.drop_value(tree);
                Ok(Some(s.b.alt_new(ra, ok as u32, &[v])))
            },
            &mut |s| {
                let et = s.b.m.alts[ra.index()].cases[err].fields[0].1;
                let TyKind::Alt(ea) = s.b.m.types.kind(et).clone() else {
                    return Err(Error::new("a runtime status needs an error alternative"));
                };
                let cases = s.status_cases(ea);
                let e = s.status_error(ea, code, &cases, None)?;
                Ok(Some(s.b.alt_new(ra, err as u32, &[e])))
            },
        )
    }
}
