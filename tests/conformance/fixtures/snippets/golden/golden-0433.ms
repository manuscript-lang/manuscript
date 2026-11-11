// conform: tags=diagnostics
// conform: phase=check
value := result(fn():
        if true: return error(TextError("failed"))
        return ok(4)
    )