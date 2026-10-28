//! Tests for the guide and search modules.

use ms_check::{CheckOptions, ImportMap};
use ms_tooling::guide::{
    cheatsheet, format_matches, index, mistake_entries, mistakes, module_names, page, search,
    standard_library,
};
use std::sync::Arc;

/// Diagnostics (or the parse error) for one source file.
fn issues(file: &str, source: &str) -> Vec<String> {
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
                vec![ms_check::load_module(&module)],
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
        cheatsheet().len() <= 4700,
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
            &format!("export def main() -> Int:\n{body}    return 0\n"),
        )
    };
    for body in [
        "    let a = [1, 2]\n",
        "    let m = Map[String, Int]()\n    let s = Set[Int]()\n",
        "    var n = 1\n    n = 2\n",
        "    var n = 1\n    n += 2\n    n %= 2\n",
        "    let o: Optional[Int] = none\n    let v = o.get(3)\n",
        "    let name = \"x\"\n    let text = f\"hi {name}\"\n",
        "    var m = Map[String, Int]()\n    for e in m.entries():\n        let k = e.key\n    if var n = m.get(\"k\"):\n        n += 1\n",
    ] {
        let found = check(body);
        assert!(
            found.is_empty(),
            "claim should check clean:\n{body}{found:?}"
        );
    }
    for body in [
        "    let n = 1\n    n = 2\n",
        "    let a = [1, \"x\"]\n",
        "    let x = none\n",
        "    let a = 1\n  let b = 2\n",
    ] {
        assert!(!check(body).is_empty(), "claim should be rejected:\n{body}");
    }
    let inherent = "type T:\n    a: Int\n\nimpl T:\n    def f(self) -> Int:\n        return 1\n\nexport def main() -> Int:\n    return 0\n";
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
    assert!(index().len() <= 3500, "index is {} bytes", index().len());
    for module in standard_library() {
        let name = module
            .path
            .trim_start_matches("@std/")
            .trim_end_matches(".ms");
        let text = page(name).unwrap();
        assert!(
            text.len() <= 3500 && text.matches('\n').count() <= 45 + 4,
            "Page({name:?}): {} bytes",
            text.len()
        );
        for d in &module.declarations {
            let path = format!("{name}.{}", bare(&d.name));
            let text = page(&path).unwrap();
            assert!(
                text.len() <= 3500 + 200,
                "Page({path:?}): {} bytes",
                text.len()
            );
            for member in &d.members {
                let path = format!("{path}.{}", bare(&member.name));
                let text = page(&path).unwrap();
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
    for path in [
        "json",
        "@std/json.ms",
        "json.parse",
        "@std/json.ms.parse",
        "prelude.List",
        "prelude.List.sorted",
        "prelude.List.group_by",
    ] {
        let text = page(path).unwrap_or_else(|e| panic!("Page({path:?}): {e}"));
        assert!(!text.is_empty(), "Page({path:?}) is empty");
    }
    assert!(
        page("json")
            .unwrap()
            .contains("from \"@std/json.ms\" import Name")
    );
    for path in ["nope", "json.nope", "prelude.List.nope"] {
        let error = page(path).unwrap_err();
        assert!(error.len() <= 700, "Page({path:?}) error = {error}");
    }
    let index = index();
    assert!(index.contains("json "));
    assert!(
        index.split_once("\n\n").unwrap().1.starts_with("prelude"),
        "index = {:.200}",
        index
    );
    let names = module_names();
    assert!(
        names.len() >= 20 && names.iter().any(|n| n == "json") && names[0] == "prelude",
        "{names:?}"
    );
}

#[test]
fn search_output_stays_bounded() {
    for query in ["list", "read", "file", "string", "parse", "a", "map set"] {
        let text = format_matches(query, &search(query, 15));
        assert!(
            text.len() <= 3000 + 100,
            "search {query:?} output is {} bytes",
            text.len()
        );
    }
}

#[test]
fn search_finds_apis_from_loose_queries() {
    let cases = [
        ("jsn parse", "@std/json.ms", "parse"),
        ("read file", "@std/fs.ms", "FileSystem.read_file"),
        ("JSON PARSE", "@std/json.ms", "parse"),
        ("http server", "@std/http.ms", "HttpServer"),
        ("parse_int", "@std/math.ms", "parse_int"),
        ("sleep", "@std/time.ms", "sleep"),
        ("regex replace", "@std/string.ms", "Regex.replace_all"),
        ("base64 encode", "@std/encoding.ms", "base64_encode"),
        ("sorted", "prelude", "List.sorted"),
        ("sort by", "prelude", "List.sorted"),
        ("read stdin lines", "@std/io.ms", "read_line"),
        ("uppercase", "prelude", "String.upper"),
    ];
    for (query, module, name) in cases {
        let matches = search(query, 3);
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
    let matches = search("sleep", 5);
    assert!(!matches.is_empty() && matches[0].name == "sleep");
}

#[test]
fn search_is_stable_and_bounded() {
    let (a, b) = (search("list", 5), search("list", 5));
    assert!(a.len() == 5 && a == b);
    let mut seen = std::collections::HashSet::new();
    for m in search("sorted", 25) {
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
    assert!(search("   ", 5).is_empty());
    let partial = search("split zzqxjv", 3);
    assert!(
        !partial.is_empty() && partial[0].name == "String.split",
        "{partial:?}"
    );
    assert!(search("zzqxjv", 5).is_empty());
    assert!(format_matches("zzqxjv", &[]).contains("No standard-library match"));
}

/// `with` binds its resource with `let` or `var`; the removed `with expr as name:` spelling must not return.
#[test]
fn cheatsheet_uses_the_current_with_syntax() {
    let text = cheatsheet();
    for line in text.lines().filter(|l| l.contains("`with ")) {
        assert!(!line.contains(" as "), "old with-as spelling: {line}");
    }
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
            format!("{setup}\nexport def main() -> Int:\n    {filled}\n    return 0\n")
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
