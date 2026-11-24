// conform: tags=diagnostics
// conform: phase=check
enum Flag:
    Ready
fn use(value Int?) Int:
    Flag := 2
    match value:
        ready => return Ready
        null => return 0
