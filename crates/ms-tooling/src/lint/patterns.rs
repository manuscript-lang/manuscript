//! Payload names that shadow a type or case (`MSL106`).

use super::matches::path_text;
use super::{Finding, finding, module_file};
use crate::walk::walk_module;
use ms_check::ModuleData;
use ms_check::api::types::{self, Kind};
use ms_syntax::ast::*;
use ms_syntax::visit::Visitor;

pub(super) fn lint(syms: ms_syntax::Names, module: &ModuleData, findings: &mut Vec<Finding>) {
    let file = module_file(syms, module);
    let mut scan = Scan {
        syms: ms_syntax::Names::global(),
        module,
        file: &file,
        findings,
    };
    walk_module(module, &mut scan);
}

struct Scan<'a> {
    syms: ms_syntax::Names,
    module: &'a ModuleData,
    file: &'a std::sync::Arc<str>,
    findings: &'a mut Vec<Finding>,
}

impl Scan<'_> {
    fn arm(&mut self, syms: ms_syntax::Names, arm: &Arm) {
        let facts = self.module.facts();
        let Some(arm_facts) = facts.arms.get(&arm.id) else {
            return;
        };
        for (index, conflict) in arm_facts.conflicts.iter().enumerate() {
            let (Some(conflict), Some(written)) = (conflict, arm.bindings.get(index)) else {
                continue;
            };
            let name = syms.str(written.name);
            if !name.starts_with(|c: char| c.is_ascii_uppercase()) {
                continue;
            }
            let Some(binding) = arm_facts.bindings.get(index).and_then(Option::as_ref) else {
                continue;
            };
            let case = conflict.case.filter(|c| !syms.str(c).is_empty());
            let identity = match (case, &conflict.ty) {
                (None, _) => "a type name".to_string(),
                (Some(_), None) => "a visible alternative case name".to_string(),
                (Some(_), Some(owner)) => {
                    format!("a case of {owner_t}", owner_t = owner.display(syms))
                }
            };
            let mut message = format!(
                "{name} is {identity}, but this pattern creates a fresh binding for every {} payload; use a lowercase binding name if intentional",
                binding.ty.display(syms)
            );
            if case.is_some()
                && binding.ty.kind == Kind::Alternative
                && types::same_opt(&Some(binding.ty.clone()), &conflict.ty)
            {
                let mut names: Vec<String> = arm
                    .bindings
                    .iter()
                    .map(|b| syms.str(b.name).to_string())
                    .collect();
                let mut payload = "payload".to_string();
                let mut suffix = 2;
                while names.contains(&payload) {
                    payload = format!("payload{suffix}");
                    suffix += 1;
                }
                names[index] = payload.clone();
                let path = match &arm_facts.contract {
                    Some(target) => target.display(syms).to_string(),
                    None => path_text(syms, &arm.path),
                };
                let mut nested = name.to_string();
                for case in types::cases(&binding.ty) {
                    if syms.str(case.name) == name && !case.fields.is_empty() {
                        let ignored = vec!["_"; case.fields.len()];
                        nested += &format!("({})", ignored.join(", "));
                    }
                }
                message += &format!(
                    "; nested patterns are unsupported: write '{path}({}):', handle the payload in a separate helper using 'match {payload}:' with a '{nested}:' arm",
                    names.join(", ")
                );
            }
            self.findings
                .push(finding("MSL106", message, self.file, written.pos));
        }
    }
}

impl Visitor for Scan<'_> {
    fn expr(&mut self, e: &Expr) {
        let syms = self.syms;
        if let ExprKind::Match { arms, .. } = &e.kind {
            arms.iter().for_each(|a| self.arm(syms, a));
        }
    }
}
