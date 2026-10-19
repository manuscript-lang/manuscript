//! Differential tests: the same client session against the Go server and this
//! crate's server must produce the same messages.

mod support;

use ms_lsp::json::obj;
use support::{Script, Workspace, compare};

/// Offsets of every identifier start in `text` as (line, character).
fn identifier_positions(text: &str) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    for (line, content) in text.split('\n').enumerate() {
        let chars: Vec<char> = content.chars().collect();
        let mut column = 0;
        while column < chars.len() {
            if chars[column].is_alphabetic() || chars[column] == '_' {
                let start = column;
                while column < chars.len()
                    && (chars[column].is_alphanumeric() || chars[column] == '_')
                {
                    column += 1;
                }
                out.push((line, start));
                if column - start > 2 {
                    out.push((line, start + 2));
                }
            } else {
                column += 1;
            }
        }
    }
    out
}

#[test]
fn lifecycle_and_diagnostics() {
    let ws = Workspace::new("lifecycle");
    let main = ws.uri("main.ms");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), true);
    s.open(&main, &ws.read("main.ms"), 1);
    let broken = ws.uri("broken.ms");
    s.open(
        &broken,
        "fn broken() Int:\n    let x: String = 1\n    return missing\n",
        1,
    );
    let syntax = ws.uri("syntax.ms");
    s.open(&syntax, "fn (:\n", 1);
    s.request("workspace/unknown", obj([]));
    s.notify("workspace/unknown", obj([]));
    s.request(
        "textDocument/unknown",
        obj([("textDocument", obj([("uri", main.as_str().into())]))]),
    );
    compare("lifecycle", &s);
}

#[test]
fn navigation_over_every_identifier() {
    let ws = Workspace::new("navigation");
    let main = ws.uri("main.ms");
    let source = ws.read("main.ms");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), true);
    s.open(&main, &source, 1);
    for (line, character) in identifier_positions(&source) {
        for method in [
            "textDocument/hover",
            "textDocument/definition",
            "textDocument/references",
            "textDocument/typeDefinition",
            "textDocument/documentHighlight",
        ] {
            s.at(method, &main, line, character);
        }
    }
    s.request(
        "textDocument/documentSymbol",
        obj([("textDocument", obj([("uri", main.as_str().into())]))]),
    );
    s.request(
        "textDocument/semanticTokens/full",
        obj([("textDocument", obj([("uri", main.as_str().into())]))]),
    );
    s.request(
        "textDocument/foldingRange",
        obj([("textDocument", obj([("uri", main.as_str().into())]))]),
    );
    compare("navigation", &s);
}

fn completion_positions(text: &str) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    for (line, content) in text.split('\n').enumerate() {
        let chars: Vec<char> = content.chars().collect();
        let mut column = 0;
        while column < chars.len() {
            if chars[column].is_alphabetic() || chars[column] == '_' {
                let start = column;
                while column < chars.len()
                    && (chars[column].is_alphanumeric() || chars[column] == '_')
                {
                    column += 1;
                }
                out.push((line, start + 1));
                out.push((line, column));
            } else {
                if matches!(chars[column], '.' | '(' | ',' | ':' | '[' | '"') {
                    out.push((line, column + 1));
                }
                column += 1;
            }
        }
        out.push((line, chars.len()));
    }
    out.sort();
    out.dedup();
    out
}

fn complete_everywhere(name: &str, snippets: bool) {
    let ws = Workspace::new(name);
    let main = ws.uri("main.ms");
    let source = ws.read("main.ms");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), snippets);
    s.open(&main, &source, 1);
    for (line, character) in completion_positions(&source) {
        s.at("textDocument/completion", &main, line, character);
        s.at("textDocument/signatureHelp", &main, line, character);
    }
    compare(name, &s);
}

#[test]
fn completion_and_signatures_with_snippets() {
    complete_everywhere("completion-snippets", true);
}

#[test]
fn completion_and_signatures_without_snippets() {
    complete_everywhere("completion-plain", false);
}

