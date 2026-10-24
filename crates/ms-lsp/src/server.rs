//! The language server session: framed JSON-RPC over a reader and a writer.
//!
//! One thread owns every document, analysis and cache; only frame decoding runs
//! elsewhere, because checking relies on thread-local standard-library state.

use crate::actions::editor_actions;
use crate::analysis::{
    self, Analysis, Document, Documents, Options, analyze, analyze_with, compile_file,
};
use crate::completion::{completion_at, signature_help};
use crate::features::{folding_ranges, inlay_hints};
use crate::json::{self, Json, obj};
use crate::lint::{Lint, Tooling};
use crate::nav::{self, Navigate};
use crate::rename::rename;
use crate::semantic::{TOKEN_TYPES, semantic_tokens};
use crate::symbols::document_symbols;
use crate::text::{self, Position, Range};
use crate::transport::{FrameError, Incoming, Transport};
use crate::uri;
use crate::workspace::{workspace_references, workspace_symbols};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::rc::Rc;
use std::sync::mpsc::TryRecvError;
use std::time::{Duration, Instant};

const MAX_BATCH: usize = 32;
const BATCH_WINDOW: Duration = Duration::from_millis(25);

/// Runs a session until the client exits or input ends.
pub fn serve(input: impl Read + Send + 'static, output: impl Write) -> Result<(), String> {
    serve_with(input, output, &Tooling)
}

/// Runs a session that takes its lint findings from `lint`.
pub fn serve_with(
    input: impl Read + Send + 'static,
    output: impl Write,
    lint: &dyn Lint,
) -> Result<(), String> {
    let mut server = Server {
        transport: Transport::new(input),
        output: Box::new(output),
        lint,
        docs: Documents::new(),
        cache: HashMap::new(),
        analyses: HashMap::new(),
        overlay_checked: false,
        share_overlays: false,
        roots: Vec::new(),
        snippets: false,
        shutdown: false,
        defer_diagnostics: false,
        diagnostics_dirty: false,
    };
    server.serve_messages()
}

/// How a request ended.
enum Outcome {
    Result(Json),
    Error(Json),
}

/// Why the session must end.
enum Stop {
    Exit,
    Failed(String),
}

impl From<std::io::Error> for Stop {
    fn from(e: std::io::Error) -> Stop {
        Stop::Failed(e.to_string())
    }
}

type Flow = Result<(), Stop>;

fn failure(code: i64, message: &str) -> Json {
    obj([("code", code.into()), ("message", message.into())])
}

fn not_open() -> Outcome {
    Outcome::Error(failure(-32602, "document is not open"))
}

fn ok(result: Json) -> Outcome {
    Outcome::Result(result)
}

/// A decoded client message.
struct Request {
    id: Option<Json>,
    method: String,
    params: Json,
    fields: Params,
}

/// The parameters any supported method reads.
#[derive(Default)]
struct Params {
    query: String,
    range: Range,
    new_name: String,
    document: Document,
    position: Position,
    only: Vec<String>,
    include_declaration: bool,
    changes: Vec<(String, Option<Range>)>,
}

impl Default for Document {
    fn default() -> Document {
        Document::new("", "")
    }
}

fn typed<'a>(value: &'a Json, key: &str) -> Result<Option<&'a Json>, ()> {
    match value.get(key) {
        None | Some(Json::Null) => Ok(None),
        Some(v) => Ok(Some(v)),
    }
}

fn string_field(value: &Json, key: &str) -> Result<String, ()> {
    match typed(value, key)? {
        None => Ok(String::new()),
        Some(Json::Str(s)) => Ok(s.clone()),
        Some(_) => Err(()),
    }
}

fn integer_field(value: &Json, key: &str) -> Result<i64, ()> {
    match typed(value, key)? {
        None => Ok(0),
        Some(v) => v.as_i64().ok_or(()),
    }
}

fn position_of(value: &Json) -> Result<Position, ()> {
    if !matches!(value, Json::Obj(_)) {
        return Err(());
    }
    let coordinate =
        |key| integer_field(value, key).map(|n| usize::try_from(n).unwrap_or(usize::MAX));
    Ok(Position {
        line: coordinate("line")?,
        character: coordinate("character")?,
    })
}

