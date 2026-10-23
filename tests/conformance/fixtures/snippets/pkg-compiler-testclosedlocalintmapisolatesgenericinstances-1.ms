# conform: tags=aliasing,diagnostics,faults,generics,maps,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_int_map_test.go:79 TestClosedLocalIntMapIsolatesGenericInstances
fn lookup[T: Hashable](key: T, value: T) T:
    var values = Map[T, T]()
    values.add(key, value)
    return values.get(key).get()

fn probe() Int:
    let number = lookup[Int](1, 2)
    let text = lookup[String]("one", "two")
    return number
