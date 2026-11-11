// conform: tags=diagnostics
// conform: phase=check
enum Failure:
    NotFound
fn use() Int:
    NotFound := 1
    return NotFound