fn range_of(value: &Json) -> Result<Range, ()> {
    if !matches!(value, Json::Obj(_)) {
        return Err(());
    }
    let side = |key| match typed(value, key)? {
        None => Ok(Position::default()),
        Some(v) => position_of(v),
    };
    Ok(Range {
        start: side("start")?,
        end: side("end")?,
    })
}

impl Params {
    fn decode(value: &Json) -> Result<Params, ()> {
        let mut p = Params::default();
        match value {
            Json::Null => return Ok(p),
            Json::Obj(_) => {}
            _ => return Err(()),
        }
        p.query = string_field(value, "query")?;
        p.new_name = string_field(value, "newName")?;
        if let Some(range) = typed(value, "range")? {
            p.range = range_of(range)?;
        }
        if let Some(position) = typed(value, "position")? {
            p.position = position_of(position)?;
        }
        if let Some(document) = typed(value, "textDocument")? {
            if !matches!(document, Json::Obj(_)) {
                return Err(());
            }
            p.document = Document {
                uri: string_field(document, "uri")?,
                text: string_field(document, "text")?,
                version: integer_field(document, "version")?,
            };
        }
        if let Some(context) = typed(value, "context")? {
            if !matches!(context, Json::Obj(_)) {
                return Err(());
            }
            if let Some(only) = typed(context, "only")? {
                for kind in only.as_array().ok_or(())? {
                    p.only.push(kind.as_str().ok_or(())?.to_string());
                }
            }
            p.include_declaration = match typed(context, "includeDeclaration")? {
                None => false,
                Some(v) => v.as_bool().ok_or(())?,
            };
        }
        if let Some(changes) = typed(value, "contentChanges")? {
            for change in changes.as_array().ok_or(())? {
                if !matches!(change, Json::Obj(_)) {
                    return Err(());
                }
                let range = match typed(change, "range")? {
                    None => None,
                    Some(r) => Some(range_of(r)?),
                };
                p.changes.push((string_field(change, "text")?, range));
            }
        }
        Ok(p)
    }
}

/// Two sessions never share this state; one thread mutates it.
struct Server<'a> {
    transport: Transport,
    output: Box<dyn Write + 'a>,
    lint: &'a dyn Lint,
    docs: Documents,
    cache: HashMap<String, Rc<Analysis>>,
    analyses: HashMap<(String, Option<String>), Rc<Analysis>>,
    overlay_checked: bool,
    share_overlays: bool,
    roots: Vec<String>,
    snippets: bool,
    shutdown: bool,
    defer_diagnostics: bool,
    diagnostics_dirty: bool,
}

