// conform: tags=diagnostics
// conform: phase=check
export fn main() Int:
    insert := [1].insert
    insert(index: 5, value: 9)
    return 0
