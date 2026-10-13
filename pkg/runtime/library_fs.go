package msruntime

import (
	"errors"
	"github.com/manuscript-lang/manuscript/internal/hostos"
	"io"
	"math/big"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

func init() {
	LibraryMethods = append(LibraryMethods, LibraryMethod{"FileSystem", "open_flags", libraryResult("FileHandle", "FileSystemError"), []LibraryParam{{"path", "String"}, {"flags", "Int64"}, {"mode", "Int"}}})
	LibraryMethods = append(LibraryMethods, []LibraryMethod{
		{"Directory", "path", "String", nil},
		{"FileHandle", "append_file", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"data", "Bytes"}}},
		{"FileSystem", "access", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"path", "String"}, {"mode", "Int"}}},
		{"FileSystem", "append_file", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"path", "String"}, {"data", "Bytes"}}},
		{"FileSystem", "chmod", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"path", "String"}, {"mode", "Int"}}},
		{"FileSystem", "chown", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"path", "String"}, {"uid", "Int64"}, {"gid", "Int64"}, {"follow_links", "Bool"}}},
		{"FileSystem", "truncate", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"path", "String"}, {"size", "Int64"}}},
		{"FileSystem", "set_times", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"path", "String"}, {"accessed", "Timestamp"}, {"modified", "Timestamp"}, {"follow_links", "Bool"}}},
		{"FileSystem", "hard_link", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"source", "String"}, {"destination", "String"}}},
		{"FileSystem", "open", libraryResult("FileHandle", "FileSystemError"), []LibraryParam{{"path", "String"}, {"flags", "String"}, {"mode", "Int"}}},
		{"FileSystem", "open_directory", libraryResult("Directory", "FileSystemError"), []LibraryParam{{"path", "String"}}},
		{"FileSystem", "copy_tree", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"source", "String"}, {"destination", "String"}, {"replace", "Bool"}, {"max_entries", "Optional[Int]"}, {"max_bytes", "Optional[Int64]"}}},
		{"FileSystem", "glob", libraryResult("List[String]", "FileSystemError"), []LibraryParam{{"path", "String"}, {"pattern", "String"}, {"max_entries", "Optional[Int]"}}},
		{"FileSystem", "watch", libraryResult("FileWatcher", "FileSystemError"), []LibraryParam{{"path", "String"}, {"recursive", "Bool"}, {"interval", "Duration"}, {"max_entries", "Optional[Int]"}}},
		{"FileSystem", "temporary", libraryResult("TemporaryDirectory", "FileSystemError"), []LibraryParam{{"prefix", "String"}}},
		{"FileHandle", "close", "Unit", []LibraryParam{}},
		{"FileHandle", "read", libraryResult("Optional[Bytes]", "FileSystemError"), []LibraryParam{{"max_bytes", "Optional[Int64]"}}},
		{"FileHandle", "write", libraryResult("Int64", "FileSystemError"), []LibraryParam{{"data", "Bytes"}}},
		{"FileHandle", "read_at", libraryResult("Bytes", "FileSystemError"), []LibraryParam{{"offset", "Int64"}, {"max_bytes", "Optional[Int64]"}}},
		{"FileHandle", "write_at", libraryResult("Int64", "FileSystemError"), []LibraryParam{{"offset", "Int64"}, {"data", "Bytes"}}},
		{"FileHandle", "read_file", libraryResult("Bytes", "FileSystemError"), []LibraryParam{{"max_bytes", "Optional[Int64]"}}},
		{"FileHandle", "write_file", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"data", "Bytes"}}},
		{"FileHandle", "read_vectors", libraryResult("List[Bytes]", "FileSystemError"), []LibraryParam{{"sizes", "List[Int]"}, {"offset", "Int64"}}},
		{"FileHandle", "write_vectors", libraryResult("Int64", "FileSystemError"), []LibraryParam{{"buffers", "List[Bytes]"}, {"offset", "Int64"}}},
		{"FileHandle", "seek", libraryResult("Int64", "FileSystemError"), []LibraryParam{{"offset", "Int64"}, {"origin", "Int"}}},
		{"FileHandle", "stat", libraryResult("FileInfo", "FileSystemError"), []LibraryParam{}},
		{"FileHandle", "truncate", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"size", "Int64"}}},
		{"FileHandle", "sync", libraryResult("Unit", "FileSystemError"), []LibraryParam{}},
		{"FileHandle", "data_sync", libraryResult("Unit", "FileSystemError"), []LibraryParam{}},
		{"FileHandle", "chmod", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"mode", "Int"}}},
		{"FileHandle", "chown", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"uid", "Int64"}, {"gid", "Int64"}}},
		{"FileHandle", "set_times", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"accessed", "Timestamp"}, {"modified", "Timestamp"}}},
		{"Directory", "close", "Unit", []LibraryParam{}},
		{"Directory", "read", libraryResult("Optional[DirectoryEntry]", "FileSystemError"), []LibraryParam{}},
		{"FileWatcher", "close", "Unit", []LibraryParam{}},
		{"FileWatcher", "next", libraryResult("List[FileEvent]", "FileSystemError"), []LibraryParam{}},
		{"TemporaryDirectory", "close", "Unit", []LibraryParam{}},
		{"TemporaryDirectory", "path", "String", []LibraryParam{}},
	}...)
}

