//! Module-level constants.

use crate::checker::Checker;
use crate::syntax::*;
use crate::types::*;
use ms_syntax::ast::*;
use std::collections::HashMap;

impl Checker {
    /// Resolves a constant's type once: its annotation, or the type of its
    /// initializer. A constant that depends on itself is reported and typed
    /// `<invalid>`. The use-site rewrite makes every use evaluate the
    /// initializer, so constants have no initialization order and hold no
    /// shared state.
    pub(crate) fn constant_type(&mut self, s: &SymRef) {
        if s.ty_opt().is_some() {
            return;
        }
        let decl = s.decl.clone().expect("constant declaration");
        let constant = decl.constant().expect("constant");
        if self.constants_visiting.contains(&s.key()) {
            self.report_constant_cycle(s);
            *s.ty.borrow_mut() = Some(function(Vec::new(), invalid()));
            return;
        }
        self.constants_visiting.insert(s.key());
        let ok = self.constant_expression(&constant.value);
        let result = if !ok {
            Some(invalid())
        } else if constant.ty.is_some() {
            Some(self.resolve(constant.ty.as_ref(), false))
        } else {
            None
        };
        let result = match result {
            Some(t) => t,
            None => {
                let old = std::mem::replace(&mut self.scope, crate::checker::Scope::new(None));
                let info = self.expression(&constant.value, None);
                self.scope = old;
                info.t()
            }
        };
        self.constants_visiting.remove(&s.key());
        if s.ty_opt().is_none() {
            *s.ty.borrow_mut() = Some(function(Vec::new(), result));
        }
    }

    /// Accepts literals, operators, collection literals, and names of other
    /// constants or nullary cases; everything else needs a function.
    fn constant_expression(&mut self, e: &Expr) -> bool {
        let reject = "a constant takes literals, operators, collections, and other constants; compute this value in a function";
        match &e.kind {
            ExprKind::Number(_) | ExprKind::Bool(_) | ExprKind::Unit => true,
            // A failed part stops the walk: one diagnostic per constant.
            ExprKind::Text(parts) => parts.iter().all(|p| match p {
                TextPart::Lit(_) => true,
                TextPart::Interp(x) => self.constant_expression(x),
            }),
            ExprKind::List(items) => items.iter().all(|x| self.constant_expression(x)),
            ExprKind::Map(entries) => entries
                .iter()
                .all(|en| self.constant_expression(&en.key) && self.constant_expression(&en.value)),
            ExprKind::Unary { operand, .. } => self.constant_expression(operand),
            ExprKind::Binary { left, right, .. } => {
                self.constant_expression(left) && self.constant_expression(right)
            }
            ExprKind::Member { left, .. } => {
                // Type.Case names a payloadless case; the checker rejects other members.
                let type_name = match &left.kind {
                    ExprKind::Name(nm) => self.sym(*nm).filter(|s| s.kind == SymKind::Type),
                    _ => None,
                };
                if type_name.is_none() {
                    self.type_error(e.pos, reject);
                    return false;
                }
                true
            }
            ExprKind::Name(name) => {
                if let Some(s) = self.sym(*name).filter(|s| !s.is_constant()) {
                    let description = self.symbol_description(&s);
                    self.type_error(
                        e.pos,
                        format!("a constant can refer only to other constants, but {name} is a {description}; compute the value in a function"),
                    );
                    return false;
                }
                true
            }
            _ => {
                self.type_error(e.pos, reject);
                false
            }
        }
    }

    /// Reports constants that reach themselves through other constants.
    /// Annotated constants never need their initializer's type, so
    /// `constant_type` does not follow them; without this pass `let A: Int = B`
    /// and `let B: Int = A` would pass the check and recurse until the
    /// call-depth limit.
    pub(crate) fn check_constant_cycles(&mut self, module: &ModRef) {
        let mut state: HashMap<usize, u8> = HashMap::new(); // 1 visiting, 2 done
        for d in &module.decls {
            if !d.is_constant() {
                continue;
            }
            if let Some(s) = self.own_symbol(d) {
                self.visit_constant(&s, module, &mut state);
            }
        }
    }

    fn visit_constant(&mut self, s: &SymRef, module: &ModRef, state: &mut HashMap<usize, u8>) {
        match state.get(&s.key()) {
            Some(1) => {
                self.report_constant_cycle(s);
                return;
            }
            Some(_) => return,
            None => {}
        }
        state.insert(s.key(), 1);
        let decl = s.decl.clone().expect("constant declaration");
        if let Some(c) = decl.constant() {
            self.walk_constant(&c.value, module, state);
        }
        state.insert(s.key(), 2);
    }

    fn walk_constant(&mut self, e: &Expr, module: &ModRef, state: &mut HashMap<usize, u8>) {
        match &e.kind {
            ExprKind::Name(name) => {
                if let Some(t) = self
                    .sym(*name)
                    .filter(|t| t.is_constant() && t.module == module.file)
                {
                    self.visit_constant(&t, module, state);
                }
            }
            ExprKind::Member { left, .. } => self.walk_constant(left, module, state),
            ExprKind::Unary { operand, .. } => self.walk_constant(operand, module, state),
            ExprKind::Binary { left, right, .. } => {
                self.walk_constant(left, module, state);
                self.walk_constant(right, module, state);
            }
            ExprKind::List(items) => {
                for x in items {
                    self.walk_constant(x, module, state);
                }
            }
            ExprKind::Map(entries) => {
                for en in entries {
                    self.walk_constant(&en.key, module, state);
                    self.walk_constant(&en.value, module, state);
                }
            }
            ExprKind::Text(parts) => {
                for part in parts {
                    if let TextPart::Interp(x) = part {
                        self.walk_constant(x, module, state);
                    }
                }
            }
            _ => {}
        }
    }

    fn report_constant_cycle(&mut self, s: &SymRef) {
        if !self.cycle_reported.insert(s.key()) {
            return;
        }
        let decl = s.decl.clone().expect("constant declaration");
        self.type_error(
            decl.pos(),
            format!(
                "constant {} depends on itself; break the cycle or compute the value in a function",
                decl.name()
            ),
        );
    }
}
