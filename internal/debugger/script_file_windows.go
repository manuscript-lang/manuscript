package debugger

import (
	"fmt"
	"os"

	"golang.org/x/sys/windows"
)

func scriptFile(file *os.File) (*os.File, func(), error) {
	var handle windows.Handle
	current := windows.CurrentProcess()
	if err := windows.DuplicateHandle(current, windows.Handle(file.Fd()), current, &handle, 0, false, windows.DUPLICATE_SAME_ACCESS); err != nil {
		return nil, nil, err
	}
	return os.NewFile(uintptr(handle), file.Name()), func() {}, nil
}

func validateScriptInput(file *os.File) error {
	raw, err := file.SyscallConn()
	if err != nil {
		return err
	}
	console := false
	if err := raw.Control(func(handle uintptr) {
		var mode uint32
		console = windows.GetConsoleMode(windows.Handle(handle), &mode) == nil
	}); err != nil {
		return err
	}
	if console {
		return fmt.Errorf("script debugging cannot cancel a Windows console stdin read safely; use --script <file> or redirected pipe input")
	}
	return nil
}

func interruptScriptOutput(file *os.File) {
	// A synchronous inherited WriteFile may accept a deadline but remain blocked
	// inside the syscall. Go's pipe Close uses CancelIoEx to unblock it. This
	// handle is an owned duplicate; cancellation may prevent final output records.
	_ = file.Close()
}
