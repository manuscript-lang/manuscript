# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:671 TestLocalQueueBoundaries
let queue = Queue[Int](capacity: 2)
    queue.close()
