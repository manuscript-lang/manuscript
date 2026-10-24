# conform: tags=formatter,lists,maps,match,optional,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:75 TestStatementMatchDiscardsArmValues
def f(var counts: Map[String, Int], var names: List[String], found: Optional[Int]) -> Unit:
    match found:
        case some(n):
            counts.add(key: "a", value: n)
        case none:
            names.append("x")
