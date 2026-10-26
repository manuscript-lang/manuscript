//! `textDocument/completion` and `textDocument/signatureHelp`.

use crate::analysis::{Document, Documents, workspace_analysis};
use crate::editor::{
    self, CursorContext, EditorAnalysis, call_arguments, context_at, query_call, query_editor,
    type_expression,
};
use crate::index::DeclFiles;
use crate::json::{Json, obj};
use crate::nav;
use crate::text::{self, EditorKind, Position, Range};
use crate::uri;
use crate::workspace::workspace_documents;
use ms_check::editor::{MemberKind, members, prelude_type_names, standard_export_inventory};
use ms_check::stdlib::is_prelude_symbol;
use ms_check::syntax::{DeclRef, FuncRef};
use ms_check::types::{Kind, Name, SymKind, SymRef, Ty, cases, constructor_signature, n};
use ms_driver::project::pathops;
use ms_syntax::ast::DeclKind;
use std::collections::{HashMap, HashSet};

/// One completion item before JSON encoding.
pub struct Item {
    label: String,
    kind: i64,
    detail: String,
    documentation: Json,
    sort_text: String,
    insert_format: i64,
    edit: Json,
    additional: Vec<Json>,
}

impl Item {
    /// The LSP form.
    pub fn json(&self) -> Json {
        let mut item = obj([
            ("label", self.label.clone().into()),
            ("kind", self.kind.into()),
            ("sortText", self.sort_text.clone().into()),
            ("filterText", self.label.clone().into()),
            ("insertTextFormat", self.insert_format.into()),
            ("textEdit", self.edit.clone()),
        ]);
        if !self.detail.is_empty() {
            item.set("detail", self.detail.clone().into());
        }
        if !self.documentation.is_null() {
            item.set("documentation", self.documentation.clone());
        }
        if !self.additional.is_empty() {
            item.set("additionalTextEdits", Json::Arr(self.additional.clone()));
        }
        item
    }
}

fn text_edit(range: Range, text: &str) -> Json {
    obj([("range", range.json()), ("newText", text.into())])
}

/// Text inserted for a callable, with snippet placeholders when supported.
pub fn callable_text(name: &str, t: Option<&Ty>, variables: &[Ty], snippets: bool) -> String {
    let Some(t) = t.filter(|t| snippets && t.kind == Kind::Function) else {
        return name.to_string();
    };
    let mut out = String::from(name);
    let mut at = 1;
    if !variables.is_empty() {
        out.push('[');
        for (i, v) in variables.iter().enumerate() {
            if i > 0 {
                out.push_str(", ");
            }
            out.push_str(&format!("${{{at}:{}}}", v.name));
            at += 1;
        }
        out.push(']');
    }
    out.push('(');
    let mut written = 0;
    for p in &t.params {
        if t.is_default(p.name) {
            continue;
        }
        if written > 0 {
            out.push_str(", ");
        }
        if t.params.len() != 1 {
            out.push_str(&format!("{}: ", p.name));
        }
        out.push_str(&format!("${{{at}:{}}}", p.name));
        at += 1;
        written += 1;
    }
    out.push_str(")$0");
    out
}

/// Case-insensitive subsequence match used for identifiers.
pub fn name_matches(name: &str, query: &str) -> bool {
    let name = name.to_lowercase();
    let query = query.to_lowercase();
    let query = query.as_bytes();
    let mut at = 0;
    for c in name.chars() {
        if at < query.len() && c as u32 == u32::from(query[at]) {
            at += 1;
        }
    }
    at == query.len()
}

fn sort(items: &mut [Item]) {
    items.sort_by(|a, b| {
        a.sort_text
            .cmp(&b.sort_text)
            .then_with(|| a.detail.cmp(&b.detail))
    });
}

