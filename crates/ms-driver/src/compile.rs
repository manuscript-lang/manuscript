//! Checking a loaded graph: everything up to (not including) lowering.

use std::sync::Arc;

use ms_check::api::types::{SymKind, n};
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
    /// Symbolic links the imports passed through; watch mode follows their targets.
    pub links: Vec<String>,
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
pub fn check_graph(syms: ms_syntax::Names, graph: Graph, request: CheckRequest) -> Checked {
    check_graph_at(syms, graph, request, None)
}

/// [`check_graph`] that also captures the lexical scope at every name
/// expression spelled `scope_marker` (editor completion queries).
pub fn check_graph_at(
    syms: ms_syntax::Names,
    graph: Graph,
    request: CheckRequest,
    scope_marker: Option<&str>,
) -> Checked {
    check_graph_in(
        syms,
        &ms_check::Session::new(),
        graph,
        request,
        scope_marker,
    )
}

/// [`check_graph_at`] against a session the caller keeps, so the standard library loads once.
pub fn check_graph_in(
    syms: ms_syntax::Names,
    session: &std::rc::Rc<ms_check::Session>,
    graph: Graph,
    request: CheckRequest,
    scope_marker: Option<&str>,
) -> Checked {
    let mut checked = Checked {
        source_root: graph.source_root.clone(),
        project_root: graph.project_root.clone(),
        configuration: graph.configuration.clone(),
        entry: graph.entry.clone(),
        program: None,
        diagnostics: graph.diagnostics.clone(),
        links: graph.links.clone(),
    };
    if graph.modules.is_empty() && (!graph.library || !graph.diagnostics.is_empty()) {
        return checked;
    }
    let program = ms_check::check_in(
        syms,
        session,
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
    crate::imports::suggest_project_imports(syms, &mut checked.diagnostics, &graph.source_root);
    // Import hints from either standard or project modules share source placement.
    // Keep the advertised JSON fix identical to what `ms check --fix` applies.
    let mut sources = None;
    for issue in &mut checked.diagnostics {
        let Some(fix) = &mut issue.fix else { continue };
        if fix.pos.offset != 0 || fix.end.offset != 0 || !fix.replacement.starts_with("import ") {
            continue;
        }
        let sources = sources.get_or_insert_with(|| {
            program
                .modules
                .iter()
                .map(|module| (syms.str(module.file), module.source.as_ref()))
                .collect::<std::collections::HashMap<&str, &str>>()
        });
        if let Some(source) = sources.get(issue.file.as_ref()) {
            fix.pos = crate::imports::import_position(source);
            fix.end = fix.pos;
        }
    }
    if checked.success()
        && request.entry
        && let Some(issue) = check_entry(syms, &program, &graph.entry)
    {
        checked.diagnostics.push(issue);
    }
    checked.program = Some(program);
    checked
}

/// Entry validation: an exported, nongeneric, parameterless `main` returning `Int`.
fn check_entry(syms: ms_syntax::Names, program: &Program, entry: &str) -> Option<Diagnostic> {
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
            let shown =
                result.map_or_else(|| "<invalid>".to_string(), |r| r.display(syms).to_string());
            format!(
                "main returns {shown}, so declare its result type Int and return an exit status, e.g. 'return 0'"
            )
        };
    }
    Some(Diagnostic {
        opener_line: 0,
        file,
        pos: position,
        phase: Phase::Type,
        message: format!("entry must export fn main() Int; {detail}"),
        end: None,
        fix: None,
    })
}
