package msruntime

import (
	"errors"
	"io"
	"math/big"
	"os"
	"path/filepath"
	goruntime "runtime"
	"sort"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"

	"github.com/manuscript-lang/manuscript/internal/hostos"
)

// Fs_Constants is the fs.constants table of host file constants.
func Fs_Constants(*Execution) *Map[string, int] { return constantsMap(hostos.FileConstants()) }

func constantsMap(values map[string]int64) *Map[string, int] {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	result := NewMap[string, int]()
	for _, key := range keys {
		result.Put(key, int(values[key]))
	}
	return result
}

// bigIntOf builds the BigInt a FileInfo.Exact entry holds.
func bigIntOf(n *big.Int) *BigInt { return &BigInt{n} }

type osErrorKind int

const (
	kindFailed osErrorKind = iota
	kindInvalidInput
	kindUnsupported
	kindNotFound
	kindNotEmpty
	kindAlreadyExists
	kindPermissionDenied
)

// notEmpty reports a directory-not-empty failure. Windows reports
// ERROR_DIR_NOT_EMPTY (145), which Go classifies as os.ErrExist.
func notEmpty(err error) bool {
	if errors.Is(err, syscall.ENOTEMPTY) {
		return true
	}
	var errno syscall.Errno
	return goruntime.GOOS == "windows" && errors.As(err, &errno) && errno == 145
}

// classifyOS maps an operating-system error to the shared failure kinds. Only
// the filesystem domain distinguishes a non-empty directory.
func classifyOS(err error, filesystem bool) osErrorKind {
	switch {
	case errors.Is(err, errInvalidInput):
		return kindInvalidInput
	case errors.Is(err, errors.ErrUnsupported):
		return kindUnsupported
	case errors.Is(err, os.ErrNotExist):
		return kindNotFound
	case filesystem && notEmpty(err):
		return kindNotEmpty
	case errors.Is(err, os.ErrExist):
		return kindAlreadyExists
	case errors.Is(err, syscall.EISDIR), errors.Is(err, syscall.ENOTDIR), errors.Is(err, syscall.EBADF), errors.Is(err, syscall.EINVAL):
		return kindInvalidInput
	case errors.Is(err, os.ErrPermission):
		return kindPermissionDenied
	}
	return kindFailed
}

func fsErrorOf(err error) FileSystemError {
	switch classifyOS(err, true) {
	case kindInvalidInput:
		return FileSystemError_InvalidInput{}
	case kindUnsupported:
		return FileSystemError_Unsupported{}
	case kindNotFound:
		return FileSystemError_NotFound{}
	case kindNotEmpty:
		return FileSystemError_NotEmpty{}
	case kindAlreadyExists:
		return FileSystemError_AlreadyExists{}
	case kindPermissionDenied:
		return FileSystemError_PermissionDenied{}
	}
	return FileSystemError_Failed{Message: err.Error()}
}

func fsFail[T any](e FileSystemError) Result[T, FileSystemError] {
	return Fail[T, FileSystemError](e)
}

func fsInvalid[T any]() Result[T, FileSystemError] { return fsFail[T](FileSystemError_InvalidInput{}) }

// fsDone is the Result of an operation that produced value or err.
func fsDone[T any](value T, err error) Result[T, FileSystemError] {
	if err != nil {
		return fsFail[T](fsErrorOf(err))
	}
	return Ok[T, FileSystemError](value)
}

func fsOK[T any](value T) Result[T, FileSystemError] { return Ok[T, FileSystemError](value) }

func fsUnit(err error) Result[Unit, FileSystemError] { return fsDone(Unit{}, err) }

// readFailure maps a bounded-read failure code to its filesystem error.
func readFailure(code string) FileSystemError {
	switch code {
	case "LimitExceeded":
		return FileSystemError_LimitExceeded{}
	case "InvalidData":
		return FileSystemError_InvalidData{}
	}
	return FileSystemError_Failed{}
}

