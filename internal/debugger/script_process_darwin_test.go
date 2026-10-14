package debugger

import (
	"os"
	"os/exec"
	"testing"
)

func TestScriptDarwinExitObservationSurvivesReap(t *testing.T) {
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
	defer input.Close()
	control, err := openScriptExitObservation(child.Process.Pid, func() error { return nil })
	if err != nil {
		input.Close()
		child.Wait()
		t.Fatal(err)
	}
	defer control.Close()
	input.Close()
	if err := child.Wait(); err != nil {
		t.Fatal(err)
	}
	// The process has been reaped, but its registered knote still reports its
	// exit without consulting or signaling any later occupant of that PID.
	if err := control.Reap(); err != nil {
		t.Fatal(err)
	}
	if err := control.Interrupt(); err != nil {
		t.Fatal(err)
	}
}
