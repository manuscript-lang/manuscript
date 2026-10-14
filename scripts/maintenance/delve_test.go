package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestDelveScriptPatchReplay(t *testing.T) {
	root := t.TempDir()
	files := map[string][]byte{}
	for _, line := range strings.Split(string(delveScriptPatch), "\n") {
		if !strings.HasPrefix(line, "diff --git a/") {
			continue
		}
		name := strings.Fields(line)[3][2:]
		data, err := os.ReadFile(filepath.Join("../..", name))
		if err != nil {
			t.Fatal(err)
		}
		files[name] = data
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, data, 0600); err != nil {
			t.Fatal(err)
		}
	}
	if len(files) < 6 {
		t.Fatal("missing scripted backend patch")
	}
	if err := applyDelveScriptPatch(root); err != nil {
		t.Fatal("already applied patch", err)
	}
	cmd := exec.Command("git", "apply", "--reverse", "-")
	cmd.Dir, cmd.Stdin = root, bytes.NewReader(delveScriptPatch)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("restore upstream: %v %s", err, output)
	}
	if err := applyDelveScriptPatch(root); err != nil {
		t.Fatal("reapply after vendor refresh", err)
	}
	if err := applyDelveScriptPatch(root); err != nil {
		t.Fatal("idempotence", err)
	}
	for name, want := range files {
		got, err := os.ReadFile(filepath.Join(root, name))
		if err != nil || !bytes.Equal(got, want) {
			t.Fatalf("replay drift %s: %v", name, err)
		}
	}
	path := filepath.Join(root, "vendor/github.com/go-delve/delve/pkg/proc/gdbserial/script_session.go")
	if err := os.WriteFile(path, []byte("package changed\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := applyDelveScriptPatch(root); err == nil {
		t.Fatal("upstream drift accepted without review")
	}
}
