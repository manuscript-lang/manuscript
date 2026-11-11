// conform: tags=diagnostics
// conform: phase=check
fn double(x:Int) Int:return x*2
fn f(x:Int) Int:
    if x>0:return double(x)
    else:return 0