/// Bundled module paths that export something outside the prelude.
fn standard_paths() -> Vec<String> {
    let mut paths: Vec<String> = standard_export_inventory()
        .into_iter()
        .filter(|(_, symbols)| symbols.iter().any(|s| !is_prelude_symbol(s)))
        .map(|(path, _)| path)
        .collect();
    paths.sort();
    paths
}

fn editor_project(d: &Document) -> Option<ms_driver::project::Project> {
    let manifest = ms_driver::project::find_manifest(&d.path())?;
    ms_driver::project::read_project(&manifest).ok()
}

struct Completer<'a> {
    d: &'a Document,
    docs: &'a Documents,
    c: &'a CursorContext,
    snippets: bool,
    a: EditorAnalysis,
    items: Vec<Item>,
    seen: HashSet<String>,
    files: DeclFiles,
}

impl Completer<'_> {
    fn range(&self) -> Range {
        Range {
            start: text::position(&self.d.text, self.c.start),
            end: text::position(&self.d.text, self.c.end),
        }
    }

    fn doc(&self, decl: Option<&DeclRef>, fallback: Name) -> Json {
        let Some(decl) = decl else {
            return Json::Null;
        };
        let file = self.files.of_decl(decl).unwrap_or(fallback);
        nav::description(&self.a.result, file, decl.pos())
    }

    fn method_doc(&self, decl: Option<&FuncRef>, fallback: Name) -> Json {
        let Some(decl) = decl else {
            return Json::Null;
        };
        nav::description(&self.a.result, self.files.file(decl, fallback), decl.pos())
    }

    #[allow(clippy::too_many_arguments)]
    fn add(
        &mut self,
        name: &str,
        kind: i64,
        t: Option<&Ty>,
        priority: usize,
        insert: &str,
        documentation: Json,
    ) {
        if self.seen.contains(name)
            || !name_matches(name, &self.c.prefix)
            || name.starts_with("__manuscript_completion")
        {
            return;
        }
        self.seen.insert(name.to_string());
        let format = if self.snippets && (insert.contains("${") || insert.contains("$0")) {
            2
        } else {
            1
        };
        self.items.push(Item {
            label: name.to_string(),
            kind,
            detail: t.map(|t| t.to_string()).unwrap_or_default(),
            documentation,
            sort_text: format!("{priority:02}_{name}"),
            insert_format: format,
            edit: text_edit(self.range(), insert),
            additional: Vec::new(),
        });
    }

    fn add_import(&mut self, s: &SymRef, path: &str) {
        let before = self.items.len();
        let mut kind = if s.kind == SymKind::Type { 7 } else { 3 };
        let ty = s.ty_opt();
        let mut insert = callable_text(s.name.as_str(), ty.as_ref(), &s.variables(), self.snippets);
        if s.is_constant() {
            kind = 21;
            insert = s.name.as_str().to_string();
        }
        let documentation = self.doc(s.decl.as_ref(), s.module);
        self.add(
            s.name.as_str(),
            kind,
            s.value_type().as_ref(),
            4,
            &insert,
            documentation,
        );
        if self.items.len() > before {
            let item = self.items.last_mut().expect("added");
            item.detail.push_str(&format!(" — {path}"));
            item.additional = vec![text_edit(
                Range::at(Position::default()),
                &format!(
                    "from {} import {}\n",
                    ms_driver::project::quoting::quote(path),
                    s.name
                ),
            )];
        }
    }

    fn member_items(&mut self) {
        let Some(expr) = self.a.expression.clone() else {
            return;
        };
        let ms_syntax::ast::ExprKind::Member { left, .. } = &expr.kind else {
            return;
        };
        if let Some(ty) = type_expression(left, &self.a.scope) {
            for case in cases(&ty) {
                let signature = ms_check::types::function(case.fields.clone(), ty.clone());
                let insert = if case.fields.is_empty() {
                    case.name.as_str().to_string()
                } else {
                    callable_text(case.name.as_str(), Some(&signature), &[], self.snippets)
                };
                self.add(
                    case.name.as_str(),
                    20,
                    Some(&signature),
                    0,
                    &insert,
                    Json::Null,
                );
            }
            return;
        }
        let result = self.a.result.clone();
        let (Some(program), Some(module)) = (&result.program, self.a.module.clone()) else {
            return;
        };
        let file = module.file;
        let Some(ty) = module.facts().info(left.id).and_then(|i| i.ty.clone()) else {
            return;
        };
        for member in members(program, &ty, Some(file)) {
            let (kind, insert) = match member.kind {
                MemberKind::Method => (
                    2,
                    callable_text(member.name.as_str(), Some(&member.ty), &[], self.snippets),
                ),
                MemberKind::Field => (5, member.name.as_str().to_string()),
            };
            let documentation = self.method_doc(member.declaration.as_ref(), file);
            self.add(
                member.name.as_str(),
                kind,
                Some(&member.ty),
                0,
                &insert,
                documentation,
            );
        }
    }

    fn argument_items(&mut self) {
        let Some((call, signature)) = query_call(&self.a) else {
            return;
        };
        let used: HashSet<String> = call_arguments(&self.a, &call)
            .into_iter()
            .map(|(name, _)| name)
            .filter(|name| *name != self.a.marker)
            .collect();
        for param in &signature.params {
            if used.contains(param.name.as_str()) {
                continue;
            }
            let mut insert = format!("{}: ", param.name);
            if self.snippets {
                insert.push_str(&format!("${{1:{}}}", param.name));
            }
            self.add(
                param.name.as_str(),
                6,
                Some(&param.ty),
                0,
                &insert,
                Json::Null,
            );
        }
    }

    fn visible_symbols(&self) -> HashMap<Name, SymRef> {
        if !self.a.scope.symbols.is_empty() {
            return self.a.scope.symbols.clone();
        }
        let (Some(program), Some(module)) = (
            &self.a.result.program,
            &self.a.result.module(&self.a.document),
        ) else {
            return HashMap::new();
        };
        program
            .symbols
            .get(&module.file)
            .map(|names| names.borrow().clone())
            .unwrap_or_default()
    }

    fn scope_items(&mut self) {
        let c = self.c;
        let scope = self.a.scope.clone();
        if !c.type_context {
            for (name, b) in &scope.bindings {
                let insert = callable_text(name.as_str(), Some(&b.ty), &[], self.snippets);
                self.add(name.as_str(), 6, Some(&b.ty), 0, &insert, Json::Null);
            }
        }
        for (name, t) in &scope.types {
            self.add(name.as_str(), 25, Some(t), 1, name.as_str(), Json::Null);
        }
        let symbols = self.visible_symbols();
        let module_file = self.a.result.module(&self.a.document).map(|m| m.file);
        if c.type_context && self.a.expression.is_none() {
            // Signature markers are type syntax rather than captured expressions.
            // Use the checked variables of the enclosing callable before offering
            // module symbols, so a type parameter retains its own identity and arity.
            let text = self.a.document.text.clone();
            for symbol in symbols.values() {
                let Some(decl) = &symbol.decl else { continue };
                if Some(symbol.module) != module_file || decl.pos().offset as usize > c.start {
                    continue;
                }
                let start = decl.pos().offset as usize;
                let mut header_end = text.len();
                let first = match &decl.decl().kind {
                    DeclKind::Fn(f) => f.body.first().map(|s| s.pos.offset as usize),
                    _ => None,
                };
                if let Some(first) = first {
                    header_end = first;
                } else if start <= text.len() {
                    let mut depth = 0i32;
                    for token in text::editor_tokens(&text[start..]) {
                        match token.kind {
                            EditorKind::Char(b'(' | b'[' | b'{') => depth += 1,
                            EditorKind::Char(b')' | b']' | b'}') => depth -= 1,
                            EditorKind::Char(b':') if depth == 0 => {
                                header_end = start + token.start;
                            }
                            _ => {}
                        }
                        if header_end != text.len() {
                            break;
                        }
                    }
                }
                if c.end > header_end {
                    continue;
                }
                for variable in symbol.variables() {
                    self.add(
                        variable.name.as_str(),
                        25,
                        Some(&variable),
                        1,
                        variable.name.as_str(),
                        Json::Null,
                    );
                }
            }
        }
        for (name, s) in &symbols {
            if c.type_context && s.kind != SymKind::Type {
                continue;
            }
            let Some(ty) = s.ty_opt() else { continue };
            let mut kind = 3;
            let mut insert = callable_text(name.as_str(), Some(&ty), &s.variables(), self.snippets);
            if s.kind == SymKind::Type {
                kind = 7;
                insert = name.as_str().to_string();
                let variables = ty
                    .def
                    .as_ref()
                    .map(|d| d.variables.borrow().clone())
                    .unwrap_or_default();
                if c.type_context && self.snippets && !variables.is_empty() {
                    let parts: Vec<String> = variables
                        .iter()
                        .enumerate()
                        .map(|(i, v)| format!("${{{}:{}}}", i + 1, v.name))
                        .collect();
                    insert = format!("{name}[{}]", parts.join(", "));
                }
                if !c.type_context && ty.kind == Kind::Record {
                    let signature = constructor_signature(&ty);
                    insert = callable_text(
                        name.as_str(),
                        Some(&signature),
                        &s.variables(),
                        self.snippets,
                    );
                }
            }
            if s.is_constant() {
                kind = 21;
                insert = name.as_str().to_string();
            }
            let documentation = self.doc(s.decl.as_ref(), s.module);
            self.add(
                name.as_str(),
                kind,
                s.value_type().as_ref(),
                2,
                &insert,
                documentation,
            );
        }
        // Preserve useful declaration suggestions even when another declaration has
        // malformed syntax. Scope-sensitive results above only use checked snapshots.
        if symbols.is_empty() {
            let file: std::sync::Arc<str> = uri::filename(&self.d.uri).into();
            let (module, _) = ms_syntax::parse_partial(&file, &self.d.text);
            // The parser reports `type` declarations as records, so Go's kind
            // test for types never matches here: every fallback item is a function.
            for decl in &module.decls {
                let name = decl_name(decl);
                self.add(&name, 3, None, 2, &name, Json::Null);
            }
        }
    }

    fn keyword_items(&mut self) {
        let c = self.c;
        let text = &self.d.text;
        let line_start = text[..c.start].rfind('\n').map_or(0, |at| at + 1);
        if text[line_start..c.start].trim().is_empty() {
            let mut words: Vec<&str> = vec![
                "let", "var", "if", "elif", "else", "for", "while", "match", "with", "return",
                "break", "continue",
            ];
            if line_start == c.start {
                words = vec![
                    "def",
                    "type",
                    "interface",
                    "impl",
                    "from",
                    "export",
                    "extern",
                    "test",
                ];
            }
            for word in words {
                let mut insert = format!("{word} ");
                if self.snippets
                    && let Some(template) = keyword_template(word)
                {
                    insert = template.to_string();
                }
                self.add(word, 14, None, 5, &insert, Json::Null);
            }
            if line_start != c.start && self.snippets {
                self.add(
                    "if let",
                    14,
                    None,
                    5,
                    "if let ${1:value} = ${2:optional}:\n    $0",
                    Json::Null,
                );
            }
        }
        if !c.type_context {
            for word in ["True", "False", "lambda", "not", "try"] {
                self.add(word, 14, None, 5, word, Json::Null);
            }
        }
        if c.type_context {
            let symbols = self.visible_symbols();
            for name in prelude_type_names() {
                if self.a.scope.bindings.contains_key(&n(name)) {
                    continue;
                }
                if symbols
                    .get(&n(name))
                    .is_some_and(|s| s.kind != SymKind::Type)
                {
                    continue;
                }
                self.add(name, 7, None, 3, name, Json::Null);
            }
        }
    }

    fn standard_imports(&mut self) {
        let inventory = standard_export_inventory();
        for path in standard_paths() {
            for s in inventory.get(&path).into_iter().flatten() {
                if is_prelude_symbol(s)
                    || self.seen.contains(s.name.as_str())
                    || !name_matches(s.name.as_str(), &self.c.prefix)
                    || (self.c.type_context && s.kind != SymKind::Type)
                {
                    continue;
                }
                self.add_import(s, &path);
            }
        }
    }

    fn workspace_imports(&mut self) {
        let Ok(files) = workspace_documents(self.d, self.docs, false, None) else {
            return;
        };
        for file in files {
            if file.uri == self.d.uri {
                continue;
            }
            let name: std::sync::Arc<str> = uri::filename(&file.uri).into();
            let Ok(parsed) = ms_syntax::parser::parse(&name, &file.text) else {
                continue;
            };
            let matches = parsed.decls.iter().any(|decl| {
                let name = decl_name(decl);
                decl.export && name_matches(&name, &self.c.prefix) && !self.seen.contains(&name)
            });
            if !matches {
                continue;
            }
            let checked = workspace_analysis(&file, self.docs);
            let (Some(module), Some(program)) = (checked.module(&file), &checked.program) else {
                continue;
            };
            let Ok(relative) = pathops::rel(&pathops::dir(&self.d.path()), &file.path()) else {
                continue;
            };
            let mut path = relative;
            if !path.starts_with('.') {
                path = format!("./{path}");
            }
            let symbols: Vec<SymRef> = program
                .symbols
                .get(&module.file)
                .map(|names| names.borrow().values().cloned().collect())
                .unwrap_or_default();
            let mut symbols: Vec<SymRef> = symbols;
            symbols.sort_by(|a, b| a.name.as_str().cmp(b.name.as_str()));
            for s in symbols {
                if !s.export
                    || s.decl.is_none()
                    || s.module != module.file
                    || self.seen.contains(s.name.as_str())
                    || !name_matches(s.name.as_str(), &self.c.prefix)
                    || (self.c.type_context && s.kind != SymKind::Type)
                {
                    continue;
                }
                self.add_import(&s, &path);
            }
        }
    }
}

