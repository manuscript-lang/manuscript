// conform: tags=diagnostics
// conform: phase=check
fn work(early Int) Int {
    result := subtract(try
        match 0 {
            _value => {
                10
            }
            null => 10
        }
    )
    return result
}
// expect-error: MS1000 4:24-4:27 'try' was replaced by a postfix '?': write f(x)? instead of try f(x), and x | step? instead of x | try step
// expect-error: MS1000 11:5 mismatched closing delimiter ')'; the '{' opened at line 3:24 needs '}'