func permissionBits(mode os.FileMode) int {
	bits := int(mode.Perm())
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

func fileMode(bits int) os.FileMode {
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

func statTime(stamp time.Time, info os.FileInfo) time.Time {
	if stamp.IsZero() {
		return info.ModTime().UTC()
	}
	return stamp
}

func nanosecondsSinceEpoch(stamp time.Time) *big.Int {
	number := big.NewInt(0)
	if !stamp.IsZero() {
		number.Mul(big.NewInt(stamp.Unix()), big.NewInt(1000000000))
		number.Add(number, big.NewInt(int64(stamp.Nanosecond())))
	}
	return number
}

// fileInfoOf builds the FileInfo record; birth, when nonzero, overrides the
// creation time the info carries.
func fileInfoOf(info os.FileInfo, birth time.Time) *FileInfo {
	mode := permissionBits(info.Mode())
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
	stat := hostos.StatInfo(info)
	accessed, changed := statTime(stat.Atime, info), statTime(stat.Ctime, info)
	created := hostos.BirthInfo(info)
	if !birth.IsZero() {
		created = birth
	}
	result := &FileInfo{
		Name: info.Name(), Size: FitInt(info.Size()), Directory: info.IsDir(), Symlink: info.Mode()&os.ModeSymlink != 0,
		Regular: info.Mode().IsRegular(), Modified: timestampOf(info.ModTime()), Accessed: timestampOf(accessed), Changed: timestampOf(changed),
		Mode: mode, Permissions: permissionBits(info.Mode()),
		BlockSize: FitInt(stat.Blksize.Int()), Blocks: FitInt(stat.Blocks.Int()), Rdev: FitInt(stat.Rdev.Int()), Device: FitInt(stat.Dev.Int()), Inode: FitInt(stat.Ino.Int()),
		Links: FitInt(stat.Nlink.Int()), Uid: FitInt(stat.Uid.Int()), Gid: FitInt(stat.Gid.Int()),
		Fifo: info.Mode()&os.ModeNamedPipe != 0, Socket: info.Mode()&os.ModeSocket != 0,
		BlockDevice: info.Mode()&os.ModeDevice != 0 && info.Mode()&os.ModeCharDevice == 0,
		CharDevice:  info.Mode()&os.ModeCharDevice != 0,
	}
	if !created.IsZero() {
		result.Created = Some(timestampOf(created))
	}
	exact := NewMap[string, *BigInt]()
	natives := map[string]hostos.Number{"device": stat.Dev, "inode": stat.Ino, "links": stat.Nlink, "uid": stat.Uid, "gid": stat.Gid, "rdev": stat.Rdev, "blocks": stat.Blocks, "block_size": stat.Blksize}
	values := map[string]int{"size": result.Size, "mode": result.Mode, "device": result.Device, "inode": result.Inode, "links": result.Links, "uid": result.Uid, "gid": result.Gid, "block_size": result.BlockSize, "blocks": result.Blocks, "rdev": result.Rdev}
	for _, name := range []string{"size", "mode", "device", "inode", "links", "uid", "gid", "block_size", "blocks", "rdev"} {
		number := big.NewInt(int64(values[name]))
		if native, ok := natives[name]; ok && stat.Valid && native.IsUnsigned {
			number = new(big.Int).SetUint64(native.Unsigned)
		}
		exact.Put(name, bigIntOf(number))
	}
	exact.Put("accessed_ns", bigIntOf(nanosecondsSinceEpoch(accessed)))
	exact.Put("modified_ns", bigIntOf(nanosecondsSinceEpoch(info.ModTime())))
	exact.Put("changed_ns", bigIntOf(nanosecondsSinceEpoch(changed)))
	exact.Put("created_ns", bigIntOf(nanosecondsSinceEpoch(created)))
	result.Exact = exact
	return result
}

func directoryEntryOf(name string, directory, symlink bool) *DirectoryEntry {
	return &DirectoryEntry{Name: name, Directory: directory, Symlink: symlink}
}

// osFileSystem is the host filesystem. A nonempty directory pins relative
// paths; otherwise they resolve against the live working directory.
type osFileSystem struct{ directory string }

var _ FileSystem = (*osFileSystem)(nil)

func (f *osFileSystem) path(s string) (string, bool) {
	if s == "" {
		return "", false
	}
	return hostPath(f.directory, s)
}

func (f *osFileSystem) ReadFile(ctx *Execution, path string, maxBytes Option[int]) Result[*Bytes, FileSystemError] {
	n, ok := optionLimit(maxBytes, unlimited)
	p, pathOK := f.path(path)
	if !ok || !pathOK {
		return fsInvalid[*Bytes]()
	}
	file, err := os.Open(p)
	if err != nil {
		return fsDone[*Bytes](nil, err)
	}
	defer file.Close()
	if info, err := file.Stat(); err == nil && info.IsDir() {
		return fsInvalid[*Bytes]()
	}
	b, code := readBounded(ctx, file, n)
	if code != "" {
		return fsFail[*Bytes](readFailure(code))
	}
	return fsOK(NewBytes(b))
}

func (f *osFileSystem) WriteFile(ctx *Execution, path string, data *Bytes, replace bool) Result[Unit, FileSystemError] {
	p, ok := f.path(path)
	if !ok {
		return fsInvalid[Unit]()
	}
	flags := os.O_WRONLY | os.O_CREATE | os.O_EXCL
	if replace {
		flags = os.O_WRONLY | os.O_CREATE | os.O_TRUNC
	}
	file, err := os.OpenFile(p, flags, 0600)
	if err != nil {
		return fsUnit(err)
	}
	defer file.Close()
	rest := data.Data
	for len(rest) > 0 {
		CheckCancelled(ctx)
		written, err := file.Write(rest[:min(len(rest), 65536)])
		if err != nil {
			return fsUnit(err)
		}
		if written == 0 {
			return fsFail[Unit](FileSystemError_Failed{Message: "short write"})
		}
		rest = rest[written:]
	}
	return fsUnit(file.Close())
}

func (f *osFileSystem) Stat(ctx *Execution, path string, followLinks bool) Result[*FileInfo, FileSystemError] {
	p, ok := f.path(path)
	if !ok {
		return fsInvalid[*FileInfo]()
	}
	var info os.FileInfo
	var err error
	if followLinks {
		info, err = os.Stat(p)
	} else {
		info, err = os.Lstat(p)
	}
	if err != nil {
		return fsDone[*FileInfo](nil, err)
	}
	if !utf8.ValidString(info.Name()) {
		return fsFail[*FileInfo](FileSystemError_Unsupported{})
	}
	return fsOK(fileInfoOf(info, hostos.BirthPath(p, followLinks)))
}

func (f *osFileSystem) List(ctx *Execution, path string, maxEntries Option[int]) Result[*List[*DirectoryEntry], FileSystemError] {
	n, ok := optionLimit(maxEntries, unlimited)
	p, pathOK := f.path(path)
	if !ok || !pathOK {
		return fsInvalid[*List[*DirectoryEntry]]()
	}
	directory, err := os.Open(p)
	if err != nil {
		return fsDone[*List[*DirectoryEntry]](nil, err)
	}
	defer directory.Close()
	if info, err := directory.Stat(); err == nil && !info.IsDir() {
		return fsInvalid[*List[*DirectoryEntry]]()
	}
	var entries []*DirectoryEntry
	for {
		CheckCancelled(ctx)
		batch, err := directory.ReadDir(64)
		for _, e := range batch {
			if len(entries) >= n {
				return fsFail[*List[*DirectoryEntry]](FileSystemError_LimitExceeded{})
			}
			if !utf8.ValidString(e.Name()) {
				return fsFail[*List[*DirectoryEntry]](FileSystemError_Unsupported{})
			}
			entries = append(entries, directoryEntryOf(e.Name(), e.IsDir(), e.Type()&os.ModeSymlink != 0))
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return fsDone[*List[*DirectoryEntry]](nil, err)
		}
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name < entries[j].Name })
	return fsOK(NewList(entries...))
}

func (f *osFileSystem) CreateDirectory(ctx *Execution, path string, recursive bool) Result[Unit, FileSystemError] {
	p, ok := f.path(path)
	if !ok {
		return fsInvalid[Unit]()
	}
	if recursive {
		return fsUnit(os.MkdirAll(p, 0700))
	}
	return fsUnit(os.Mkdir(p, 0700))
}

func (f *osFileSystem) Remove(ctx *Execution, path string, recursive bool) Result[Unit, FileSystemError] {
	if _, ok := f.path(path); !ok {
		return fsInvalid[Unit]()
	}
	p, err := f.removalPath(path)
	if err != nil {
		return fsUnit(err)
	}
	if recursive {
		err = removeTree(ctx, p)
	} else {
		err = os.Remove(p)
	}
	return fsUnit(err)
}

func (f *osFileSystem) Rename(ctx *Execution, source, destination string) Result[Unit, FileSystemError] {
	p, ok := f.path(source)
	dest, ok2 := f.path(destination)
	if !ok || !ok2 {
		return fsInvalid[Unit]()
	}
	return fsUnit(os.Rename(p, dest))
}

func (f *osFileSystem) CopyFile(ctx *Execution, source, destination string, replace bool, maxBytes Option[int]) Result[Unit, FileSystemError] {
	n, okLimit := optionLimit(maxBytes, unlimited)
	p, ok := f.path(source)
	dest, ok2 := f.path(destination)
	if !ok || !ok2 || !okLimit {
		return fsInvalid[Unit]()
	}
	in, err := os.Open(p)
	if err != nil {
		return fsUnit(err)
	}
	defer in.Close()
	b, code := readBounded(ctx, in, n)
	if code != "" {
		return fsFail[Unit](readFailure(code))
	}
	return f.WriteFile(ctx, dest, NewBytes(b), replace)
}

func (f *osFileSystem) Canonicalize(ctx *Execution, path string) Result[string, FileSystemError] {
	p, ok := f.path(path)
	if !ok {
		return fsInvalid[string]()
	}
	s, err := filepath.EvalSymlinks(p)
	if !utf8.ValidString(s) {
		return fsFail[string](FileSystemError_Unsupported{})
	}
	return fsDone(s, err)
}

func (f *osFileSystem) ReadLink(ctx *Execution, path string) Result[string, FileSystemError] {
	p, ok := f.path(path)
	if !ok {
		return fsInvalid[string]()
	}
	s, err := os.Readlink(p)
	if !utf8.ValidString(s) {
		return fsFail[string](FileSystemError_Unsupported{})
	}
	return fsDone(s, err)
}

func (f *osFileSystem) CreateLink(ctx *Execution, path, target string) Result[Unit, FileSystemError] {
	p, ok := f.path(path)
	if !ok || target == "" || strings.ContainsRune(target, 0) {
		return fsInvalid[Unit]()
	}
	return fsUnit(os.Symlink(target, p))
}

func validPrefix(prefix string) bool {
	return prefix != "" && !strings.ContainsAny(prefix, "/\\\x00")
}

func (f *osFileSystem) TemporaryDirectory(ctx *Execution, prefix string) Result[string, FileSystemError] {
	if !validPrefix(prefix) {
		return fsInvalid[string]()
	}
	s, err := os.MkdirTemp("", prefix)
	if err == nil && ctx.Context.Err() != nil {
		os.Remove(s)
		CheckCancelled(ctx)
	}
	return fsDone(s, err)
}

func (f *osFileSystem) Temporary(ctx *Execution, prefix string) Result[TemporaryDirectory, FileSystemError] {
	if !validPrefix(prefix) {
		return fsInvalid[TemporaryDirectory]()
	}
	s, err := os.MkdirTemp("", prefix)
	if err == nil && ctx.Context.Err() != nil {
		os.Remove(s)
		CheckCancelled(ctx)
	}
	if err != nil {
		return fsDone[TemporaryDirectory](nil, err)
	}
	return fsOK[TemporaryDirectory](&osTemporary{path: s})
}

func (f *osFileSystem) StatFilesystem(ctx *Execution, path string) Result[*FileSystemInfo, FileSystemError] {
	p, ok := f.path(path)
	if !ok {
		return fsInvalid[*FileSystemInfo]()
	}
	info, err := hostos.StatFS(p)
	if err != nil {
		return fsDone[*FileSystemInfo](nil, err)
	}
	return fsOK(&FileSystemInfo{TypeId: FitInt(info.Type), BlockSize: FitInt(info.BlockSize), Blocks: FitInt(info.Blocks), BlocksFree: FitInt(info.BlocksFree), BlocksAvailable: FitInt(info.BlocksAvailable), Files: FitInt(info.Files), FilesFree: FitInt(info.FilesFree)})
}

func (f *osFileSystem) ChmodLink(ctx *Execution, path string, mode int) Result[Unit, FileSystemError] {
	p, ok := f.path(path)
	if !ok || mode < 0 || mode > 07777 {
		return fsInvalid[Unit]()
	}
	return fsUnit(hostos.LinkMode(p, uint32(mode)))
}

func (f *osFileSystem) Access(ctx *Execution, path string, mode int) Result[Unit, FileSystemError] {
	p, ok := f.path(path)
	if !ok || mode < 0 || mode > 7 {
		return fsInvalid[Unit]()
	}
	return fsUnit(hostos.Access(p, uint32(mode)))
}

func (f *osFileSystem) AppendFile(ctx *Execution, path string, data *Bytes) Result[Unit, FileSystemError] {
	p, ok := f.path(path)
	if !ok {
		return fsInvalid[Unit]()
	}
	file, err := os.OpenFile(p, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0600)
	if err != nil {
		return fsUnit(err)
	}
	defer file.Close()
	_, err = writeChunks(ctx, file, data.Data, nil)
	if err == nil {
		err = file.Close()
	}
	return fsUnit(err)
}

func (f *osFileSystem) Chmod(ctx *Execution, path string, mode int) Result[Unit, FileSystemError] {
	p, ok := f.path(path)
	if !ok || mode < 0 || mode > 07777 {
		return fsInvalid[Unit]()
	}
	return fsUnit(os.Chmod(p, fileMode(mode)))
}

func (f *osFileSystem) Chown(ctx *Execution, path string, uid, gid int, followLinks bool) Result[Unit, FileSystemError] {
	p, ok := f.path(path)
	if !ok || uid < -1 || gid < -1 || uid > 2147483647 || gid > 2147483647 {
		return fsInvalid[Unit]()
	}
	if followLinks {
		return fsUnit(os.Chown(p, int(uid), int(gid)))
	}
	return fsUnit(os.Lchown(p, int(uid), int(gid)))
}

func (f *osFileSystem) Truncate(ctx *Execution, path string, size int) Result[Unit, FileSystemError] {
	p, ok := f.path(path)
	if !ok || size < 0 {
		return fsInvalid[Unit]()
	}
	return fsUnit(os.Truncate(p, int64(size)))
}

func (f *osFileSystem) SetTimes(ctx *Execution, path string, accessed, modified Timestamp, followLinks bool) Result[Unit, FileSystemError] {
	p, ok := f.path(path)
	if !ok {
		return fsInvalid[Unit]()
	}
	if !followLinks {
		return fsUnit(hostos.LinkTimes(p, timeOf(accessed), timeOf(modified)))
	}
	return fsUnit(os.Chtimes(p, timeOf(accessed), timeOf(modified)))
}

func (f *osFileSystem) HardLink(ctx *Execution, source, destination string) Result[Unit, FileSystemError] {
	p, ok := f.path(source)
	dest, ok2 := f.path(destination)
	if !ok || !ok2 {
		return fsInvalid[Unit]()
	}
	return fsUnit(os.Link(p, dest))
}

var openModes = map[string]int{"r": os.O_RDONLY, "r+": os.O_RDWR, "w": os.O_WRONLY | os.O_CREATE | os.O_TRUNC, "wx": os.O_WRONLY | os.O_CREATE | os.O_EXCL, "w+": os.O_RDWR | os.O_CREATE | os.O_TRUNC, "wx+": os.O_RDWR | os.O_CREATE | os.O_EXCL, "a": os.O_WRONLY | os.O_CREATE | os.O_APPEND, "ax": os.O_WRONLY | os.O_CREATE | os.O_APPEND | os.O_EXCL, "a+": os.O_RDWR | os.O_CREATE | os.O_APPEND, "ax+": os.O_RDWR | os.O_CREATE | os.O_APPEND | os.O_EXCL}

func (f *osFileSystem) Open(ctx *Execution, path, flags string, mode int) Result[FileHandle, FileSystemError] {
	value, ok := openModes[flags]
	if !ok {
		return fsInvalid[FileHandle]()
	}
	return f.openFile(ctx, path, value, mode)
}

func (f *osFileSystem) OpenFlags(ctx *Execution, path string, flags, mode int) Result[FileHandle, FileSystemError] {
	if flags < 0 || flags > 2147483647 {
		return fsInvalid[FileHandle]()
	}
	return f.openFile(ctx, path, int(flags), mode)
}

func (f *osFileSystem) openFile(ctx *Execution, path string, flags int, mode int) Result[FileHandle, FileSystemError] {
	p, ok := f.path(path)
	if !ok || mode < 0 || mode > 07777 {
		return fsInvalid[FileHandle]()
	}
	file, err := os.OpenFile(p, flags, fileMode(mode))
	if err != nil {
		return fsDone[FileHandle](nil, err)
	}
	if ctx.Context.Err() != nil {
		file.Close()
		CheckCancelled(ctx)
	}
	return fsOK[FileHandle](&osFileHandle{file: file, noRead: flags&3 == os.O_WRONLY, noWrite: flags&3 == os.O_RDONLY})
}

func (f *osFileSystem) OpenDirectory(ctx *Execution, path string) Result[Directory, FileSystemError] {
	p, ok := f.path(path)
	if !ok {
		return fsInvalid[Directory]()
	}
	file, err := os.Open(p)
	if err != nil {
		return fsDone[Directory](nil, err)
	}
	info, err := file.Stat()
	if err != nil || !info.IsDir() {
		file.Close()
		if err == nil {
			err = errors.New("not a directory")
		}
		return fsDone[Directory](nil, err)
	}
	if ctx.Context.Err() != nil {
		file.Close()
		CheckCancelled(ctx)
	}
	return fsOK[Directory](&osDirectory{file: file})
}

func (f *osFileSystem) Glob(ctx *Execution, path, pattern string, maxEntries Option[int]) Result[*List[string], FileSystemError] {
	max, okLimit := optionLimit(maxEntries, unlimited)
	p, ok := f.path(path)
	if !ok || !okLimit || !globValid(pattern) {
		return fsInvalid[*List[string]]()
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
			return errEncoding
		}
		if rel != "." && globMatch(filepath.ToSlash(rel), pattern) {
			if len(items) >= max {
				return errLimit
			}
			items = append(items, filepath.ToSlash(rel))
		}
		return nil
	})
	switch {
	case errors.Is(err, errLimit):
		return fsFail[*List[string]](FileSystemError_LimitExceeded{})
	case errors.Is(err, errEncoding):
		return fsFail[*List[string]](FileSystemError_Unsupported{})
	case err != nil:
		return fsDone[*List[string]](nil, err)
	}
	sort.Strings(items)
	return fsOK(NewList(items...))
}

