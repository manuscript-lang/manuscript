# conform: tags=diagnostics,lists,maps,match,optional,strings,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:75 TestStatementMatchDiscardsArmValues
fn f(counts: Map[String, Int], names: List[String], found: Optional[Int]) Unit:
    match found:
        some(n):
            counts.add(key: "a", value: n)
        none:
            names.append("x")
