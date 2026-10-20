//! `@std/html.ms` `parse`: the runtime parses into a tree handle (`msrt_html_*`, see
//! `ms-std-html`) and one MIR function per `HtmlNode` type converts a node id into the value.

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use crate::native::NArg;
use ms_check::hir::ModuleHir;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncId, Mode, Module, Op, Param, Value};
use ms_mir::types::{AltId, Ty as MTy, TyKind};
use std::rc::Rc;

const KIND_DOCUMENT: i64 = 0;
const KIND_ELEMENT: i64 = 1;
const KIND_TEXT: i64 = 2;
const KIND_COMMENT: i64 = 3;

/// `u32::MAX`: no further sibling.
const NO_NODE: i64 = 0xffff_ffff;

/// The queued conversion of one tree node into an `HtmlNode`.
pub struct HtmlJob {
    /// The `HtmlNode` alternative.
    pub node: MTy,
    /// Module of the use.
    pub hir: Rc<ModuleHir>,
}

fn borrowed(ty: MTy) -> Param {
    Param {
        ty,
        mode: Mode::Borrow,
    }
}

fn tree_ty(m: &mut Module) -> MTy {
    m.types.obj("HtmlTree", Vec::new())
}

impl Cx {
    /// The function turning a node id of a parsed tree into an `HtmlNode`, reserved on first use.
    fn html_node_fn(&mut self, m: &mut Module, hir: &Rc<ModuleHir>, node: MTy) -> FuncId {
        let key = format!("html-node:{}", node.0);
        if let Some(f) = self.helpers.get(&key) {
            return *f;
        }
        let tree = tree_ty(m);
        let id = m.add_func(ms_mir::ir::Func::new(
            "html_node",
            vec![borrowed(tree), borrowed(MTy::INT)],
            node,
        ));
        self.helpers.insert(key, id);
        self.queue.push(Job {
            func: id,
            kind: JobKind::Html(Rc::new(HtmlJob {
                node,
                hir: hir.clone(),
            })),
        });
        id
    }
}

/// Lowers the body of a queued node conversion.
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
    let result = fl.lower_html_node(func, job.node);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

