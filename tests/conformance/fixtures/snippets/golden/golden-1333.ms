// conform: tags=diagnostics
// conform: phase=check
enum Shape:
    Dot
    Line
fn use(value: Shape) Int:
    return match value:
        Dot: 0
        Line: 1
