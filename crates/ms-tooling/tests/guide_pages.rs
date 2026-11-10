//! Tests for the guide and search modules.

use ms_check::{CheckOptions, ImportMap};
use ms_tooling::guide::{
    cheatsheet, format_matches, index, mistake_entries, mistakes, module_names, page, search,
    standard_library,
};
use std::sync::Arc;

/// Diagnostics (or the parse error) for one source file.
fn issues(file: &str, source: &str) -> Vec<String> {
    let syms = ms_syntax::Names::global();
    let (file, source) = (file.to_string(), source.to_string());
    std::thread::Builder::new()
        .stack_size(64 << 20)
        .spawn(move || {
            let name: Arc<str> = Arc::from(file.as_str());
            let module = match ms_syntax::parser::parse(&name, &source) {
                Ok(module) => module,
                Err(error) => return vec![error.message.clone()],
            };
            let program = ms_check::check(
                syms,
                vec![ms_check::load_module(syms, &module)],
                ImportMap::default(),
                CheckOptions::default(),
            );
            // The guide's fragments bind names only to show a rule; unread bindings are not their claim.
            program
                .diagnostics
                .iter()
                .map(|d| d.message.clone())
                .filter(|m| !m.contains("is never read"))
                .collect()
        })
        .unwrap()
        .join()
        .unwrap()
}

// The cheat sheet's complete program is the one claim a reader can copy verbatim.
#[test]
fn cheatsheet_program_checks() {
    let (_, after) = cheatsheet()
        .split_once("<!-- complete -->\n```manuscript\n")
        .expect("cheat sheet lost its complete program");
    let source = after.split("```").next().unwrap();
    let found = issues("cheatsheet.ms", source);
    assert!(found.is_empty(), "cheat sheet program: {found:?}");
}

// Agents read the guide every session, so its size is part of the contract.
#[test]
fn cheatsheet_stays_short() {
    assert!(
        cheatsheet().len() <= 5800,
        "cheat sheet is {} bytes",
        cheatsheet().len()
    );
}

// Each cheat-sheet claim a reader might get wrong is checked against the compiler.
#[test]
fn cheatsheet_claims_match_the_compiler() {
    let check = |body: &str| {
        issues(
            "claim.ms",
            &format!("export fn main() Int:\n{body}    return 0\n"),
        )
    };
    for body in [
        "    a := [1, 2]\n",
        "    m := Map[String, Int]()\n    s := Set[Int]()\n",
        "    var n = 1\n    n = 2\n",
        "    var n = 1\n    n += 2\n    n %= 2\n",
        "    o: Int? = none\n    v := o.get(3)\n",
        "    name := \"x\"\n    text := \"hi {name}\"\n",
        "    var m = Map[String, Int]()\n    for e in m.entries():\n        k := e.key\n    if var n = m[\"k\"]?:\n        n += 1\n",
    ] {
        let found = check(body);
        assert!(
            found.is_empty(),
            "claim should check clean:\n{body}{found:?}"
        );
    }
    for body in [
        "    n := 1\n    n = 2\n",
        "    a := [1, \"x\"]\n",
        "    x := none\n",
        "    a := 1\n  b := 2\n",
    ] {
        assert!(!check(body).is_empty(), "claim should be rejected:\n{body}");
    }
    let inherent = "type T:\n    a: Int\n\nimpl T:\n    fn f(self) Int:\n        return 1\n\nexport fn main() Int:\n    return 0\n";
    assert!(
        !issues("claim.ms", inherent).is_empty(),
        "`impl T:` should be rejected"
    );
}

fn bare(name: &str) -> &str {
    name.split('[').next().unwrap()
}

