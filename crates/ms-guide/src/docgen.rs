//! Reference documentation for the bundled standard library
//! (`pkg/tooling/docgen`): Markdown pages, the structured JSON download, and
//! the description inventory and policy.

use crate::api::{ApiDeclaration, ApiMember, ApiModule, standard_library};
use crate::json::{self, Json};
use std::collections::{BTreeMap, BTreeSet};

fn declaration_kind(kind: &str) -> &str {
    match kind {
        "fn" => "Function",
        "constant" => "Constant",
        "record" => "Record",
        "alternative" => "Alternative",
        "interface" => "Interface",
        "type" => "Type",
        "native" => "Native type",
        other => other,
    }
}

/// Renders one module as portable Markdown.
pub fn render_module(module: &ApiModule) -> String {
    render(module, false)
}

/// Renders one module for the book, with each heading tagged by its kind.
pub fn render_site_module(module: &ApiModule) -> String {
    render(module, true)
}

fn render(module: &ApiModule, for_site: bool) -> String {
    let path = module.path.as_str();
    let mut b = format!("# {path}\n\n");
    if path == "prelude" {
        b += "Names available in every module; no import required.\n\n";
    } else if matches!(
        path,
        "@std/optional.ms" | "@std/result.ms" | "@std/equality.ms"
    ) {
        b += "These names are available in the prelude; no import required.\n\n";
        b += "Explicit imports of these prelude declarations are rejected; remove them from the import.\n\n";
    } else if path == "@std/errors.ms" {
        b += "`Error` and `MissingValue` are prelude declarations; explicit imports of them are rejected.\n\n";
        b += &format!("Import other names with `import Name from {path:?}`.\n\n");
    } else if path == "@std/collections.ms" {
        b += "`List`, `Map`, `Set`, `CollectionError`, `ListEntry`, and `MapEntry` are prelude declarations; explicit imports of them are rejected.\n\n";
        b += &format!("Import other names with `import Name from {path:?}`.\n\n");
    } else if path.starts_with("@std/") {
        b += &format!("Import each required symbol with `import Name from {path:?}`.\n\n");
    }
    for d in &module.declarations {
        let mut kind = declaration_kind(&d.kind);
        // Native types with receiver signatures share the checker's interface
        // representation, but their source declaration remains a type.
        if d.kind == "interface" && d.declaration.starts_with("type ") {
            kind = "Native type";
        }
        if for_site {
            b += &format!("## {} {{data-api-kind={kind:?}}}\n\n", d.name);
        } else {
            b += &format!("## {}\n\n**{kind}**\n\n", d.name);
        }
        if d.declaration.is_empty() {
            b += "This member uses compiler-defined call behavior.\n\n";
            continue;
        }
        if !d.doc.is_empty() {
            b += &format!("{}\n\n", d.doc);
        }
        b += &format!("```manuscript\n{}```\n\n", d.declaration);
        for implementation in &d.implementation_declarations {
            b += &format!("```manuscript\n{implementation}```\n\n");
        }
        for member in &d.members {
            if member.doc.trim().is_empty() {
                continue;
            }
            let name = if member.contract.is_empty() {
                format!("{}.{}", d.name, member.name)
            } else {
                format!("{}.{}.{}", d.name, member.contract, member.name)
            };
            b += &format!(
                "### {name}\n\n{}\n\n```manuscript\n{}\n```\n\n",
                member.doc, member.signature
            );
        }
    }
    b
}

/// Every generated site file by repository-relative path.
pub fn site_files() -> BTreeMap<String, Vec<u8>> {
    let modules = standard_library();
    let mut files = BTreeMap::new();
    let mut index = String::from(
        "+++\ntitle = \"API reference\"\nweight = 2\n+++\n\n# Standard library API reference\n\nLook up types, functions, and import paths in the bundled standard library. These declarations are generated from source and omit implementation bodies.\n\n[Plain Markdown](/stdlib.md) · [Structured JSON](/stdlib.json) · [LLM index](/llms.txt)\n\n",
    );
    let full = standard_library_markdown();
    for module in modules {
        let name = module.path.strip_prefix("@std/").unwrap_or(&module.path);
        let name = name.strip_suffix(".ms").unwrap_or(name);
        let body = render(module, true);
        files.insert(
            format!("documentation/standard-library/reference/{name}.md"),
            format!("+++\ntitle = {name:?}\n+++\n\n{body}").into_bytes(),
        );
        index += &format!("- [{}]({name}.md)\n", module.path);
    }
    files.insert(
        "documentation/standard-library/reference/_index.md".to_string(),
        index.into_bytes(),
    );
    files.insert("website/static/stdlib.md".to_string(), full.into_bytes());
    files.insert(
        "website/static/stdlib.json".to_string(),
        to_json(modules).into_bytes(),
    );
    files
}

