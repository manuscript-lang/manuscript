package msruntime

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/manuscript-lang/manuscript/internal/hostos"
)

func init() {
	libraryAdd("fs", "constants", "Map[String][Int]", nil, func(_ *Execution, _ string, _ []Value) Value {
		return libraryConstants(hostos.FileConstants())
	})
	LibraryMethods = append(LibraryMethods, []LibraryMethod{
		{"FileSystem", "stat_filesystem", libraryResult("FileSystemInfo", "FileSystemError"), []LibraryParam{{"path", "String"}}},
		{"FileSystem", "chmod_link", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"path", "String"}, {"mode", "Int"}}},
		{"FileHandle", "read_lines", libraryResult("List[String]", "FileSystemError"), []LibraryParam{{"max_bytes", "Optional[Int]"}, {"max_lines", "Optional[Int]"}}},
		{"FileHandle", "reader", "ReadStream", nil},
		{"FileHandle", "writer", "WriteStream", nil},
	}...)
}

var libraryDirectoryMu sync.Mutex

// Kept here so host path operations can consistently use a live directory after
// ProcessControl.change_directory, while explicitly constructed fakes stay pinned.
func libraryHostPath(directory, s string) (string, bool) {
	if strings.ContainsRune(s, 0) {
		return "", false
	}
	if filepath.IsAbs(s) {
		return s, true
	}
	if directory == "" {
		libraryDirectoryMu.Lock()
		defer libraryDirectoryMu.Unlock()
		var err error
		directory, err = os.Getwd()
		if err != nil {
			return "", false
		}
	}
	return filepath.Join(directory, s), true
}

func libraryFileTimes(file *os.File, accessed, modified time.Time) error {
	return hostos.FileTimes(file, accessed, modified)
}

func libraryConstants(values map[string]int64) *Map {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sortStrings(keys)
	result := &Map{Type: "@std/Map[String][Int]"}
	for _, key := range keys {
		result.Entries = append(result.Entries, Entry{key, values[key]})
	}
	return result
}

func libraryInterrupt(ctx *Execution, deadline func(time.Time) error) func() {
	done := make(chan struct{})
	stop := context.AfterFunc(ctx.Context, func() { defer close(done); deadline(time.Now()) })
	return func() {
		if !stop() {
			<-done
		}
		deadline(time.Time{})
	}
}
