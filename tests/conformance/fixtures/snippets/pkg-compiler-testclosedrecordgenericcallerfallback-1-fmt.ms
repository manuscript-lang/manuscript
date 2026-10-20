# conform: tags=control-flow,formatter,generics,mutation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/record_bounds_test.go:102 TestClosedRecordGenericCallerFallback
fn count[T](value: T) Int:
    let cell = Cell(0)
    var i = 0
    while i < 1000:
        cell.bump(1)
        i += 1
    return cell.total
fn probe() Int: return count[String]("unused")