// Stat_t fields differ by host. Reflection keeps standalone builds portable;
// absent native fields use zero, as documented in the filesystem contract.
func libraryStatInt(info os.FileInfo, name string) int64 {
	v := reflect.ValueOf(info.Sys())
	if v.Kind() == reflect.Pointer {
		v = v.Elem()
	}
	if v.Kind() != reflect.Struct {
		return 0
	}
	v = v.FieldByName(name)
	if v.IsValid() {
		if v.CanInt() {
			return v.Int()
		}
		if v.CanUint() && v.Uint() <= uint64(^uint64(0)>>1) {
			return int64(v.Uint())
		}
	}
	return 0
}
func libraryStatTime(info os.FileInfo, names ...string) libraryTimestamp {
	v := reflect.ValueOf(info.Sys())
	if v.Kind() == reflect.Pointer {
		v = v.Elem()
	}
	if v.Kind() == reflect.Struct {
		for _, name := range names {
			field := v.FieldByName(name)
			if field.Kind() == reflect.Struct {
				sec, ns := field.FieldByName("Sec"), field.FieldByName("Nsec")
				if sec.IsValid() && ns.IsValid() {
					return libraryTimestamp{time.Unix(sec.Int(), ns.Int()).UTC()}
				}
			}
		}
	}
	return libraryTimestamp{info.ModTime().UTC()}
}
func libraryPermissionBits(mode os.FileMode) int64 {
	bits := int64(mode.Perm())
	if mode&os.ModeSetuid != 0 {
		bits |= 04000
	}
	if mode&os.ModeSetgid != 0 {
		bits |= 02000
	}
	if mode&os.ModeSticky != 0 {
		bits |= 01000
	}
	return bits
}
func libraryFileMode(bits int64) os.FileMode {
	mode := os.FileMode(bits & 0777)
	if bits&04000 != 0 {
		mode |= os.ModeSetuid
	}
	if bits&02000 != 0 {
		mode |= os.ModeSetgid
	}
	if bits&01000 != 0 {
		mode |= os.ModeSticky
	}
	return mode
}
func libraryFileInfo(info os.FileInfo) Record {
	mode := libraryPermissionBits(info.Mode())
	switch {
	case info.Mode()&os.ModeSymlink != 0:
		mode |= 0120000
	case info.IsDir():
		mode |= 0040000
	case info.Mode()&os.ModeNamedPipe != 0:
		mode |= 0010000
	case info.Mode()&os.ModeSocket != 0:
		mode |= 0140000
	case info.Mode()&os.ModeCharDevice != 0:
		mode |= 0020000
	case info.Mode()&os.ModeDevice != 0:
		mode |= 0060000
	default:
		mode |= 0100000
	}
	accessed, changed := libraryStatTime(info, "Atim", "Atimespec"), libraryStatTime(info, "Ctim", "Ctimespec")
	created := hostos.BirthInfo(info)
	hasCreated := !created.IsZero()
	fields := map[string]Value{"name": info.Name(), "size": info.Size(), "directory": info.IsDir(), "symlink": info.Mode()&os.ModeSymlink != 0, "regular": info.Mode().IsRegular(), "modified": libraryTimestamp{info.ModTime().UTC()}, "accessed": accessed, "changed": changed, "mode": mode, "permissions": libraryPermissionBits(info.Mode()), "created": optional("@std/Timestamp", libraryTimestamp{created.UTC()}, hasCreated), "block_size": libraryStatInt(info, "Blksize"), "blocks": libraryStatInt(info, "Blocks"), "rdev": libraryStatInt(info, "Rdev"), "device": libraryStatInt(info, "Dev"), "inode": libraryStatInt(info, "Ino"), "links": libraryStatInt(info, "Nlink"), "uid": libraryStatInt(info, "Uid"), "gid": libraryStatInt(info, "Gid"), "fifo": info.Mode()&os.ModeNamedPipe != 0, "socket": info.Mode()&os.ModeSocket != 0, "block_device": info.Mode()&os.ModeDevice != 0 && info.Mode()&os.ModeCharDevice == 0, "char_device": info.Mode()&os.ModeCharDevice != 0}
	exact := &Map{Type: "@std/Map[String][@std/BigInt]"}
	for _, name := range []string{"size", "mode", "device", "inode", "links", "uid", "gid", "block_size", "blocks", "rdev"} {
		number := big.NewInt(nativeInteger(fields[name]))
		nativeNames := map[string]string{"device": "Dev", "inode": "Ino", "links": "Nlink", "uid": "Uid", "gid": "Gid", "rdev": "Rdev", "blocks": "Blocks", "block_size": "Blksize"}
		if nativeName := nativeNames[name]; nativeName != "" {
			value := reflect.ValueOf(info.Sys())
			if value.Kind() == reflect.Pointer {
				value = value.Elem()
			}
			if value.Kind() == reflect.Struct {
				value = value.FieldByName(nativeName)
				if value.IsValid() && value.CanUint() {
					number = new(big.Int).SetUint64(value.Uint())
				}
			}
		}
		exact.Entries = append(exact.Entries, Entry{name, libraryBigInt{number}})
	}
	for _, value := range []struct {
		name  string
		stamp time.Time
	}{{"accessed_ns", accessed.t}, {"modified_ns", info.ModTime()}, {"changed_ns", changed.t}, {"created_ns", created}} {
		name, stamp := value.name, value.stamp
		number := big.NewInt(0)
		if !stamp.IsZero() {
			number.Mul(big.NewInt(stamp.Unix()), big.NewInt(1000000000))
			number.Add(number, big.NewInt(int64(stamp.Nanosecond())))
		}
		exact.Entries = append(exact.Entries, Entry{name, libraryBigInt{number}})
	}
	fields["exact"] = exact
	return nativeHostRecord("@std/FileInfo", fields)
}
func libraryFileInfoBirth(record Record, birth time.Time) Record {
	if !birth.IsZero() {
		record.Fields["created"] = optional("@std/Timestamp", libraryTimestamp{birth.UTC()}, true)
		exact := record.Fields["exact"].(*Map)
		number := new(big.Int).Mul(big.NewInt(birth.Unix()), big.NewInt(1000000000))
		number.Add(number, big.NewInt(int64(birth.Nanosecond())))
		for i, entry := range exact.Entries {
			if entry.Key == "created_ns" {
				exact.Entries[i].Value = libraryBigInt{number}
			}
		}
		record.Fields["exact"] = exact
	}
	return record
}
func libraryWriteChunks(ctx *Execution, file *os.File, data []byte, offset *int64) (int64, error) {
	var total int64
	for len(data) > 0 {
		CheckCancelled(ctx)
		end := len(data)
		if end > 65536 {
			end = 65536
		}
		var n int
		var err error
		if offset == nil {
			n, err = file.Write(data[:end])
		} else {
			n, err = file.WriteAt(data[:end], *offset+total)
		}
		total += int64(n)
		data = data[n:]
		if err != nil {
			return total, err
		}
		if n == 0 {
			return total, io.ErrShortWrite
		}
	}
	return total, nil
}
func libraryOpenFlags(flags string) (int, bool) {
	modes := map[string]int{"r": os.O_RDONLY, "r+": os.O_RDWR, "w": os.O_WRONLY | os.O_CREATE | os.O_TRUNC, "wx": os.O_WRONLY | os.O_CREATE | os.O_EXCL, "w+": os.O_RDWR | os.O_CREATE | os.O_TRUNC, "wx+": os.O_RDWR | os.O_CREATE | os.O_EXCL, "a": os.O_WRONLY | os.O_CREATE | os.O_APPEND, "ax": os.O_WRONLY | os.O_CREATE | os.O_APPEND | os.O_EXCL, "a+": os.O_RDWR | os.O_CREATE | os.O_APPEND, "ax+": os.O_RDWR | os.O_CREATE | os.O_APPEND | os.O_EXCL}
	v, ok := modes[flags]
	return v, ok
}
func (f *libraryFileSystem) extended(ctx *Execution, r, name, p string, a []Value) Value {
	switch name {
	case "watch_native":
		return libraryNewNativeWatch(ctx, r, p, a[1].(bool), nativeInteger(a[2]), nativeInteger(a[3]), a[4].(string))
	case "stat_filesystem":
		info, err := hostos.StatFS(p)
		if err != nil {
			return libraryOSResult(r, nil, err)
		}
		return libraryOK(r, nativeHostRecord("@std/FileSystemInfo", map[string]Value{"type_id": info.Type, "block_size": info.BlockSize, "blocks": info.Blocks, "blocks_free": info.BlocksFree, "blocks_available": info.BlocksAvailable, "files": info.Files, "files_free": info.FilesFree}))
	case "chmod_link":
		mode := nativeInteger(a[1])
		if mode < 0 || mode > 07777 {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOSResult(r, Unit{}, hostos.LinkMode(p, uint32(mode)))
	case "access":
		mode := nativeInteger(a[1])
		if mode < 0 || mode > 7 {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOSResult(r, Unit{}, hostos.Access(p, uint32(mode)))
	case "append_file":
		file, err := os.OpenFile(p, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0600)
		if err != nil {
			return libraryOSResult(r, nil, err)
		}
		defer file.Close()
		_, err = libraryWriteChunks(ctx, file, a[1].(Bytes).Items, nil)
		if err == nil {
			err = file.Close()
		}
		return libraryOSResult(r, Unit{}, err)
	case "chmod":
		mode := nativeInteger(a[1])
		if mode < 0 || mode > 07777 {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOSResult(r, Unit{}, os.Chmod(p, libraryFileMode(mode)))
	case "chown":
		uid, gid := nativeInteger(a[1]), nativeInteger(a[2])
		if uid < -1 || gid < -1 || uid > 2147483647 || gid > 2147483647 {
			return libraryError(r, "InvalidInput", "")
		}
		var err error
		if a[3].(bool) {
			err = os.Chown(p, int(uid), int(gid))
		} else {
			err = os.Lchown(p, int(uid), int(gid))
		}
		return libraryOSResult(r, Unit{}, err)
	case "set_times":
		if !a[3].(bool) {
			return libraryOSResult(r, Unit{}, hostos.LinkTimes(p, a[1].(libraryTimestamp).t, a[2].(libraryTimestamp).t))
		}
		return libraryOSResult(r, Unit{}, os.Chtimes(p, a[1].(libraryTimestamp).t, a[2].(libraryTimestamp).t))
	case "truncate":
		size := nativeInteger(a[1])
		if size < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOSResult(r, Unit{}, os.Truncate(p, size))
	case "hard_link":
		dest, ok := f.path(a[1].(string))
		if !ok {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOSResult(r, Unit{}, os.Link(p, dest))
	case "open", "open_flags":
		flags, ok := 0, true
		if name == "open" {
			flags, ok = libraryOpenFlags(a[1].(string))
		} else {
			value := nativeInteger(a[1])
			if value < 0 || value > 2147483647 {
				ok = false
			} else {
				flags = int(value)
			}
		}
		mode := nativeInteger(a[2])
		if !ok || mode < 0 || mode > 07777 {
			return libraryError(r, "InvalidInput", "")
		}
		file, err := os.OpenFile(p, flags, libraryFileMode(mode))
		if err != nil {
			return libraryOSResult(r, nil, err)
		}
		if ctx.Context.Err() != nil {
			file.Close()
			CheckCancelled(ctx)
		}
		return libraryOK(r, ViewOf("@std/FileHandle", &libraryFileHandle{file: file, noRead: flags&3 == os.O_WRONLY, noWrite: flags&3 == os.O_RDONLY}))
	case "open_directory":
		file, err := os.Open(p)
		if err != nil {
			return libraryOSResult(r, nil, err)
		}
		info, err := file.Stat()
		if err != nil || !info.IsDir() {
			file.Close()
			if err == nil {
				err = errors.New("not a directory")
			}
			return libraryOSResult(r, nil, err)
		}
		if ctx.Context.Err() != nil {
			file.Close()
			CheckCancelled(ctx)
		}
		return libraryOK(r, ViewOf("@std/Directory", &libraryDirectory{file: file}))
	case "copy_tree":
		dest, ok := f.path(a[1].(string))
		entries, bytes := nativeInteger(a[3]), nativeInteger(a[4])
		if !ok || entries < 0 || bytes < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		source, err := filepath.EvalSymlinks(p)
		if err != nil {
			return libraryOSResult(r, nil, err)
		}
		// Resolve existing destination ancestors to prevent copying into the source
		// through a symlink. Walking never follows source symlinks.
		ancestor := dest
		var suffix []string
		for {
			_, err = os.Lstat(ancestor)
			if err == nil {
				break
			}
			if !errors.Is(err, os.ErrNotExist) {
				return libraryOSResult(r, nil, err)
			}
			parent := filepath.Dir(ancestor)
			if parent == ancestor {
				return libraryError(r, "InvalidInput", "")
			}
			suffix = append(suffix, filepath.Base(ancestor))
			ancestor = parent
		}
		real, err := filepath.EvalSymlinks(ancestor)
		if err != nil {
			return libraryOSResult(r, nil, err)
		}
		for i := len(suffix) - 1; i >= 0; i-- {
			real = filepath.Join(real, suffix[i])
		}
		rel, err := filepath.Rel(source, real)
		if err == nil && (rel == "." || rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator))) {
			return libraryError(r, "InvalidInput", "")
		}
		err = libraryCopyTree(ctx, p, dest, a[2].(bool), &entries, &bytes)
		if errors.Is(err, errLibraryLimit) {
			return libraryError(r, "LimitExceeded", "")
		}
		return libraryOSResult(r, Unit{}, err)
	case "glob":
		pattern := a[1].(string)
		max := nativeInteger(a[2])
		if max < 0 || !libraryValidGlob(pattern) {
			return libraryError(r, "InvalidInput", "")
		}
		var items []string
		err := filepath.WalkDir(p, func(child string, e os.DirEntry, err error) error {
			CheckCancelled(ctx)
			if err != nil {
				return err
			}
			rel, err := filepath.Rel(p, child)
			if err != nil {
				return err
			}
			if !utf8.ValidString(rel) {
				return errLibraryEncoding
			}
			if rel != "." && libraryGlobMatch(filepath.ToSlash(rel), pattern) {
				if int64(len(items)) >= max {
					return errLibraryLimit
				}
				items = append(items, rel)
			}
			return nil
		})
		if errors.Is(err, errLibraryLimit) {
			return libraryError(r, "LimitExceeded", "")
		}
		if errors.Is(err, errLibraryEncoding) {
			return libraryError(r, "Unsupported", "")
		}
		if err != nil {
			return libraryOSResult(r, nil, err)
		}
		sort.Strings(items)
		return libraryOK(r, libraryStrings(items))
	case "watch":
		interval := a[2].(Duration)
		max := nativeInteger(a[3])
		if interval <= 0 || max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		snapshot, err := librarySnapshot(ctx, p, a[1].(bool), max)
		if err != nil {
			return librarySnapshotError(r, err)
		}
		w := &libraryWatcher{path: p, recursive: a[1].(bool), interval: time.Duration(interval), max: max, snapshot: snapshot, done: make(chan struct{}), gate: make(chan struct{}, 1)}
		return libraryOK(r, ViewOf("@std/FileWatcher", w))
	}
	return Panic("unknown filesystem operation " + name)
}

var errLibraryLimit = errors.New("library limit exceeded")
var errLibraryEncoding = errors.New("filename is not UTF-8")

func libraryCopyTree(ctx *Execution, source, dest string, replace bool, entries, bytes *int64) error {
	CheckCancelled(ctx)
	if *entries == 0 {
		return errLibraryLimit
	}
	*entries--
	info, err := os.Lstat(source)
	if err != nil {
		return err
	}
	if old, err := os.Lstat(dest); err == nil {
		if os.SameFile(info, old) {
			return errors.New("source and destination are the same file")
		}
		if !replace {
			return os.ErrExist
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 {
		target, err := os.Readlink(source)
		if err != nil {
			return err
		}
		if replace {
			if err = os.Remove(dest); err != nil && !errors.Is(err, os.ErrNotExist) {
				return err
			}
		}
		return os.Symlink(target, dest)
	}
	if info.IsDir() {
		if old, err := os.Lstat(dest); err == nil && !old.IsDir() {
			return errors.New("destination is not a directory")
		}
		if err = os.Mkdir(dest, info.Mode().Perm()); err != nil && !errors.Is(err, os.ErrExist) {
			return err
		}
		dir, err := os.Open(source)
		if err != nil {
			return err
		}
		defer dir.Close()
		for {
			batch, err := dir.ReadDir(64)
			for _, entry := range batch {
				if err := libraryCopyTree(ctx, filepath.Join(source, entry.Name()), filepath.Join(dest, entry.Name()), replace, entries, bytes); err != nil {
					return err
				}
			}
			if err == io.EOF {
				break
			}
			if err != nil {
				return err
			}
		}
		return nil
	}
	if !info.Mode().IsRegular() {
		return errors.New("copy_tree requires regular files, directories, or symlinks")
	}
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	defer in.Close()
	flags := os.O_CREATE | os.O_WRONLY | os.O_EXCL
	if replace {
		if err := os.Remove(dest); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	out, err := os.OpenFile(dest, flags, info.Mode().Perm())
	if err != nil {
		return err
	}
	defer out.Close()
	buffer := make([]byte, 65536)
	for {
		CheckCancelled(ctx)
		n, err := in.Read(buffer)
		if int64(n) > *bytes {
			return errLibraryLimit
		}
		if n > 0 {
			if _, e := libraryWriteChunks(ctx, out, buffer[:n], nil); e != nil {
				return e
			}
			*bytes -= int64(n)
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
	}
	return out.Close()
}

// FileHandle serializes offset-changing operations. Close first closes the OS
// descriptor to interrupt pollable I/O, then joins admitted calls.
type libraryFileHandle struct {
	mu     sync.Mutex
	file   *os.File
	closed bool
	// noRead and noWrite record the open mode so misuse is InvalidInput on
	// every host instead of a platform-specific errno.
	noRead, noWrite bool
	active          sync.WaitGroup
	released        chan struct{}
	gate            chan struct{}
	// ahead holds bytes read_line took from the reader beyond the current line.
	ahead []byte
}

// rewindAhead returns read-ahead bytes to the file so position-based operations see them.
func (h *libraryFileHandle) rewindAhead() {
	h.mu.Lock()
	ahead := h.ahead
	h.ahead = nil
	h.mu.Unlock()
	if len(ahead) > 0 {
		h.file.Seek(-int64(len(ahead)), io.SeekCurrent)
	}
}

func (h *libraryFileHandle) close() {
	h.mu.Lock()
	if h.released == nil {
		h.released = make(chan struct{})
	}
	done := h.released
	if h.closed {
		h.mu.Unlock()
		<-done
		return
	}
	h.closed = true
	h.mu.Unlock()
	h.file.Close()
	h.active.Wait()
	close(done)
}
func (h *libraryFileHandle) Operation(name string) Function {
	return libraryMethod("FileHandle", name, func(ctx *Execution, r string, a []Value) Value {
		if name == "reader" || name == "writer" {
			typ := "@std/ReadStream"
			if name == "writer" {
				typ = "@std/WriteStream"
			}
			return ViewOf(typ, libraryHandleStream{handle: h, write: name == "writer"})
		}
		if name == "read_lines" {
			max, lines := nativeInteger(a[0]), nativeInteger(a[1])
			if max < 0 || lines < 0 {
				return libraryError(r, "InvalidInput", "")
			}
			v := h.Operation("read_file").Body(ctx, []Value{max}).(Alternative)
			if v.Tag == "error" {
				return Alternative{r, "error", v.Fields}
			}
			data := v.Fields[0].(Bytes).Items
			if !utf8.Valid(data) {
				return libraryError(r, "InvalidData", "")
			}
			var items []Value
			if len(data) > 0 {
				parts := strings.Split(string(data), "\n")
				if parts[len(parts)-1] == "" {
					parts = parts[:len(parts)-1]
				}
				if int64(len(parts)) > lines {
					return libraryError(r, "LimitExceeded", "")
				}
				for _, line := range parts {
					items = append(items, strings.TrimSuffix(line, "\r"))
				}
			}
			return libraryOK(r, libraryList("String", items))
		}
		if name == "close" {
			h.close()
			return Unit{}
		}
		h.mu.Lock()
		if h.gate == nil {
			h.gate = make(chan struct{}, 1)
		}
		gate := h.gate
		closed := h.closed
		h.mu.Unlock()
		if closed {
			return libraryError(r, "Closed", "")
		}
		select {
		case gate <- struct{}{}:
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		}
		defer func() { <-gate }()
		h.mu.Lock()
		if h.closed {
			h.mu.Unlock()
			return libraryError(r, "Closed", "")
		}
		h.active.Add(1)
		h.mu.Unlock()
		defer h.active.Done()
		CheckCancelled(ctx)
		h.rewindAhead()
		stop := libraryInterrupt(ctx, func(t time.Time) error { h.file.SetReadDeadline(t); return h.file.SetWriteDeadline(t) })
		defer stop()
		finish := func(v Value, err error) Value {
			CheckCancelled(ctx)
			h.mu.Lock()
			closed := h.closed
			h.mu.Unlock()
			if closed {
				return libraryError(r, "Closed", "")
			}
			return libraryOSResult(r, v, err)
		}
		switch name {
		case "read", "read_at", "read_file", "read_vectors":
			if h.noRead {
				return libraryError(r, "InvalidInput", "")
			}
		case "write", "write_file", "write_at", "append_file", "write_vectors", "truncate":
			if h.noWrite {
				return libraryError(r, "InvalidInput", "")
			}
		}
		switch name {
		case "read", "read_at":
			at := int64(0)
			n := nativeInteger(a[0])
			if name == "read_at" {
				at = n
				n = nativeInteger(a[1])
			}
			if n <= 0 || at < 0 {
				return libraryError(r, "InvalidInput", "")
			}
			if n > 65536 {
				n = 65536
			}
			data := make([]byte, int(n))
			var count int
			var err error
			if name == "read" {
				count, err = h.file.Read(data)
			} else {
				count, err = h.file.ReadAt(data, at)
			}
			eof := err == io.EOF
			if eof {
				err = nil
			}
			if name == "read" {
				return finish(optional("@std/Bytes", Bytes{data[:count]}, !(count == 0 && eof)), err)
			}
			return finish(Bytes{data[:count]}, err)
		case "read_file":
			n := nativeInteger(a[0])
			if n < 0 {
				return libraryError(r, "InvalidInput", "")
			}
			b, code := libraryReadBounded(ctx, h.file, n)
			if code != "" {
				return libraryError(r, code, "")
			}
			return finish(Bytes{b}, nil)
		case "write", "write_file", "write_at", "append_file":
			var offset *int64
			data := a[0]
			if name == "write_at" {
				v := nativeInteger(a[0])
				if v < 0 {
					return libraryError(r, "InvalidInput", "")
				}
				offset = &v
				data = a[1]
			}
			n, err := libraryWriteChunks(ctx, h.file, data.(Bytes).Items, offset)
			if name == "write_file" || name == "append_file" {
				return finish(Unit{}, err)
			}
			return finish(n, err)
		case "read_vectors":
			sizes := a[0].(*List).Items
			offset := nativeInteger(a[1])
			var total int64
			if offset < -1 {
				return libraryError(r, "InvalidInput", "")
			}
			for _, v := range sizes {
				n := nativeInteger(v)
				if n < 0 || n > 65536 || total > 16*1024*1024-n {
					return libraryError(r, "InvalidInput", "")
				}
				total += n
			}
			var result []Value
			for _, v := range sizes {
				CheckCancelled(ctx)
				b := make([]byte, int(nativeInteger(v)))
				var n int
				var err error
				if offset == -1 {
					n, err = h.file.Read(b)
				} else {
					n, err = h.file.ReadAt(b, offset)
					offset += int64(n)
				}
				result = append(result, Bytes{b[:n]})
				if err != nil && err != io.EOF {
					return finish(nil, err)
				}
			}
			return finish(libraryList("@std/Bytes", result), nil)
		case "write_vectors":
			offset := nativeInteger(a[1])
			if offset < -1 {
				return libraryError(r, "InvalidInput", "")
			}
			var total int64
			for _, v := range a[0].(*List).Items {
				var ptr *int64
				if offset != -1 {
					ptr = &offset
				}
				n, err := libraryWriteChunks(ctx, h.file, v.(Bytes).Items, ptr)
				total += n
				if offset != -1 {
					offset += n
				}
				if err != nil {
					return finish(nil, err)
				}
			}
			return finish(total, nil)
		case "seek":
			origin := nativeInteger(a[1])
			if origin < 0 || origin > 2 {
				return libraryError(r, "InvalidInput", "")
			}
			if nativeInteger(a[0]) < 0 && origin == 0 {
				return libraryError(r, "InvalidInput", "")
			}
			n, err := h.file.Seek(nativeInteger(a[0]), int(origin))
			return finish(n, err)
		case "stat":
			info, err := h.file.Stat()
			if err != nil {
				return finish(nil, err)
			}
			if !utf8.ValidString(info.Name()) {
				return libraryError(r, "Unsupported", "")
			}
			h.mu.Lock()
			if h.closed {
				h.mu.Unlock()
				return libraryError(r, "Closed", "")
			}
			birth := hostos.BirthFile(h.file)
			h.mu.Unlock()
			return finish(libraryFileInfoBirth(libraryFileInfo(info), birth), nil)
		case "truncate":
			n := nativeInteger(a[0])
			if n < 0 {
				return libraryError(r, "InvalidInput", "")
			}
			return finish(Unit{}, h.file.Truncate(n))
		case "sync":
			return finish(Unit{}, h.file.Sync())
		case "data_sync":
			h.mu.Lock()
			if h.closed {
				h.mu.Unlock()
				return libraryError(r, "Closed", "")
			}
			err := hostos.DataSync(h.file)
			h.mu.Unlock()
			return finish(Unit{}, err)
		case "chmod":
			n := nativeInteger(a[0])
			if n < 0 || n > 07777 {
				return libraryError(r, "InvalidInput", "")
			}
			return finish(Unit{}, h.file.Chmod(libraryFileMode(n)))
		case "chown":
			uid, gid := nativeInteger(a[0]), nativeInteger(a[1])
			if uid < -1 || gid < -1 || uid > 2147483647 || gid > 2147483647 {
				return libraryError(r, "InvalidInput", "")
			}
			return finish(Unit{}, h.file.Chown(int(uid), int(gid)))
		case "set_times":
			h.mu.Lock()
			if h.closed {
				h.mu.Unlock()
				return libraryError(r, "Closed", "")
			}
			err := libraryFileTimes(h.file, a[0].(libraryTimestamp).t, a[1].(libraryTimestamp).t)
			h.mu.Unlock()
			if errors.Is(err, errors.ErrUnsupported) {
				return libraryError(r, "Unsupported", "")
			}
			return finish(Unit{}, err)
		}
		return Panic("unknown file operation")
	})
}

type libraryDirectory struct {
	mu     sync.Mutex
	file   *os.File
	closed bool
}

func (d *libraryDirectory) Operation(name string) Function {
	return libraryMethod("Directory", name, func(ctx *Execution, r string, _ []Value) Value {
		d.mu.Lock()
		defer d.mu.Unlock()
		if name == "path" {
			return d.file.Name()
		}
		if name == "close" {
			if !d.closed {
				d.closed = true
				d.file.Close()
			}
			return Unit{}
		}
		if d.closed {
			return libraryError(r, "Closed", "")
		}
		CheckCancelled(ctx)
		entries, err := d.file.ReadDir(1)
		CheckCancelled(ctx)
		if err == io.EOF {
			return libraryOK(r, optional("@std/DirectoryEntry", nil, false))
		}
		if err != nil {
			return libraryOSResult(r, nil, err)
		}
		entry := entries[0]
		if !utf8.ValidString(entry.Name()) {
			return libraryError(r, "Unsupported", "")
		}
		return libraryOK(r, optional("@std/DirectoryEntry", Record{"@std/DirectoryEntry", map[string]Value{"name": entry.Name(), "directory": entry.IsDir(), "symlink": entry.Type()&os.ModeSymlink != 0}}, true))
	})
}

type libraryTemporary struct {
	mu     sync.Mutex
	path   string
	closed bool
}

func (t *libraryTemporary) Operation(name string) Function {
	return libraryMethod("TemporaryDirectory", name, func(ctx *Execution, _ string, _ []Value) Value {
		t.mu.Lock()
		defer t.mu.Unlock()
		if name == "path" {
			return t.path
		}
		if !t.closed {
			if err := libraryRemoveTree(ctx, t.path); err != nil {
				Panic(err.Error())
			}
			t.closed = true
		}
		return Unit{}
	})
}

type libraryWatchStamp struct {
	mode     os.FileMode
	size     int64
	modified time.Time
}
type libraryWatcher struct {
	mu        sync.Mutex
	path      string
	recursive bool
	interval  time.Duration
	max       int64
	snapshot  map[string]libraryWatchStamp
	done      chan struct{}
	closed    bool
	gate      chan struct{}
}

func librarySnapshot(ctx *Execution, p string, recursive bool, max int64) (map[string]libraryWatchStamp, error) {
	snapshot := map[string]libraryWatchStamp{}
	err := filepath.WalkDir(p, func(child string, e os.DirEntry, err error) error {
		CheckCancelled(ctx)
		if err != nil {
			return err
		}
		if int64(len(snapshot)) >= max {
			return errLibraryLimit
		}
		if !utf8.ValidString(child) {
			return errLibraryEncoding
		}
		info, err := e.Info()
		if err != nil {
			return err
		}
		snapshot[child] = libraryWatchStamp{info.Mode(), info.Size(), info.ModTime()}
		if child != p && e.IsDir() && !recursive {
			return filepath.SkipDir
		}
		return nil
	})
	return snapshot, err
}
func librarySnapshotError(r string, err error) Value {
	if errors.Is(err, errLibraryLimit) {
		return libraryError(r, "LimitExceeded", "")
	}
	if errors.Is(err, errLibraryEncoding) {
		return libraryError(r, "Unsupported", "")
	}
	return libraryOSResult(r, nil, err)
}
func (w *libraryWatcher) Operation(name string) Function {
	return libraryMethod("FileWatcher", name, func(ctx *Execution, r string, _ []Value) Value {
		if name == "close" {
			w.mu.Lock()
			if !w.closed {
				w.closed = true
				close(w.done)
			}
			w.mu.Unlock()
			w.gate <- struct{}{}
			<-w.gate
			return Unit{}
		}
		select {
		case w.gate <- struct{}{}:
		case <-w.done:
			return libraryError(r, "Closed", "")
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		}
		defer func() { <-w.gate }()
		timer := time.NewTimer(w.interval)
		defer timer.Stop()
		for {
			select {
			case <-w.done:
				return libraryError(r, "Closed", "")
			case <-ctx.Context.Done():
				CheckCancelled(ctx)
			case <-timer.C:
			}
			now, err := librarySnapshot(ctx, w.path, w.recursive, w.max)
			if errors.Is(err, os.ErrNotExist) {
				now = map[string]libraryWatchStamp{}
				err = nil
			}
			if err != nil {
				return librarySnapshotError(r, err)
			}
			changes := map[string]string{}
			for p, stamp := range now {
				old, ok := w.snapshot[p]
				if !ok {
					changes[p] = "rename"
				} else if old != stamp {
					changes[p] = "change"
				}
			}
			for p := range w.snapshot {
				if _, ok := now[p]; !ok {
					changes[p] = "rename"
				}
			}
			w.snapshot = now
			if len(changes) > 0 {
				keys := make([]string, 0, len(changes))
				for p := range changes {
					keys = append(keys, p)
				}
				sort.Strings(keys)
				items := make([]Value, 0, len(keys))
				for _, p := range keys {
					items = append(items, Record{"@std/FileEvent", map[string]Value{"path": p, "kind": changes[p]}})
				}
				return libraryOK(r, libraryList("@std/FileEvent", items))
			}
			timer.Reset(w.interval)
		}
	})
}

type libraryHandleStream struct {
	handle *libraryFileHandle
	write  bool
}

func (s libraryHandleStream) Operation(name string) Function {
	if name == "close" {
		return s.handle.Operation("close")
	}
	result := "@std/Result[@std/Optional[@std/Bytes]][@std/IoError]"
	params := []string{"max_bytes"}
	operation := name
	if s.write {
		result = "@std/Result[Unit][@std/IoError]"
		params = []string{"data"}
		if name == "flush" {
			params = nil
			operation = "sync"
		} else {
			operation = "write_file"
		}
	}
	return NewFunction(params, result, func(ctx *Execution, a []Value) Value {
		if name == "read" && !s.write {
			s.handle.mu.Lock()
			if ahead := s.handle.ahead; len(ahead) > 0 {
				take := len(ahead)
				if n, ok := nativeIntegerValue(a[0]); ok && n > 0 && int(n) < take {
					take = int(n)
				}
				s.handle.ahead = ahead[take:]
				s.handle.mu.Unlock()
				return Alternative{result, "ok", []Value{optional("@std/Bytes", Bytes{ahead[:take:take]}, true)}}
			}
			s.handle.mu.Unlock()
		}
		value := s.handle.Operation(operation).Body(ctx, a).(Alternative)
		if value.Tag == "ok" {
			return Alternative{result, "ok", value.Fields}
		}
		failure := value.Fields[0].(Alternative)
		tag := failure.Tag
		if tag != "Closed" && tag != "InvalidInput" {
			tag = "Failed"
		}
		message := failure.Tag
		if failure.Tag == "Failed" {
			message = failure.Fields[0].(string)
		}
		return ioError(result, tag, message)
	})
}
