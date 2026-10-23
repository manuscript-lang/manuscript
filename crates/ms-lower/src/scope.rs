//! Module scopes of implementations: a local extension is visible only in its own module, so
//! anything keyed by a type that has one is also keyed by the module that asks.

use crate::cx::Cx;
use ms_check::types::{self as ct, Name};
use ms_mir::ir::Module;
use ms_mir::types::{Ty as MTy, TyKind};

/// Whether `t` mentions a type variable.
fn has_variable(t: &ct::Ty) -> bool {
    t.kind == ct::Kind::Variable
        || t.args.iter().any(has_variable)
        || t.params.iter().any(|p| has_variable(&p.ty))
        || t.result.as_ref().is_some_and(has_variable)
}

impl crate::func::FnLower<'_> {
    /// The module whose local implementations this expression uses: the caller's, for what
    /// is written with the instance's type variables, else this module.
    pub(crate) fn evidence(&self) -> Name {
        self.scope_override.unwrap_or(self.hir.data.file)
    }

    /// The module whose evidence this generic instance was created for.
    fn instance_evidence(&self) -> Option<Name> {
        self.subst.get(&ct::n(EVIDENCE)).map(|t| t.id)
    }

    /// The evidence scope for an expression whose declared (unsubstituted) types are `pre`.
    pub(crate) fn evidence_of(&self, pre: &[ct::Ty]) -> Option<Name> {
        pre.iter()
            .any(has_variable)
            .then(|| self.instance_evidence())
            .flatten()
    }

    /// The scope number of the glue this body builds for `t`.
    pub(crate) fn glue_scope(&mut self, t: MTy) -> u32 {
        let module = self.evidence();
        self.cx.glue_scope(self.b.m, t, module)
    }

    /// The instance of `c` under `subst`, created for the current evidence scope.
    pub(crate) fn instance(
        &mut self,
        c: &std::rc::Rc<ms_check::hir::Callable>,
        subst: &ct::Subst,
    ) -> Result<ms_mir::ir::FuncId, crate::Error> {
        let scope = self.evidence();
        self.cx.function_in(self.b.m, c, subst, scope)
    }
}

/// The substitution entry naming the module that provides an instance's type evidence.
const EVIDENCE: &str = "$evidence";

impl Cx {
    /// The instance of `c` under `subst`. An instance over a type with a local extension is
    /// separate per `scope`, the module whose implementations its type variables use.
    pub(crate) fn function_in(
        &mut self,
        m: &mut Module,
        c: &std::rc::Rc<ms_check::hir::Callable>,
        subst: &ct::Subst,
        scope: Name,
    ) -> Result<ms_mir::ir::FuncId, crate::Error> {
        let key = ct::n(EVIDENCE);
        if subst.contains_key(&key) || !subst.values().any(|t| self.mentions_extension(t)) {
            return self.function_for(m, c, subst);
        }
        let mut scoped = subst.clone();
        scoped.insert(key, ct::primitive(scope.as_str()));
        self.function_for(m, c, &scoped)
    }

    /// The descriptor scope number of a module (`0` is no scope).
    pub(crate) fn scope_tok(&mut self, scope: Name) -> u32 {
        if let Some(i) = self.scope_names.iter().position(|s| *s == scope) {
            return i as u32 + 1;
        }
        self.scope_names.push(scope);
        self.scope_names.len() as u32
    }

    /// The module behind a scope number. Without a scope no local extension is visible.
    pub(crate) fn scope_name(&self, tok: u32) -> Name {
        match tok.checked_sub(1) {
            Some(i) => self.scope_names[i as usize],
            None => ct::n(""),
        }
    }

    /// Whether `t` is, or is built from, a type with a local extension.
    pub(crate) fn mentions_extension(&self, t: &ct::Ty) -> bool {
        self.extended.contains(&t.id)
            || t.args.iter().any(|a| self.mentions_extension(a))
            || t.params.iter().any(|p| self.mentions_extension(&p.ty))
            || t.result
                .as_ref()
                .is_some_and(|r| self.mentions_extension(r))
    }

    /// The key suffix that separates `t`'s per-module tables.
    pub(crate) fn scope_key(&self, t: &ct::Ty, scope: Name) -> String {
        if self.mentions_extension(t) {
            format!("@{scope}")
        } else {
            String::new()
        }
    }

    /// Whether values of the MIR type hold a type with a local extension.
    pub(crate) fn holds_extension(&self, m: &Module, t: MTy) -> bool {
        self.holds_extension_in(m, t, &mut Vec::new())
    }

    fn holds_extension_in(&self, m: &Module, t: MTy, seen: &mut Vec<MTy>) -> bool {
        if seen.contains(&t) {
            return false;
        }
        seen.push(t);
        if self
            .source_tys
            .get(&t)
            .is_some_and(|c| self.mentions_extension(c))
        {
            return true;
        }
        match m.types.kind(t).clone() {
            TyKind::Rec(r) => m.records[r.index()]
                .fields
                .iter()
                .any(|f| self.holds_extension_in(m, f.1, seen)),
            TyKind::Alt(a) => m.alts[a.index()]
                .cases
                .iter()
                .flat_map(|c| c.fields.iter())
                .any(|f| self.holds_extension_in(m, f.1, seen)),
            TyKind::List(e) | TyKind::Opt(e) => self.holds_extension_in(m, e, seen),
            TyKind::Obj(_, args) => args.iter().any(|a| self.holds_extension_in(m, *a, seen)),
            TyKind::Fn(params, ret) => params
                .iter()
                .chain(std::iter::once(&ret))
                .any(|a| self.holds_extension_in(m, *a, seen)),
            _ => false,
        }
    }

    /// The scope number `t`'s equality and descriptor glue are built for in `scope`.
    pub(crate) fn glue_scope(&mut self, m: &Module, t: MTy, scope: Name) -> u32 {
        if self.holds_extension(m, t) {
            self.scope_tok(scope)
        } else {
            0
        }
    }
}
