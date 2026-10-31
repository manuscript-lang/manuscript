import stdout from "@std/io.ms"
import Val, str_cps from "./vals.ms"
import FnDef from "./ast.ms"
import parse_main, parse_defs from "./parse.ms"

fn pl(s: String) Unit:
    stdout().write("{s}\n").get()

export fn main() Int:
    let d = parse_defs(str_cps("def f(a; $b): a + b;"), List[FnDef](), 0)
    pl("defs ok={d.ok} n={d.fns.length()}")
    let r = parse_main(str_cps(".a[0] | map(select(. > 1)) as $x | \{a: 1, $x, \"b\": .c, (.d): 2\} | reduce .[] as [$a, \{b: $c\}] (0; . + 1)"), d.fns, d.nid)
    pl("main ok={r.ok}")
    let bad = parse_main(str_cps("1 +"), List[FnDef](), 0)
    pl("bad ok={bad.ok}")
    return 0
