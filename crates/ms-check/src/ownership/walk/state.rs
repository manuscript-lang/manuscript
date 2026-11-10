//! Walker state: declarations, diagnostics, liveness, borrows and place resolution.

use super::active::ActiveBorrows;
use super::*;

impl Walker<'_> {
    pub(super) fn declare(
        &mut self,
        b: &BindingRef,
        role: Role,
        perm: Perm,
        parameter: Option<usize>,
        is_receiver: bool,
    ) {
        let class = self.cx.classes.class(self.syms, &b.ty);
        self.meta.insert(
            b.uid,
            Meta {
                binding: b.clone(),
                role,
                class,
                perm,
                origins: Vec::new(),
                lambda: None,
                parameter,
                is_receiver,
                parent: None,
                deferred: None,
                in_lambda: !self.captured.is_empty(),
            },
        );
        self.declared.push(b.uid);
        self.facts.bindings.insert(
            b.uid,
            BindingFacts {
                binding: b.clone(),
                role,
                class,
                owned: !matches!(perm, Perm::Borrowed | Perm::MutBorrowed)
                    && !matches!(
                        role,
                        Role::Parameter | Role::SelfValue | Role::LambdaParameter | Role::Fixture
                    ),
                borrows: Vec::new(),
                exclusive: false,
            },
        );
    }

    /// Declares a `var` binding that holds `origins` exclusively.
    pub(super) fn declare_mut_borrow(
        &mut self,
        b: &BindingRef,
        role: Role,
        origins: Vec<Place>,
        pos: Pos,
        parent: Option<usize>,
    ) {
        self.declare(b, role, Perm::MutBorrowed, None, false);
        if let Some(m) = self.meta.get_mut(&b.uid) {
            m.parent = parent;
        }
        if let Some(f) = self.facts.bindings.get_mut(&b.uid) {
            f.owned = false;
            f.exclusive = true;
            f.borrows = origins.clone();
        }
        if let Some(m) = self.meta.get_mut(&b.uid) {
            m.origins = origins.clone();
        }
        self.active.push(Borrow {
            holder: b.uid,
            holder_name: b.name,
            origins: origins.into_iter().map(|p| (p, true)).collect(),
            pos,
            why: "mutable borrow".to_string(),
        });
    }

    /// Declares a binding that borrows from `origins`.
    pub(super) fn declare_borrow(
        &mut self,
        b: &BindingRef,
        role: Role,
        origins: Vec<Place>,
        pos: Pos,
        why: &str,
    ) {
        self.declare(b, role, Perm::Borrowed, None, false);
        if let Some(f) = self.facts.bindings.get_mut(&b.uid) {
            f.owned = false;
            f.borrows = origins.clone();
        }
        if let Some(m) = self.meta.get_mut(&b.uid) {
            m.origins = origins.clone();
        }
        self.active.push(Borrow {
            holder: b.uid,
            holder_name: b.name,
            origins: origins.into_iter().map(|p| (p, false)).collect(),
            pos,
            why: why.to_string(),
        });
    }

    /// Remembers the scrutinee a borrowed part would make consume its parameter.
    pub(super) fn defer(&mut self, b: &BindingRef, source: &Scrutinee) {
        if let Some(m) = self.meta.get_mut(&b.uid) {
            m.deferred = source.deferred;
        }
    }

    // ------------------------------------------------------ diagnostics

    pub(super) fn error(&mut self, pos: Pos, message: impl Into<String>) {
        let message = message.into();
        if self
            .diags
            .iter()
            .any(|d| d.pos == pos && d.message == message)
        {
            return;
        }
        self.diags.push(Diagnostic {
            cause: Default::default(),
            opener_line: 0,
            file: Arc::from(self.syms.str(self.cx.m.data.file)),
            pos,
            phase: Phase::Type,
            message,
            end: None,
            fix: None,
        });
    }

    /// Reports like `error`, with a machine-applicable fix.
    pub(super) fn error_fix(&mut self, pos: Pos, message: impl Into<String>, fix: DiagnosticFix) {
        let message = message.into();
        self.error(pos, message.clone());
        if let Some(d) = self.diags.last_mut()
            && d.pos == pos
            && d.message == message
        {
            d.fix = Some(fix);
        }
    }

    pub(super) fn at(&self, node: NodeId) -> String {
        self.positions
            .get(&node)
            .map(|p| format!("{}:{}", p.line, p.column))
            .unwrap_or_else(|| "later".to_string())
    }

    /// Where a moved value is used again: a use that is the move itself runs again on the
    /// next pass of an enclosing loop.
    pub(super) fn later_at(&self, moved: NodeId, next: NodeId) -> String {
        if moved == next {
            " on the next loop iteration".to_string()
        } else {
            format!(" at {}", self.at(next))
        }
    }

    // ------------------------------------------------------------ types

    pub(super) fn class_of(&self, e: &Expr) -> Class {
        self.cx.classes.class(self.syms, &self.cx.m.ty(e))
    }

    pub(super) fn name_of(&self, uid: usize) -> Name {
        self.meta
            .get(&uid)
            .map(|m| m.binding.name)
            .unwrap_or_else(|| n("?"))
    }

    // ----------------------------------------------------- liveness

    pub(super) fn is_last(&self, node: NodeId, b: &BindingRef) -> bool {
        self.cx.live.uses.get(&(node, b.uid)).is_none_or(|u| u.last)
    }

    pub(super) fn next_use(&self, node: NodeId, b: &BindingRef) -> Option<NodeId> {
        self.cx.live.uses.get(&(node, b.uid)).and_then(|u| u.next)
    }

    pub(super) fn record(&mut self, node: NodeId, b: &BindingRef, access: Access) {
        let last = access != Access::Write && self.is_last(node, b);
        self.facts.uses.insert(
            (node, b.uid),
            Use {
                node,
                binding: b.uid,
                access,
                last,
            },
        );
        if last
            && self
                .active
                .iter()
                .any(|a| a.holder == b.uid && a.why != PROMISE_WHY)
        {
            self.pending.push(b.uid);
        }
        if last && access == Access::Move {
            // A promise handed on (`wait_all([p, q])`) ends where its new owner does: a binding or
            // local container that receives it takes the borrow over (`take_carried`).
            let (moved, kept): (Vec<_>, Vec<_>) = std::mem::take(&mut self.active)
                .into_iter()
                .partition(|a| a.holder == b.uid && a.why == PROMISE_WHY);
            self.active = kept.into_iter().collect();
            self.carried.extend(moved);
        }
    }

    // ------------------------------------------------------- borrows

    /// Reports a change to `places` while a live borrow covers them.
    pub(super) fn check_change(
        &mut self,
        pos: Pos,
        places: &[Place],
        what: &str,
        shown: &str,
        ignore: Option<usize>,
    ) {
        // Only a borrow rooted at one of these places can conflict; the per-root counts tell
        // that without scanning every live borrow.
        if !places.iter().any(|p| self.active.touches(p.root, false)) {
            return;
        }
        let found = self.active.iter().find(|a| {
            a.origins
                .iter()
                .any(|(o, _)| places.iter().any(|p| p.overlaps(o)))
                && !ignore.is_some_and(|i| self.related(a.holder, i))
        });
        if let Some(a) = found {
            let (holder, why, bpos) = (a.holder_name, a.why.clone(), a.pos);
            let held_ty = self.meta.get(&a.holder).map(|m| m.binding.ty.clone());
            let remedy = if self.syms.str(holder) == "for" {
                format!(
                    "iterate over a clone instead by appending `.{CLONE}()` to the loop's iterable expression"
                )
            } else if why == PROMISE_WHY {
                String::new()
            } else if held_ty.as_ref().and_then(clone_blocker).is_some() {
                format!(
                    "or give `{holder_t}` its own value by converting a clone of the concrete value",
                    holder_t = self.syms.str(holder)
                )
            } else {
                format!(
                    "or give `{holder_t}` its own value by ending its initializer with `.{CLONE}()`",
                    holder_t = self.syms.str(holder)
                )
            };
            if why == PROMISE_WHY {
                self.error(
                    pos,
                    format!(
                        "cannot {what} `{shown}` while promise `{holder_t}` (started at {}:{}) reads it; a promise reads what it captures until it is dropped, so wait for it and move it into `wait_all` first, or {what} a copy",
                        bpos.line, bpos.column
                    , holder_t = self.syms.str(holder)),
                );
                return;
            }
            self.error(
                pos,
                format!(
                    "cannot {what} `{shown}` while `{holder_t}` borrows it ({why}, at {}:{}); finish using `{holder_t}` before this, {remedy}",
                    bpos.line, bpos.column
                , holder_t = self.syms.str(holder)),
            );
        }
    }

    /// Reports a read of `places` while a closure or a `var` borrow holds them
    /// exclusively; `reader` is the binding the read goes through.
    pub(super) fn check_read(&mut self, pos: Pos, places: &[Place], shown: &str, reader: usize) {
        if !places.iter().any(|p| self.active.touches(p.root, true)) {
            return;
        }
        let found = self.active.iter().find(|a| {
            a.origins
                .iter()
                .any(|(o, exclusive)| *exclusive && places.iter().any(|p| p.overlaps(o)))
                && !self.related(a.holder, reader)
        });
        if let Some(a) = found {
            let (holder, bpos, why) = (a.holder_name, a.pos, a.why.clone());
            let text = if why == "mutable borrow" {
                format!(
                    "cannot use `{shown}` while `{holder_t}` (a mutable borrow at {}:{}) holds it; finish using `{holder_t}` first, or use the value through `{holder_t}`",
                    bpos.line,
                    bpos.column,
                    holder_t = self.syms.str(holder)
                )
            } else {
                format!(
                    "cannot use `{shown}` while closure `{holder_t}` (made at {}:{}) changes it; call or drop the closure first, or clone the value before creating it",
                    bpos.line,
                    bpos.column,
                    holder_t = self.syms.str(holder)
                )
            };
            self.error(pos, text);
        }
    }

    pub(super) fn release_pending(&mut self) {
        if self.pending.is_empty() {
            return;
        }
        let pending = std::mem::take(&mut self.pending);
        self.active.release(&pending, |a| a.why != PROMISE_WHY);
    }

    pub(super) fn join_active(a: ActiveBorrows, b: ActiveBorrows) -> ActiveBorrows {
        let mut out = a;
        for x in b {
            if !out.held_by(x.holder) {
                out.push(x);
            }
        }
        out
    }

    // ------------------------------------------------------- places

    pub(super) fn is_place(&self, e: &Expr) -> bool {
        match &e.kind {
            ExprKind::Name(_) => matches!(self.cx.m.resolution(e), Resolution::Local(_)),
            // A bound method (`value.method` as a function value) is a new closure, not a part;
            // a function-valued field is one.
            ExprKind::Member { left, .. } => {
                (self.cx.m.ty(e).kind != Kind::Function
                    || !matches!(self.cx.m.resolution(e), Resolution::Method(_)))
                    && self.is_place(left)
            }
            ExprKind::Index { left, .. } => self.is_place(left),
            ExprKind::Apply {
                left,
                value: Some(_),
                ..
            } => self.cx.m.info(e).native_str(self.syms) == "index" && self.is_place(left),
            _ => false,
        }
    }

    pub(super) fn resolve(&self, p: &Place) -> Vec<Place> {
        match self.meta.get(&p.root) {
            Some(m)
                if matches!(m.perm, Perm::Borrowed | Perm::MutBorrowed)
                    && !m.origins.is_empty() =>
            {
                m.origins.iter().map(|o| o.join(&p.path)).collect()
            }
            _ => vec![p.clone()],
        }
    }

    /// The step for `left[index]`: a list element at a non-negative literal index is told apart
    /// from the others; every other element access may alias any element.
    pub(super) fn element_step(&self, left: &Expr, index: &Expr) -> Step {
        let ExprKind::Number(t) = &index.kind else {
            return Step::Element;
        };
        let literal = || {
            ms_syntax::number::canonical(self.syms.str(t))
                .parse::<u64>()
                .ok()
        };
        if self.cx.m.ty(left).is(Builtin::List) {
            return literal().map_or(Step::Element, Step::Index);
        }
        Step::Element
    }

    /// Evaluates the index expressions of a place chain and returns the place.
    pub(super) fn place(&mut self, e: &Expr) -> Option<(PlaceInfo, Place)> {
        match &e.kind {
            ExprKind::Name(_) => {
                let Resolution::Local(b) = self.cx.m.resolution(e) else {
                    return None;
                };
                let p = Place::local(b.uid);
                let info = PlaceInfo {
                    resolved: self.resolve(&p),
                    root: b.clone(),
                    root_node: e.id,
                    projection: false,
                    through_ref: None,
                    text: self.syms.str(b.name).to_string(),
                };
                Some((info, p))
            }
            ExprKind::Member { left, name } => {
                let (mut info, p) = self.place(left)?;
                let p = p.then(Step::Field(*name));
                info.resolved = self.resolve(&p);
                info.projection = true;
                info.text = format!("{}.{}", info.text, self.syms.str(name));
                Some((info, p))
            }
            ExprKind::Index { left, index } => {
                let (mut info, p) = self.place(left)?;
                self.expr(index, Demand::Read);
                let p = p.then(self.element_step(left, index));
                info.resolved = self.resolve(&p);
                info.projection = true;
                info.text = format!("{}[..]", info.text);
                Some((info, p))
            }
            ExprKind::Apply {
                left,
                value: Some(v),
                ..
            } => {
                let (mut info, p) = self.place(left)?;
                self.expr(v, Demand::Read);
                let p = p.then(self.element_step(left, v));
                info.resolved = self.resolve(&p);
                info.projection = true;
                info.text = format!("{}[..]", info.text);
                Some((info, p))
            }
            _ => None,
        }
    }
}
