// conform: tags=diagnostics
// conform: phase=check

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
func checkPoll(fn func(*rt.Execution, *rt.List[int], int) rt.Void, start, stop, count, last int) {
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
// expect-error: MS1000 5:23-5:29 expected '{', found name 'struct'; block headers (fn, if, else, for, while, match, type, enum, interface, test) end with '{' on the same line, and the block closes with '}'
// expect-error: MS1000 10:1-10:5 'func' is not a Manuscript declaration keyword; declare a function as 'fn name(a Int) Int { ... }' with the result type after the parameters
// expect-fix: 10:1-10:5 "fn"
// expect-error: MS1000 21:30-21:31 unexpected source character ';'; Manuscript ends a statement at the end of the line, so remove the semicolon
// expect-error: MS1000 31:1-31:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
// expect-error: MS1000 33:20-33:21 unexpected source character ';'; Manuscript ends a statement at the end of the line, so remove the semicolon
// expect-error: MS1000 51:1-51:2 unmatched closing delimiter '}'; remove it or add the matching opener before it
