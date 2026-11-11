// conform: tags=diagnostics
// conform: phase=check
export fn main() Int:
    values := [1, 2]
    values.insert(3, 9)
    return values.length()
