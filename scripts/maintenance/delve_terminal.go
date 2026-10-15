package main

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

//go:embed testdata/liner/input_manuscript_test.go
var linerLifecycleTest []byte

// These small embedding patches join terminal signal and input workers. Keep
// exact upstream context so vendor refresh fails when it needs a fresh review.
func patchDelveTerminal(root string) error {
	for _, patch := range delveTerminalPatches {
		path := filepath.Join(root, patch.path)
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		source := string(data)
		if strings.Contains(source, patch.after) {
			continue
		}
		if strings.Count(source, patch.before) != 1 {
			return fmt.Errorf("%s terminal lifecycle context changed; review the embedding patch", patch.path)
		}
		if err := os.WriteFile(path, []byte(strings.Replace(source, patch.before, patch.after, 1)), 0644); err != nil {
			return err
		}
	}
	return os.WriteFile(filepath.Join(root, "vendor/github.com/go-delve/liner/input_manuscript_test.go"), linerLifecycleTest, 0644)
}

type vendorPatch struct{ path, before, after string }

var delveTerminalPatches = []vendorPatch{
	{path: "vendor/github.com/go-delve/delve/pkg/terminal/terminal.go", before: `//lint:file-ignore ST1005 errors here can be capitalized

import (
	"errors"
	"fmt"
	"io"
`, after: `//lint:file-ignore ST1005 errors here can be capitalized

import (
	"context"
	"errors"
	"fmt"
	"io"
`},
	{path: "vendor/github.com/go-delve/delve/pkg/terminal/terminal.go", before: `	}
}

func (t *Term) sigintGuard(ch <-chan os.Signal, multiClient bool) {
	for range ch {
		t.longCommandCancel()
		t.starlarkEnv.Cancel()
		state, err := t.client.GetStateNonBlocking()
`, after: `	}
}

// WaitForInput joins liner's prompt readers after the caller interrupts owned
// input. Close cancels pending deliveries; it does not close borrowed stdin.
func (t *Term) WaitForInput() { t.line.WaitForInput() }

func (t *Term) sigintGuard(ctx context.Context, ch <-chan os.Signal, multiClient bool) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-ch:
		}
		if ctx.Err() != nil {
			return
		}
		t.longCommandCancel()
		t.starlarkEnv.Cancel()
		state, err := t.client.GetStateNonBlocking()
`},
	{path: "vendor/github.com/go-delve/delve/pkg/terminal/terminal.go", before: `
// Run begins running dlv in the terminal.
func (t *Term) Run() (int, error) {
	defer t.Close()

	multiClient := t.client.IsMulticlient()

	// Send the debugger a halt command on SIGINT
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT)
	go t.sigintGuard(ch, multiClient)

	fns := trie.New()
	cmds := trie.New()
`, after: `
// Run begins running dlv in the terminal.
func (t *Term) Run() (int, error) {
	return t.RunWithContext(context.Background())
}

// RunWithContext is Manuscript's embedded-terminal lifecycle entrypoint. The
// caller interrupts owned terminal I/O on cancellation; Run joins its signal
// guard before restoring terminal modes and closing the transcript.
func (t *Term) RunWithContext(ctx context.Context) (status int, err error) {
	defer t.Close()
	defer func() {
		if t.historyFile != nil {
			if closeErr := t.historyFile.Close(); closeErr != nil {
				status, err = 1, errors.Join(err, closeErr)
			}
			t.historyFile = nil
		}
	}()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	multiClient := t.client.IsMulticlient()

	// Send the debugger a halt command on SIGINT
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT)
	guardDone := make(chan struct{})
	go func() { defer close(guardDone); t.sigintGuard(ctx, ch, multiClient) }()
	defer func() {
		signal.Stop(ch)
		cancel()
		<-guardDone
	}()

	fns := trie.New()
	cmds := trie.New()
`},
	{path: "vendor/github.com/go-delve/delve/pkg/terminal/terminal.go", before: `	_, _ = t.client.GetState()

	for {
		locs = nil

		cmdstr, err := t.promptForInput()
		if err != nil {
			if err == io.EOF {
				fmt.Fprintln(t.stdout, "exit")
`, after: `	_, _ = t.client.GetState()

	for {
		if err := ctx.Err(); err != nil {
			return 1, err
		}
		locs = nil

		cmdstr, err := t.promptForInput()
		if ctx.Err() != nil {
			return 1, ctx.Err()
		}
		if err != nil {
			if err == io.EOF {
				fmt.Fprintln(t.stdout, "exit")
`},
	{path: "vendor/github.com/go-delve/delve/pkg/terminal/terminal.go", before: `
		lastCmd = cmdstr

		if err := t.cmds.Call(cmdstr, t); err != nil {
			if _, ok := err.(ExitRequestError); ok {
				return t.handleExit()
`, after: `
		lastCmd = cmdstr

		if err := ctx.Err(); err != nil {
			return 1, err
		}
		if err := t.cmds.Call(cmdstr, t); err != nil {
			if _, ok := err.(ExitRequestError); ok {
				return t.handleExit()
`},
	{path: "vendor/github.com/go-delve/delve/pkg/terminal/terminal.go", before: `		if err := t.historyFile.Close(); err != nil {
			fmt.Printf("error closing history file: %s\n", err)
		}
	}

	t.quittingMutex.Lock()
`, after: `		if err := t.historyFile.Close(); err != nil {
			fmt.Printf("error closing history file: %s\n", err)
		}
		t.historyFile = nil
	}

	t.quittingMutex.Lock()
`},
	{path: "vendor/github.com/go-delve/liner/common.go", before: `)

type commonState struct {
	terminalSupported bool
	outputRedirected  bool
	inputRedirected   bool
`, after: `)

type commonState struct {
	inputReaders      sync.WaitGroup
	terminalSupported bool
	outputRedirected  bool
	inputRedirected   bool
`},
	{path: "vendor/github.com/go-delve/liner/common.go", before: `	needRefresh       bool
}

// TabStyle is used to select how tab completions are displayed.
type TabStyle int

`, after: `	needRefresh       bool
}

// WaitForInput joins prompt readers. The caller must first interrupt its owned
// input and call Close; borrowed input is never closed by liner.
func (s *commonState) WaitForInput() { s.inputReaders.Wait() }

// TabStyle is used to select how tab completions are displayed.
type TabStyle int

`},
	{path: "vendor/github.com/go-delve/liner/input.go", before: `	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)
`, after: `	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)
`},
	{path: "vendor/github.com/go-delve/liner/input.go", before: `	winch       chan os.Signal
	pending     []rune
	useCHA      bool
}

// NewLiner initializes a new *State, and sets the terminal into raw mode. To
// restore the terminal to its previous state, call State.Close().
func NewLiner() *State {
	var s State
	s.r = bufio.NewReader(os.Stdin)

	s.terminalSupported = TerminalSupported()
`, after: `	winch       chan os.Signal
	pending     []rune
	useCHA      bool
	inputDone   chan struct{}
	inputClose  sync.Once
}

// NewLiner initializes a new *State, and sets the terminal into raw mode. To
// restore the terminal to its previous state, call State.Close().
func NewLiner() *State {
	var s State
	s.inputDone = make(chan struct{})
	s.r = bufio.NewReader(os.Stdin)

	s.terminalSupported = TerminalSupported()
`},
	{path: "vendor/github.com/go-delve/liner/input.go", before: `
func (s *State) restartPrompt() {
	next := make(chan nexter, 200)
	go func() {
		for {
			var n nexter
			n.r, _, n.err = s.r.ReadRune()
			next <- n
			// Shut down nexter loop when an end condition has been reached
			if n.err != nil || n.r == '\n' || n.r == '\r' || n.r == ctrlC || n.r == ctrlD {
				close(next)
				return
			}
		}
`, after: `
func (s *State) restartPrompt() {
	next := make(chan nexter, 200)
	s.inputReaders.Add(1)
	go func() {
		defer s.inputReaders.Done()
		defer close(next)
		for {
			var n nexter
			n.r, _, n.err = s.r.ReadRune()
			select {
			case next <- n:
			case <-s.inputDone:
				return
			}
			// Shut down nexter loop when an end condition has been reached
			if n.err != nil || n.r == '\n' || n.r == '\r' || n.r == ctrlC || n.r == ctrlD {
				return
			}
		}
`},
	{path: "vendor/github.com/go-delve/liner/input.go", before: `
// Close returns the terminal to its previous mode
func (s *State) Close() error {
	signal.Stop(s.winch)
	if !s.inputRedirected {
		s.origMode.ApplyMode()
`, after: `
// Close returns the terminal to its previous mode
func (s *State) Close() error {
	s.inputClose.Do(func() { close(s.inputDone) })
	signal.Stop(s.winch)
	if !s.inputRedirected {
		s.origMode.ApplyMode()
`},
}
