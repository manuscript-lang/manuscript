// conform: tags=diagnostics
// conform: phase=check
fn double(xInt) Int =>return x*2
fn f(xInt) Int {
    if x>0 { return double(x) }
    else:return 0
}
// expect-error: MS1000 3:11-3:15 parameter 'xInt' has no type; every parameter is written name Type, e.g. xInt Int
// expect-error: MS1000 4:6-4:10 parameter 'xInt' has no type; every parameter is written name Type, e.g. xInt Int