/// All modules as one Markdown document.
pub fn standard_library_markdown() -> String {
    let mut b = String::from(
        "# Manuscript implemented standard library\n\nGenerated by ms doc --stdlib from bundled standard-library declarations.\n\n",
    );
    for module in standard_library() {
        b += &render_module(module);
    }
    b
}

fn member_json(m: &ApiMember) -> Json {
    let mut fields = vec![
        ("name".to_string(), Json::str(&m.name)),
        ("kind".to_string(), Json::str(&m.kind)),
        ("signature".to_string(), Json::str(&m.signature)),
        ("doc".to_string(), Json::str(&m.doc)),
    ];
    if !m.contract.is_empty() {
        fields.push(("contract".to_string(), Json::str(&m.contract)));
    }
    Json::Obj(fields)
}

fn declaration_json(d: &ApiDeclaration) -> Json {
    let mut fields = vec![("name".to_string(), Json::str(&d.name))];
    if !d.doc.is_empty() {
        fields.push(("doc".to_string(), Json::str(&d.doc)));
    }
    fields.push(("kind".to_string(), Json::str(&d.kind)));
    fields.push(("type".to_string(), Json::str(&d.ty)));
    for (key, items) in [
        ("type_parameters", &d.parameters),
        ("fields", &d.fields),
        ("cases", &d.cases),
        ("operations", &d.operations),
    ] {
        if !items.is_empty() {
            fields.push((key.to_string(), Json::strings(items)));
        }
    }
    if !d.members.is_empty() {
        fields.push((
            "members".to_string(),
            Json::Arr(d.members.iter().map(member_json).collect()),
        ));
    }
    if !d.implements.is_empty() {
        fields.push(("implements".to_string(), Json::strings(&d.implements)));
    }
    Json::Obj(fields)
}

/// The structured API snapshot, as `website/static/stdlib.json` writes it.
pub fn to_json(modules: &[ApiModule]) -> String {
    let modules: Vec<Json> = modules
        .iter()
        .map(|m| {
            Json::Obj(vec![
                ("path".to_string(), Json::str(&m.path)),
                (
                    "declarations".to_string(),
                    Json::Arr(m.declarations.iter().map(declaration_json).collect()),
                ),
            ])
        })
        .collect();
    let value = Json::Obj(vec![
        ("format".to_string(), Json::int(1)),
        ("modules".to_string(), Json::Arr(modules)),
    ]);
    value.pretty_line(ms_json::Escape::GoHtml)
}

/// Includes every rendered declaration and member, including prelude aliases.
/// It records missing descriptions without inventing them or treating
/// signature presence as descriptive coverage.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DocumentationInventory {
    /// Always 1.
    pub format: i64,
    /// Whether any entry belongs to the prelude.
    pub includes_prelude_aliases: bool,
    /// Declaration count.
    pub declarations: usize,
    /// Declarations with a description.
    pub described_declarations: usize,
    /// Member count.
    pub members: usize,
    /// Members with a description.
    pub described_members: usize,
    /// Declarations whose description passes the structural checks.
    pub qualified_declarations: usize,
    /// Members whose description passes the structural checks.
    pub qualified_members: usize,
    /// One entry per declaration and member.
    pub entries: Vec<DocumentationEntry>,
}

/// One declaration or member in the inventory.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DocumentationEntry {
    /// Module path.
    pub module: String,
    /// Declaration name.
    pub declaration: String,
    /// `declaration`, or the member kind.
    pub kind: String,
    /// Declaration or member name.
    pub name: String,
    /// Implemented contract, for contract operations.
    pub contract: String,
    /// Has any description.
    pub described: bool,
    /// Passes the structural checks.
    pub qualified: bool,
    /// Why it fails the checks.
    pub problem: String,
}