fn keyword_template(word: &str) -> Option<&'static str> {
    Some(match word {
        "interface" => "interface ${1:Name}:\n    ${0:def operation() -> Unit}",
        "def" => "def ${1:name}(${2}) -> ${3:Unit}:\n    ${0:return ()}",
        "from" => "from \"${1:path}\" import ${0:name}",
        "type" => "type ${1:Name}:\n    ${0:field: String}",
        "if" => "if ${1:condition}:\n    $0",
        "for" => "for ${1:item} in ${2:items}:\n    $0",
        "with" => "with ${1:initializer} as ${2:resource}:\n    $0",
        "test" => "test \"${1:name}\":\n    ${0:return ()}",
        _ => return None,
    })
}

fn decl_name(decl: &ms_syntax::ast::Decl) -> String {
    match &decl.kind {
        DeclKind::Fn(f) => f.name.as_str().to_string(),
        DeclKind::Const(c) => c.name.as_str().to_string(),
        DeclKind::Record(r) => r.name.as_str().to_string(),
        DeclKind::Alternative(a) => a.name.as_str().to_string(),
        DeclKind::Interface(i) => i.name.as_str().to_string(),
        DeclKind::Test(t) => t.name.to_string(),
        DeclKind::Impl(_) => String::new(),
    }
}

