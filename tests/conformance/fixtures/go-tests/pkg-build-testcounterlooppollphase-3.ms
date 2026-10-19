# conform: tags=closures,control-flow,faults,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/loop_poll_test.go:81 TestCounterLoopPollPhase

//line generated.go:1
type pollProbeContext struct {
    pollcontext.Context
    calls int
    stop int
}
func (c *pollProbeContext) Err() error {
    c.calls++
    if c.calls == c.stop { return pollcontext.Canceled }
    return nil
}
func checkPoll(fn func(*rt.Execution, *rt.List[int], int) rt.Unit, start, stop, count, last int) {
    c := &pollProbeContext{Context: pollcontext.Background(), stop: stop}
    log := rt.NewList[int]()
    cancelled := false
    func() {
        defer func() {
            if p := recover(); p != nil {
                if _, fault := p.(rt.Fault); fault { panic(p) }
                cancelled = true
            }
        }()
        fn(&rt.Execution{Context: c}, log, start)
    }()
    if !cancelled || c.calls != stop || len(log.Items) != count || log.Items[count-1] != last {
        panic("loop cancellation phase changed")
    }
}
func init() {
    for repeat := 0; repeat < 2; repeat++ {
        checkPoll(poll_literal_up, 0, 1, 63, -75)
        checkPoll(poll_literal_up, 0, 2, 127, -11)
        checkPoll(poll_literal_down, 0, 1, 63, 438)
        checkPoll(poll_literal_down, 0, 2, 127, 374)
        checkPoll(poll_literal_nested, 0, 2, 133, 62)
        for _, start := range []int{-137, 0, 5, -9223372036854775808} {
            checkPoll(poll_up, start, 1, 63, start+62)
            checkPoll(poll_up, start, 2, 127, start+126)
        }
        for _, start := range []int{137, 500, 9223372036854775807} {
            checkPoll(poll_down, start, 1, 63, start-62)
            checkPoll(poll_down, start, 2, 127, start-126)
        }
        checkPoll(poll_continue, 0, 2, 122, 121)
        checkPoll(poll_reset, 0, 2, 127, 1)
        checkPoll(poll_nested, 0, 2, 133, 63)
    }
}
