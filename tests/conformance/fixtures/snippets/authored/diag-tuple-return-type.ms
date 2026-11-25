// conform: tags=diagnostics,tier-core
// conform: phase=check
fn pair() (Int, Int) {
    return 1, 2
}

export fn main() Int {
    return 0
}
// expect-error: MS1000 3:15-3:16 Manuscript has no tuples; declare a type with 'type Pair { ... }' and named fields to return several values, or use a List when the items share one type
