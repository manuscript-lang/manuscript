# Data loading shared by the runner: challenges, languages, pricing. Paths are relative to the repository
# root, where every command in README.md runs.
import JsonValue, parse from "@std/json.ms"
import panic from "@std/core.ms"
import access, list, read_file from "@std/fs.ms"
import env from "../lib/text.ms"

# `bench/agent` when the command runs from the repository root, `.` when it runs inside this directory (as `ms test` does).
export fn root() String:
    if access("bench/agent/languages.json", 0).is_ok(): return "bench/agent"

    return "."


# Documentation for the Manuscript context bundle comes from here; override to pin a different checkout.
export fn repo() String: env("MSBENCH_REPO", if root() == ".": "../.." else: ".")

# One input and the exact output expected for it.
export type Case:
    name: String = "?"
    stdin: String
    stdout: String

type Meta:
    title: String
    category: String
    tier: Int
    timeout_s: Int = 5

export type Challenge:
    id: String
    title: String
    category: String
    tier: Int
    timeout_s: Int
    dir: String

impl Challenge:
    fn spec() String: read_file("{self.dir}/spec.md").get().decode_utf8().get("")

    # `which` is `examples` (visible to the agent) or `hidden`.
    fn cases(which: String) List[Case]:
        let text = read_file("{self.dir}/{which}/cases.json").get().decode_utf8().get("")
        return parse[List[Case]](text).get([])

    fn solution(lang: String) String: "{self.dir}/solutions/{lang}"

# A language the benchmark can be solved in, as `languages.json` describes it.
export type Lang:
    id: String
    name: String
    solution: String
    build: String
    run: String
    notes: String
    template: String
    context: List[String]

# The extension of the solution file, such as `.ms`.
impl Lang:
    fn suffix() String:
        let base = self.solution.split("/").last().get("")
        if let at = base.last_index_of("."): return base.slice(at, base.length()).get("")

        return ""

    # The file name of the reference solution, such as `main.ms.ref`.
    fn reference() String: "{self.solution.split("/").last().get("")}.ref"

fn text_of(file: String) String:
    return read_file(file).get().decode_utf8().get("")

fn field(doc: JsonValue, key: String) String:
    if let value = doc.get(key):
        return value.as_string().get("")
    return ""

# Challenges whose id equals, or starts with, one of `ids` (all when `ids` is empty), in id order.
export fn load_challenges(ids: List[String]) List[Challenge]:
    var out = List[Challenge]()
    var names = List[String]()
    for entry in list("{root()}/challenges").get([]):
        names.append(entry.name.clone())
    for name in names.sorted():
        let dir = "{root()}/challenges/{name}"
        let meta_text = read_file("{dir}/challenge.json")
        if not meta_text.is_ok(): continue
        let m = parse[Meta](meta_text.get().decode_utf8().get("")).get(Meta("", "", 0, 5))
        let wanted = ids.is_empty() or ids.any(fn i: name == i or name.starts_with("{i}-"))
        if wanted: out.append(Challenge(name.clone(), m.title.clone(), m.category.clone(), m.tier, m.timeout_s, dir))
    return out

# Languages named in `ids` (all when empty), in file order; an unknown id stops the program.
export fn load_languages(ids: List[String]) List[Lang]:
    let doc = parse(text_of("{root()}/languages.json")).get(JsonValue.Null)
    var out = List[Lang]()
    var known = List[String]()
    for entry in doc.as_map().get(Map[String, JsonValue]()).entries():
        known.append(entry.key.clone())
        if not ids.is_empty() and not ids.contains(entry.key): continue

        let d = entry.value
        var context = List[String]()
        if let items = d.get("context"):
            for item in items.as_list().get([]):
                context.append(item.as_string().get(""))
        var template = entry.key.clone()
        if let t = d.get("template"): template = t.as_string().get(entry.key)
        out.append(Lang(entry.key.clone(), field(d, "name"), field(d, "solution"), field(d, "build"), field(d, "run"), field(d, "notes"), template, context))
    let unknown = ids.filter(fn i: not known.contains(i))
    if not unknown.is_empty(): panic("unknown languages: {unknown.join(", ")}")

    return out

# Estimated USD from `pricing.json`; `tokens_in` excludes cached tokens.
export fn cost_from_tokens(tokens_in: Int, cached: Int, tokens_out: Int, model: String) Float:
    let table = parse(text_of("{root()}/pricing.json")).get(JsonValue.Null)
    var p = table.get("default").get(JsonValue.Null)
    if let own = table.get(model): p = own
    let input = p.get("input").get(JsonValue.Null).as_float().get(0.0)
    let cached_input = p.get("cached_input").get(JsonValue.Null).as_float().get(0.0)
    let output = p.get("output").get(JsonValue.Null).as_float().get(0.0)
    return (tokens_in.to_float() * input + cached.to_float() * cached_input + tokens_out.to_float() * output) / 1000000.0
