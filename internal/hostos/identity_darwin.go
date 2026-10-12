//go:build darwin

package hostos

import (
	"os"
	"sync"
	"syscall"
	"unsafe"

	"github.com/ebitengine/purego"
)

type UserInfo struct {
	Username, Home, Shell string
	UID, GID              int64
}
type darwinPasswd struct {
	Name, Password            uintptr
	UID, GID                  uint32
	Change                    int64
	Class, Gecos, Home, Shell uintptr
	Expire                    int64
	Fields                    int32
}

var darwinIdentity struct {
	sync.Mutex
	once     sync.Once
	err      error
	getUser  func(uint32, unsafe.Pointer, unsafe.Pointer, uintptr, unsafe.Pointer) int32
	getTitle func() string
	setTitle func(uintptr)
	title    []byte
}

func darwinIdentityInit() {
	darwinIdentity.once.Do(func() {
		library, err := purego.Dlopen("/usr/lib/libSystem.B.dylib", purego.RTLD_LAZY|purego.RTLD_LOCAL)
		if err != nil {
			darwinIdentity.err = err
			return
		}
		purego.RegisterLibFunc(&darwinIdentity.getUser, library, "getpwuid_r")
		purego.RegisterLibFunc(&darwinIdentity.getTitle, library, "getprogname")
		purego.RegisterLibFunc(&darwinIdentity.setTitle, library, "setprogname")
	})
}
func CurrentUser() (UserInfo, error) {
	darwinIdentityInit()
	if darwinIdentity.err != nil {
		return UserInfo{}, darwinIdentity.err
	}
	var record darwinPasswd
	var result uintptr
	buffer := make([]byte, 65536)
	code := darwinIdentity.getUser(uint32(os.Getuid()), unsafe.Pointer(&record), unsafe.Pointer(&buffer[0]), uintptr(len(buffer)), unsafe.Pointer(&result))
	if code != 0 {
		return UserInfo{}, syscall.Errno(code)
	}
	if result == 0 {
		return UserInfo{}, os.ErrNotExist
	}
	// All returned strings are within the supplied buffer. Slice that Go-owned
	// buffer by offset rather than dereferencing arbitrary native pointers.
	text := func(pointer uintptr) string {
		start := pointer - uintptr(unsafe.Pointer(&buffer[0]))
		if start >= uintptr(len(buffer)) {
			return ""
		}
		end := int(start)
		for end < len(buffer) && buffer[end] != 0 {
			end++
		}
		return string(buffer[int(start):end])
	}
	return UserInfo{Username: text(record.Name), Home: text(record.Home), Shell: text(record.Shell), UID: int64(record.UID), GID: int64(record.GID)}, nil
}
func ProcessTitle() (string, error) {
	darwinIdentityInit()
	if darwinIdentity.err != nil {
		return "", darwinIdentity.err
	}
	darwinIdentity.Lock()
	defer darwinIdentity.Unlock()
	return darwinIdentity.getTitle(), nil
}
func SetProcessTitle(title string) error {
	darwinIdentityInit()
	if darwinIdentity.err != nil {
		return darwinIdentity.err
	}
	darwinIdentity.Lock()
	defer darwinIdentity.Unlock()
	darwinIdentity.title = append([]byte(title), 0)
	darwinIdentity.setTitle(uintptr(unsafe.Pointer(&darwinIdentity.title[0])))
	return nil
}
