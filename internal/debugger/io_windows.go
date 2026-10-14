package debugger

import (
	"errors"
	"os"
	"runtime"

	"golang.org/x/sys/windows"
)

var cancelSynchronousIO = windows.NewLazySystemDLL("kernel32.dll").NewProc("CancelSynchronousIo")

func cancellationThread() (cancel, finish func() error, err error) {
	runtime.LockOSThread()
	thread, err := windows.OpenThread(windows.THREAD_TERMINATE, false, windows.GetCurrentThreadId())
	if err != nil {
		runtime.UnlockOSThread()
		return nil, nil, err
	}
	return func() error {
			ok, _, err := cancelSynchronousIO.Call(uintptr(thread))
			if ok != 0 || errors.Is(err, windows.ERROR_NOT_FOUND) {
				return nil
			}
			return err
		}, func() error {
			err := windows.CloseHandle(thread)
			runtime.UnlockOSThread()
			return err
		}, nil
}

func duplicateIO(original *os.File) (*os.File, func() error, error) {
	raw, err := original.SyscallConn()
	if err != nil {
		return nil, nil, err
	}
	var handle windows.Handle
	var duplicateErr error
	err = raw.Control(func(fd uintptr) {
		process := windows.CurrentProcess()
		duplicateErr = windows.DuplicateHandle(process, windows.Handle(fd), process, &handle, 0, false, windows.DUPLICATE_SAME_ACCESS)
	})
	if err == nil {
		err = duplicateErr
	}
	if err != nil {
		return nil, nil, err
	}
	return os.NewFile(uintptr(handle), original.Name()), func() error { return nil }, nil
}

func boundedFileWrite(file *os.File) bool {
	raw, err := file.SyscallConn()
	if err != nil {
		return false
	}
	var kind uint32
	var typeErr error
	err = raw.Control(func(fd uintptr) { kind, typeErr = windows.GetFileType(windows.Handle(fd)) })
	// Pipe I/O is interrupted by the owned handle close and, for synchronous
	// inherited handles, the joined worker's CancelSynchronousIo loop.
	return err == nil && typeErr == nil && kind == windows.FILE_TYPE_PIPE
}

func replaceConsoleStdio(input, output, errorOutput *os.File) (func() error, error) {
	streams := []struct {
		file     *os.File
		kind     uint32
		original windows.Handle
		mode     uint32
		console  bool
	}{{file: input, kind: windows.STD_INPUT_HANDLE}, {file: output, kind: windows.STD_OUTPUT_HANDLE}, {file: errorOutput, kind: windows.STD_ERROR_HANDLE}}
	for i := range streams {
		var err error
		streams[i].original, err = windows.GetStdHandle(streams[i].kind)
		if err != nil {
			return nil, err
		}
		streams[i].console = windows.GetConsoleMode(streams[i].original, &streams[i].mode) == nil
	}
	undo := func() error {
		var err error
		// liner restores via GetStdHandle; cancellation may already have closed
		// our duplicates. Restore modes through the original console handles too.
		for _, stream := range streams {
			err = errors.Join(err, windows.SetStdHandle(stream.kind, stream.original))
			if stream.console {
				err = errors.Join(err, windows.SetConsoleMode(stream.original, stream.mode))
			}
		}
		return err
	}
	for _, stream := range streams {
		raw, err := stream.file.SyscallConn()
		if err == nil {
			var setErr error
			err = raw.Control(func(fd uintptr) { setErr = windows.SetStdHandle(stream.kind, windows.Handle(fd)) })
			if err == nil {
				err = setErr
			}
		}
		if err != nil {
			return nil, errors.Join(err, undo())
		}
	}
	return undo, nil
}
