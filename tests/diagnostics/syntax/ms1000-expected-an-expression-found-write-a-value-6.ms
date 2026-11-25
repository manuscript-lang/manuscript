// conform: tags=diagnostics
// conform: phase=check
    bad := = 1
    return 1
// expect-error: MS1000 3:12-3:13 expected an expression, found '='; write a value, name, call, or literal here
