package debugger

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

func diagnosticPipeCapacity(file *os.File) (int, error) {
	raw, err := file.SyscallConn()
	if err != nil {
		return 0, err
	}
	var flags, output, input uint32
	var queryErr error
	err = raw.Control(func(fd uintptr) {
		queryErr = windows.GetNamedPipeInfo(windows.Handle(fd), &flags, &output, &input, nil)
	})
	if err := errors.Join(err, queryErr); err != nil {
		return 0, err
	}
	capacity := input // The server read end consumes its inbound buffer.
	if flags&windows.PIPE_SERVER_END == 0 {
		capacity = output
	}
	if capacity == 0 {
		return 0, fmt.Errorf("output pipe has no fixed buffer capacity")
	}
	return int(capacity), nil
}

func processAlive(pid int) bool {
	process, err := windows.OpenProcess(windows.SYNCHRONIZE, false, uint32(pid))
	if err != nil {
		return false
	}
	defer windows.CloseHandle(process)
	state, err := windows.WaitForSingleObject(process, 0)
	return err == nil && state == uint32(windows.WAIT_TIMEOUT)
}

func checkClosedHistory(path string) error {
	closed := path + ".closed"
	if err := os.Rename(path, closed); err != nil {
		return err
	}
	return os.Rename(closed, path)
}

// Allocate an actual console in the disposable child. A redirected pipe test
// cannot exercise liner's direct ReadConsoleInputW path or console mode restore.
func nativeConsole(ctx context.Context, cancel context.CancelFunc) (func() error, error) {
	dll := windows.NewLazySystemDLL("kernel32.dll")
	alloc, free := dll.NewProc("AllocConsole"), dll.NewProc("FreeConsole")
	oldInput, _ := windows.GetStdHandle(windows.STD_INPUT_HANDLE)
	oldOutput, _ := windows.GetStdHandle(windows.STD_OUTPUT_HANDLE)
	_, _, _ = free.Call()
	if ok, _, err := alloc.Call(); ok == 0 {
		return nil, fmt.Errorf("AllocConsole: %w", err)
	}
	input, err := os.OpenFile("CONIN$", os.O_RDWR, 0)
	if err != nil {
		_, _, _ = free.Call()
		return nil, err
	}
	output, err := os.OpenFile("CONOUT$", os.O_RDWR, 0)
	if err != nil {
		_ = input.Close()
		_, _, _ = free.Call()
		return nil, err
	}
	var hIn, hOut windows.Handle
	inRaw, _ := input.SyscallConn()
	outRaw, _ := output.SyscallConn()
	_ = inRaw.Control(func(fd uintptr) { hIn = windows.Handle(fd) })
	_ = outRaw.Control(func(fd uintptr) { hOut = windows.Handle(fd) })
	var inputMode, outputMode uint32
	if err := errors.Join(windows.GetConsoleMode(hIn, &inputMode), windows.GetConsoleMode(hOut, &outputMode)); err != nil {
		_ = input.Close()
		_ = output.Close()
		_, _, _ = free.Call()
		return nil, err
	}
	oldStdin, oldStdout := os.Stdin, os.Stdout
	os.Stdin, os.Stdout = input, output
	_ = windows.SetStdHandle(windows.STD_INPUT_HANDLE, hIn)
	_ = windows.SetStdHandle(windows.STD_OUTPUT_HANDLE, hOut)
	done := make(chan struct{})
	go func() {
		defer close(done)
		tick := time.NewTicker(10 * time.Millisecond)
		defer tick.Stop()
		read := dll.NewProc("ReadConsoleOutputCharacterW")
		buffer := make([]uint16, 4096)
		for {
			select {
			case <-ctx.Done():
				return
			case <-tick.C:
				var count uint32
				ok, _, _ := read.Call(uintptr(hOut), uintptr(unsafe.Pointer(&buffer[0])), uintptr(len(buffer)), 0, uintptr(unsafe.Pointer(&count)))
				if ok != 0 && strings.Contains(windows.UTF16ToString(buffer[:count]), "(dlv)") {
					cancel()
					return
				}
			}
		}
	}()
	return func() error {
		cancel()
		<-done
		var inMode, outMode uint32
		err := errors.Join(windows.GetConsoleMode(hIn, &inMode), windows.GetConsoleMode(hOut, &outMode))
		if inMode != inputMode || outMode != outputMode {
			err = errors.Join(err, fmt.Errorf("terminal console modes changed: input %x/%x, output %x/%x", inMode, inputMode, outMode, outputMode))
		}
		os.Stdin, os.Stdout = oldStdin, oldStdout
		err = errors.Join(err, windows.SetStdHandle(windows.STD_INPUT_HANDLE, oldInput), windows.SetStdHandle(windows.STD_OUTPUT_HANDLE, oldOutput), input.Close(), output.Close())
		_, _, _ = free.Call()
		return err
	}, nil
}
