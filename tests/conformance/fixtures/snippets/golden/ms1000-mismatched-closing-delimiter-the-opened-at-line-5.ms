// conform: tags=diagnostics
// conform: phase=check
value := result(fn() {
        n := checked()?
        return ok(n)
    )
}
// expect-error: MS1000 6:5 mismatched closing delimiter ')'; the '{' opened at line 3:22 needs '}'
