//! Mutation of places and the patterns that bind parts of a matched value.

use super::*;

impl Walker<'_> {
    // ------------------------------------------------------- mutation

    pub(super) fn mark_mutated(&mut self, uid: usize) {
        for set in &mut self.mutated {
            set.insert(uid);
        }
    }

    /// A change in place through a place expression (`var` argument,
    /// mutating receiver, field assignment).
    pub(super) fn mutate(&mut self, pos: Pos, info: &PlaceInfo, what: &str) {
        let root = info.root.clone();
        let (perm, role, parameter, receiver) = {
            let m = &self.meta[&root.uid];
            (m.perm, m.role, m.parameter, m.is_receiver)
        };
        let text = info.text.clone();
        // `?.` desugars to a hidden `?N` binding of the payload. Changing it changes the
        // optional it was read from, so the binding becomes an exclusive borrow of that place.
        if self.syms.str(root.name).starts_with('?') && perm != Perm::MutBorrowed {
            let Some(place) = self.chain_places.get(&root.uid).cloned() else {
                // Only a variable (or a part of one) can be changed through `?.`; a call result
                // such as `m.get(k)` is a read-only view.
                self.error(
                    pos,
                    format!("cannot {what} through `?.` on a value that is not a variable; bind it to a `var` first, or index the collection and assign"),
                );
                return;
            };
            // The read-only borrow `?N` held becomes the exclusive one.
            self.active.release(&[root.uid], |_| true);
            let before = self.diags.len();
            self.mutate(pos, &place, what);
            if self.diags.len() == before {
                let origins = place.resolved.clone();
                let parent = self.borrow_parent(&place.root);
                self.declare_mut_borrow(&root, role, origins, pos, parent);
            }
            return;
        }
        if let Some(field) = info.through_ref {
            self.error(
                pos,
                format!("cannot {what} `{text}`: `{field_t}` is a `ref` field, a read-only view of another value", field_t = self.syms.str(field)),
            );
            return;
        }
        match perm {
            Perm::Mutable | Perm::ClosureOwned | Perm::MutBorrowed => {}
            Perm::Borrowed => {
                let from = self
                    .meta
                    .get(&root.uid)
                    .and_then(|m| m.origins.first())
                    .map(|o| self.syms.str(self.name_of(o.root)).to_string())
                    .unwrap_or_else(|| "another value".to_string());
                self.error(
                    pos,
                    format!(
                        "cannot {what} `{text}`: `{}` only borrows from `{from}`; clone it first with `var {} = {}.{CLONE}()`",
                        self.syms.str(root.name), self.syms.str(root.name), self.syms.str(root.name)
                    ),
                );
            }
            Perm::Immutable if receiver => {
                let message = format!(
                    "cannot {what} `{text}`: this method does not change its receiver; declare it `var fn` to allow that"
                );
                match self.cx.c.func.method() {
                    Some(m) => self.error_fix(pos, message, insert_at(back(m.pos, 3), "var ")),
                    None => self.error(pos, message),
                }
            }
            Perm::Immutable if parameter.is_some() => {
                let message = format!(
                    "cannot {what} `{text}`: parameter `{}` is not declared var; write `var {}: <Type>` in the signature and pass `var` at every call",
                    self.syms.str(root.name),
                    self.syms.str(root.name)
                );
                let declared = match (self.cx.c.func.method(), self.cx.c.func.func()) {
                    (Some(m), _) => m.func.params.get(parameter.unwrap_or(0)).map(|p| p.pos),
                    (None, Some(f)) => f.params.get(parameter.unwrap_or(0)).map(|p| p.pos),
                    (None, None) => None,
                };
                match declared {
                    Some(at) => self.error_fix(pos, message, insert_at(at, "var ")),
                    None => self.error(pos, message),
                }
            }
            Perm::Immutable => {
                let _ = role;
                let message = format!(
                    "cannot {what} `{text}`: `{}` is an immutable binding, immutable including its contents; declare it `var {}` to change it",
                    self.syms.str(root.name),
                    self.syms.str(root.name)
                );
                match self.var_fixes.get(&root.uid).cloned() {
                    Some(fix) => self.error_fix(pos, message, fix),
                    None => self.error(pos, message),
                }
            }
        }
        self.check_change(pos, &info.resolved, what, &text, Some(root.uid));
        self.mark_mutated(root.uid);
        self.record(info.root_node, &root, Access::Mutate);
    }

    /// A read through a place.
    pub(super) fn read_place(&mut self, pos: Pos, info: &PlaceInfo) {
        let text = info.text.clone();
        self.check_read(pos, &info.resolved, &text, info.root.uid);
        let root = info.root.clone();
        self.record(info.root_node, &root, Access::Borrow);
    }

    // ------------------------------------------------------ patterns

    /// Evaluates a matched or destructured value and says how its parts are held.
    pub(super) fn scrutinee(&mut self, e: &Expr) -> Scrutinee {
        if self.is_place(e) {
            let class = self.class_of(e);
            let whole = matches!(e.kind, ExprKind::Name(_));
            let mut deferred = None;
            if whole
                && !std::mem::take(&mut self.keep_scrutinee)
                && class != Class::Copy
                && let Resolution::Local(b) = self.cx.m.resolution(e)
                && self.is_last(e.id, &b)
            {
                let owned_local = self.meta.get(&b.uid).is_some_and(|m| {
                    !matches!(m.perm, Perm::Borrowed | Perm::MutBorrowed)
                        && m.role != Role::Parameter
                        && m.role != Role::SelfValue
                });
                // A parameter is borrowed unless a part of it is moved out of the match or loop.
                let param = self.is_consumable_param(&b);
                if owned_local || param && self.escaped.contains(&e.id) {
                    self.expr(e, Demand::Move);
                    return Scrutinee {
                        owned: true,
                        origins: Vec::new(),
                        deferred: None,
                    };
                }
                if param {
                    deferred = Some(e.id);
                }
            }
            let Some((info, _)) = self.place(e) else {
                return Scrutinee {
                    owned: true,
                    origins: Vec::new(),
                    deferred: None,
                };
            };
            self.read_place(e.pos, &info);
            return Scrutinee {
                owned: false,
                origins: info.resolved,
                deferred,
            };
        }
        if let Some(origins) = self.projection_origins(e) {
            self.expr(e, Demand::Read);
            return Scrutinee {
                owned: false,
                origins,
                deferred: None,
            };
        }
        self.expr(e, Demand::Move);
        Scrutinee {
            owned: true,
            origins: Vec::new(),
            deferred: None,
        }
    }

    /// `if var name = value`: the payload is an exclusive borrow of the part of
    /// its origin the value reads in place, or an owned value otherwise.
    pub(super) fn mutable_payload(&mut self, p: &Pattern, value: &Expr, source: &Scrutinee) {
        let Some(b) = self.cx.m.pattern_binding(p) else {
            return;
        };
        self.mutable_entry(&b, Role::Pattern, value, source, p.pos);
    }

    /// `b` borrows the entry `value` (`place[key]?` or `map.get(key)`) of `source` exclusively.
    pub(super) fn mutable_entry(
        &mut self,
        b: &BindingRef,
        role: Role,
        value: &Expr,
        source: &Scrutinee,
        pos: Pos,
    ) {
        // `place[key]?` and `map.get(key)` both find an entry in place.
        let probe = matches!(value.kind, ExprKind::Probe(_)) || self.map_get(value);
        let value = match &value.kind {
            ExprKind::Probe(target) => &**target,
            _ => value,
        };
        let named = self.root_name(value);
        let root = named.and_then(|n| match self.cx.m.resolution(n) {
            Resolution::Local(r) => Some((r, n.id)),
            _ => None,
        });
        let (Some((root, root_node)), false) = (root, source.owned) else {
            self.declare(b, role, Perm::Mutable, None, false);
            return;
        };
        let info = PlaceInfo {
            text: self.expr_text(value),
            root,
            root_node,
            resolved: source.origins.clone(),
            projection: true,
            through_ref: None,
        };
        if !probe {
            self.error(
                pos,
                format!(
                    "`if var` borrows an entry written as `place[key]?` or `map.get(key)`, but `{}` is not one; read the payload with `if x := value:`, then use `var copy = x.clone()` for an independent mutable copy, or write the changed value back",
                    info.text
                ),
            );
            self.declare(b, role, Perm::Mutable, None, false);
            return;
        }
        let before = self.diags.len();
        self.mutate(pos, &info, "borrow mutably");
        if self.diags.len() == before {
            let parent = self.borrow_parent(&info.root);
            self.declare_mut_borrow(b, role, source.origins.clone(), pos, parent);
        } else {
            self.declare(b, role, Perm::Mutable, None, false);
        }
    }

    /// The name expression a place chain or accessor call starts from.
    pub(super) fn root_name<'e>(&self, e: &'e Expr) -> Option<&'e Expr> {
        match &e.kind {
            ExprKind::Name(_) => Some(e),
            ExprKind::Member { left, .. }
            | ExprKind::Index { left, .. }
            | ExprKind::Apply { left, .. } => self.root_name(left),
            ExprKind::Call { callee, .. } => self.root_name(callee),
            _ => None,
        }
    }

    /// The mutable borrow a new borrow is taken through, if its root is one.
    pub(super) fn borrow_parent(&self, root: &BindingRef) -> Option<usize> {
        self.meta
            .get(&root.uid)
            .filter(|m| m.perm == Perm::MutBorrowed)
            .map(|_| root.uid)
    }

    /// Whether `holder` is `of` or a mutable borrow `of` was taken through.
    pub(super) fn related(&self, holder: usize, of: usize) -> bool {
        let mut cur = Some(of);
        while let Some(c) = cur {
            if c == holder {
                return true;
            }
            cur = self.meta.get(&c).and_then(|m| m.parent);
        }
        false
    }

    pub(super) fn is_consumable_param(&self, b: &BindingRef) -> bool {
        self.meta
            .get(&b.uid)
            .is_some_and(|m| m.perm == Perm::Immutable && m.parameter.is_some())
    }

    /// Registers the resources an owning pattern binds for the scope-end close.
    pub(super) fn pattern_resources(&mut self, p: &Pattern, s: &Stmt) {
        match &p.kind {
            PatternKind::Name(_) => {
                if let Some(b) = self.cx.m.pattern_binding(p)
                    && self.may_close(&b.ty)
                {
                    let closable = self.closable(s, &b.ty);
                    self.resources.push((b.uid, b.name, p.pos, closable));
                }
            }
            PatternKind::List(items) => items.iter().for_each(|i| self.pattern_resources(i, s)),
            PatternKind::Type(fields) => fields
                .iter()
                .for_each(|f| self.pattern_resources(&f.pattern, s)),
        }
    }

    pub(super) fn pattern_bindings(&mut self, p: &Pattern, source: &Scrutinee, role: Role) {
        match &p.kind {
            PatternKind::Name(_) => {
                if let Some(b) = self.cx.m.pattern_binding(p) {
                    self.payload(&b, source, role, p.pos);
                }
            }
            PatternKind::List(items) => items
                .iter()
                .for_each(|i| self.pattern_bindings(i, source, role)),
            PatternKind::Type(fields) => fields
                .iter()
                .for_each(|f| self.pattern_bindings(&f.pattern, source, role)),
        }
    }

    pub(super) fn payload(&mut self, b: &BindingRef, source: &Scrutinee, role: Role, pos: Pos) {
        let class = self.cx.classes.class(self.syms, &b.ty);
        if class == Class::Copy || source.owned {
            let perm = if role == Role::Var {
                Perm::Mutable
            } else {
                Perm::Immutable
            };
            self.declare(b, role, perm, None, false);
        } else {
            self.declare_borrow(b, role, source.origins.clone(), pos, "pattern binding");
            self.defer(b, source);
        }
    }
}
