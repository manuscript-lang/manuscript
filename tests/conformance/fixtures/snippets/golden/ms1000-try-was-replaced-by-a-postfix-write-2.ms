// conform: tags=diagnostics
// conform: phase=check
output := try value
    return ok(output)
// expect-error: MS1000 3:11-3:20 'try' was replaced by a postfix '?': write f(x)? instead of try f(x), and x | step? instead of x | try step
// expect-fix: 3:11-3:20 "value?"
