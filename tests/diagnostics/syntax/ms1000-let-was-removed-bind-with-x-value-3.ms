// conform: tags=diagnostics
// conform: phase=check
fn use() Void {
    ListEntry := fn() Int => 1
    let value: ListE|
}
// expect-error: MS1000 5:5-5:8 'let' was removed; bind with 'x := value' (or 'x Type := value'), destructure with '[a, b] := value', and use 'var x = value' for a mutable binding
