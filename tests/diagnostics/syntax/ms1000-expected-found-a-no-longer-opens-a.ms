// conform: tags=diagnostics
// conform: phase=check
fn f() Void => if true: return
// expect-error: MS1000 3:23-3:24 expected '{', found ':'; a ':' no longer opens a block: write the body in braces on the same line as its header, as in if c { ... } or fn f() Int { ... }
