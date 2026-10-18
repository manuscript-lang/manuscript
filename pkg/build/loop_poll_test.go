package build

import (
	"context"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// A context cancels on a selected query; the log counts executed source bodies
// independently of the lowerer's polling expression.
func TestCounterLoopPollPhase(t *testing.T) {
	r := compiler.CompileSource("poll.ms", `fn poll_literal_up(log: List[Int], start: Int) Unit:
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
`, compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	r.Source = strings.Replace(r.Source, "package main\n", "package main\nimport pollcontext \"context\"\n", 1)
	r.Source += `
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
`
	binary := filepath.Join(t.TempDir(), "probe")
	if _, err := BuildCheckedWithType(r, binary, compiler.Release); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if output, err := exec.CommandContext(ctx, binary).CombinedOutput(); err != nil {
		t.Fatalf("polling changed: %v\n%s", err, output)
	}
}
