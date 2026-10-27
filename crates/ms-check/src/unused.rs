//! Local and match payload bindings that are never read. Names starting with `_` are exempt.

use crate::syntax::ModuleData;
use crate::types::BindingRef;
use crate::{Diagnostic, Program};
use ms_syntax::ast::*;
use ms_syntax::visit::{Visitor, walk_decl, walk_expr};
use std::collections::HashMap;

/// Errors for every unread binding in the program's own (non-standard) modules.
pub(crate) fn check(program: &Program) -> Vec<Diagnostic> {
    let mut found = Vec::new();
    // Unfinished code (an editor buffer with a parse error) has bindings it has not read yet.
    for module in program
        .modules
        .iter()
        .filter(|m| !m.is_standard() && m.recovered.is_empty() && m.omitted.is_empty())
    {
        let reads = binding_reads(module);
        let mut scan = Scan {
            module,
            reads: &reads,
            found: &mut found,
        };
        for decl in &module.decls {
            walk_decl(&mut scan, decl.decl());
        }
    }
    found
}

fn walk<V: Visitor>(module: &ModuleData, v: &mut V) {
    for decl in &module.decls {
        walk_decl(v, decl.decl());
    }
}

/// Reads of each binding by uid. A read inside the right-hand side of an
/// assignment to the same binding (`total = total + 2`) only feeds that
/// binding's next value, so it does not make the binding observable.
fn binding_reads(module: &ModuleData) -> HashMap<usize, i64> {
    let mut reads: HashMap<usize, i64> = HashMap::new();
    for info in module.facts().exprs.iter().flatten() {
        if let Some(binding) = &info.binding {
            *reads.entry(binding.uid).or_default() += 1;
        }
    }
    let mut assigned = Assigned {
        module,
        reads: &mut reads,
    };
    walk(module, &mut assigned);
    reads
}

struct Assigned<'a> {
    module: &'a ModuleData,
    reads: &'a mut HashMap<usize, i64>,
}

impl Visitor for Assigned<'_> {
    fn expr(&mut self, e: &Expr) {
        let Some(target) = self.module.facts().assigned.get(&e.id).cloned() else {
            return;
        };
        let mut discount = Discount {
            module: self.module,
            target: target.uid,
            reads: self.reads,
        };
        walk_expr(&mut discount, e);
    }
}

struct Discount<'a> {
    module: &'a ModuleData,
    target: usize,
    reads: &'a mut HashMap<usize, i64>,
}

impl Visitor for Discount<'_> {
    fn expr(&mut self, e: &Expr) {
        let reads_target = self
            .module
            .facts()
            .info(e.id)
            .and_then(|i| i.binding.as_ref())
            .is_some_and(|b| b.uid == self.target);
        if reads_target {
            *self.reads.entry(self.target).or_default() -= 1;
        }
    }
}

struct Scan<'a> {
    module: &'a ModuleData,
    reads: &'a HashMap<usize, i64>,
    found: &'a mut Vec<Diagnostic>,
}

impl Scan<'_> {
    fn unread(&self, binding: &BindingRef) -> bool {
        self.reads.get(&binding.uid).copied().unwrap_or(0) == 0
            && !binding.name.as_str().starts_with('_')
    }

    fn report(&mut self, binding: &BindingRef, pos: ms_syntax::Pos) {
        self.found.push(Diagnostic {
            file: std::sync::Arc::from(self.module.file.as_str()),
            pos,
            phase: ms_syntax::Phase::Type,
            message: format!(
                "local binding {} is never read; remove it, use it, or name it with a leading '_' to ignore it",
                binding.name.as_str()
            ),
            end: None,
            fix: None,
        });
    }

    fn pattern(&mut self, p: &Pattern) {
        let binding = self.module.facts().patterns.get(&p.id).cloned();
        if let Some(binding) = binding
            && self.unread(&binding)
        {
            self.report(&binding, p.pos);
        }
        match &p.kind {
            PatternKind::Name(_) => {}
            PatternKind::List(items) => items.iter().for_each(|i| self.pattern(i)),
            PatternKind::Record(fields) => fields.iter().for_each(|f| self.pattern(&f.pattern)),
        }
    }

    fn arm(&mut self, arm: &Arm) {
        let facts = self.module.facts();
        let Some(arm_facts) = facts.arms.get(&arm.id) else {
            return;
        };
        let mut unread = Vec::new();
        for (index, binding) in arm_facts.bindings.iter().enumerate() {
            // A payload name that shadows a case or type is explained by the lint MSL106.
            if arm_facts.conflicts.get(index).is_some_and(Option::is_some) {
                continue;
            }
            if let Some(binding) = binding
                && self.unread(binding)
            {
                let pos = arm.bindings.get(index).map_or(arm.pos, |b| b.pos);
                unread.push((binding.clone(), pos));
            }
        }
        drop(facts);
        for (binding, pos) in unread {
            self.report(&binding, pos);
        }
    }
}

impl Visitor for Scan<'_> {
    fn stmt(&mut self, s: &Stmt) {
        match &s.kind {
            StmtKind::Bind { pattern, .. } => self.pattern(pattern),
            // `if var n = m.get(k): n += 1` writes through the borrow into `m`,
            // so a borrow that is only written is not unread.
            StmtKind::If {
                binding: Some(pattern),
                mutable: false,
                ..
            } => self.pattern(pattern),
            _ => {}
        }
    }

    fn expr(&mut self, e: &Expr) {
        if let ExprKind::Match { arms, .. } = &e.kind {
            arms.iter().for_each(|a| self.arm(a));
        }
    }
}