// Agents read these pages whole, so every page of the real library must fit its budget.
#[test]
fn std_pages_stay_bounded() {
    let syms = ms_syntax::Names::global();
    assert!(
        index(syms).len() <= 4000,
        "index is {} bytes",
        index(syms).len()
    );
    for module in standard_library(syms) {
        let name = module
            .path
            .trim_start_matches("@std/")
            .trim_end_matches(".ms");
        let text = page(syms, name).unwrap();
        assert!(
            text.len() <= 3500 && text.matches('\n').count() <= 45 + 4,
            "Page({name:?}): {} bytes",
            text.len()
        );
        for d in &module.declarations {
            let path = format!("{name}.{}", bare(&d.name));
            let text = page(syms, &path).unwrap();
            assert!(
                text.len() <= 3500 + 200,
                "Page({path:?}): {} bytes",
                text.len()
            );
            for member in &d.members {
                let path = format!("{path}.{}", bare(&member.name));
                let text = page(syms, &path).unwrap();
                assert!(
                    text.len() <= 3 * (300 + 800 + 200) + 3500 / 2,
                    "Page({path:?}): {} bytes",
                    text.len()
                );
            }
        }
    }
}

#[test]
fn std_pages_resolve_forms() {
    let syms = ms_syntax::Names::global();
    for path in [
        "json",
        "@std/data/json.ms",
        "json.parse",
        "@std/data/json.ms.parse",
        "prelude.List",
        "prelude.List.sorted",
        "prelude.List.group_by",
    ] {
        let text = page(syms, path).unwrap_or_else(|e| panic!("Page({path:?}): {e}"));
        assert!(!text.is_empty(), "Page({path:?}) is empty");
    }
    assert!(
        page(syms, "json")
            .unwrap()
            .contains("import Name from \"@std/data/json.ms\"")
    );
    for path in ["nope", "json.nope", "prelude.List.nope"] {
        let error = page(syms, path).unwrap_err();
        assert!(error.len() <= 700, "Page({path:?}) error = {error}");
    }
    let index = index(syms);
    assert!(index.contains("json "));
    assert!(
        index.split_once("\n\n").unwrap().1.starts_with("prelude"),
        "index = {:.200}",
        index
    );
    let names = module_names(syms);
    assert!(
        names.len() >= 20 && names.iter().any(|n| n == "json") && names[0] == "prelude",
        "{names:?}"
    );
}

#[test]
fn search_output_stays_bounded() {
    let syms = ms_syntax::Names::global();
    for query in ["list", "read", "file", "string", "parse", "a", "map set"] {
        let text = format_matches(query, &search(syms, query, 15));
        assert!(
            text.len() <= 3000 + 100,
            "search {query:?} output is {} bytes",
            text.len()
        );
    }
}

#[test]
fn search_finds_apis_from_loose_queries() {
    let syms = ms_syntax::Names::global();
    let cases = [
        ("jsn parse", "@std/data/json.ms", "parse"),
        ("read file", "@std/os/fs.ms", "read_file"),
        ("JSON PARSE", "@std/data/json.ms", "parse"),
        ("http server", "@std/net/http.ms", "HttpServer"),
        ("parse_int", "@std/math/math.ms", "parse_int"),
        ("sleep", "@std/time.ms", "sleep"),
        ("regex replace", "@std/string.ms", "Regex.replace_all"),
        ("base64 encode", "@std/data/encoding.ms", "base64_encode"),
        ("sorted", "prelude", "List.sorted"),
        ("sort by", "prelude", "List.sorted"),
        ("read stdin lines", "@std/io/streams.ms", "lines"),
        ("uppercase", "prelude", "String.upper"),
    ];
    for (query, module, name) in cases {
        let matches = search(syms, query, 3);
        assert!(
            matches.iter().any(|m| m.module == module && m.name == name),
            "search({query:?}) top 3 = {:?}, want {module} {name}",
            matches
                .iter()
                .map(|m| format!("{} {}", m.module, m.name))
                .collect::<Vec<_>>()
        );
    }
}

#[test]
fn search_exact_name_outranks_fuzzy_names() {
    let syms = ms_syntax::Names::global();
    let matches = search(syms, "sleep", 5);
    assert!(!matches.is_empty() && matches[0].name == "sleep");
}

