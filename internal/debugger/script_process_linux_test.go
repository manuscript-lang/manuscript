package debugger

import (
	"errors"
	"os"
	"os/exec"
	"syscall"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func TestScriptProcessHandleSurvivesReap(t *testing.T) {
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	child := exec.Command(executable, "-test.run=^TestScriptProcessFixture$")
	child.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	child.Env = append(os.Environ(), "MANUSCRIPT_PROCESS_FIXTURE=1")
	input, err := child.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = input.Close(); _ = child.Process.Kill(); _ = child.Wait() }()
	target, err := openScriptProcess(child.Process.Pid)
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	_ = input.Close()
	if err := child.Wait(); err != nil {
		t.Fatal(err)
	}
	// Delve/another owner may have reaped the process before cancellation.
	// The retained pidfd still refers only to that retired process identity.
	if err := target.Interrupt(); !errors.Is(err, os.ErrProcessDone) {
		t.Fatalf("signal after reap: %v", err)
	}
	target.Reap()
}

func TestScriptProcessRejectsPidfdFailure(t *testing.T) {
	for _, failure := range []error{unix.ENOSYS, unix.EPERM, unix.EMFILE} {
		target, err := openScriptPIDFD(os.Getpid(), func(int, int) (int, error) { return -1, failure })
		if target != nil || !errors.Is(err, failure) {
			t.Fatalf("unsafe fallback on %v: %v %v", failure, target, err)
		}
	}
}

func TestScriptProcessReapKeepsOtherGroupWaitable(t *testing.T) {
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	fixture := func() *exec.Cmd {
		cmd := exec.Command(executable, "-test.run=^TestScriptProcessFixture$")
		cmd.Env = append(os.Environ(), "MANUSCRIPT_PROCESS_FIXTURE=1")
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		return cmd
	}
	child := fixture()
	input, err := child.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { input.Close(); child.Process.Kill(); child.Wait() }()
	target, err := openScriptProcess(child.Process.Pid)
	if err != nil {
		t.Fatal(err)
	}
	defer target.Close()
	unrelated := fixture() // null stdin: exits immediately, retain its wait status
	if err := unrelated.Start(); err != nil {
		t.Fatal(err)
	}
	fd, err := unix.PidfdOpen(unrelated.Process.Pid, 0)
	if err != nil {
		unrelated.Wait()
		t.Fatal(err)
	}
	defer unix.Close(fd)
	if n, err := unix.Poll([]unix.PollFd{{Fd: int32(fd), Events: unix.POLLIN}}, 5000); err != nil || n != 1 {
		t.Fatalf("unrelated child exit: %d %v", n, err)
	}
	done := make(chan error, 1)
	go func() { done <- target.Reap() }()
	// Keep our target alive while its wait loop runs alongside another exited
	// child. A wait-any fallback would steal that child's status in this window.
	<-time.After(100 * time.Millisecond)
	if err := target.Interrupt(); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("target reap did not join")
	}
	if err := unrelated.Wait(); err != nil {
		t.Fatalf("unrelated child's status was consumed: %v", err)
	}
}
