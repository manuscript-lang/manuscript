package debugger

import (
	"errors"
	"os"
	"os/exec"
	"testing"

	"golang.org/x/sys/unix"
)

func TestScriptProcessHandleSurvivesReap(t *testing.T) {
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	child := exec.Command(executable, "-test.run=^TestScriptProcessFixture$")
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
	if err := target.Kill(); !errors.Is(err, os.ErrProcessDone) {
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
