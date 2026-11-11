// conform: tags=diagnostics
// conform: phase=check
fn optional(value: Int = 1) Int: return value
fn required(value: Int) Int: return value
fn call(x: Int?) Int:
    chosen := match x:
        n: optional
        none: required
    return chosen()
