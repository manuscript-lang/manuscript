# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:673 TestLocalQueueBoundaries
let queue = Queue[Int](capacity: 2)
    let resource = Closeable(value: queue)
