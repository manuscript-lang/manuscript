package debugger

import (
	"errors"
	"os"
	"os/exec"
	"testing"
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
	if err := target.Interrupt(); !errors.Is(err, os.ErrProcessDone) {
		t.Fatalf("signal after reap: %v", err)
	}
	target.Reap()
}
