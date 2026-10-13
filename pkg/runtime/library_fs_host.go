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

// Validate before traversal: removing the base (or an ancestor) must never
// partially erase its contents. Lstat preserves removal of a final symlink;
// SameFile also catches directory aliases through intermediate symlinks.
func (f *libraryFileSystem) removalPath(s string) (string, error) {
	if s == "" || filepath.Base(s) == "." || filepath.Base(s) == ".." {
		return "", errLibraryInput
	}
	// Capture the live base once, so a concurrent change_directory cannot make
	// resolution and protection refer to different working directories.
	base, ok := libraryHostPath(f.directory, ".")
	if !ok {
		return "", errLibraryInput
	}
	p, ok := libraryHostPath(base, s)
	if !ok {
		return "", errLibraryInput
	}
	clean := filepath.Clean(p)
	if filepath.Dir(clean) == clean {
		return "", errLibraryInput
	}
	// Preserve native resolution of absolute paths containing symlink/../.
	// Only strip trailing separators so a final symlink is removed as a link.
	p = strings.TrimRightFunc(p, func(c rune) bool { return c == '/' || c == rune(os.PathSeparator) })
	base, err := filepath.EvalSymlinks(base)
	if err != nil {
		return "", err
	}
	info, err := os.Lstat(p)
	if os.IsNotExist(err) {
		return p, nil
	}
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return p, nil
	}
	for {
		ancestor, err := os.Stat(base)
		if err != nil {
			return "", err
		}
		if os.SameFile(info, ancestor) {
			return "", errLibraryInput
		}
		parent := filepath.Dir(base)
		if parent == base {
			break
		}
		base = parent
	}
	return p, nil
}

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
