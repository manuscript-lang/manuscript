// conform: tags=diagnostics
// conform: phase=check
enum First:
    Ready(value: Int)
enum Second:
    Ready(value: Int)
fn wrong() First:
    return Ready(value: 1)