#[test]
fn search_is_stable_and_bounded() {
    let syms = ms_syntax::Names::global();
    let (a, b) = (search(syms, "list", 5), search(syms, "list", 5));
    assert!(a.len() == 5 && a == b);
    let mut seen = std::collections::HashSet::new();
    for m in search(syms, "sorted", 25) {
        assert!(
            seen.insert(format!("{}{}", m.name, m.signature)),
            "duplicate declaration {} from {}",
            m.name,
            m.module
        );
    }
}

#[test]
fn search_rejects_noise_and_empty_queries() {
    let syms = ms_syntax::Names::global();
    assert!(search(syms, "   ", 5).is_empty());
    let partial = search(syms, "split zzqxjv", 3);
    assert!(
        !partial.is_empty() && partial[0].name == "String.split",
        "{partial:?}"
    );
    assert!(search(syms, "zzqxjv", 5).is_empty());
    assert!(format_matches("zzqxjv", &[]).contains("No standard-library match"));
}

/// Scope-end close replaced the `with` statement; the cheat sheet must not teach it.
#[test]
fn cheatsheet_does_not_teach_with() {
    let text = cheatsheet();
    let taught = text.lines().find(|l| l.contains("`with "));
    assert!(taught.is_none(), "removed with statement: {taught:?}");
}

// Every listed mistake is real: `wrong` fails (or is silently accepted) as stated, `right` checks clean.
#[test]
fn common_mistakes_match_the_compiler() {
    let entries = mistake_entries();
    assert!(
        entries.len() >= 10,
        "mistakes list shrank to {}",
        entries.len()
    );
    for m in entries {
        let program = |text: &str| {
            let filled = m.body.replace("{}", text).replace(";;", "\n    ");
            let setup = m.setup.replace(";;", "\n");
            format!("{setup}\nexport fn main() Int:\n    {filled}\n    return 0\n")
        };
        let wrong = issues("mistake.ms", &program(&m.wrong));
        match &m.diagnostic {
            Some(fragment) => assert!(
                wrong.iter().any(|d| d.contains(fragment.as_str())),
                "`{}` should report {fragment:?}, got {wrong:?}",
                m.wrong
            ),
            None => assert!(
                wrong.is_empty(),
                "`{}` should check clean: {wrong:?}",
                m.wrong
            ),
        }
        let right = issues("fixed.ms", &program(&m.right));
        assert!(
            right.is_empty(),
            "`{}` should check clean: {right:?}",
            m.right
        );
    }
}

#[test]
fn common_mistakes_stay_short() {
    assert!(
        mistakes().len() <= 1600,
        "mistakes section is {} bytes",
        mistakes().len()
    );
}

#[test]
fn enum_reference_declarations_keep_methods_in_impl_blocks() {
    let syms = ms_syntax::Names::global();
    let mut seen = 0;
    for module in standard_library(syms) {
        for declaration in &module.declarations {
            if declaration.kind != "alternative" {
                continue;
            }
            seen += 1;
            assert!(
                declaration.declaration.starts_with(if declaration.opaque {
                    "opaque enum "
                } else {
                    "enum "
                }),
                "{}",
                declaration.declaration
            );
            // Reference method signatures omit bodies. The enum schema must
            // parse on its own, and methods must follow in a separate impl.
            let schema = declaration.declaration.split("\nimpl ").next().unwrap();
            if declaration.opaque {
                // Public opaque excerpts deliberately omit the inaccessible cases.
                assert_eq!(schema.lines().count(), 1, "{schema}");
            } else {
                let parsed = ms_syntax::parser::parse(&Arc::from("reference.ms"), schema);
                assert!(parsed.is_ok(), "{schema}: {parsed:?}");
            }
            assert!(!schema.contains("    fn ") && !schema.contains("    var fn "));
            for member in declaration
                .members
                .iter()
                .filter(|member| member.kind == "case")
            {
                assert!(
                    !member.signature.starts_with("case "),
                    "{}",
                    member.signature
                );
            }
            if !declaration.members.is_empty() && declaration.declaration.contains("    fn ") {
                assert!(
                    declaration.declaration.contains("\nimpl "),
                    "{}",
                    declaration.declaration
                );
            }
        }
    }
    assert!(seen > 5);
}
