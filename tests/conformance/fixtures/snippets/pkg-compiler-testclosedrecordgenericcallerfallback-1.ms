# conform: tags=control-flow,diagnostics,generics,mutation,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/record_bounds_test.go:102 TestClosedRecordGenericCallerFallback
def count[T](value: T) -> Int:
    let cell = Cell(0)
    var i = 0

    while i < 1000:
        cell.bump(1)
        i += 1

    return cell.total

def probe() -> Int: return count[String]("unused")
