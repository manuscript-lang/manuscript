# conform: tags=diagnostics,parser,tier-core
# conform: phase=parse
# conform: origin=foreign-syntax diagnostics
fn f() Int:
    let g = lambda x: x
    return 0