/// Half-written code: the checker cannot see these, so the editor repairs a
/// private snapshot.
#[test]
fn completion_in_unfinished_code() {
    let ws = Workspace::new("unfinished");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), true);
    let cases: &[(&str, &str)] = &[
        (
            "member",
            "fn main() Int:\n    let p = Point(x: 1)\n    let q = p.",
        ),
        (
            "std-member",
            "import stdout from \"@std/io.ms\"\nfn main() Int:\n    let w = stdout().",
        ),
        ("list-member", "fn main() Int:\n    let w = [1]."),
        ("string-member", "fn main() Int:\n    let w = \"a\"."),
        (
            "member-prefix",
            "fn main() Int:\n    let p = Point(x: 1)\n    return p.no",
        ),
        ("call", "fn main() Int:\n    return add("),
        ("call-second", "fn main() Int:\n    return add(1, "),
        ("call-label", "fn main() Int:\n    return add(a: 1, b"),
        ("constructor", "fn main() Int:\n    let p = Point("),
        ("case", "fn main() Int:\n    let s = Shape.C"),
        ("type", "fn main() Int:\n    let z: In"),
        ("param-type", "fn run(shape: Sh"),
        ("import-name", "import {st"),
        ("import-path", "import stdout from \"@std/i"),
        (
            "import-from",
            "import {stdout} from \"@std/io.ms\"\nimport {} from \"@std/testing.ms\"",
        ),
        ("import-local", "import {x} from \"./"),
        ("keyword", "fn main() Int:\n    ret"),
        ("top-level", "fn main() Int:\n    return 0\n\nim"),
        (
            "match",
            "fn area(shape: Shape) Int:\n    match shape:\n        Ci",
        ),
        ("string", "fn main() String:\n    return \"abc"),
        ("comment", "fn main() Int:\n    # note"),
    ];
    let prelude = "type Point:\n    x: Int\n    y: Int = 0\n\ntype Shape:\n    case Circle(radius: Int)\n    case Empty\n\nfn add(a: Int, b: Int) Int:\n    return a + b\n\n";
    for (index, (name, tail)) in cases.iter().enumerate() {
        let uri = ws.uri(&format!("case{index}.ms"));
        let text = if name.starts_with("import") {
            (*tail).to_string()
        } else {
            format!("{prelude}{tail}")
        };
        s.open(&uri, &text, 1);
        let line = text.split('\n').count() - 1;
        let character = text.rsplit('\n').next().map_or(0, |l| l.chars().count());
        s.at("textDocument/completion", &uri, line, character);
        s.at("textDocument/signatureHelp", &uri, line, character);
        if *name == "import-from" {
            s.at("textDocument/completion", &uri, 1, 8);
        }
    }
    compare("unfinished", &s);
}

#[test]
fn rename_actions_and_formatting() {
    let ws = Workspace::new("rename");
    let main = ws.uri("main.ms");
    let source = ws.read("main.ms");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), true);
    s.open(&main, &source, 1);
    for (line, character) in identifier_positions(&source) {
        s.at("textDocument/prepareRename", &main, line, character);
    }
    for (line, character) in [
        (22usize, 4usize),
        (22, 15),
        (31, 14),
        (41, 8),
        (8, 9),
        (3, 7),
        (27, 4),
    ] {
        let id = s.request(
            "textDocument/rename",
            obj([
                ("textDocument", obj([("uri", main.as_str().into())])),
                (
                    "position",
                    obj([("line", line.into()), ("character", character.into())]),
                ),
                ("newName", "renamed".into()),
            ]),
        );
        let _ = id;
    }
    let whole = obj([
        (
            "start",
            obj([("line", 0usize.into()), ("character", 0usize.into())]),
        ),
        (
            "end",
            obj([("line", 100usize.into()), ("character", 0usize.into())]),
        ),
    ]);
    s.request(
        "textDocument/codeAction",
        obj([
            ("textDocument", obj([("uri", main.as_str().into())])),
            ("range", whole.clone()),
            (
                "context",
                obj([("diagnostics", ms_lsp::json::Json::Arr(vec![]))]),
            ),
        ]),
    );
    s.request(
        "textDocument/formatting",
        obj([("textDocument", obj([("uri", main.as_str().into())]))]),
    );
    s.request(
        "textDocument/inlayHint",
        obj([
            ("textDocument", obj([("uri", main.as_str().into())])),
            ("range", whole),
        ]),
    );
    let messy = ws.uri("messy.ms");
    s.open(
        &messy,
        "import {expect_equal} from \"@std/testing.ms\"   \nimport stdout from \"@std/io.ms\"\nimport unused from \"@std/json.ms\"\nfn  main( )  Int:\n    return 0",
        1,
    );
    let all = obj([
        (
            "start",
            obj([("line", 0usize.into()), ("character", 0usize.into())]),
        ),
        (
            "end",
            obj([("line", 10usize.into()), ("character", 0usize.into())]),
        ),
    ]);
    s.request(
        "textDocument/codeAction",
        obj([
            ("textDocument", obj([("uri", messy.as_str().into())])),
            ("range", all.clone()),
            (
                "context",
                obj([("diagnostics", ms_lsp::json::Json::Arr(vec![]))]),
            ),
        ]),
    );
    s.request(
        "textDocument/codeAction",
        obj([
            ("textDocument", obj([("uri", messy.as_str().into())])),
            ("range", all),
            (
                "context",
                obj([(
                    "only",
                    ms_lsp::json::Json::Arr(vec!["source.organizeImports".into()]),
                )]),
            ),
        ]),
    );
    s.request(
        "textDocument/formatting",
        obj([("textDocument", obj([("uri", messy.as_str().into())]))]),
    );
    compare("rename", &s);
}

