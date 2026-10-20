# conform: tags=closures,faults,maps,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_int_map_test.go:31 TestClosedLocalIntMapLowering
let callback = fn() Int:
        let values = Map[Int, Int]()
        values.add(1, 2)
        return values.get(1).get()