/// Completion items at a position.
pub fn completion_at(
    d: &Document,
    docs: &Documents,
    p: Position,
    snippets: bool,
) -> Result<Vec<Item>, &'static str> {
    let c = context_at(d, p)?;
    if c.comment {
        return Ok(Vec::new());
    }
    if let Some(items) = import_completion(d, docs, &c) {
        return Ok(items);
    }
    if c.literal {
        return Ok(Vec::new());
    }
    let a = query_editor(d, docs, &c);
    let files = DeclFiles::new(&a.result.source_modules());
    let mut k = Completer {
        d,
        docs,
        c: &c,
        snippets,
        a,
        items: Vec::new(),
        seen: HashSet::new(),
        files,
    };
    if c.member {
        k.member_items();
    } else if c.argument {
        k.argument_items();
    } else {
        k.scope_items();
        k.keyword_items();
        if !c.prefix.is_empty() {
            k.standard_imports();
            k.workspace_imports();
        }
    }
    sort(&mut k.items);
    Ok(k.items)
}

fn simple_item(name: &str, detail: &str, kind: i64, range: Range, text: &str) -> Item {
    Item {
        label: name.to_string(),
        kind,
        detail: detail.to_string(),
        documentation: Json::Null,
        sort_text: name.to_string(),
        insert_format: 1,
        edit: text_edit(range, text),
        additional: Vec::new(),
    }
}