impl DocumentationInventory {
    /// The inventory as JSON, as `-coverage` writes it.
    pub fn to_json(&self) -> String {
        let entries = self
            .entries
            .iter()
            .map(|e| {
                let mut fields = vec![
                    ("module".to_string(), Json::str(&e.module)),
                    ("declaration".to_string(), Json::str(&e.declaration)),
                    ("kind".to_string(), Json::str(&e.kind)),
                    ("name".to_string(), Json::str(&e.name)),
                ];
                if !e.contract.is_empty() {
                    fields.push(("contract".to_string(), Json::str(&e.contract)));
                }
                fields.push(("described".to_string(), Json::Bool(e.described)));
                fields.push(("qualified".to_string(), Json::Bool(e.qualified)));
                if !e.problem.is_empty() {
                    fields.push(("problem".to_string(), Json::str(&e.problem)));
                }
                Json::Obj(fields)
            })
            .collect();
        let count = |n: usize| Json::int(n as i64);
        let value = Json::Obj(vec![
            ("format".to_string(), Json::int(self.format)),
            (
                "includes_prelude_aliases".to_string(),
                Json::Bool(self.includes_prelude_aliases),
            ),
            ("declarations".to_string(), count(self.declarations)),
            (
                "described_declarations".to_string(),
                count(self.described_declarations),
            ),
            ("members".to_string(), count(self.members)),
            (
                "described_members".to_string(),
                count(self.described_members),
            ),
            (
                "qualified_declarations".to_string(),
                count(self.qualified_declarations),
            ),
            (
                "qualified_members".to_string(),
                count(self.qualified_members),
            ),
            ("entries".to_string(), Json::Arr(entries)),
        ]);
        value.pretty_line(ms_json::Escape::GoHtml)
    }
}

/// Counts and classifies every description in `modules`.
pub fn inventory(modules: &[ApiModule]) -> DocumentationInventory {
    let mut report = DocumentationInventory {
        format: 1,
        ..DocumentationInventory::default()
    };
    let mut visit = |mut entry: DocumentationEntry, doc: &str| {
        entry.described = !doc.trim().is_empty();
        entry.problem = description_problem(&entry, doc);
        entry.qualified = entry.problem.is_empty();
        if entry.module == "prelude" {
            report.includes_prelude_aliases = true;
        }
        if entry.kind == "declaration" {
            report.declarations += 1;
            report.described_declarations += usize::from(entry.described);
            report.qualified_declarations += usize::from(entry.qualified);
        } else {
            report.members += 1;
            report.described_members += usize::from(entry.described);
            report.qualified_members += usize::from(entry.qualified);
        }
        report.entries.push(entry);
    };
    for module in modules {
        for d in &module.declarations {
            visit(
                DocumentationEntry {
                    module: module.path.clone(),
                    declaration: d.name.clone(),
                    kind: "declaration".into(),
                    name: d.name.clone(),
                    ..DocumentationEntry::default()
                },
                &d.doc,
            );
            for m in &d.members {
                visit(
                    DocumentationEntry {
                        module: module.path.clone(),
                        declaration: d.name.clone(),
                        kind: m.kind.clone(),
                        name: m.name.clone(),
                        contract: m.contract.clone(),
                        ..DocumentationEntry::default()
                    },
                    &m.doc,
                );
            }
        }
    }
    report
}

/// The recorded exact existing gaps. It is not an exemption: new gaps fail,
/// invalid prose cannot use it, and described entries must be removed. The
/// completed sweep leaves this list empty.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DescriptionPolicy {
    /// Always 1.
    pub format: i64,
    /// Keys of entries allowed to stay undescribed.
    pub backlog: Vec<String>,
}

/// Reads the policy that ships with the compiler.
pub fn standard_description_policy() -> Result<DescriptionPolicy, String> {
    parse_policy(include_str!(
        "../../../pkg/tooling/docgen/description_backlog.json"
    ))
}

