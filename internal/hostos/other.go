//go:build !linux && !darwin && !windows

package hostos

import (
	"errors"
	"os"
	"runtime"
	"syscall"
	"time"
)

func StatFS(string) (FileSystemInfo, error)          { return FileSystemInfo{}, errors.ErrUnsupported }
func FileTimes(*os.File, time.Time, time.Time) error { return errors.ErrUnsupported }
func GetPriority(int) (int, error)                   { return 0, errors.ErrUnsupported }
func SetPriority(int, int) error                     { return errors.ErrUnsupported }
func ResourceUsage() (Usage, error)                  { return Usage{}, errors.ErrUnsupported }
func Umask(int) int                                  { return -1 }
func SetIdentity(string, int) error                  { return errors.ErrUnsupported }
func SetGroups([]int) error                          { return errors.ErrUnsupported }
func LinkTimes(string, time.Time, time.Time) error   { return errors.ErrUnsupported }
func DataSync(file *os.File) error                   { return file.Sync() }
func LinkMode(string, uint32) error                  { return errors.ErrUnsupported }
func OSRelease() (string, error)                     { return "", errors.ErrUnsupported }
func OSVersion() (string, error)                     { return "", errors.ErrUnsupported }
func Access(path string, mode uint32) error {
	_, err := os.Stat(path)
	if err != nil {
		return err
	}
	if mode != 0 {
		return errors.ErrUnsupported
	}
	return nil
}

func Constants() map[string]int64 { return map[string]int64{"SIGINT": 2, "SIGTERM": 15} }

func Exec(string, []string, []string) error { return errors.ErrUnsupported }

func AvailableParallelism() (int, error) { return runtime.NumCPU(), nil }

func CloneFile(string, string) error { return errors.ErrUnsupported }

func BirthInfo(os.FileInfo) time.Time  { return time.Time{} }
func BirthPath(string, bool) time.Time { return time.Time{} }
func BirthFile(*os.File) time.Time     { return time.Time{} }

func FileConstants() map[string]int64 {
	return map[string]int64{"O_RDONLY": int64(os.O_RDONLY), "O_WRONLY": int64(os.O_WRONLY), "O_RDWR": int64(os.O_RDWR), "O_APPEND": int64(os.O_APPEND), "O_EXCL": int64(os.O_EXCL), "O_SYNC": int64(os.O_SYNC), "O_TRUNC": int64(os.O_TRUNC), "O_CREAT": int64(os.O_CREATE), "F_OK": 0, "R_OK": 4, "W_OK": 2, "X_OK": 1, "COPYFILE_EXCL": 1, "COPYFILE_FICLONE": 2, "COPYFILE_FICLONE_FORCE": 4}
}

func ProcessTitle() (string, error) { return "", errors.ErrUnsupported }
func SetProcessTitle(string) error  { return errors.ErrUnsupported }

func SendSignal(pid, signal int) error {
	process, err := os.FindProcess(pid)
	if err != nil {
		return err
	}
	defer process.Release()
	return process.Signal(syscall.Signal(signal))
}