func (f *osFileSystem) Watch(ctx *Execution, path string, recursive bool, interval Duration, maxEntries Option[int]) Result[FileWatcher, FileSystemError] {
	max, okLimit := optionLimit(maxEntries, unlimited)
	p, ok := f.path(path)
	if !ok || !okLimit || interval <= 0 {
		return fsInvalid[FileWatcher]()
	}
	snapshot, err := watchSnapshot(ctx, p, recursive, max)
	if err != nil {
		return fsFail[FileWatcher](snapshotError(err))
	}
	return fsOK[FileWatcher](&pollWatcher{path: p, recursive: recursive, interval: time.Duration(interval), max: max, snapshot: snapshot, done: make(chan struct{}), gate: make(chan struct{}, 1)})
}

func snapshotError(err error) FileSystemError {
	switch {
	case errors.Is(err, errLimit):
		return FileSystemError_LimitExceeded{}
	case errors.Is(err, errEncoding):
		return FileSystemError_Unsupported{}
	}
	return fsErrorOf(err)
}

// removalPath validates before traversal: removing the base (or an ancestor)
// must never partially erase its contents. Lstat preserves removal of a final
// symlink; SameFile also catches directory aliases through intermediate
// symlinks.
func (f *osFileSystem) removalPath(s string) (string, error) {
	if s == "" || filepath.Base(s) == "." || filepath.Base(s) == ".." {
		return "", errInvalidInput
	}
	// Capture the live base once, so a concurrent change_directory cannot make
	// resolution and protection refer to different working directories.
	base, ok := hostPath(f.directory, ".")
	if !ok {
		return "", errInvalidInput
	}
	p, ok := hostPath(base, s)
	if !ok {
		return "", errInvalidInput
	}
	clean := filepath.Clean(p)
	if filepath.Dir(clean) == clean {
		return "", errInvalidInput
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
			return "", errInvalidInput
		}
		parent := filepath.Dir(base)
		if parent == base {
			break
		}
		base = parent
	}
	return p, nil
}

