//go:build linux || darwin || openbsd || freebsd || netbsd || solaris

package liner

import (
	"bufio"
	"io"
	"strings"
	"testing"
	"time"
)

func waitInputReaders(t *testing.T, s *State) {
	t.Helper()
	done := make(chan struct{})
	go func() { s.WaitForInput(); close(done) }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("prompt reader survived owned input shutdown")
	}
}

func TestManuscriptCloseCancelsBlockedPromptDelivery(t *testing.T) {
	s := &State{inputDone: make(chan struct{})}
	s.inputRedirected = true
	s.r = bufio.NewReader(strings.NewReader(strings.Repeat("x", 1000)))
	s.restartPrompt()
	deadline := time.Now().Add(5 * time.Second)
	for len(s.next) < 200 {
		if time.Now().After(deadline) {
			t.Fatal("prompt delivery never filled")
		}
		time.Sleep(time.Millisecond)
	}
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	waitInputReaders(t, s)
}

type observedInput struct {
	io.Reader
	started chan struct{}
}

func (r *observedInput) Read(p []byte) (int, error) {
	close(r.started)
	return r.Reader.Read(p)
}

func TestManuscriptWaitJoinsInterruptedPromptRead(t *testing.T) {
	input, output := io.Pipe()
	defer input.Close()
	defer output.Close()
	reader := &observedInput{Reader: input, started: make(chan struct{})}
	s := &State{inputDone: make(chan struct{})}
	s.inputRedirected = true
	s.r = bufio.NewReader(reader)
	s.restartPrompt()
	<-reader.started
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	_ = input.Close()
	waitInputReaders(t, s)
}
