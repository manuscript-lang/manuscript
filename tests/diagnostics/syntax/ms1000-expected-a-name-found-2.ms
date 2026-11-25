// conform: tags=diagnostics
// conform: phase=check
interface Compare[T] {
    fn compare(other T) Int
}
fn compare[T Compare[T]](first T, second T) Int => first.|
// expect-error: MS1000 6:58-6:59 expected a name, found '|'
