import files from "@oracle"
import hex_encode, hex_decode from "@std/data/encoding.ms"
import PathOperations, PathParts, posix, win32 from "@std/os/path.ms"
import fail from "@std/test/test.ms"

// Replays data/path.tsv, the corpus recorded from the original path implementation (the Go oracle,
// then the Rust natives): one case per line as `operation<TAB>windows<TAB>inputs...<TAB>=><TAB>expected`.
// A text is `x` followed by the hex of its UTF-8 bytes; a list is `[x61,x62]`; path parts are five
// texts separated by spaces.

fn text(token: String) String:
    let digits = token.drop(1)
    let bytes = hex_decode(digits, none) | .get("".to_bytes())
    return bytes.decode_utf8().get("")

fn hex(value: String) String:
    return "x{hex_encode(value.to_bytes())}"

fn list_of(token: String) List[String]:
    let inner = token.slice(1, token.length() - 1).get("")
    if inner.is_empty(): return []

    return inner.split(",", none).map(fn item: text(item))

fn parts_of(token: String) PathParts:
    let f = token.split(" ", none).map(fn item: text(item))
    return PathParts(
        root: f[0].clone(), directory: f[1].clone(), base: f[2].clone(),
        extension: f[3].clone(), name: f[4].clone()
    )

fn parts_text(parts: PathParts) String:
    return [parts.root, parts.directory, parts.base, parts.extension, parts.name].map(
        fn item: hex(item)
    ).join(" ")

fn result(outcome: String!) String:
    if let value = outcome: return "ok {hex(value)}"

    return "err InvalidInput"

fn answer(rules: PathOperations, f: List[String]) String:
    let op = f[0]
    if op == "basename": return hex(rules.basename(text(f[2])))
    if op == "basename_without": return hex(
        rules.basename_without(text(f[2]), text(f[3]))
    )
    if op == "dirname": return hex(rules.dirname(text(f[2])))
    if op == "extension": return hex(rules.extension(text(f[2])))
    if op == "is_absolute": return if rules.is_absolute(text(f[2])): "1" else: "0"
    if op == "normalize": return hex(rules.normalize(text(f[2])))
    if op == "namespaced": return hex(rules.to_namespaced_path(text(f[2])))
    if op == "parse": return parts_text(rules.parse(text(f[2])))
    if op == "format": return hex(rules.format(parts_of(f[2])))
    if op == "join": return hex(rules.join(list_of(f[2])))

    if op == "resolve":
        let parts = if f[3] == "[]": List[String]() else: list_of(f[3])
        return result(rules.resolve(text(f[2]), parts))

    if op == "relative": return result(rules.relative(text(f[2]), text(f[3])))

    if op == "glob":
        if let matched = rules.matches_glob(text(f[2]), text(f[3])):
            return "ok {if matched: 1 else: 0}"

        return "err InvalidInput"

    return "unknown case {op}"

test "path operations match the recorded corpus":
    let data = files().read("path.tsv", none) | .get(
        "".to_bytes()
    ) | .decode_utf8() | .get("")
    var checked = 0
    var failures = List[String]()

    for line in data.split("\n", none):
        if line.is_empty() or line.starts_with("#"): continue

        let f = line.split("\t", none)
        let want = f[f.length() - 1]
        let rules = if f[1] == "1": win32() else: posix()
        let got = answer(rules, f)
        checked += 1
        if got != want and failures.length() < 10: failures.append("{line} -> {got}")

    if failures.length() > 0: return fail(
        "{failures.length()} mismatches, first:\n{failures.join("\n")}"
    )
    if checked < 9000: return fail("only {checked} cases")

    return ok(unit)
