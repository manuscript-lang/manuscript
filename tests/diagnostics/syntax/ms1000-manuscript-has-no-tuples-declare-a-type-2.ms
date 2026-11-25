// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    p := (1, 2)
    return 0
}
// expect-error: MS1000 4:12-4:13 Manuscript has no tuples; declare a type with 'type Pair { ... }' and named fields, or use a List when the items share one type
