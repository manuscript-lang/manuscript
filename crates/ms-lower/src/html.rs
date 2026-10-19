//! `@std/html.ms` `parse`: the runtime parses into a tree handle, and one generated function
//! copies that tree into `HtmlNode` values (`msrt_html_*` read a node at a time).

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use crate::native::NArg;
use crate::rtcall::Input;
use ms_check::hir::ModuleHir;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncId, Imm, Mode, Module, Op, Param, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use std::rc::Rc;

const KIND_DOCUMENT: i64 = 0;
const KIND_ELEMENT: i64 = 1;
const KIND_TEXT: i64 = 2;
const KIND_COMMENT: i64 = 3;
const KIND_DOCTYPE: i64 = 4;
/// `first_child` and `next_sibling` answer this when there is no node.
const NO_NODE: i64 = 0xffff_ffff;

/// A queued tree copier.
pub struct HtmlJob {
    /// `HtmlNode`.
    pub ty: ct::Ty,
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
    /// The function copying a parsed node (and its subtree) into an `HtmlNode`.
    pub(crate) fn html_fn(
        &mut self,
        m: &mut Module,
        hir: &Rc<ModuleHir>,
        node: &ct::Ty,
    ) -> Result<FuncId, Error> {
        let key = format!("html-node:{}", ct::type_key(node));
        if let Some(f) = self.helpers.get(&key) {
            return Ok(*f);
        }
        let mt = self.lower_ty(m, node)?;
        let tree = tree_ty(m);
        let params = vec![borrowed(tree), borrowed(MTy::INT)];
        let id = m.add_func(ms_mir::ir::Func::new("html_node", params, mt));
        self.helpers.insert(key, id);
        self.queue.push(Job {
            func: id,
            kind: JobKind::Html(Rc::new(HtmlJob {
                ty: node.clone(),
                hir: hir.clone(),
            })),
        });
        Ok(id)
    }
}

/// Lowers the body of a queued tree copier.
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
    let result = fl.lower_html_node(&job.ty, func);
    let mut f = fl.b.into_func();
    result?;
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

