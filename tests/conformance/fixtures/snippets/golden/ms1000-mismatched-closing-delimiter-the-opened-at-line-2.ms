// conform: tags=diagnostics
// conform: phase=check
value := result(fn() {
        if true { return error(TextError("failed")) }
        return ok(4)
    )
}
// expect-error: MS1000 6:5 mismatched closing delimiter ')'; the '{' opened at line 3:22 needs '}'
