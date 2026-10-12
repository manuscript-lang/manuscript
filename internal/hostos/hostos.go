// Package hostos contains platform calls needed by the capability runtime. It is
// bundled alongside vendored dependencies for CGO-free standalone builds.
package hostos

import "os"

type FileSystemInfo struct{ Type, BlockSize, Blocks, BlocksFree, BlocksAvailable, Files, FilesFree int64 }
type Usage struct{ User, System, MaxRSS, MinorFaults, MajorFaults, Reads, Writes, VoluntarySwitches, InvoluntarySwitches int64 }

// Control borrows the descriptor without File.Fd's transition to blocking I/O,
// preserving deadline/cancellation support for pollable files and streams.
func control(file *os.File, operation func(uintptr) error) error {
	raw, err := file.SyscallConn()
	if err != nil {
		return err
	}
	var outcome error
	if err = raw.Control(func(fd uintptr) { outcome = operation(fd) }); err != nil {
		return err
	}
	return outcome
}
