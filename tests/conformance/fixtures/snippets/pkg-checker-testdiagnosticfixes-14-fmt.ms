# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:34 TestDiagnosticFixes
def f() -> Int:
    let a = SetBuilder[Int]()
    let b = SetBuilder[Int]()
    var m = Queue[Int]()
    var n = Queue[Int]()
    return 0
