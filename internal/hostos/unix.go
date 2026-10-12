//go:build linux || darwin

package hostos

import (
	"os"
	"runtime"
	"syscall"
	"time"
)

func StatFS(path string) (FileSystemInfo, error) {
	var stat syscall.Statfs_t
	err := syscall.Statfs(path, &stat)
	return FileSystemInfo{int64(stat.Type), int64(stat.Bsize), int64(stat.Blocks), int64(stat.Bfree), int64(stat.Bavail), int64(stat.Files), int64(stat.Ffree)}, err
}
func FileTimes(file *os.File, atime, mtime time.Time) error {
	times := []syscall.Timeval{syscall.NsecToTimeval(atime.UnixNano()), syscall.NsecToTimeval(mtime.UnixNano())}
	return control(file, func(fd uintptr) error { return syscall.Futimes(int(fd), times) })
}
func GetPriority(pid int) (int, error) {
	n, err := syscall.Getpriority(syscall.PRIO_PROCESS, pid)
	if runtime.GOOS == "linux" {
		n = 20 - n
	}
	return n, err
}
func SetPriority(pid, priority int) error {
	return syscall.Setpriority(syscall.PRIO_PROCESS, pid, priority)
}
func ResourceUsage() (Usage, error) {
	var r syscall.Rusage
	err := syscall.Getrusage(syscall.RUSAGE_SELF, &r)
	rss := int64(r.Maxrss)
	if runtime.GOOS == "linux" {
		rss *= 1024
	}
	return Usage{r.Utime.Sec*1000000 + int64(r.Utime.Usec), r.Stime.Sec*1000000 + int64(r.Stime.Usec), rss, int64(r.Minflt), int64(r.Majflt), int64(r.Inblock), int64(r.Oublock), int64(r.Nvcsw), int64(r.Nivcsw)}, err
}
func Umask(mask int) int { return syscall.Umask(mask) }
func SetIdentity(kind string, id int) error {
	switch kind {
	case "uid":
		return syscall.Setuid(id)
	case "gid":
		return syscall.Setgid(id)
	case "euid":
		return syscall.Seteuid(id)
	case "egid":
		return syscall.Setegid(id)
	}
	return syscall.EINVAL
}
func SetGroups(groups []int) error          { return syscall.Setgroups(groups) }
func Access(path string, mode uint32) error { return syscall.Access(path, mode) }

func Exec(program string, arguments, environment []string) error {
	return syscall.Exec(program, arguments, environment)
}

func SendSignal(pid, signal int) error { return syscall.Kill(pid, syscall.Signal(signal)) }
