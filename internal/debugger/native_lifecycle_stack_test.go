package debugger

import (
	"bytes"
	"testing"
)

func terminalWorkerStack(stacks []byte) string {
	for _, line := range bytes.Split(stacks, []byte("\n")) {
		// Creator ancestry is not an active frame. In particular, the signal
		// guard wrapper may still be retiring after its deferred close has
		// released RunWithContext's join; its guard has already returned.
		if bytes.HasPrefix(bytes.TrimSpace(line), []byte("created by ")) {
			continue
		}
		for _, worker := range []string{"terminal.(*Term).Run(", "terminal.(*Term).RunWithContext(", "terminal.(*Term).sigintGuard(", "liner.(*State).restartPrompt"} {
			if bytes.Contains(line, []byte(worker)) {
				return worker
			}
		}
	}
	return ""
}

func TestTerminalWorkerStack(t *testing.T) {
	const wrapper = `goroutine 40 [runnable]:
github.com/go-delve/delve/pkg/terminal.(*Term).RunWithContext.func2()
    terminal.go:313 +0xdb
created by github.com/go-delve/delve/pkg/terminal.(*Term).RunWithContext in goroutine 20
    terminal.go:313 +0x3ba
`
	for _, tc := range []struct {
		name, stack string
		live        bool
	}{
		{"joined guard wrapper", wrapper, false},
		{"creator ancestry", "created by github.com/go-delve/delve/pkg/terminal.(*Term).RunWithContext in goroutine 20\ncreated by github.com/go-delve/liner.(*State).restartPrompt in goroutine 21", false},
		{"terminal loop", "github.com/go-delve/delve/pkg/terminal.(*Term).Run(0xc000012340)", true},
		{"context terminal loop", "github.com/go-delve/delve/pkg/terminal.(*Term).RunWithContext(0xc000012340, 0xc000032100)", true},
		{"signal guard", "github.com/go-delve/delve/pkg/terminal.(*Term).sigintGuard(0xc000012340, 0xc000032100)", true},
		{"wrapper and live guard", wrapper + "github.com/go-delve/delve/pkg/terminal.(*Term).sigintGuard(0xc000012340, 0xc000032100)", true},
		{"prompt reader", "github.com/go-delve/liner.(*State).restartPrompt.func1()", true},
		{"unrelated worker", "goroutine 39 [syscall]:\nos/signal.signal_recv()\nos/signal.loop()", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if worker := terminalWorkerStack([]byte(tc.stack)); (worker != "") != tc.live {
				t.Fatalf("worker %q, want live=%v\n%s", worker, tc.live, tc.stack)
			}
		})
	}
}
