//go:build darwin

package hostos

import (
	"os"
	"syscall"
	"time"
)

// StatInfo reads native stat fields from a file's FileInfo.
func StatInfo(info os.FileInfo) Stat {
	s, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return Stat{}
	}
	return Stat{true, number(s.Blksize), number(s.Blocks), number(s.Rdev), number(s.Dev), number(s.Ino), number(s.Nlink), number(s.Uid), number(s.Gid),
		time.Unix(int64(s.Atimespec.Sec), int64(s.Atimespec.Nsec)).UTC(), time.Unix(int64(s.Ctimespec.Sec), int64(s.Ctimespec.Nsec)).UTC()}
}
