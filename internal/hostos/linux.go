//go:build linux

package hostos

import (
	"golang.org/x/sys/unix"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func LinkTimes(path string, atime, mtime time.Time) error {
	return unix.UtimesNanoAt(unix.AT_FDCWD, path, []unix.Timespec{unix.NsecToTimespec(atime.UnixNano()), unix.NsecToTimespec(mtime.UnixNano())}, unix.AT_SYMLINK_NOFOLLOW)
}
func AvailableParallelism() (int, error) {
	var set unix.CPUSet
	if err := unix.SchedGetaffinity(0, &set); err != nil {
		return 0, err
	}
	return set.Count(), nil
}
func DataSync(file *os.File) error {
	return control(file, func(fd uintptr) error { return syscall.Fdatasync(int(fd)) })
}
func LinkMode(path string, mode uint32) error { return syscall.ENOTSUP }
func OSRelease() (string, error) {
	data, err := os.ReadFile("/proc/sys/kernel/osrelease")
	return string(data), err
}
func OSVersion() (string, error) {
	data, err := os.ReadFile("/proc/sys/kernel/version")
	return string(data), err
}

func CloneFile(source, destination string) error {
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	info, err := input.Stat()
	if err != nil {
		return err
	}
	output, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, info.Mode())
	if err != nil {
		return err
	}
	defer output.Close()
	if err = unix.IoctlFileClone(int(output.Fd()), int(input.Fd())); err != nil {
		output.Close()
		os.Remove(destination)
		return err
	}
	return output.Close()
}

func BirthPath(path string, follow bool) time.Time {
	flags := 0
	if !follow {
		flags = unix.AT_SYMLINK_NOFOLLOW
	}
	var stat unix.Statx_t
	if err := unix.Statx(unix.AT_FDCWD, path, flags, unix.STATX_BTIME, &stat); err != nil || stat.Mask&unix.STATX_BTIME == 0 {
		return time.Time{}
	}
	return time.Unix(stat.Btime.Sec, int64(stat.Btime.Nsec))
}
func BirthFile(file *os.File) time.Time {
	var stat unix.Statx_t
	err := control(file, func(fd uintptr) error { return unix.Statx(int(fd), "", unix.AT_EMPTY_PATH, unix.STATX_BTIME, &stat) })
	if err != nil || stat.Mask&unix.STATX_BTIME == 0 {
		return time.Time{}
	}
	return time.Unix(stat.Btime.Sec, int64(stat.Btime.Nsec))
}
func BirthInfo(os.FileInfo) time.Time { return time.Time{} }

func ProcessTitle() (string, error) {
	data, err := os.ReadFile("/proc/self/task/" + strconv.Itoa(os.Getpid()) + "/comm")
	return strings.TrimSuffix(string(data), "\n"), err
}
func SetProcessTitle(title string) error {
	if len(title) > 15 {
		return syscall.ENAMETOOLONG
	}
	return os.WriteFile("/proc/self/task/"+strconv.Itoa(os.Getpid())+"/comm", []byte(title), 0600)
}
