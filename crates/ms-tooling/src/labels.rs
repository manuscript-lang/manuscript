//! `ms fmt --drop-labels`.

use crate::walk::walk_module;
use ms_check::Program;
use ms_check::api::types::{self, Kind, Param};
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
        syms: ms_syntax::Names::global(),
        session: &program.session,
        module,
        source,
        colons: None,
        removed: 0,
        cuts: Vec::new(),
    };
    walk_module(module, &mut scan);
    let count = scan.removed;
    let mut cuts = scan.cuts;
    if cuts.is_empty() {
        return (source.to_string(), 0);
    }
    cuts.sort_by_key(|cut| cut.0);
    let mut edited = String::with_capacity(source.len());
    let mut cursor = 0;
    for &(from, to) in &cuts {
        edited.push_str(&source[cursor..from]);
        cursor = to;
    }
    edited.push_str(&source[cursor..]);
    (edited, count)
}

struct Scan<'a> {
    syms: ms_syntax::Names,
    session: &'a std::rc::Rc<ms_check::Session>,
    module: &'a ms_check::ModuleData,
    source: &'a str,
    colons: Option<Vec<usize>>,
    removed: usize,
    cuts: Vec<(usize, usize)>,
}

impl Scan<'_> {
    fn drop_label(&mut self, from: usize, to: usize, name: &str) {
        let gap = &self.source[from..to];
        if gap.contains("//") || gap.contains("/*") {
            // Checked label gaps contain only the name, colon and trivia.
            // Preserve comments and line breaks; colons inside comments are not
            // label punctuation. Index actual colon tokens once, only when needed.
            let colons = self.colons.get_or_insert_with(|| {
                let file = self.syms.str(self.module.file).into();
                ms_syntax::lexer::lex(&file, self.source)
                    .map(|lexed| {
                        lexed
                            .tokens
                            .iter()
                            .filter(|t| t.kind == ms_syntax::token::Tok::Colon)
                            .map(|t| t.pos.offset as usize)
                            .collect()
                    })
                    .unwrap_or_default()
            });
            let at = colons.partition_point(|&offset| offset < from + name.len());
            let Some(&colon) = colons.get(at).filter(|&&offset| offset < to) else {
                return;
            };
            self.cuts.push((from, from + name.len()));
            let spaces = self.source[colon + 1..to]
                .bytes()
                .take_while(|b| matches!(b, b' ' | b'\t'))
                .count();
            self.cuts.push((colon, colon + 1 + spaces));
        } else {
            self.cuts.push((from, to));
        }
        self.removed += 1;
    }
}

/// The declared parameters of a function, method, or record constructor call.
/// Alternative cases and contract views are skipped.
fn call_parameters(
    syms: ms_syntax::Names,
    session: &std::rc::Rc<ms_check::Session>,
    module: &ms_check::ModuleData,
    callee: &Expr,
    info: &ms_check::api::syntax::Info,
) -> Option<Vec<Param>> {
    if info.native_str(syms) == "view" || info.case.is_some_and(|c| !syms.str(c).is_empty()) {
        return None;
    }
    if let Some(constructor) = &info.constructor {
        return Some(
            types::constructor_signature(syms, session, constructor)
                .params
                .clone(),
        );
    }
    let facts = module.facts();
    let ty = facts.info(callee.id)?.ty.clone()?;
    (ty.kind == Kind::Function).then(|| ty.params.clone())
}

fn first_unsupplied(
    syms: ms_syntax::Names,
    params: &[Param],
    seen: &HashSet<&str>,
) -> Option<&'static str> {
    params
        .iter()
        .map(|p| syms.str(p.name))
        .find(|name| !seen.contains(name))
}

impl Visitor for Scan<'_> {
    fn expr(&mut self, e: &Expr) {
        let syms = self.syms;
        let ExprKind::Call { callee, args } = &e.kind else {
            return;
        };
        let info = self.module.facts().info(e.id).cloned();
        let Some(params) =
            info.and_then(|i| call_parameters(syms, self.session, self.module, callee, &i))
        else {
            return;
        };
        let mut seen: HashSet<&str> = HashSet::with_capacity(params.len());
        for arg in args {
            let name: &str = match arg.name {
                None => first_unsupplied(syms, &params, &seen).unwrap_or(""),
                Some(label) => {
                    let label = syms.str(label);
                    if first_unsupplied(syms, &params, &seen) == Some(label)
                        && matches!(&arg.value.kind, ExprKind::Name(n) if syms.str(n) == label)
                        && !arg.mutable
                        && arg.pos.offset < arg.value.pos.offset
                        && arg.value.pos.offset as usize <= self.source.len()
                    {
                        self.drop_label(
                            arg.pos.offset as usize,
                            arg.value.pos.offset as usize,
                            label,
                        );
                    }
                    label
                }
            };
            seen.insert(name);
        }
    }
}