#[test]
fn project_references_symbols_and_edits() {
    let ws = Workspace::new("project");
    let root = ws.root.join("project");
    let mut s = Script::initialize(&root.to_string_lossy(), true);
    let main = ws.uri("project/main.ms");
    let util = ws.uri("project/util.ms");
    let helper = ws.uri("project/helper.ms");
    s.open(&main, &ws.read("project/main.ms"), 1);
    s.open(&util, &ws.read("project/util.ms"), 1);
    s.request("workspace/symbol", obj([("query", "".into())]));
    s.request("workspace/symbol", obj([("query", "dou".into())]));
    for (uri, text) in [
        (&main, "project/main.ms"),
        (&util, "project/util.ms"),
        (&helper, "project/helper.ms"),
    ] {
        let source = ws.read(text);
        if uri == &helper {
            s.open(uri, &source, 1);
        }
        for (line, character) in identifier_positions(&source) {
            s.at("textDocument/references", uri, line, character);
            s.at("textDocument/definition", uri, line, character);
            s.at("textDocument/hover", uri, line, character);
            s.at("textDocument/prepareRename", uri, line, character);
        }
    }
    s.request(
        "textDocument/rename",
        obj([
            ("textDocument", obj([("uri", util.as_str().into())])),
            (
                "position",
                obj([("line", 3usize.into()), ("character", 11usize.into())]),
            ),
            ("newName", "twice".into()),
        ]),
    );
    // Incremental edit, then a stale edit, then a change to a closed document.
    s.notify(
        "textDocument/didChange",
        obj([
            (
                "textDocument",
                obj([("uri", util.as_str().into()), ("version", 2usize.into())]),
            ),
            (
                "contentChanges",
                ms_lsp::json::Json::Arr(vec![obj([
                    (
                        "range",
                        obj([
                            (
                                "start",
                                obj([("line", 4usize.into()), ("character", 11usize.into())]),
                            ),
                            (
                                "end",
                                obj([("line", 4usize.into()), ("character", 16usize.into())]),
                            ),
                        ]),
                    ),
                    ("text", "n * \"x\"".into()),
                ])]),
            ),
        ]),
    );
    s.at("textDocument/hover", &main, 5, 18);
    s.notify(
        "textDocument/didChange",
        obj([
            (
                "textDocument",
                obj([("uri", util.as_str().into()), ("version", 2usize.into())]),
            ),
            (
                "contentChanges",
                ms_lsp::json::Json::Arr(vec![obj([("text", "stale".into())])]),
            ),
        ]),
    );
    s.notify(
        "textDocument/didClose",
        obj([("textDocument", obj([("uri", util.as_str().into())]))]),
    );
    s.notify(
        "workspace/didChangeWatchedFiles",
        obj([(
            "changes",
            ms_lsp::json::Json::Arr(vec![obj([
                ("uri", helper.as_str().into()),
                ("type", 2usize.into()),
            ])]),
        )]),
    );
    s.notify(
        "workspace/didChangeWatchedFiles",
        obj([(
            "changes",
            ms_lsp::json::Json::Arr(vec![obj([
                ("uri", ws.uri("notes.txt").as_str().into()),
                ("type", 2usize.into()),
            ])]),
        )]),
    );
    compare("project", &s);
}

