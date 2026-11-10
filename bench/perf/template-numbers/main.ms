import compile from "@std/text/template.ms"
import parse from "@std/data/json.ms"
import arguments from "@std/os/env.ms"

// Arguments: left JSON number, right JSON number, comparison, repetitions.
// Choose a comparison that is true; an incorrect result exits nonzero.
fn main() Int:
    let args = arguments()
    if args.length() != 4: return 2

    let repeats = args[3].parse_int().get(-1)
    if repeats < 0: return 2

    let compiled = compile("\{\{ if a {args[2]} b \}\}yes\{\{ else \}\}no\{\{ end \}\}")
    if compiled.is_error(): return 2

    let parsed = parse("\{\"a\":{args[0]},\"b\":{args[1]}\}")
    if parsed.is_error(): return 2

    let template = compiled.get()
    let data = parsed.get()

    for i in 0..repeats:
        let result = template.render(data)
        if result.is_error(): return 1
        if result.get() != "yes": return 1

    return 0
