// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
    let values={"a":1,"b":{1:2},}
    consume(values,other: {})
}
// expect-error: MS1000 4:5-4:16 'let' was removed; bind with 'x := value' (or 'x Type := value'), destructure with '[a, b] := value', and use 'var x = value' for a mutable binding
// expect-fix: 4:5-4:16 "values :="
