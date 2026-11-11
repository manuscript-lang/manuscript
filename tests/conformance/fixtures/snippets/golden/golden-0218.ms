// conform: tags=diagnostics
// conform: phase=check
fn f() Unit:
    var outer = 1
    callback := fn(value: Int = (fn() Int:
        outer = 2
        return outer
    )()) Int:
        return value