#[test]
fn protocol_errors_and_standard_library() {
    let ws = Workspace::new("protocol");
    let main = ws.uri("main.ms");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), false);
    s.raw("{not json");
    s.raw("[1,2]");
    s.raw("{\"jsonrpc\":\"1.0\",\"id\":9,\"method\":\"x\"}");
    s.raw("{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"textDocument/hover\",\"params\":{\"position\":\"nope\"}}");
    s.raw("{\"jsonrpc\":\"2.0\",\"id\":\"str-id\",\"method\":\"nothing/known\"}");
    s.raw("{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///missing.ms\"},\"position\":{\"line\":0,\"character\":0}}}");
    s.request(
        "textDocument/documentSymbol",
        obj([("textDocument", obj([("uri", "file:///missing.ms".into())]))]),
    );
    s.request(
        "textDocument/rename",
        obj([
            ("textDocument", obj([("uri", "file:///missing.ms".into())])),
            ("newName", "a".into()),
        ]),
    );
    s.open(&main, &ws.read("main.ms"), 1);
    s.request(
        "manuscript/standardLibrarySource",
        obj([(
            "textDocument",
            obj([("uri", "manuscript-stdlib:///io.ms".into())]),
        )]),
    );
    s.request(
        "manuscript/standardLibrarySource",
        obj([(
            "textDocument",
            obj([("uri", "manuscript-stdlib:///nope.ms".into())]),
        )]),
    );
    s.open("manuscript-stdlib:///io.ms", "", 1);
    for (line, character) in [(0, 20), (5, 5), (10, 3), (20, 6)] {
        s.at(
            "textDocument/hover",
            "manuscript-stdlib:///io.ms",
            line,
            character,
        );
        s.at(
            "textDocument/definition",
            "manuscript-stdlib:///io.ms",
            line,
            character,
        );
        s.at(
            "textDocument/references",
            "manuscript-stdlib:///io.ms",
            line,
            character,
        );
        s.at(
            "textDocument/completion",
            "manuscript-stdlib:///io.ms",
            line,
            character,
        );
    }
    s.request(
        "textDocument/semanticTokens/full",
        obj([(
            "textDocument",
            obj([("uri", "manuscript-stdlib:///io.ms".into())]),
        )]),
    );
    s.request(
        "textDocument/documentSymbol",
        obj([(
            "textDocument",
            obj([("uri", "manuscript-stdlib:///io.ms".into())]),
        )]),
    );
    s.request(
        "textDocument/codeAction",
        obj([
            (
                "textDocument",
                obj([("uri", "manuscript-stdlib:///io.ms".into())]),
            ),
            (
                "range",
                obj([
                    (
                        "start",
                        obj([("line", 0usize.into()), ("character", 0usize.into())]),
                    ),
                    (
                        "end",
                        obj([("line", 1usize.into()), ("character", 0usize.into())]),
                    ),
                ]),
            ),
            ("context", obj([])),
        ]),
    );
    compare("protocol", &s);
}

#[test]
fn broken_documents() {
    let ws = Workspace::new("broken");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), true);
    let sources = [
        "fn broken() Int:\n    let x: String = 1\n    return missing\n",
        "fn (:\nfn ok() Int:\n    return 1\n",
        "type T:\n    a: Int\nfn f() T:\n    return T(a: \n",
        "fn f(a: Int) Int:\n  return a\n",
        "\u{feff}fn f() Int:\n    return 1\n",
        "fn f() String:\n    return \"héllo 😀 {1 +\n",
        "import nothing from \"./nowhere.ms\"\nfn f() Int:\n    return nothing()\n",
        "",
    ];
    for (index, source) in sources.iter().enumerate() {
        let uri = ws.uri(&format!("b{index}.ms"));
        s.open(&uri, source, 1);
        for (line, character) in identifier_positions(source) {
            s.at("textDocument/hover", &uri, line, character);
            s.at("textDocument/definition", &uri, line, character);
            s.at("textDocument/completion", &uri, line, character);
        }
        s.request(
            "textDocument/documentSymbol",
            obj([("textDocument", obj([("uri", uri.as_str().into())]))]),
        );
        s.request(
            "textDocument/semanticTokens/full",
            obj([("textDocument", obj([("uri", uri.as_str().into())]))]),
        );
        s.request(
            "textDocument/foldingRange",
            obj([("textDocument", obj([("uri", uri.as_str().into())]))]),
        );
        s.request(
            "textDocument/formatting",
            obj([("textDocument", obj([("uri", uri.as_str().into())]))]),
        );
    }
    compare("broken", &s);
}

#[test]
fn batched_changes_publish_once() {
    let ws = Workspace::new("batched");
    let main = ws.uri("main.ms");
    let mut s = Script::initialize(&ws.root.to_string_lossy(), true);
    s.open(&main, "fn f() Int:\n    return 1\n", 1);
    for version in 2..7 {
        let range = obj([
            (
                "start",
                obj([("line", 1usize.into()), ("character", 11usize.into())]),
            ),
            (
                "end",
                obj([("line", 1usize.into()), ("character", 12usize.into())]),
            ),
        ]);
        s.notify(
            "textDocument/didChange",
            obj([
                (
                    "textDocument",
                    obj([
                        ("uri", main.as_str().into()),
                        ("version", (version as usize).into()),
                    ]),
                ),
                (
                    "contentChanges",
                    ms_lsp::json::Json::Arr(vec![obj([
                        ("range", range),
                        (
                            "text",
                            (if version % 2 == 0 { "\"s\"" } else { "2" }).into(),
                        ),
                    ])]),
                ),
            ]),
        );
    }
    s.at("textDocument/hover", &main, 1, 11);
    compare("batched", &s);
}