fn parse_policy(text: &str) -> Result<DescriptionPolicy, String> {
    let Json::Obj(fields) = json::parse(text)? else {
        return Err("description policy must be an object".to_string());
    };
    let mut policy = DescriptionPolicy::default();
    for (key, value) in fields {
        match (key.as_str(), value) {
            ("format", n @ Json::Num(_)) => {
                policy.format = n.as_i64().ok_or("format must be an integer")?
            }
            ("backlog", Json::Arr(items)) => {
                for item in items {
                    let Json::Str(s) = item else {
                        return Err("backlog entries must be strings".to_string());
                    };
                    policy.backlog.push(s);
                }
            }
            ("backlog", Json::Null) => {}
            (other, _) => return Err(format!("unknown field {other:?} in description policy")),
        }
    }
    if policy.format != 1 {
        return Err(format!(
            "unsupported description policy format {}",
            policy.format
        ));
    }
    Ok(policy)
}

/// Identifies a checked declaration or member, including its actual module and
/// implementation contract. Prelude aliases keep separate entries.
pub fn description_key(entry: &DocumentationEntry) -> String {
    [
        entry.module.as_str(),
        entry.declaration.as_str(),
        entry.kind.as_str(),
        entry.name.as_str(),
        entry.contract.as_str(),
    ]
    .join("|")
}

/// Enforces source-derived coverage and a shrinking backlog. Quality checks
/// reject obvious boilerplate; semantic accuracy still requires reviewing the
/// source and native contracts.
pub fn check_descriptions(
    report: &DocumentationInventory,
    policy: &DescriptionPolicy,
) -> Vec<String> {
    let mut backlog = BTreeSet::new();
    let mut problems = Vec::new();
    for key in &policy.backlog {
        if !backlog.insert(key.as_str()) {
            problems.push(format!("{key}: duplicate description backlog entry"));
        }
    }
    let mut seen = BTreeSet::new();
    for entry in &report.entries {
        let key = description_key(entry);
        if backlog.contains(key.as_str()) && entry.described {
            problems.push(format!(
                "{key}: description exists; remove the stale backlog entry"
            ));
        }
        if entry.qualified || (!entry.described && backlog.contains(key.as_str())) {
            seen.insert(key);
            continue;
        }
        problems.push(format!(
            "{key}: {}; describe observable behavior, units, defaults, errors or ownership",
            entry.problem
        ));
        seen.insert(key);
    }
    for key in &backlog {
        if !seen.contains(*key) {
            problems.push(format!(
                "{key}: API no longer exists; remove the stale backlog entry"
            ));
        }
    }
    problems.sort();
    problems
}

const PLACEHOLDERS: [&str; 7] = [
    "todo",
    "tbd",
    "fixme",
    "placeholder",
    "undocumented",
    "description goes here",
    "documentation goes here",
];

const IGNORED: &str = "a an the this that these those it its s of for to from with without and or in on at by as is are be can may will field member method function operation case type declaration public exported native standard api value data object property describes describing represents returns holds provides gets sets has about information description documentation named called contains containing stores stored storing reports whether behavior behaviour contract fn record interface int int64 float float64 bool unit never string bytes optional result list map set payload";

fn description_problem(entry: &DocumentationEntry, doc: &str) -> String {
    let raw = doc.trim();
    let text = raw.to_lowercase();
    if text.is_empty() {
        return "missing description".to_string();
    }
    let trimmed = text.trim_start_matches(['#', ' ', '`', '*']);
    for placeholder in PLACEHOLDERS {
        if trimmed.starts_with(placeholder) {
            return "placeholder description".to_string();
        }
    }
    let words = description_words(raw);
    if words.len() < 4 {
        return "description is too terse to state a contract".to_string();
    }
    let mut ignored: BTreeSet<String> =
        description_words(&format!("{} {}", entry.name, entry.declaration))
            .into_iter()
            .collect();
    ignored.extend(IGNORED.split_whitespace().map(str::to_string));
    if words.iter().any(|w| !ignored.contains(w)) {
        return String::new();
    }
    "description only restates the API name or kind".to_string()
}

fn description_words(text: &str) -> Vec<String> {
    // Split camel-case names as well as ordinary prose and snake_case names.
    let mut separated = String::new();
    let mut previous = '\0';
    for c in text.chars() {
        if c.is_uppercase() && previous.is_lowercase() {
            separated.push(' ');
        }
        separated.extend(c.to_lowercase());
        previous = c;
    }
    separated
        .split(|c: char| !c.is_alphabetic() && !c.is_numeric())
        .filter(|w| !w.is_empty())
        .map(str::to_string)
        .collect()
}
