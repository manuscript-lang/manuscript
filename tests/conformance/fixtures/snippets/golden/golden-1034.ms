// conform: tags=diagnostics
// conform: phase=check
fn example(value String) Bool
// expect-error: MS1000 3:30-3:30 expected '{', found end of line; block headers (fn, if, else, for, while, match, type, enum, interface, test) end with '{' on the same line, and the block closes with '}'
