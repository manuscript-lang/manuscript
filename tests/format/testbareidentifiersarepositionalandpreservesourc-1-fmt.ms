// conform: tags=formatter,generics,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/checker_test.go:107 TestBareIdentifiersArePositionalAndPreserveSourceAST
fn first[T](hold left T, right T) &T => return left

fn call(left Int, right Int) Int => return first(right, left)
// expect-format: rewritten
// expect-formatted: fn first[T](hold left T, right T) &T => return left
// expect-formatted:
// expect-formatted: fn call(left, right Int) Int => return first(right, left)
