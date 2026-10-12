//go:build darwin

package hostos

import (
	"golang.org/x/sys/unix"
	"os"
	"syscall"
	"time"
)

func LinkTimes(path string, atime, mtime time.Time) error {
	return unix.UtimesNanoAt(unix.AT_FDCWD, path, []unix.Timespec{unix.NsecToTimespec(atime.UnixNano()), unix.NsecToTimespec(mtime.UnixNano())}, unix.AT_SYMLINK_NOFOLLOW)
}
func DataSync(file *os.File) error { return file.Sync() }
func LinkMode(path string, mode uint32) error {
	return unix.Fchmodat(unix.AT_FDCWD, path, mode, unix.AT_SYMLINK_NOFOLLOW)
}
func OSRelease() (string, error) { return syscall.Sysctl("kern.osrelease") }
func OSVersion() (string, error) { return syscall.Sysctl("kern.version") }

func AvailableParallelism() (int, error) {
	n, err := unix.SysctlUint32("hw.activecpu")
	return int(n), err
}

func CloneFile(source, destination string) error { return unix.Clonefile(source, destination, 0) }

func BirthInfo(info os.FileInfo) time.Time {
	if stat, ok := info.Sys().(*syscall.Stat_t); ok {
		return time.Unix(stat.Birthtimespec.Sec, stat.Birthtimespec.Nsec)
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
