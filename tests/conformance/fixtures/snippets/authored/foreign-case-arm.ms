// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
// conform: origin=foreign-syntax diagnostics
enum E:
    A

fn f(e: E) Int:
    match e:
        case A: return 1
