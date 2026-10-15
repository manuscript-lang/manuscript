//go:build unix

package msruntime

import (
	"fmt"
	"os"
	"strings"
	"syscall"
	"testing"
	"time"
)

// processAlive treats unreaped zombies as dead: orphans may lack a reaper.
func processAlive(pid int) bool {
	if syscall.Kill(pid, 0) != nil {
		return false
	}
	stat, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
	if err != nil {
		return true
	}
	fields := strings.Fields(string(stat[strings.LastIndex(string(stat), ")")+1:]))
	return len(fields) == 0 || fields[0] != "Z"
}

func TestSubprocessCloseKillsProcessGroup(t *testing.T) {
	if _, err := os.Stat("/bin/sh"); err != nil {
		t.Skip("requires POSIX shell")
	}
	root := RootExecution()
	result := Invoke(root, (&commands{}).Operation("spawn"), []Argument{{"program", "/bin/sh"}, {"arguments", &List{Items: []Value{"-c", "sleep 60 & echo $!; wait"}}}}).(Alternative)
	if result.Tag != "ok" {
		t.Fatal(result)
	}
	p := result.Fields[0].(View).Receiver.(*subprocess)
	data := make([]byte, 32)
	n, err := p.stdout.file.Read(data)
	if err != nil {
		t.Fatal(err)
	}
	var child int
	fmt.Sscanf(string(data[:n]), "%d", &child)
	wait := Invoke(root, p.Operation("wait"), []Argument{{"timeout", Duration(50 * time.Millisecond)}}).(Alternative)
	if wait.Tag != "error" || wait.Fields[0].(Alternative).Tag != "TimedOut" {
		t.Fatal(wait)
	}
	p.close()
	p.close()
	deadline := time.Now().Add(2 * time.Second)
	for processAlive(child) {
		if time.Now().After(deadline) {
			t.Fatal("descendant survived close")
		}
		time.Sleep(10 * time.Millisecond)
	}
	read := Invoke(root, p.Operation("stdout"), nil)
	if r := Invoke(root, Bind(read, "", "read"), nil).(Alternative); r.Tag != "error" {
		t.Fatal(r)
	}
}
