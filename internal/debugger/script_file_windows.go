package debugger

import (
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

func interruptScriptOutput(file *os.File) {
	// A synchronous inherited WriteFile may accept a deadline but remain blocked
	// inside the syscall. Go's pipe Close uses CancelIoEx to unblock it. This
	// handle is an owned duplicate; cancellation may prevent final output records.
	_ = file.Close()
}
