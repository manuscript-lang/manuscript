// conform: tags=diagnostics
// conform: phase=check
type Val:
    val: Int
fn work(value: Val) Unit:
    callback := fn() Unit:
        value.val = value.val + 1
    callback()
    copy := value.clone()
    list := [copy]
    list.clone().append(value)
