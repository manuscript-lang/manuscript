// conform: tags=diagnostics
// conform: phase=check
fn identity[T](value T) T => value

fn first() String => identity(1)

fn second() Int => identity(2)
// expect-error: MS3001 5:22 expected String, found Int (in the return value); Int does not convert to String implicitly; interpolate it into text, e.g. f"{value}"
// expect-fix: 5:22-5:33 "f\"{identity(1)}\""
