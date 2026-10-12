//go:build windows

package hostos

import (
	"errors"
	hoststats "github.com/shirou/gopsutil/v4/host"
	"golang.org/x/sys/windows"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var kernel32 = syscall.NewLazyDLL("kernel32.dll")

//go:uintptrescapes
func windowsCall(name string, a ...uintptr) error {
	success, _, err := kernel32.NewProc(name).Call(a...)
	if success == 0 {
		return err
	}
	return nil
}
func StatFS(path string) (FileSystemInfo, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return FileSystemInfo{}, err
	}
	root, err := syscall.UTF16PtrFromString(filepath.VolumeName(absolute) + "\\")
	if err != nil {
		return FileSystemInfo{}, err
	}
	var sectors, bytes, free, total uint32
	err = windowsCall("GetDiskFreeSpaceW", uintptr(unsafe.Pointer(root)), uintptr(unsafe.Pointer(&sectors)), uintptr(unsafe.Pointer(&bytes)), uintptr(unsafe.Pointer(&free)), uintptr(unsafe.Pointer(&total)))
	if err != nil {
		return FileSystemInfo{}, err
	}
	var availableBytes, totalBytes, freeBytes uint64
	err = windowsCall("GetDiskFreeSpaceExW", uintptr(unsafe.Pointer(root)), uintptr(unsafe.Pointer(&availableBytes)), uintptr(unsafe.Pointer(&totalBytes)), uintptr(unsafe.Pointer(&freeBytes)))
	block := uint64(sectors) * uint64(bytes)
	if block == 0 {
		return FileSystemInfo{}, errors.New("invalid filesystem block size")
	}
	return FileSystemInfo{BlockSize: int64(block), Blocks: int64(totalBytes / block), BlocksFree: int64(freeBytes / block), BlocksAvailable: int64(availableBytes / block)}, err
}
func FileTimes(file *os.File, atime, mtime time.Time) error {
	a, m := syscall.NsecToFiletime(atime.UnixNano()), syscall.NsecToFiletime(mtime.UnixNano())
	return control(file, func(fd uintptr) error { return syscall.SetFileTime(syscall.Handle(fd), nil, &a, &m) })
}
func windowsProcess(pid int, access uint32) (syscall.Handle, func(), error) {
	if pid == 0 || pid == os.Getpid() {
		h, err := syscall.GetCurrentProcess()
		return h, func() {}, err
	}
	h, err := syscall.OpenProcess(access, false, uint32(pid))
	return h, func() { syscall.CloseHandle(h) }, err
}
func GetPriority(pid int) (int, error) {
	h, close, err := windowsProcess(pid, 0x0400)
	if err != nil {
		return 0, err
	}
	defer close()
	value, _, err := kernel32.NewProc("GetPriorityClass").Call(uintptr(h))
	if value == 0 {
		return 0, err
	}
	priorities := map[uintptr]int{0x40: 19, 0x4000: 10, 0x20: 0, 0x8000: -7, 0x80: -14, 0x100: -20}
	return priorities[value], nil
}
func SetPriority(pid, priority int) error {
	h, close, err := windowsProcess(pid, 0x0200)
	if err != nil {
		return err
	}
	defer close()
	class := uintptr(0x40)
	switch {
	case priority < -14:
		class = 0x100
	case priority < -7:
		class = 0x80
	case priority < 0:
		class = 0x8000
	case priority < 10:
		class = 0x20
	case priority < 19:
		class = 0x4000
	}
	return windowsCall("SetPriorityClass", uintptr(h), class)
}
func ResourceUsage() (Usage, error) {
	h, err := syscall.GetCurrentProcess()
	if err != nil {
		return Usage{}, err
	}
	var creation, exit, kernel, user syscall.Filetime
	if err = syscall.GetProcessTimes(h, &creation, &exit, &kernel, &user); err != nil {
		return Usage{}, err
	}
	micros := func(f syscall.Filetime) int64 { return int64(uint64(f.HighDateTime)<<32|uint64(f.LowDateTime)) / 10 }
	var counters struct {
		Size, Faults                                                                                 uint32
		PeakWorkingSet, WorkingSet, PeakPaged, Paged, PeakNonPaged, NonPaged, Pagefile, PeakPagefile uintptr
	}
	counters.Size = uint32(unsafe.Sizeof(counters))
	err = windowsCall("K32GetProcessMemoryInfo", uintptr(h), uintptr(unsafe.Pointer(&counters)), uintptr(counters.Size))
	if err != nil {
		return Usage{}, err
	}
	var ioCounters struct{ Reads, Writes, Other, ReadBytes, WriteBytes, OtherBytes uint64 }
	if err = windowsCall("GetProcessIoCounters", uintptr(h), uintptr(unsafe.Pointer(&ioCounters))); err != nil {
		return Usage{}, err
	}
	return Usage{User: micros(user), System: micros(kernel), MaxRSS: int64(counters.PeakWorkingSet), Reads: int64(ioCounters.Reads), Writes: int64(ioCounters.Writes)}, nil
}
func Umask(int) int                                { return -1 }
func SetIdentity(string, int) error                { return errors.ErrUnsupported }
func SetGroups([]int) error                        { return errors.ErrUnsupported }
func LinkTimes(string, time.Time, time.Time) error { return errors.ErrUnsupported }
func DataSync(file *os.File) error                 { return file.Sync() }
func LinkMode(string, uint32) error                { return errors.ErrUnsupported }
func OSRelease() (string, error)                   { return hoststats.KernelVersion() }
func OSVersion() (string, error) {
	platform, _, version, err := hoststats.PlatformInformation()
	return platform + " " + version, err
}
func Access(path string, mode uint32) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if mode == 0 || info.IsDir() {
		return nil
	}
	flags := os.O_RDONLY
	if mode&2 != 0 {
		flags = os.O_RDWR
	}
	file, err := os.OpenFile(path, flags, 0)
	if err != nil {
		return err
	}
	return file.Close()
}
func Constants() map[string]int64 {
	return map[string]int64{"SIGINT": 2, "SIGTERM": 15, "PRIORITY_LOW": 19, "PRIORITY_BELOW_NORMAL": 10, "PRIORITY_NORMAL": 0, "PRIORITY_ABOVE_NORMAL": -7, "PRIORITY_HIGH": -14, "PRIORITY_HIGHEST": -20}
}
func Exec(string, []string, []string) error { return errors.ErrUnsupported }

