# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:34 TestDiagnosticFixes
fn f() Int:
    let a = SetBuilder[Int]()
    let b = SetBuilder[Int]()
    let m = Queue[Int]()
    let n = Queue[Int]()
    return 0
