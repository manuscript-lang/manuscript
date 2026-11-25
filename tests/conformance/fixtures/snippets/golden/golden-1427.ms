// conform: tags=diagnostics
// conform: phase=check
export main := 0
// expect-error: MS3000 3:8 entry must declare fn main; main is a constant, so rename it and declare 'fn main() Void { ... }'
