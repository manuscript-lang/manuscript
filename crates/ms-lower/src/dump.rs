//! Developer dump of the checked facts a lowering consumes.

use ms_check::Program;
use ms_check::hir::{ModuleHir, Resolution};
use ms_syntax::ast::*;
use ms_syntax::visit::{Visitor, walk_decl};
use std::fmt::Write;

struct Dump<'a> {
    hir: &'a ModuleHir,
    out: String,
    depth: usize,
}

fn tag(e: &Expr) -> &'static str {
    match &e.kind {
        ExprKind::Number(_) => "number",
        ExprKind::Bool(_) => "bool",
        ExprKind::Unit => "unit",
        ExprKind::Text(_) => "text",
        ExprKind::Name(_) => "name",
        ExprKind::Member { .. } => "member",
        ExprKind::Apply { .. } => "apply",
        ExprKind::Index { .. } => "index",
        ExprKind::List(_) => "list",
        ExprKind::Map(_) => "map",
        ExprKind::Unary { .. } => "unary",
        ExprKind::Binary { .. } => "binary",
        ExprKind::Lambda(_) => "lambda",
        ExprKind::Call { .. } => "call",
        ExprKind::Match { .. } => "match",
    }
}

impl Visitor for Dump<'_> {
    fn stmt(&mut self, s: &Stmt) {
        let _ = writeln!(
            self.out,
            "{}stmt {:?}",
            "  ".repeat(self.depth),
            kind_name(s)
        );
    }
    fn expr(&mut self, e: &Expr) {
        let info = self.hir.info(e);
        let res = match self.hir.resolution(e) {
            Resolution::Local(b) => format!("local {}#{}", b.name, b.uid),
            Resolution::Constant(s) => format!("constant {}", s.name),
            Resolution::Function(s) => format!(
                "function {} native={:?} module={}",
                s.name,
                s.native.as_str(),
                s.module
            ),
            Resolution::Type(s) => format!("type {}", s.name),
            Resolution::Constructor { ty, case } => format!("constructor {ty} case={case:?}"),
            Resolution::Method(m) => format!(
                "method recv={} native={:?} contract={:?} decl={:?}",
                m.receiver,
                m.native.as_str(),
                m.contract.as_ref().map(|c| c.to_string()),
                m.name().map(|n| n.to_string())
            ),
            Resolution::Native(n) => format!("native {n}"),
            Resolution::Value => "value".to_string(),
        };
        let extra = if let Some(c) = self.hir.call(e) {
            format!(
                " targs={:?} const={}",
                c.type_args
                    .iter()
                    .map(|t| t.as_ref().map(|t| t.to_string()))
                    .collect::<Vec<_>>(),
                c.constant_use
            )
        } else {
            String::new()
        };
        let _ = writeln!(
            self.out,
            "{}{} : {} [{}]{}",
            "  ".repeat(self.depth + 1),
            tag(e),
            info.t(),
            res,
            extra
        );
    }
}

fn kind_name(s: &Stmt) -> &'static str {
    match &s.kind {
        StmtKind::Bind { .. } => "bind",
        StmtKind::Assign { .. } => "assign",
        StmtKind::Call(_) => "call",
        StmtKind::Return(_) => "return",
        StmtKind::Break => "break",
        StmtKind::Continue => "continue",
        StmtKind::If { .. } => "if",
        StmtKind::While { .. } => "while",
        StmtKind::For { .. } => "for",
        StmtKind::With { .. } => "with",
    }
}

/// Dumps the facts of every non-standard module.
pub fn dump(program: &Program) -> String {
    let mut out = String::new();
    for m in program.hir().modules() {
        if m.data.is_standard() {
            continue;
        }
        let _ = writeln!(out, "module {}", m.data.file);
        for d in &m.data.decls {
            let _ = writeln!(out, " decl");
            let mut v = Dump {
                hir: &m,
                out: String::new(),
                depth: 1,
            };
            walk_decl(&mut v, d.decl());
            out.push_str(&v.out);
        }
    }
    out
}
