package debugger

import (
	"os"

	"golang.org/x/sys/windows"
)

type scriptWindowsProcess struct{ handle windows.Handle }

func scriptProcessSupported() error { return nil }

func openScriptProcess(pid int) (scriptProcess, error) {
	handle, err := windows.OpenProcess(windows.PROCESS_TERMINATE|windows.SYNCHRONIZE, false, uint32(pid))
	if err != nil {
		return nil, err
	}
	return &scriptWindowsProcess{handle: handle}, nil
}

func (p *scriptWindowsProcess) Interrupt() error {
	state, err := windows.WaitForSingleObject(p.handle, 0)
	if err != nil {
		return err
	}
	if state == windows.WAIT_OBJECT_0 {
		return os.ErrProcessDone
	}
	return windows.TerminateProcess(p.handle, 1)
}

func (p *scriptWindowsProcess) Reap() error {
	_, err := windows.WaitForSingleObject(p.handle, windows.INFINITE)
	return err
}
func (p *scriptWindowsProcess) Close() error { return windows.CloseHandle(p.handle) }
