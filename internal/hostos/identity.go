//go:build !darwin

package hostos

import (
	"os"
	"os/user"
	"runtime"
	"strconv"
	"strings"
)

type UserInfo struct {
	Username, Home, Shell string
	UID, GID              int64
}

func CurrentUser() (UserInfo, error) {
	u, err := user.Current()
	if err != nil {
		return UserInfo{}, err
	}
	uid, e1 := strconv.ParseInt(u.Uid, 10, 64)
	gid, e2 := strconv.ParseInt(u.Gid, 10, 64)
	if e1 != nil {
		uid = -1
	}
	if e2 != nil {
		gid = -1
	}
	shell := ""
	if runtime.GOOS == "linux" {
		// os/user's CGO-free record omits shell; recover the local passwd field.
		// Directory-service users without a local entry retain an empty shell.
		if passwd, err := os.ReadFile("/etc/passwd"); err == nil {
			for _, line := range strings.Split(string(passwd), "\n") {
				fields := strings.Split(line, ":")
				if len(fields) >= 7 && fields[0] == u.Username && fields[2] == u.Uid {
					shell = fields[6]
					break
				}
			}
		}
	}
	return UserInfo{Username: u.Username, Home: u.HomeDir, Shell: shell, UID: uid, GID: gid}, nil
}
