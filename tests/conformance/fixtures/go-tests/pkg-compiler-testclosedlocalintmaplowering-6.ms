# conform: tags=closures,maps,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_int_map_test.go:28 TestClosedLocalIntMapLowering
let callback = fn() Int:
        let values = Map[Int, Int]()
        let child = fn() Int:
            let grandchild = fn() Int: values.length()
            return grandchild()
        return child()
