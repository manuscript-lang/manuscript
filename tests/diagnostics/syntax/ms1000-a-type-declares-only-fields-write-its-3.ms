// conform: tags=diagnostics
// conform: phase=check
type A {
    x Int
    fn f() Int {
        return x
    }
}
// expect-error: MS1000 5:5-5:7 a type declares only fields; write its methods after it as 'fn A.name(...)'
