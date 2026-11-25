// conform: tags=diagnostics
// conform: phase=check
fn work() Result[Int, Error] {
    return Result[Int, Error].|
}
// expect-error: MS1000 4:31-4:32 expected a name, found '|'
