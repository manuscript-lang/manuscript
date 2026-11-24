// conform: tags=diagnostics
// conform: phase=check
enum First:
    Ready
enum Second:
    Ready
fn use(value Int?) Int:
    match value:
        ready => return Ready
        null => return 0
