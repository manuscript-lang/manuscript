# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:34 TestDiagnosticFixes
fn f() Int:
    let a = Set[Int]()
    let b = Set[Int]()
    var m = Queue[Int]()
    var n = Queue[Int]()
    return 0