func removeTree(ctx *Execution, p string) error {
	CheckCancelled(ctx)
	info, err := os.Lstat(p)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return os.Remove(p)
	}
	root, err := os.OpenRoot(p)
	if err != nil {
		return err
	}
	defer root.Close()
	if err := removeRoot(ctx, root, "."); err != nil {
		return err
	}
	// Windows cannot remove the root directory while its handle is open.
	if err := root.Close(); err != nil {
		return err
	}
	return os.Remove(p)
}

func removeRoot(ctx *Execution, root *os.Root, p string) error {
	CheckCancelled(ctx)
	file, err := root.Open(p)
	if err != nil {
		return err
	}
	defer file.Close()
	for {
		batch, err := file.ReadDir(64)
		for _, entry := range batch {
			child := filepath.Join(p, entry.Name())
			if entry.IsDir() {
				if err := removeRoot(ctx, root, child); err != nil {
					return err
				}
			} else if err := root.Remove(child); err != nil {
				return err
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		CheckCancelled(ctx)
	}
	if err := file.Close(); err != nil {
		return err
	}
	if p == "." {
		return nil
	}
	return root.Remove(p)
}

func writeChunks(ctx *Execution, file *os.File, data []byte, offset *int) (int, error) {
	var total int
	for len(data) > 0 {
		CheckCancelled(ctx)
		end := min(len(data), 65536)
		var n int
		var err error
		if offset == nil {
			n, err = file.Write(data[:end])
		} else {
			n, err = file.WriteAt(data[:end], int64(*offset+total))
		}
		total += int(n)
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