impl FnLower<'_> {
    fn hmasked(&mut self, sym: &str, args: &[Value], mask: i64) -> Result<Value, Error> {
        let raw = self.call_runtime(sym, args, MTy::INT)?;
        let m = self.b.iconst(mask);
        Ok(self.b.binop(Op::And, raw, m))
    }

    /// A string the runtime reads from node `id`, owned.
    fn htext(
        &mut self,
        sym: &str,
        tree: Value,
        id: Value,
        which: Option<i64>,
    ) -> Result<Value, Error> {
        let mut args = vec![tree, id];
        if let Some(w) = which {
            args.push(self.b.iconst(w));
        }
        self.call_runtime(sym, &args, MTy::STR)
    }

    fn lower_html_node(&mut self, t: &ct::Ty, me: FuncId) -> Result<(), Error> {
        let mt = self.cx.lower_ty(self.b.m, t)?;
        let TyKind::Alt(a) = self.b.m.types.kind(mt).clone() else {
            return Err(Error::new("HtmlNode is an alternative"));
        };
        let cases = ct::cases(t);
        let case = |name: &str| -> Result<usize, Error> {
            cases
                .iter()
                .position(|c| c.name.as_str() == name)
                .ok_or_else(|| Error::new(format!("HtmlNode lacks {name}")))
        };
        let (document, element, text, comment, doctype) = (
            case("Document")?,
            case("Element")?,
            case("Text")?,
            case("Comment")?,
            case("Doctype")?,
        );
        let p = self.b.params();
        let (tree, id) = (p[0], p[1]);
        let kind = self.hmasked("msrt_html_kind", &[tree, id], 0xff)?;
        let kinds = [
            KIND_DOCUMENT,
            KIND_ELEMENT,
            KIND_TEXT,
            KIND_COMMENT,
            KIND_DOCTYPE,
        ];
        let blocks: Vec<_> = kinds.iter().map(|_| self.b.new_block()).collect();
        let other = self.b.new_block();
        let arms: Vec<(i64, _)> = kinds.iter().copied().zip(blocks.iter().copied()).collect();
        self.b.switch(kind, &arms, other);
        self.b.seal_block(other);
        for b in &blocks {
            self.b.seal_block(*b);
        }
        // An unknown kind reads as an empty document.
        self.b.switch_to(other);
        let children_ty = self.cx.lower_ty(self.b.m, &cases[document].fields[0].ty)?;
        let nodes = self.hchildren(tree, id, children_ty, me)?;
        let v = self.b.alt_new(a, document as u32, &[nodes]);
        self.b.ret(Some(v));

        self.b.switch_to(blocks[0]);
        let nodes = self.hchildren(tree, id, children_ty, me)?;
        let v = self.b.alt_new(a, document as u32, &[nodes]);
        self.b.ret(Some(v));

        self.b.switch_to(blocks[1]);
        let fields = &cases[element].fields;
        let tag = self.htext("msrt_html_data", tree, id, None)?;
        let space = self.htext("msrt_html_namespace", tree, id, None)?;
        let attrs_ty = self.cx.lower_ty(self.b.m, &fields[2].ty)?;
        let attrs = self.hattributes(tree, id, attrs_ty)?;
        let kids_ty = self.cx.lower_ty(self.b.m, &fields[3].ty)?;
        let kids = self.hchildren(tree, id, kids_ty, me)?;
        let v = self
            .b
            .alt_new(a, element as u32, &[tag, space, attrs, kids]);
        self.b.ret(Some(v));

        for (blk, idx) in [(blocks[2], text), (blocks[3], comment)] {
            self.b.switch_to(blk);
            let data = self.htext("msrt_html_data", tree, id, None)?;
            let v = self.b.alt_new(a, idx as u32, &[data]);
            self.b.ret(Some(v));
        }

        self.b.switch_to(blocks[4]);
        let name = self.htext("msrt_html_data", tree, id, None)?;
        let public = self.htext("msrt_html_doctype_id", tree, id, Some(0))?;
        let system = self.htext("msrt_html_doctype_id", tree, id, Some(1))?;
        let v = self.b.alt_new(a, doctype as u32, &[name, public, system]);
        self.b.ret(Some(v));
        Ok(())
    }

    /// An owned list of the copied children of node `id`.
    fn hchildren(&mut self, tree: Value, id: Value, lt: MTy, me: FuncId) -> Result<Value, Error> {
        let TyKind::List(et) = self.b.m.types.kind(lt).clone() else {
            return Err(Error::new("children are a list"));
        };
        let acc = self.fresh_var(lt);
        let zero = self.b.iconst(0);
        let empty = self.b.list_new(et, zero);
        self.b.def_var(acc, empty);
        let cur = self.b.declare_var(MTy::INT, Mode::Borrow);
        let first = self.hmasked("msrt_html_first_child", &[tree, id], NO_NODE)?;
        self.b.def_var(cur, first);
        let (head, body, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(head, &[]);
        self.b.switch_to(head);
        let c = self.b.use_var(cur);
        let end = self.b.iconst(NO_NODE);
        let more = self.b.icmp(Cc::Ne, c, end);
        self.b.br_if(more, body, &[], exit, &[]);
        self.b.seal_block(body);
        self.b.switch_to(body);
        let c = self.b.use_var(cur);
        let node = self.b.call(me, &[tree, c]);
        let l = self.b.use_var(acc);
        let l2 = self.b.list_push(l, node);
        self.b.def_var(acc, l2);
        let next = self.hmasked("msrt_html_next_sibling", &[tree, c], NO_NODE)?;
        self.b.def_var(cur, next);
        self.b.br(head, &[]);
        self.b.seal_block(head);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(self.b.use_var(acc))
    }

    /// An owned list of the attributes of element `id`.
    fn hattributes(&mut self, tree: Value, id: Value, lt: MTy) -> Result<Value, Error> {
        let TyKind::List(et) = self.b.m.types.kind(lt).clone() else {
            return Err(Error::new("attributes are a list"));
        };
        let TyKind::Rec(rid) = self.b.m.types.kind(et).clone() else {
            return Err(Error::new("an attribute is a record"));
        };
        let n = self.call_runtime("msrt_html_attr_count", &[tree, id], MTy::INT)?;
        let acc = self.fresh_var(lt);
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
        let attr = self.b.rec_new(rid, &fields);
        let l = self.b.use_var(acc);
        let l2 = self.b.list_push(l, attr);
        self.b.def_var(acc, l2);
        let one = self.b.iconst(1);
        let next = self.b.binop(Op::IAdd, iv, one);
        self.b.def_var(i, next);
        self.b.br(head, &[]);
        self.b.seal_block(head);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(self.b.use_var(acc))
    }

    /// `parse(text, limits)`: the runtime tree copied into an `HtmlNode` on success.
    pub(crate) fn html_parse(
        &mut self,
        node: &ct::Ty,
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let sym = "msrt_html_parse";
        let sig = crate::rtcall::rt_sig(sym).ok_or_else(|| Error::new("no html parser"))?;
        let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("parse returns a Result"));
        };
        let ok = self.ok_case_index(a)?;
        let text = self.borrow(args[0].val);
        let limits = args.get(1).copied();
        let mut vals = Vec::new();
        let input = Input {
            val: limits.map(|l| l.val),
            wrapped: limits.is_some_and(|l| l.wrapped),
        };
        // `params` begins at the first field's presence flag.
        self.flatten_optional_record(input, &sig.params[1..7], &mut vals)?;
        let mut call = vec![text];
        call.extend_from_slice(&vals[1..]);
        let tree_t = tree_ty(self.b.m);
        let tree_slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(tree_t), Some(MTy::PTR))
            .expect("slot");
        let zero = self.b.iconst(0);
        let root_slot = self.put_slot(zero);
        call.push(tree_slot);
        call.push(root_slot);
        let code = self.status_code(sym, &call)?;
        let zero = self.b.iconst(0);
        let good = self.b.icmp(Cc::Eq, code, zero);
        let hir = self.hir.clone();
        let copier = self.cx.html_fn(self.b.m, &hir, node)?;
        self.two_ways(
            good,
            result,
            &mut |s| {
                let tree =
                    s.b.emit(Op::Take, &[tree_slot], Imm::Ty(tree_t), Some(tree_t))
                        .expect("take");
                let root = s.take_slot(root_slot, MTy::INT);
                let doc = s.b.call(copier, &[tree, root]);
                s.drop_value(tree);
                Ok(Some(s.b.alt_new(a, ok as u32, &[doc])))
            },
            &mut |s| s.status_failure(result, code, sym).map(Some),
        )
    }
}
