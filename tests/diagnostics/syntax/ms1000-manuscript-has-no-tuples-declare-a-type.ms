// conform: tags=diagnostics
// conform: phase=check
let (a, b) = pair
// expect-error: MS1000 3:7-3:8 Manuscript has no tuples; declare a type with 'type Pair { ... }' and named fields to return several values, or use a List when the items share one type
