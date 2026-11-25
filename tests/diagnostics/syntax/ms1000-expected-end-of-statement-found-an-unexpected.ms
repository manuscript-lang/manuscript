// conform: tags=diagnostics
// conform: phase=check
interface Read {
    fn get() Int {
        return 1
    }
}
// expect-error: MS1000 4:18-4:19 expected end of statement, found an unexpected '{'; put one statement per line, and join operands with an operator or a comma inside brackets
