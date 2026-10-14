package debugger

import (
	"bytes"
	"context"
	"os"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"golang.org/x/sys/windows"
)

func TestScriptRejectsWindowsConsoleInput(t *testing.T) {
	input, err := os.OpenFile("CONIN$", os.O_RDONLY, 0)
	if err != nil {
		kernel := windows.NewLazySystemDLL("kernel32.dll")
		created, _, failure := kernel.NewProc("AllocConsole").Call()
		if created == 0 {
			t.Fatalf("create console fixture: %v", failure)
		}
		defer kernel.NewProc("FreeConsole").Call()
		input, err = os.OpenFile("CONIN$", os.O_RDONLY, 0)
	}
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	var output bytes.Buffer
	status := Script(context.Background(), "must-not-launch", nil, tooling.Inspection{}, input, &output, false)
	events := decodeEvents(t, output.Bytes())
	if status != 1 || len(events) != 2 || events[0].Code != "input" || events[0].PID != 0 || !strings.Contains(events[0].Message, "console stdin") {
		t.Fatal(status, events)
	}
}

func TestScriptWindowsFileAndPipeInput(t *testing.T) {
	file, err := os.CreateTemp(t.TempDir(), "commands")
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	defer writer.Close()
	for _, input := range []*os.File{file, reader} {
		if err := validateScriptInput(input); err != nil {
			t.Fatal("rejected cancellable script input", err)
		}
	}
}
