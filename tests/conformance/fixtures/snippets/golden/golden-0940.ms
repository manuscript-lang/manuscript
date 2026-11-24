// conform: tags=diagnostics
// conform: phase=check
fn f() Void:
    g := fn(x Int) Int: return x
    use(fn(x Int) Int: return x, other: 1)
    gs := [fn() Void: return, fn() Int: return 2]