impl Server<'_> {
    /// Only the main loop mutates documents and analyses. Batch consecutive
    /// changes already available from the bounded transport, applying every
    /// range in order. Empty queues and non-change frames are barriers.
    fn serve_messages(&mut self) -> Result<(), String> {
        let mut next: Option<Incoming> = None;
        loop {
            let mut current = match next.take() {
                Some(queued) => queued,
                None => match self.transport.messages.recv() {
                    Ok(message) => message,
                    Err(_) => return Self::finish(self.flush_diagnostics()),
                },
            };
            if let Some(error) = current.error.take() {
                Self::finish(self.flush_diagnostics())?;
                return match error {
                    FrameError::Eof => Ok(()),
                    FrameError::Failed(message) => Err(message),
                };
            }
            if current.change {
                self.defer_diagnostics = true;
                let started = Instant::now();
                let mut count = 0;
                loop {
                    if let Err(stop) = self.serve(&current.body) {
                        self.defer_diagnostics = false;
                        return Self::ended(stop);
                    }
                    if count + 1 >= MAX_BATCH || started.elapsed() >= BATCH_WINDOW {
                        break;
                    }
                    count += 1;
                    match self.transport.messages.try_recv() {
                        Ok(queued) if queued.error.is_none() && queued.change => current = queued,
                        Ok(queued) => {
                            next = Some(queued);
                            break;
                        }
                        Err(TryRecvError::Empty | TryRecvError::Disconnected) => break,
                    }
                }
                self.defer_diagnostics = false;
                Self::finish(self.flush_diagnostics())?;
                continue;
            }
            if let Err(stop) = self.serve(&current.body) {
                return Self::ended(stop);
            }
        }
    }

    fn finish(flow: Flow) -> Result<(), String> {
        match flow {
            Ok(()) => Ok(()),
            Err(stop) => Self::ended(stop),
        }
    }

    fn ended(stop: Stop) -> Result<(), String> {
        match stop {
            Stop::Exit => Ok(()),
            Stop::Failed(message) => Err(message),
        }
    }

    fn flush_diagnostics(&mut self) -> Flow {
        if self.diagnostics_dirty {
            return self.publish();
        }
        Ok(())
    }

    fn send(&mut self, value: &Json) -> Flow {
        let body = value.compact(ms_json::Escape::Plain);
        write!(
            self.output,
            "Content-Length: {}\r\n\r\n{}",
            body.len(),
            body
        )?;
        self.output.flush()?;
        Ok(())
    }

    /// The live analysis of an open document, cached per generation.
    fn checked_document(&mut self, d: &Document) -> Rc<Analysis> {
        if self.docs.get(&d.uri) != Some(d) {
            // Private repaired/cursor snapshots cannot read or poison live caches.
            return analyze(d, &self.docs);
        }
        if let Some(result) = self.cache.get(&d.uri) {
            return result.clone();
        }
        let share = self.can_share_overlays();
        let analyses = &mut self.analyses;
        let options = Options {
            recover: true,
            ..Options::default()
        };
        let result = analyze_with(d, &self.docs, options, &mut |target, options| {
            if share {
                compile_snapshot(analyses, target, options)
            } else {
                Rc::new(compile_file(target, options))
            }
        });
        self.cache.insert(d.uri.clone(), result.clone());
        result
    }

    /// Two URI spellings can decode to the same filename. `analyze_with`
    /// deliberately lets the requested document win that overlay key; divergent
    /// text therefore cannot share a result, even within one generation.
    fn can_share_overlays(&mut self) -> bool {
        if self.overlay_checked {
            return self.share_overlays;
        }
        let mut seen: HashMap<String, &str> = HashMap::new();
        self.share_overlays = true;
        for d in self.docs.values() {
            let path = d.path();
            if let Some(text) = seen.get(&path)
                && *text != d.text
            {
                self.share_overlays = false;
                break;
            }
            seen.insert(path, &d.text);
        }
        self.overlay_checked = true;
        self.share_overlays
    }

    /// Drops cached analyses after a document or file change.
    fn invalidate(&mut self) {
        self.cache.clear();
        self.analyses.clear();
        self.overlay_checked = false;
        self.share_overlays = false;
    }

    fn publish_diagnostics(
        &mut self,
        uri: &str,
        version: Option<i64>,
        diagnostics: Vec<Json>,
    ) -> Flow {
        let mut params = obj([("uri", uri.into())]);
        if let Some(version) = version {
            params.set("version", version.into());
        }
        params.set("diagnostics", Json::Arr(diagnostics));
        self.send(&obj([
            ("jsonrpc", "2.0".into()),
            ("method", "textDocument/publishDiagnostics".into()),
            ("params", params),
        ]))
    }

    /// Sends diagnostics for every open document, in URI order.
    fn publish(&mut self) -> Flow {
        self.diagnostics_dirty = false;
        let mut uris: Vec<String> = self.docs.keys().cloned().collect();
        uris.sort();
        for uri in uris {
            let Some(d) = self.docs.get(&uri).cloned() else {
                continue;
            };
            if uri::is_standard_library(&uri) {
                self.publish_diagnostics(&uri, Some(d.version), Vec::new())?;
                continue;
            }
            let checked = self.checked_document(&d);
            let module = checked.module(&d);
            let mut diagnostics = Vec::new();
            for issue in &checked.diagnostics {
                if let Some(m) = &module
                    && issue.file.as_ref() != m.file.as_str()
                {
                    continue;
                }
                diagnostics.push(diagnostic(
                    &d,
                    issue.pos.offset as usize,
                    1,
                    "manuscript",
                    issue.code(),
                    &issue.message,
                ));
            }
            let mut advisories = self.lint.source(&uri::filename(&d.uri), &d.text);
            if let Some(m) = &module {
                advisories.extend(
                    checked
                        .lints(self.lint)
                        .iter()
                        .filter(|f| f.file == m.file.as_str())
                        .cloned(),
                );
            }
            for issue in &advisories {
                diagnostics.push(diagnostic(
                    &d,
                    issue.offset,
                    2,
                    "manuscript-lint",
                    &issue.code,
                    &issue.message,
                ));
            }
            self.publish_diagnostics(&d.uri, Some(d.version), diagnostics)?;
        }
        Ok(())
    }

    fn request_canceled(&self, r: &Request) -> bool {
        r.id.as_ref().is_some_and(|id| self.transport.canceled(id))
    }

    /// Decodes one message, runs it, and sends the response a request expects.
    fn serve(&mut self, body: &[u8]) -> Flow {
        let message = match json::parse(body) {
            Ok(message) => message,
            Err(_) => return self.reply_error(None, -32700, "invalid JSON"),
        };
        let well_formed = matches!(message, Json::Obj(_))
            && message
                .get("jsonrpc")
                .is_none_or(|v| v.is_null() || v.as_str().is_some())
            && message
                .get("method")
                .is_none_or(|v| v.is_null() || v.as_str().is_some());
        if !well_formed {
            return self.reply_error(None, -32600, "invalid request");
        }
        let id = message.get("id").cloned();
        let method = message
            .get("method")
            .and_then(|m| m.as_str())
            .unwrap_or("")
            .to_string();
        if message.get("jsonrpc").and_then(|v| v.as_str()) != Some("2.0") || method.is_empty() {
            let flow = self.reply_error(None, -32600, "invalid request");
            if let Some(id) = &id {
                self.transport.done(id);
            }
            return flow;
        }
        let params = message.get("params").cloned().unwrap_or(Json::Null);
        let fields = match Params::decode(&params) {
            Ok(fields) => fields,
            Err(()) => {
                let Some(id) = id else { return Ok(()) };
                let flow = self.reply_error(Some(&id), -32602, "invalid parameters");
                self.transport.done(&id);
                return flow;
            }
        };
        let r = Request {
            id,
            method,
            params,
            fields,
        };
        if self.shutdown && r.method != "exit" {
            return match &r.id {
                Some(id) => self.reply_error(Some(id), -32600, "server has shut down"),
                None => Ok(()),
            };
        }
        let outcome = if self.request_canceled(&r) {
            Outcome::Error(failure(-32800, "request canceled"))
        } else {
            self.handle(&r)?
        };
        let Some(id) = &r.id else { return Ok(()) };
        let outcome = if self.transport.canceled(id) {
            Outcome::Error(failure(-32800, "request canceled"))
        } else {
            outcome
        };
        self.transport.done(id);
        let mut response = obj([("jsonrpc", "2.0".into()), ("id", id.clone())]);
        match outcome {
            Outcome::Error(error) => response.set("error", error),
            Outcome::Result(result) => response.set("result", result),
        }
        self.send(&response)
    }

    fn reply_error(&mut self, id: Option<&Json>, code: i64, message: &str) -> Flow {
        self.send(&obj([
            ("jsonrpc", "2.0".into()),
            ("id", id.cloned().unwrap_or(Json::Null)),
            ("error", failure(code, message)),
        ]))
    }

    /// Routes a request to its method.
    fn handle(&mut self, r: &Request) -> Result<Outcome, Stop> {
        let p = &r.fields;
        match r.method.as_str() {
            "initialize" => return Ok(ok(self.initialize(r))),
            "manuscript/standardLibrarySource" => {
                return Ok(match analysis::standard_library_source(&p.document.uri) {
                    Ok(source) => ok(source.into()),
                    Err(message) => Outcome::Error(failure(-32602, message)),
                });
            }
            "initialized" => return Ok(ok(Json::Null)),
            "shutdown" => {
                self.shutdown = true;
                return Ok(ok(Json::Null));
            }
            "exit" => {
                if !self.shutdown {
                    return Err(Stop::Failed("exit before shutdown".to_string()));
                }
                return Err(Stop::Exit);
            }
            "workspace/didChangeWatchedFiles" => {
                if let Some(changes) = r.params.get("changes").and_then(|c| c.as_array()) {
                    let relevant = changes.iter().any(|change| {
                        let path =
                            uri::filename(change.get("uri").and_then(|u| u.as_str()).unwrap_or(""));
                        path.ends_with(".ms")
                            || ms_driver::project::gopath::base(&path) == "ms.toml"
                    });
                    if !relevant {
                        return Ok(ok(Json::Null));
                    }
                }
                self.invalidate();
                self.publish()?;
                return Ok(ok(Json::Null));
            }
            "textDocument/didClose" => {
                self.docs.remove(&p.document.uri);
                self.invalidate();
                self.publish()?;
                self.publish_diagnostics(&p.document.uri, None, Vec::new())?;
                return Ok(ok(Json::Null));
            }
            "textDocument/didOpen" | "textDocument/didChange" => {
                self.did_change(r)?;
                return Ok(ok(Json::Null));
            }
            "workspace/symbol" => {
                let cancel = || self.request_canceled(r);
                let found = workspace_symbols(&self.docs, &self.roots, &p.query, Some(&cancel));
                return Ok(ok(found.map_or(Json::Null, Json::Arr)));
            }
            _ => {}
        }
        if !r.method.starts_with("textDocument/") {
            return Ok(if r.id.is_some() {
                Outcome::Error(failure(-32601, "method not supported"))
            } else {
                ok(Json::Null)
            });
        }
        Ok(self.document_request(r))
    }

    /// Records the client's roots and snippet support and answers with the
    /// server's capabilities.
    fn initialize(&mut self, r: &Request) -> Json {
        let params = &r.params;
        self.snippets = params
            .get("capabilities")
            .and_then(|c| c.get("textDocument"))
            .and_then(|c| c.get("completion"))
            .and_then(|c| c.get("completionItem"))
            .and_then(|c| c.get("snippetSupport"))
            .and_then(|c| c.as_bool())
            .unwrap_or(false);
        if let Some(root) = params.get("rootUri").and_then(|u| u.as_str())
            && !root.is_empty()
        {
            self.roots.push(uri::filename(root));
        }
        for folder in params
            .get("workspaceFolders")
            .and_then(|f| f.as_array())
            .unwrap_or(&[])
        {
            if let Some(root) = folder.get("uri").and_then(|u| u.as_str()) {
                self.roots.push(uri::filename(root));
            }
        }
        let strings = |items: &[&str]| Json::Arr(items.iter().map(|i| (*i).into()).collect());
        obj([
            (
                "capabilities",
                obj([
                    ("textDocumentSync", 2usize.into()),
                    ("documentFormattingProvider", true.into()),
                    ("workspaceSymbolProvider", true.into()),
                    ("documentSymbolProvider", true.into()),
                    (
                        "semanticTokensProvider",
                        obj([
                            (
                                "legend",
                                obj([
                                    ("tokenTypes", strings(&TOKEN_TYPES)),
                                    ("tokenModifiers", Json::Arr(Vec::new())),
                                ]),
                            ),
                            ("full", true.into()),
                        ]),
                    ),
                    (
                        "codeActionProvider",
                        obj([(
                            "codeActionKinds",
                            strings(&[
                                "source.fixAll.manuscript",
                                "quickfix",
                                "source.organizeImports",
                            ]),
                        )]),
                    ),
                    ("renameProvider", obj([("prepareProvider", true.into())])),
                    ("referencesProvider", true.into()),
                    (
                        "signatureHelpProvider",
                        obj([
                            ("triggerCharacters", strings(&["(", ",", ":"])),
                            ("retriggerCharacters", strings(&[","])),
                        ]),
                    ),
                    ("foldingRangeProvider", true.into()),
                    ("inlayHintProvider", true.into()),
                    ("typeDefinitionProvider", true.into()),
                    ("documentHighlightProvider", true.into()),
                    ("hoverProvider", true.into()),
                    ("definitionProvider", true.into()),
                    (
                        "completionProvider",
                        obj([("triggerCharacters", strings(&[".", ":", "/"]))]),
                    ),
                    ("positionEncoding", "utf-16".into()),
                ]),
            ),
            (
                "serverInfo",
                obj([("name", "manuscript".into()), ("version", "0.1.0".into())]),
            ),
        ])
    }

    /// Stores an opened or edited document and republishes diagnostics. Stale,
    /// empty, or malformed edits are ignored.
    fn did_change(&mut self, r: &Request) -> Flow {
        let p = &r.fields;
        let mut d = p.document.clone();
        if uri::is_standard_library(&d.uri) {
            if r.method == "textDocument/didChange" {
                return Ok(());
            }
            match analysis::standard_library_source(&d.uri) {
                Ok(source) => d.text = source,
                Err(_) => return Ok(()),
            }
        }
        if r.method == "textDocument/didChange" {
            let Some(old) = self.docs.get(&d.uri) else {
                return Ok(());
            };
            if d.version <= old.version || p.changes.is_empty() {
                return Ok(());
            }
            d.text = old.text.clone();
            for (text, range) in &p.changes {
                let Some(range) = range else {
                    d.text = text.clone();
                    continue;
                };
                let (Ok(start), Ok(end)) = (
                    text::edit_offset(&d.text, range.start),
                    text::edit_offset(&d.text, range.end),
                ) else {
                    return Ok(());
                };
                if end < start {
                    return Ok(());
                }
                d.text = format!("{}{}{}", &d.text[..start], text, &d.text[end..]);
            }
        }
        self.docs.insert(d.uri.clone(), d);
        self.invalidate();
        if self.defer_diagnostics {
            self.diagnostics_dirty = true;
            return Ok(());
        }
        self.publish()
    }

    /// Answers the `textDocument/*` requests that read one open document.
    fn document_request(&mut self, r: &Request) -> Outcome {
        let p = &r.fields;
        let open = self.docs.get(&p.document.uri).cloned();
        match r.method.as_str() {
            "textDocument/semanticTokens/full" => {
                let Some(d) = open else { return not_open() };
                let checked = self.checked_document(&d);
                if self.request_canceled(r) {
                    return ok(Json::Null);
                }
                let index = checked.index();
                ok(semantic_tokens(Some(&checked), index, &d))
            }
            "textDocument/codeAction" => {
                let Some(d) = open else { return not_open() };
                if uri::is_standard_library(&d.uri) {
                    return ok(Json::Arr(Vec::new()));
                }
                let checked = self.checked_document(&d);
                if self.request_canceled(r) {
                    return ok(Json::Null);
                }
                ok(Json::Arr(editor_actions(
                    &d, &checked, self.lint, p.range, &p.only,
                )))
            }
            "textDocument/formatting" => {
                let Some(d) = open else { return not_open() };
                if uri::is_standard_library(&d.uri) {
                    return ok(Json::Arr(Vec::new()));
                }
                let file: std::sync::Arc<str> = uri::filename(&d.uri).into();
                match ms_syntax::format(&file, &d.text) {
                    Err(e) => Outcome::Error(failure(-32602, &e.to_string())),
                    Ok(formatted) => {
                        let range = Range {
                            start: Position::default(),
                            end: text::position(&d.text, d.text.len()),
                        };
                        ok(Json::Arr(vec![obj([
                            ("range", range.json()),
                            ("newText", formatted.into()),
                        ])]))
                    }
                }
            }
            "textDocument/prepareRename" | "textDocument/rename" => {
                let Some(d) = open else { return not_open() };
                self.rename(r, &d)
            }
            "textDocument/signatureHelp" => {
                let Some(d) = open else { return ok(Json::Null) };
                match signature_help(&d, &self.docs, p.position) {
                    Ok(help) => ok(help),
                    Err(message) => Outcome::Error(failure(-32602, message)),
                }
            }
            "textDocument/foldingRange"
            | "textDocument/inlayHint"
            | "textDocument/typeDefinition"
            | "textDocument/documentHighlight" => {
                let Some(d) = open else { return ok(Json::Null) };
                ok(self.document_feature(r, &d))
            }
            "textDocument/completion" => {
                let Some(d) = open else {
                    return ok(Json::Arr(Vec::new()));
                };
                match completion_at(&d, &self.docs, p.position, self.snippets) {
                    Ok(items) => ok(Json::Arr(items.iter().map(|i| i.json()).collect())),
                    Err(message) => Outcome::Error(failure(-32602, message)),
                }
            }
            "textDocument/hover" | "textDocument/definition" | "textDocument/references" => {
                let Some(d) = open else { return ok(Json::Null) };
                let checked = self.checked_document(&d);
                if self.request_canceled(r) || checked.program.is_none() {
                    return ok(Json::Null);
                }
                let index = checked.index();
                if r.method == "textDocument/references" {
                    let cancel = || self.request_canceled(r);
                    return ok(Json::Arr(workspace_references(
                        &checked,
                        index,
                        &d,
                        &self.docs,
                        p.position,
                        p.include_declaration,
                        Some(&cancel),
                    )));
                }
                if self.request_canceled(r) {
                    return ok(Json::Null);
                }
                let method = if r.method == "textDocument/hover" {
                    Navigate::Hover
                } else {
                    Navigate::Definition
                };
                ok(nav::navigation(&checked, &d, p.position, method, index))
            }
            "textDocument/documentSymbol" => {
                let Some(d) = open else {
                    return ok(Json::Arr(Vec::new()));
                };
                let checked = self.checked_document(&d);
                if self.request_canceled(r) {
                    return ok(Json::Null);
                }
                ok(document_symbols(&checked, &d))
            }
            _ if r.id.is_some() => Outcome::Error(failure(-32601, "method not supported")),
            _ => ok(Json::Null),
        }
    }

    fn rename(&mut self, r: &Request, d: &Document) -> Outcome {
        let p = &r.fields;
        let checked = self.checked_document(d);
        if self.request_canceled(r) {
            return ok(Json::Null);
        }
        if !checked.success() {
            return Outcome::Error(failure(-32602, "rename requires a checked document"));
        }
        let mut name = p.new_name.as_str();
        if r.method == "textDocument/rename" && name.is_empty() {
            return Outcome::Error(failure(-32602, "new name is empty"));
        }
        if r.method == "textDocument/prepareRename" {
            name = "";
        }
        let cancel = || self.request_canceled(r);
        match rename(
            &checked,
            checked.index(),
            d,
            p.position,
            name,
            Some(&cancel),
            Some(&self.docs),
        ) {
            Ok(edit) => ok(edit),
            Err(message) => Outcome::Error(failure(-32602, &message)),
        }
    }

    /// Answers the folding, inlay hint, type definition, and highlight
    /// requests, which share one checked document.
    fn document_feature(&mut self, r: &Request, d: &Document) -> Json {
        let p = &r.fields;
        let checked = self.checked_document(d);
        if self.request_canceled(r) {
            return Json::Null;
        }
        match r.method.as_str() {
            "textDocument/foldingRange" => return folding_ranges(d),
            "textDocument/inlayHint" => return inlay_hints(&checked, d, p.range),
            _ => {}
        }
        let index = checked.index();
        if self.request_canceled(r) {
            return Json::Null;
        }
        if r.method == "textDocument/typeDefinition" {
            return nav::type_definition(&checked, d, p.position, index);
        }
        let mut highlights = Vec::new();
        if checked.program.is_some() {
            for location in nav::references_with_index(&checked, index, d, p.position, true) {
                let same = location
                    .get("uri")
                    .and_then(|u| u.as_str())
                    .is_some_and(|u| uri::filename(u) == uri::filename(&d.uri));
                if same && let Some(range) = location.get("range") {
                    highlights.push(obj([("range", range.clone()), ("kind", 2usize.into())]));
                }
            }
        }
        Json::Arr(highlights)
    }
}