/// Completion inside an `import` declaration, or `None` outside one.
fn import_completion(d: &Document, docs: &Documents, c: &CursorContext) -> Option<Vec<Item>> {
    // Token context handles multiline groups without mistaking comments or
    // strings for an import declaration.
    let (mut start, mut parens) = (None::<usize>, 0i32);
    let (mut quote, mut import_end) = (None::<usize>, None::<usize>);
    for token in text::editor_tokens(&d.text[..c.offset]) {
        let Some(before) = d.text.get(..token.start) else {
            continue;
        };
        let line_start = before.rfind('\n').map_or(0, |at| at + 1);
        if token.is_name("from") && token.end <= c.start && before[line_start..].trim().is_empty() {
            (start, parens, quote, import_end) = (Some(token.start), 0, None, None);
            continue;
        }
        if start.is_none() {
            continue;
        }
        match token.kind {
            EditorKind::Str if quote.is_none() => quote = Some(token.start),
            EditorKind::Name if token.text == "import" && quote.is_some() => {
                import_end = Some(token.end)
            }
            EditorKind::Char(b'(') => parens += 1,
            EditorKind::Char(b')') => parens -= 1,
            EditorKind::Char(b'\n') if parens <= 0 => start = None,
            _ => {}
        }
    }
    start?;
    let mut imported: HashSet<String> = HashSet::new();
    if let Some(from) = import_end {
        let mut depth = parens;
        let mut end = d.text.len();
        for token in text::editor_tokens(&d.text[c.end..]) {
            match token.kind {
                EditorKind::Char(b'(') => depth += 1,
                EditorKind::Char(b')') => depth -= 1,
                EditorKind::Char(b'\n') if depth <= 0 => {
                    end = c.end + token.start;
                    break;
                }
                _ => {}
            }
        }
        for token in text::editor_tokens(&d.text[from..end.max(from)]) {
            let (token_start, token_end) = (from + token.start, from + token.end);
            if token.kind == EditorKind::Name && (token_end <= c.start || token_start >= c.end) {
                imported.insert(token.text.to_string());
            }
        }
    }
    let quote_text = quote.map(|at| {
        let rest = &d.text[at..];
        text::editor_tokens(rest)
            .first()
            .map_or(String::new(), |t| t.text.to_string())
    });
    let mut items: Vec<Item> = Vec::new();
    let quote = quote
        .filter(|_| import_end.is_none())
        .map(|at| at - start.unwrap_or(0));
    let start = start.unwrap_or(0);
    if let Some(quote) = quote {
        let path_start = start + quote + 1;
        let prefix = &d.text[path_start..c.offset];
        let mut end = c.offset;
        let bytes = d.text.as_bytes();
        while end < bytes.len() && bytes[end] != b'"' && bytes[end] != b'\n' {
            end += 1;
        }
        let range = Range {
            start: text::position(&d.text, path_start),
            end: text::position(&d.text, end),
        };
        for path in standard_paths() {
            if path.starts_with(prefix) {
                items.push(simple_item(&path, &path, 17, range, &path));
            }
        }
        let project = editor_project(d);
        let aliases = project
            .as_ref()
            .map(|p| p.aliases.clone())
            .unwrap_or_default();
        for (alias, target) in &aliases {
            let mut candidate = alias.clone();
            if std::fs::metadata(target).is_ok_and(|m| m.is_dir()) {
                candidate.push('/');
            }
            if candidate.starts_with(prefix) {
                items.push(simple_item(&candidate, &candidate, 17, range, &candidate));
            }
        }
        if (prefix.starts_with("./")
            || prefix.starts_with("../")
            || (prefix.starts_with('@') && !prefix.starts_with("@std/")))
            && let Some(slash) = prefix.rfind('/')
        {
            {
                let directory_prefix = &prefix[..=slash];
                let mut directory = pathops::join(&[&pathops::dir(&d.path()), directory_prefix]);
                if prefix.starts_with('@') {
                    let trimmed = directory_prefix.trim_end_matches('/');
                    let (alias, remainder) = trimmed.split_once('/').unwrap_or((trimmed, ""));
                    directory = match aliases.get(alias).filter(|b| !b.is_empty()) {
                        Some(base) => pathops::join(&[base, remainder]),
                        None => String::new(),
                    };
                }
                if !directory.is_empty()
                    && let Ok(canonical) = pathops::eval_symlinks(&directory)
                {
                    let root = project
                        .as_ref()
                        .map_or_else(|| pathops::dir(&d.path()), |p| p.root.clone());
                    let inside = pathops::rel(&root, &canonical)
                        .map(|r| !pathops::escapes(&r))
                        .unwrap_or(false);
                    if inside && let Ok(entries) = std::fs::read_dir(&canonical) {
                        let mut entries: Vec<_> = entries.flatten().collect();
                        entries.sort_by_key(|e| e.file_name());
                        for entry in entries {
                            let is_dir = entry.file_type().is_ok_and(|t| t.is_dir())
                                || std::fs::metadata(entry.path()).is_ok_and(|m| m.is_dir());
                            let mut path = format!(
                                "{directory_prefix}{}",
                                entry.file_name().to_string_lossy()
                            );
                            if path.starts_with(prefix) && (is_dir || path.ends_with(".ms")) {
                                if is_dir {
                                    path.push('/');
                                }
                                items.push(simple_item(&path, &path, 17, range, &path));
                            }
                        }
                    }
                }
            }
        }
        sort(&mut items);
        return Some(items);
    }
    // Symbol completion in `from "..." import Name` uses only exported declarations.
    let path = import_end
        .and(quote_text)
        .and_then(|t| ms_driver::project::quoting::unquote(&t));
    let range = Range {
        start: text::position(&d.text, c.start),
        end: text::position(&d.text, c.end),
    };
    if let Some(path) = path {
        let mut exports: Vec<SymRef> = standard_export_inventory()
            .remove(&path)
            .unwrap_or_default();
        if exports.is_empty()
            && (path.starts_with('.') || (path.starts_with('@') && !path.starts_with("@std/")))
        {
            let mut file = pathops::clean(&pathops::join(&[&pathops::dir(&d.path()), &path]));
            if path.starts_with('@') {
                let (alias, remainder) = path.split_once('/').unwrap_or((&path, ""));
                file = match editor_project(d)
                    .and_then(|p| p.aliases.get(alias).cloned())
                    .filter(|b| !b.is_empty())
                {
                    Some(base) => pathops::join(&[&base, remainder]),
                    None => String::new(),
                };
            }
            let opened = docs.get(&uri::file_uri(&file)).map(|o| o.text.clone());
            let source = opened.or_else(|| std::fs::read_to_string(&file).ok());
            if let Some(source) = source.filter(|_| !file.is_empty()) {
                let target = Document::new(uri::file_uri(&file), source);
                let checked = workspace_analysis(&target, docs);
                if let (Some(m), Some(program)) = (checked.module(&target), &checked.program)
                    && let Some(names) = program.symbols.get(&m.file)
                {
                    {
                        let mut found: Vec<SymRef> = names
                            .borrow()
                            .values()
                            .filter(|s| s.export && s.decl.is_some() && s.module == m.file)
                            .cloned()
                            .collect();
                        found.sort_by(|a, b| a.name.as_str().cmp(b.name.as_str()));
                        exports.extend(found);
                    }
                }
            }
        }
        for s in &exports {
            if !is_prelude_symbol(s)
                && !imported.contains(s.name.as_str())
                && name_matches(s.name.as_str(), &c.prefix)
            {
                let kind = if s.kind == SymKind::Type {
                    7
                } else if s.is_constant() {
                    21
                } else {
                    3
                };
                items.push(simple_item(
                    s.name.as_str(),
                    &path,
                    kind,
                    range,
                    s.name.as_str(),
                ));
            }
        }
        sort(&mut items);
        return Some(items);
    }
    sort(&mut items);
    Some(items)
}

