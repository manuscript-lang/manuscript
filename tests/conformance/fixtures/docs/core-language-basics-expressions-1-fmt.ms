# conform: tags=formatter,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/basics/expressions.md:73
fn load(path: String) Config!:
    let config = try read(path)
        | try parse
        | normalize
        | try validate
    return ok(config)