impl FnLower<'_> {
    /// `u32` results of the runtime come back with undefined upper bits.
    fn hmasked(&mut self, sym: &str, args: &[Value], mask: i64) -> Result<Value, Error> {
        let raw = self.call_runtime(sym, args, MTy::INT)?;
        let m = self.b.iconst(mask);
        Ok(self.b.binop(Op::And, raw, m))
    }

    fn htext(&mut self, sym: &str, args: &[Value]) -> Result<Value, Error> {
        self.call_runtime(sym, args, MTy::STR)
    }

    fn hcase(&self, an: AltId, name: &str) -> Result<usize, Error> {
        self.b.m.alts[an.index()]
            .cases
            .iter()
            .position(|c| c.name == name)
            .ok_or_else(|| Error::new(format!("HtmlNode lacks {name}")))
    }

    /// The elements of a list-typed field of a case.
    fn hlist_elem(&self, an: AltId, case: usize, field: usize) -> Result<MTy, Error> {
        let t = self.b.m.alts[an.index()].cases[case].fields[field].1;
        match self.b.m.types.kind(t) {
            TyKind::List(e) => Ok(*e),
            _ => Err(Error::new("HtmlNode field is not a list")),
        }
    }

    /// Runs `body(i)` for `i` in `0..count`.
    fn hrepeat(
        &mut self,
        count: Value,
        body: &mut dyn FnMut(&mut Self, Value) -> Result<(), Error>,
    ) -> Result<(), Error> {
        let idx = self.b.declare_var(MTy::INT, Mode::Borrow);
        let zero = self.b.iconst(0);
        self.b.def_var(idx, zero);
        let (header, step, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(header, &[]);
        self.b.switch_to(header);
        let i = self.b.use_var(idx);
        let more = self.b.icmp(Cc::Lt, i, count);
        self.b.br_if(more, step, &[], exit, &[]);
        self.b.seal_block(step);
        self.b.switch_to(step);
        let i = self.b.use_var(idx);
        body(self, i)?;
        let one = self.b.iconst(1);
        let i = self.b.use_var(idx);
        let next = self.b.binop(Op::IAdd, i, one);
        self.b.def_var(idx, next);
        self.b.br(header, &[]);
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(())
    }

    /// The child nodes of `id` converted in order.
    fn hchildren(
        &mut self,
        func: FuncId,
        tree: Value,
        id: Value,
        elem: MTy,
    ) -> Result<Value, Error> {
        let list_ty = self.b.m.types.list(elem);
        let acc = self.fresh_var(list_ty);
        let zero = self.b.iconst(0);
        let first = self.b.list_new(elem, zero);
        self.b.def_var(acc, first);
        let cur = self.b.declare_var(MTy::INT, Mode::Borrow);
        let c0 = self.hmasked("msrt_html_first_child", &[tree, id], NO_NODE)?;
        self.b.def_var(cur, c0);
        let (header, step, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(header, &[]);
        self.b.switch_to(header);
        let c = self.b.use_var(cur);
        let none = self.b.iconst(NO_NODE);
        let more = self.b.icmp(Cc::Ne, c, none);
        self.b.br_if(more, step, &[], exit, &[]);
        self.b.seal_block(step);
        self.b.switch_to(step);
        let c = self.b.use_var(cur);
        let child = self.b.call(func, &[tree, c]);
        let l = self.b.use_var(acc);
        let l = self.b.list_push(l, child);
        self.b.def_var(acc, l);
        let c = self.b.use_var(cur);
        let next = self.hmasked("msrt_html_next_sibling", &[tree, c], NO_NODE)?;
        self.b.def_var(cur, next);
        self.b.br(header, &[]);
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(self.b.use_var(acc))
    }

    /// The attributes of element `id`.
    fn hattributes(&mut self, tree: Value, id: Value, elem: MTy) -> Result<Value, Error> {
        let TyKind::Rec(rid) = self.b.m.types.kind(elem).clone() else {
            return Err(Error::new("HtmlAttribute is a record"));
        };
        let list_ty = self.b.m.types.list(elem);
        let acc = self.fresh_var(list_ty);
        let n = self.call_runtime("msrt_html_attr_count", &[tree, id], MTy::INT)?;
        let first = self.b.list_new(elem, n);
        self.b.def_var(acc, first);
        self.hrepeat(n, &mut |s, i| {
            let mut fields = Vec::new();
            for which in 0..3 {
                let w = s.b.iconst(which);
                fields.push(s.htext("msrt_html_attr", &[tree, id, i, w])?);
            }
            let rec = s.b.rec_new(rid, &fields);
            let l = s.b.use_var(acc);
            let l = s.b.list_push(l, rec);
            s.b.def_var(acc, l);
            Ok(())
        })?;
        Ok(self.b.use_var(acc))
    }

    /// The body of `html_node(tree, id)`.
    fn lower_html_node(&mut self, func: FuncId, node: MTy) -> Result<(), Error> {
        let TyKind::Alt(an) = self.b.m.types.kind(node).clone() else {
            return Err(Error::new("HtmlNode is an alternative"));
        };
        let params = self.b.params();
        let (tree, id) = (params[0], params[1]);
        let kind = self.hmasked("msrt_html_kind", &[tree, id], 0xff)?;
        let out = self.hselect(func, an, node, tree, id, kind)?;
        self.emit_return(Some(out));
        Ok(())
    }

    /// The node of the given runtime kind: document, element, text, comment, else doctype.
    fn hselect(
        &mut self,
        func: FuncId,
        an: AltId,
        node: MTy,
        tree: Value,
        id: Value,
        kind: Value,
    ) -> Result<Val, Error> {
        let is = |s: &mut Self, k: i64| {
            let k = s.b.iconst(k);
            s.b.icmp(Cc::Eq, kind, k)
        };
        let (document, element, text, comment, doctype) = (
            self.hcase(an, "Document")?,
            self.hcase(an, "Element")?,
            self.hcase(an, "Text")?,
            self.hcase(an, "Comment")?,
            self.hcase(an, "Doctype")?,
        );
        let c = is(self, KIND_DOCUMENT);
        self.two_ways(
            c,
            node,
            &mut |s| {
                let elem = s.hlist_elem(an, document, 0)?;
                let children = s.hchildren(func, tree, id, elem)?;
                Ok(Some(s.b.alt_new(an, document as u32, &[children])))
            },
            &mut |s| {
                let c = is(s, KIND_ELEMENT);
                s.two_ways(
                    c,
                    node,
                    &mut |s| {
                        let tag = s.htext("msrt_html_data", &[tree, id])?;
                        let namespace = s.htext("msrt_html_namespace", &[tree, id])?;
                        let attr = s.hlist_elem(an, element, 2)?;
                        let attributes = s.hattributes(tree, id, attr)?;
                        let child = s.hlist_elem(an, element, 3)?;
                        let children = s.hchildren(func, tree, id, child)?;
                        Ok(Some(s.b.alt_new(
                            an,
                            element as u32,
                            &[tag, namespace, attributes, children],
                        )))
                    },
                    &mut |s| {
                        let c = is(s, KIND_TEXT);
                        s.two_ways(
                            c,
                            node,
                            &mut |s| {
                                let t = s.htext("msrt_html_data", &[tree, id])?;
                                Ok(Some(s.b.alt_new(an, text as u32, &[t])))
                            },
                            &mut |s| {
                                let c = is(s, KIND_COMMENT);
                                s.two_ways(
                                    c,
                                    node,
                                    &mut |s| {
                                        let t = s.htext("msrt_html_data", &[tree, id])?;
                                        Ok(Some(s.b.alt_new(an, comment as u32, &[t])))
                                    },
                                    &mut |s| {
                                        let name = s.htext("msrt_html_data", &[tree, id])?;
                                        let (p, q) = (s.b.iconst(0), s.b.iconst(1));
                                        let public =
                                            s.htext("msrt_html_doctype_id", &[tree, id, p])?;
                                        let system =
                                            s.htext("msrt_html_doctype_id", &[tree, id, q])?;
                                        Ok(Some(s.b.alt_new(
                                            an,
                                            doctype as u32,
                                            &[name, public, system],
                                        )))
                                    },
                                )
                                .map(|v| Some(v.v))
                            },
                        )
                        .map(|v| Some(v.v))
                    },
                )
                .map(|v| Some(v.v))
            },
        )
    }

    /// `html.parse(text, limits)`.
    pub(crate) fn html_parse(&mut self, rty: MTy, args: &[NArg]) -> Result<Val, Error> {
        let text = args
            .iter()
            .find(|a| a.name.as_str() == "text")
            .map(|a| a.val)
            .ok_or_else(|| Error::new("html.parse without text"))?;
        let text = self.borrow(text);
        let limits = args
            .iter()
            .find(|a| a.name.as_str() == "limits")
            .map(|a| a.val);
        let flat = self.jlimits(limits)?;
        let tree_ty = tree_ty(self.b.m);
        let tree_slot = self.jslot(tree_ty);
        let root_slot = self.jslot(MTy::INT);
        let mut vals = vec![text];
        vals.extend(flat);
        vals.push(tree_slot);
        vals.push(root_slot);
        let code = self.status_code("msrt_html_parse", &vals)?;
        let zero = self.b.iconst(0);
        let good = self.b.icmp(Cc::Eq, code, zero);
        let TyKind::Alt(ra) = self.b.m.types.kind(rty).clone() else {
            return Err(Error::new("parse returns a Result"));
        };
        let ok = self.ok_case_index(ra)?;
        let err = self
            .hcase(ra, "error")
            .map_err(|_| Error::new("not a Result"))?;
        let node = self.b.m.alts[ra.index()].cases[ok].fields[0].1;
        let hir = self.hir.clone();
        let convert = self.cx.html_node_fn(self.b.m, &hir, node);
        self.two_ways(
            good,
            rty,
            &mut |s| {
                let tree = s.take_slot(tree_slot, tree_ty);
                let raw = s.take_slot(root_slot, MTy::INT);
                let m = s.b.iconst(NO_NODE);
                let root = s.b.binop(Op::And, raw, m);
                let n = s.b.call(convert, &[tree, root]);
                s.drop_value(tree);
                Ok(Some(s.b.alt_new(ra, ok as u32, &[n])))
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
