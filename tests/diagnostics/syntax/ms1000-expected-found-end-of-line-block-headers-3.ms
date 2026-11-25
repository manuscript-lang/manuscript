// conform: tags=diagnostics
// conform: phase=check
fn f() Int
    return 1
// expect-error: MS1000 3:11-3:11 expected '{', found end of line; block headers (fn, if, else, for, while, match, type, enum, interface, test) end with '{' on the same line, and the block closes with '}'
