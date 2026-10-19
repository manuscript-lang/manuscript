//! Direct writes to captured values in concurrent server handlers (`MSL105`).
//! It deliberately does not infer aliasing, helper effects, or lock ownership.

use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::ModuleData;
use ms_check::effects::collection_mutation;
use ms_check::types::Kind;
use ms_syntax::ast::*;
use ms_syntax::visit::{Visitor, walk_callable};
use std::collections::HashSet;

pub(super) fn lint(module: &ModuleData, findings: &mut Vec<Finding>) {
    let file = module_file(module);
    let mut scan = Scan {
        module,
        file: &file,
        findings,
    };
    walk_module(module, &mut scan);
}

struct Scan<'a> {
    module: &'a ModuleData,
    file: &'a std::sync::Arc<str>,
    findings: &'a mut Vec<Finding>,
}

impl Visitor for Scan<'_> {
    fn expr(&mut self, e: &Expr) {
        let ExprKind::Call { args, .. } = &e.kind else {
            return;
        };
        let (method, slots) = {
            let facts = self.module.facts();
            let Some(info) = facts.info(e.id) else {
                return;
            };
            (info.method.clone(), info.arguments.clone())
        };
        let Some(method) = method else {
            return;
        };
        let serves = method.receiver.id.as_str() == "@std/Network"
            && method
                .decl
                .as_ref()
                .is_some_and(|d| matches!(d.name().as_str(), "serve" | "serve_stream"));
        if !serves {
            return;
        }
        for slot in slots.unwrap_or_default() {
            let Some(arg) = args.get(slot.index) else {
                continue;
            };
            if slot.name.as_str() == "handler"
                && let ExprKind::Lambda(lambda) = &arg.value.kind
            {
                self.handler(&arg.value, lambda);
            }
        }
    }
}

impl Scan<'_> {
    fn handler(&mut self, callback: &Expr, lambda: &Lambda) {
        let captures: HashSet<usize> = {
            let facts = self.module.facts();
            let Some(info) = facts.info(callback.id) else {
                return;
            };
            info.captures.iter().map(|b| b.uid).collect()
        };
        // The shared traversal visits nested lambdas too. Exclude their
        // bodies: creating an unrelated function is not executing its mutations.
        let mut nested = Nested::default();
        walk_callable(&mut nested, &lambda.params, &lambda.body);
        let mut report = Report {
            scan: self,
            captures,
            nested,
        };
        walk_callable(&mut report, &lambda.params, &lambda.body);
    }
}

#[derive(Default)]
struct Marks {
    stmts: HashSet<NodeId>,
    exprs: HashSet<NodeId>,
}

impl Visitor for Marks {
    fn stmt(&mut self, s: &Stmt) {
        self.stmts.insert(s.id);
    }
    fn expr(&mut self, e: &Expr) {
        self.exprs.insert(e.id);
    }
}

#[derive(Default)]
struct Nested {
    marks: Marks,
}

impl Visitor for Nested {
    fn expr(&mut self, e: &Expr) {
        if let ExprKind::Lambda(l) = &e.kind {
            walk_callable(&mut self.marks, &l.params, &l.body);
        }
    }
}

struct Report<'a, 'b> {
    scan: &'a mut Scan<'b>,
    captures: HashSet<usize>,
    nested: Nested,
}

impl Report<'_, '_> {
    fn report(&mut self, receiver: &Expr, pos: ms_syntax::Pos) {
        let ExprKind::Name(_) = receiver.kind else {
            return;
        };
        let facts = self.scan.module.facts();
        let Some(binding) = facts.info(receiver.id).and_then(|i| i.binding.as_ref()) else {
            return;
        };
        if !self.captures.contains(&binding.uid) {
            return;
        }
        self.scan.findings.push(finding(
            "MSL105",
            format!(
                "Concurrent callback mutates captured value {}; handlers run concurrently, so keep per-request state local instead of sharing it",
                binding.name.as_str()
            ),
            self.scan.file,
            pos,
        ));
    }
}

impl Visitor for Report<'_, '_> {
    fn stmt(&mut self, s: &Stmt) {
        if self.nested.marks.stmts.contains(&s.id) {
            return;
        }
        let StmtKind::Assign {
            target: AssignTarget::Member(target),
            ..
        } = &s.kind
        else {
            return;
        };
        let ExprKind::Member { left, .. } = &target.kind else {
            return;
        };
        let record = self
            .scan
            .module
            .facts()
            .info(left.id)
            .and_then(|i| i.ty.as_ref().map(|t| t.kind == Kind::Record))
            .unwrap_or(false);
        if record {
            self.report(left, target.pos);
        }
    }

    fn expr(&mut self, e: &Expr) {
        if self.nested.marks.exprs.contains(&e.id) {
            return;
        }
        let ExprKind::Call { callee, .. } = &e.kind else {
            return;
        };
        let ExprKind::Member { left, .. } = &callee.kind else {
            return;
        };
        let mutates = {
            let facts = self.scan.module.facts();
            facts
                .info(e.id)
                .and_then(|i| i.method.as_ref())
                .and_then(|m| {
                    m.decl
                        .as_ref()
                        .map(|d| collection_mutation(&m.receiver, d.name().as_str()))
                })
                .unwrap_or(false)
        };
        if mutates {
            self.report(left, e.pos);
        }
    }
}
