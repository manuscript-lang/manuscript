// conform: tags=diagnostics
// conform: phase=check
fn empty() List[Int]:
    return []
export fn main() Int:
    [value] := empty()
    return value
