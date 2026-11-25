// conform: tags=diagnostics
// conform: phase=check
result Result[Int, TextError] = fail("empty")
    return result
// expect-error: MS1000 3:31-3:32 an immutable binding uses ':=' after its type: write 'x Type := value'; '=' binds only after 'var'
// expect-fix: 3:31-3:32 ":="
