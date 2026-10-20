# conform: tags=control-flow,formatter,lists,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/loop_poll_test.go:17 TestCounterLoopPollPhase
fn poll_literal_up(log: List[Int], start: Int) Unit:
    var i = -137
    while i < 1000:
        log.append(i)
        i += 1

fn poll_literal_down(log: List[Int], start: Int) Unit:
    var i = 500
    while i > 0:
        log.append(i)
        i -= 1

fn poll_literal_nested(log: List[Int], start: Int) Unit:
    var outer = 0
    while outer < 3:
        var i = 0
        while i < 70:
            log.append(i)
            i += 1
        outer += 1

fn poll_up(log: List[Int], start: Int) Unit:
    var i = start
    while i < 1000:
        log.append(i)
        i += 1

fn poll_down(log: List[Int], start: Int) Unit:
    var i = start
    while i > 0:
        log.append(i)
        i -= 1

fn poll_continue(log: List[Int], start: Int) Unit:
    var i = start
    var skips = 0
    while i < 1000:
        if skips < 5:
            skips += 1
            continue
        log.append(i)
        i += 1

fn poll_reset(log: List[Int], start: Int) Unit:
    var i = start
    while i < 1000:
        log.append(i)
        i += 1
        if i == 5:
            i = 0

fn poll_nested(log: List[Int], start: Int) Unit:
    var outer = 0
    while outer < 3:
        var i = outer
        while i < 70:
            log.append(i)
            i += 1
        outer += 1