func AvailableParallelism() (int, error) {
	n, _, err := kernel32.NewProc("GetActiveProcessorCount").Call(0xffff)
	if n == 0 {
		return 0, err
	}
	return int(n), nil
}

func CloneFile(string, string) error { return errors.ErrUnsupported }

func BirthInfo(info os.FileInfo) time.Time {
	if stat, ok := info.Sys().(*syscall.Win32FileAttributeData); ok {
		return time.Unix(0, stat.CreationTime.Nanoseconds())
	}
	return time.Time{}
}
func BirthPath(string, bool) time.Time { return time.Time{} }
func BirthFile(file *os.File) time.Time {
	info, err := file.Stat()
	if err != nil {
		return time.Time{}
	}
	return BirthInfo(info)
}

func FileConstants() map[string]int64 {
	return map[string]int64{"O_RDONLY": int64(os.O_RDONLY), "O_WRONLY": int64(os.O_WRONLY), "O_RDWR": int64(os.O_RDWR), "O_APPEND": int64(os.O_APPEND), "O_EXCL": int64(os.O_EXCL), "O_SYNC": int64(os.O_SYNC), "O_TRUNC": int64(os.O_TRUNC), "O_CREAT": int64(os.O_CREATE), "F_OK": 0, "R_OK": 4, "W_OK": 2, "X_OK": 1, "COPYFILE_EXCL": 1, "COPYFILE_FICLONE": 2, "COPYFILE_FICLONE_FORCE": 4}
}

var windowsTitle struct {
	sync.Mutex
	value string
	set   bool
}

func ProcessTitle() (string, error) {
	windowsTitle.Lock()
	defer windowsTitle.Unlock()
	if windowsTitle.set {
		return windowsTitle.value, nil
	}
	buffer := make([]uint16, 32768)
	n, _, err := kernel32.NewProc("GetConsoleTitleW").Call(uintptr(unsafe.Pointer(&buffer[0])), uintptr(len(buffer)))
	if n == 0 {
		if err != syscall.Errno(0) {
			return filepath.Base(os.Args[0]), nil
		}
		return "", nil
	}
	return syscall.UTF16ToString(buffer[:n]), nil
}
func SetProcessTitle(title string) error {
	pointer, err := syscall.UTF16PtrFromString(title)
	if err != nil {
		return err
	}
	windowsTitle.Lock()
	defer windowsTitle.Unlock()
	err = windowsCall("SetConsoleTitleW", uintptr(unsafe.Pointer(pointer)))
	if err != nil && err != windows.ERROR_INVALID_HANDLE {
		return err
	}
	windowsTitle.value, windowsTitle.set = title, true
	return nil
}

func SendSignal(pid, signal int) error {
	if pid <= 0 {
		return syscall.EINVAL
	}
	process, err := os.FindProcess(pid)
	if err != nil {
		return err
	}
	defer process.Release()
	if signal == 0 {
		handle, close, err := windowsProcess(pid, 0x1000)
		if err != nil {
			return err
		}
		defer close()
		var status uint32
		if err = windowsCall("GetExitCodeProcess", uintptr(handle), uintptr(unsafe.Pointer(&status))); err != nil {
			return err
		}
		if status != 259 {
			return os.ErrNotExist
		}
		return nil
	}
	if signal == 2 || signal == 9 || signal == 15 {
		return process.Kill()
	}
	return errors.ErrUnsupported
}
