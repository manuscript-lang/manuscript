// conform: tags=diagnostics
// conform: phase=check
enum First:
    Ready
enum Second:
    Ready
fn use(value: Int?) Int:
    match value:
        ready: return Ready
        none: return 0