/// Signature help for the call around the cursor.
pub fn signature_help(d: &Document, docs: &Documents, p: Position) -> Result<Json, &'static str> {
    let c = context_at(d, p)?;
    if c.call_open.is_none() || c.literal || c.comment {
        return Ok(Json::Null);
    }
    let a = query_editor(d, docs, &c);
    let Some((call, t)) = query_call(&a) else {
        return Ok(Json::Null);
    };
    let name = d.text[c.callee_start..c.callee_end].trim();
    let mut parameters = Vec::new();
    let mut labels = Vec::new();
    for param in &t.params {
        let mut label = format!("{}: {}", param.name, param.ty);
        if t.is_default(param.name) {
            label.push_str(" = ...");
        }
        labels.push(label.clone());
        parameters.push(obj([("label", label.into())]));
    }
    let mut active = 0;
    let mut used: HashSet<String> = HashSet::new();
    let mut current = String::new();
    for (arg, value) in call_arguments(&a, &call) {
        if arg == a.marker {
            continue;
        }
        if editor::contains_marker(&value, &a.marker) {
            current = arg;
        } else {
            used.insert(arg);
        }
    }
    if !current.is_empty() {
        if let Some(index) = t.params.iter().position(|p| p.name.as_str() == current) {
            active = index;
        }
    } else if let Some(index) = t
        .params
        .iter()
        .position(|p| !used.contains(p.name.as_str()) && p.name.as_str().starts_with(&c.prefix))
    {
        active = index;
    }
    let result = t.result.as_ref().map(|r| r.to_string()).unwrap_or_default();
    let label = format!("{name}({}) -> {result}", labels.join(", "));
    let mut documentation = Json::Null;
    if let (Some(module), ms_syntax::ast::ExprKind::Call { callee, .. }) = (&a.module, &call.kind) {
        let files = DeclFiles::new(&a.result.source_modules());
        let info = module.facts().info(callee.id).cloned();
        if let Some(info) = info {
            if let Some(symbol) = &info.symbol
                && let Some(decl) = &symbol.decl
            {
                let file = files.of_decl(decl).unwrap_or(symbol.module);
                documentation = nav::description(&a.result, file, decl.pos());
            }
            if let Some(method) = &info.method
                && let Some(decl) = &method.decl
            {
                let file = files.file(decl, method.module);
                documentation = nav::description(&a.result, file, decl.pos());
            }
        }
    }
    Ok(obj([
        (
            "signatures",
            Json::Arr(vec![obj([
                ("label", label.into()),
                ("parameters", Json::Arr(parameters)),
                ("documentation", documentation),
            ])]),
        ),
        ("activeSignature", 0usize.into()),
        ("activeParameter", active.into()),
    ]))
}
