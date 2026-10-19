//! `ms fmt --drop-labels` (`pkg/tooling/redundant_labels.go`).

use crate::gosort;
use crate::walk::walk_module;
use ms_check::Program;
use ms_check::types::{self, Kind, Param};
use ms_syntax::ast::*;
use ms_syntax::visit::Visitor;
use std::collections::HashSet;

/// Removes `name:` from an argument written `name: name` when the call binds
/// the same parameter without it. An unlabeled argument fills the first
/// parameter not supplied by an earlier argument, so a label is only dropped
/// where that parameter is the labeled one. `source` is the text of one module
/// of `program`. Returns the edited source and the number of labels removed;
/// nothing changes when the program has errors.
pub fn drop_redundant_labels(program: &Program, source: &str) -> (String, usize) {
    if !program.diagnostics.is_empty() {
        return (source.to_string(), 0);
    }
    let Some(module) = program.modules.iter().find(|m| &*m.source == source) else {
        return (source.to_string(), 0);
    };
    let mut scan = Scan {
        module,
        source_len: source.len(),
        cuts: Vec::new(),
    };
    walk_module(module, &mut scan);
    let mut cuts = scan.cuts;
    gosort::slice(&mut cuts, |a, b| a.0 > b.0);
    let mut edited = source.to_string();
    for &(from, to) in &cuts {
        edited.replace_range(from..to, "");
    }
    (edited, cuts.len())
}

struct Scan<'a> {
    module: &'a ms_check::ModuleData,
    source_len: usize,
    cuts: Vec<(usize, usize)>,
}

/// The declared parameters of a function, method, or record constructor call.
/// Alternative cases and contract views are skipped.
fn call_parameters(
    module: &ms_check::ModuleData,
    callee: &Expr,
    info: &ms_check::syntax::Info,
) -> Option<Vec<Param>> {
    if info.native_str() == "view" || info.case.is_some_and(|c| !c.as_str().is_empty()) {
        return None;
    }
    if let Some(constructor) = &info.constructor {
        return Some(types::constructor_signature(constructor).params.clone());
    }
    let facts = module.facts();
    let ty = facts.info(callee.id)?.ty.clone()?;
    (ty.kind == Kind::Function).then(|| ty.params.clone())
}

fn first_unsupplied(params: &[Param], seen: &HashSet<&str>) -> Option<&'static str> {
    params
        .iter()
        .map(|p| p.name.as_str())
        .find(|name| !seen.contains(name))
}

impl Visitor for Scan<'_> {
    fn expr(&mut self, e: &Expr) {
        let ExprKind::Call { callee, args } = &e.kind else {
            return;
        };
        let info = self.module.facts().info(e.id).cloned();
        let Some(params) = info.and_then(|i| call_parameters(self.module, callee, &i)) else {
            return;
        };
        let mut seen: HashSet<&str> = HashSet::with_capacity(params.len());
        for arg in args {
            let name: &str = match arg.name {
                None => first_unsupplied(&params, &seen).unwrap_or(""),
                Some(label) => {
                    let label = label.as_str();
                    if first_unsupplied(&params, &seen) == Some(label)
                        && matches!(&arg.value.kind, ExprKind::Name(n) if n.as_str() == label)
                        && !arg.mutable
                        && arg.pos.offset < arg.value.pos.offset
                        && arg.value.pos.offset as usize <= self.source_len
                    {
                        self.cuts
                            .push((arg.pos.offset as usize, arg.value.pos.offset as usize));
                    }
                    label
                }
            };
            seen.insert(name);
        }
    }
}
