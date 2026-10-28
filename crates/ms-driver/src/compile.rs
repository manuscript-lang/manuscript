//! Checking a loaded graph: everything up to (not including) lowering.

use std::sync::Arc;

use ms_check::types::{SymKind, n};
use ms_check::{CheckOptions, Program};
use ms_syntax::{Diagnostic, Phase, Pos};

use crate::load::Graph;

/// A checked program and the diagnostics that stop it from being lowered.
pub struct Checked {
    pub source_root: String,
    pub project_root: String,
    pub configuration: String,
    pub entry: String,
    /// The checked program; absent when loading failed before checking.
    pub program: Option<Program>,
    pub diagnostics: Vec<Diagnostic>,
}

impl Checked {
    pub fn success(&self) -> bool {
        self.diagnostics.is_empty()
    }
}

/// What the command needs from the program.
#[derive(Clone, Copy, Debug, Default)]
pub struct CheckRequest {
    /// Require the entry to export `main() Int` (executables, not tests).
    pub entry: bool,
}

/// Check the graph and, for executables, validate the entry point.
pub fn check_graph(graph: Graph, request: CheckRequest) -> Checked {
    check_graph_at(graph, request, None)
}

/// [`check_graph`] that also captures the lexical scope at every name
/// expression spelled `scope_marker` (editor completion queries).
pub fn check_graph_at(graph: Graph, request: CheckRequest, scope_marker: Option<&str>) -> Checked {
    let mut checked = Checked {
        source_root: graph.source_root.clone(),
        project_root: graph.project_root.clone(),
        configuration: graph.configuration.clone(),
        entry: graph.entry.clone(),
        program: None,
        diagnostics: graph.diagnostics.clone(),
    };
    if graph.modules.is_empty() && (!graph.library || !graph.diagnostics.is_empty()) {
        return checked;
    }
    let program = ms_check::check(
        graph.modules,
        graph.imports,
        CheckOptions {
            scope_marker: scope_marker.map(str::to_string),
            ..CheckOptions::default()
        },
    );
    checked
        .diagnostics
        .extend(program.diagnostics.iter().cloned());
    crate::imports::suggest_project_imports(&mut checked.diagnostics, &graph.source_root);
    if checked.success()
        && request.entry
        && let Some(issue) = check_entry(&program, &graph.entry)
    {
        checked.diagnostics.push(issue);
    }
    checked.program = Some(program);
    checked
}

/// Entry validation: an exported, nongeneric, parameterless `main` returning `Int`.
fn check_entry(program: &Program, entry: &str) -> Option<Diagnostic> {
    let file: Arc<str> = Arc::from(entry);
    let main = program
        .symbols
        .get(&n(entry))
        .and_then(|names| names.borrow().get(&n("main")).cloned());
    let mut position = Pos::new(0, 1, 1);
    let mut detail = "no main function is declared, so add 'export fn main() Int:' with an indented 'return 0' body".to_string();
    if let Some(main) = &main {
        let ty = main.ty_opt();
        let constant = main.is_constant();
        let generic = !main.variables().is_empty();
        let parameters = ty.as_ref().map_or(0, |t| t.params.len());
        let result = ty.as_ref().and_then(|t| t.result.clone());
        if main.kind == SymKind::Fn
            && main.export
            && !constant
            && !generic
            && parameters == 0
            && result.as_ref().is_some_and(|r| r.id == n("Int"))
        {
            return None;
        }
        if let Some(decl) = &main.decl {
            position = decl.pos();
        }
        detail = if constant {
            "main is a constant, so rename it and declare 'export fn main() Int:'".to_string()
        } else if main.kind != SymKind::Fn {
            "main is declared as a type, so rename it and declare 'export fn main() Int:'"
                .to_string()
        } else if !main.export {
            "main is not exported, so write 'export fn main() Int:'".to_string()
        } else if generic {
            "main cannot be generic, so remove its type parameters".to_string()
        } else if parameters > 0 {
            "main takes no parameters, so remove them (read program arguments through the standard cli module)".to_string()
        } else {
            let shown = result.map_or_else(|| "<invalid>".to_string(), |r| r.to_string());
            format!(
                "main returns {shown}, so declare its result type Int and return an exit status, e.g. 'return 0'"
            )
        };
    }
    Some(Diagnostic {
        file,
        pos: position,
        phase: Phase::Type,
        message: format!("entry must export fn main() Int; {detail}"),
        end: None,
        fix: None,
    })
}
