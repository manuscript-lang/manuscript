//! Unread bindings (`MSL101`), unused imports (`MSL102`) and unreachable
//! statements (`MSL103`).

use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::types::{BindingRef, n};
use ms_check::{ModuleData, Program};
use ms_syntax::ast::*;
use ms_syntax::visit::{Visitor, walk_expr};
use std::collections::{HashMap, HashSet};

pub(super) fn lint(program: &Program, module: &ModuleData, findings: &mut Vec<Finding>) {
    let file = module_file(module);
    let reads = binding_reads(module);
    let unread = |binding: &BindingRef| {
        reads.get(&binding.uid).copied().unwrap_or(0) == 0
            && !binding.name.as_str().starts_with('_')
    };

    let mut scan = Scan {
        module,
        file: &file,
        unread: &unread,
        findings,
    };
    walk_module(module, &mut scan);

    let facts = module.facts();
    let mut used = HashSet::new();
    for info in facts.exprs.iter().flatten() {
        if let Some(symbol) = &info.symbol {
            used.insert(symbol.key());
        }
    }
    // Collection literals require canonical imports even without written types.
    let symbols = program.symbols.get(&module.file);
    let symbol_of =
        |name: &str| symbols.and_then(|names| names.borrow().get(&n(name)).map(|s| s.key()));
    let mut literals = Literals::default();
    walk_module(module, &mut literals);
    if literals.list {
        used.extend(symbol_of("List"));
    }
    if literals.map {
        used.extend(symbol_of("Map"));
    }
    for ty in facts.type_refs.values() {
        if let Some(symbol) = ty.def.as_ref().and_then(|d| d.symbol()) {
            used.insert(symbol.key());
        }
    }
    for import in &module.imports {
        let key = symbol_of(import.name.as_str());
        if !key.is_some_and(|k| used.contains(&k)) {
            findings.push(finding(
                "MSL102",
                format!("Import {} is never used", import.name.as_str()),
                &file,
                import.name_pos,
            ));
        }
    }
}

#[derive(Default)]
struct Literals {
    list: bool,
    map: bool,
}

impl Visitor for Literals {
    fn expr(&mut self, e: &Expr) {
        match e.kind {
            ExprKind::List(_) => self.list = true,
            ExprKind::Map(_) => self.map = true,
            _ => {}
        }
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
    walk_module(module, &mut assigned);
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
    file: &'a std::sync::Arc<str>,
    unread: &'a dyn Fn(&BindingRef) -> bool,
    findings: &'a mut Vec<Finding>,
}

impl Scan<'_> {
    fn pattern(&mut self, p: &Pattern) {
        if let Some(binding) = self.module.facts().patterns.get(&p.id)
            && (self.unread)(binding)
        {
            self.findings.push(finding(
                "MSL101",
                format!("Local binding {} is never read", binding.name.as_str()),
                self.file,
                p.pos,
            ));
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
        for (index, binding) in arm_facts.bindings.iter().enumerate() {
            // MSL106 already explains a payload name that shadows a case or type.
            if arm_facts.conflicts.get(index).is_some_and(Option::is_some) {
                continue;
            }
            if let Some(binding) = binding
                && (self.unread)(binding)
            {
                let pos = arm.bindings.get(index).map_or(arm.pos, |b| b.pos);
                self.findings.push(finding(
                    "MSL101",
                    format!("Local binding {} is never read", binding.name.as_str()),
                    self.file,
                    pos,
                ));
            }
        }
    }
}

impl Visitor for Scan<'_> {
    fn block(&mut self, body: &[Stmt]) {
        let mut reachable = true;
        for s in body {
            if !reachable {
                self.findings.push(finding(
                    "MSL103",
                    "Statement is unreachable",
                    self.file,
                    s.pos,
                ));
            }
            let falls_through = self
                .module
                .facts()
                .stmts
                .get(&s.id)
                .and_then(|f| f.falls_through);
            if falls_through == Some(false) {
                reachable = false;
            }
        }
    }

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