fn diagnostic(
    d: &Document,
    offset: usize,
    severity: i64,
    source: &str,
    code: &str,
    message: &str,
) -> Json {
    obj([
        ("range", text::diagnostic_range(&d.text, offset).json()),
        ("severity", severity.into()),
        ("source", source.into()),
        ("code", code.into()),
        ("message", message.into()),
    ])
}

/// A recovering analysis shared by every document of one live generation. A
/// selected fallback never replaces the default manifest entry.
fn compile_snapshot(
    analyses: &mut HashMap<(String, Option<String>), Rc<Analysis>>,
    target: &str,
    options: &Options,
) -> Rc<Analysis> {
    let mut identity = target.to_string();
    // The nearest manifest has already been selected, including invalid nested
    // manifests. Only then canonicalize an existing target for reuse.
    if ms_driver::project::gopath::base(target) == "ms.toml"
        && let Ok(root) =
            ms_driver::project::gopath::eval_symlinks(&ms_driver::project::gopath::dir(target))
    {
        identity = ms_driver::project::gopath::join(&[&root, "ms.toml"]);
    }
    let key = (identity, options.module.clone());
    if let Some(result) = analyses.get(&key) {
        return result.clone();
    }
    let result = Rc::new(compile_file(target, options));
    analyses.insert(key, result.clone());
    result
}
