// conform: tags=formatter,parser,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=documentation/core-language/basics/expressions.md:73
fn load(path: String) Config!:
    config := read(path)?
        | parse?
        | normalize
        | validate?
    return ok(config)
