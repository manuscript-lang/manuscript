# conform: tags=control-flow,diagnostics,lists,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/build/loop_poll_test.go:17 TestCounterLoopPollPhase
fn poll_literal_up(var log: List[Int], start: Int) Unit:
    var i = -137
    while i < 1000:
        log.append(i)
        i += 1

fn poll_literal_down(var log: List[Int], start: Int) Unit:
    var i = 500
    while i > 0:
        log.append(i)
        i -= 1

fn poll_literal_nested(var log: List[Int], start: Int) Unit:
    var outer = 0
    while outer < 3:
        var i = 0
        while i < 70:
            log.append(i)
            i += 1
        outer += 1

fn poll_up(var log: List[Int], start: Int) Unit:
    var i = start
    while i < 1000:
        log.append(i)
        i += 1

fn poll_down(var log: List[Int], start: Int) Unit:
    var i = start
    while i > 0:
        log.append(i)
        i -= 1

fn poll_continue(var log: List[Int], start: Int) Unit:
    var i = start
    var skips = 0
    while i < 1000:
        if skips < 5:
            skips += 1
            continue
        log.append(i)
        i += 1

fn poll_reset(var log: List[Int], start: Int) Unit:
    var i = start
    while i < 1000:
        log.append(i)
        i += 1
        if i == 5:
            i = 0

fn poll_nested(var log: List[Int], start: Int) Unit:
    var outer = 0
    while outer < 3:
        var i = outer
        while i < 70:
            log.append(i)
            i += 1
        outer += 1
