package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInitCreatesCheckableProject(t *testing.T) {
	root := filepath.Join(t.TempDir(), "My App")
	status, output, errors := invoke(t, "init", root)
	if status != 0 || errors != "" || !strings.Contains(output, "Created project") {
		t.Fatalf("init: %d %q %q", status, output, errors)
	}
	manifest, err := os.ReadFile(filepath.Join(root, "ms.toml"))
	if err != nil || !strings.Contains(string(manifest), `name = "my-app"`) {
		t.Fatalf("manifest: %v %s", err, manifest)
	}
	ignore, _ := os.ReadFile(filepath.Join(root, ".gitignore"))
	if string(ignore) != ".ms-cache/\n" {
		t.Fatalf("gitignore %q", ignore)
	}
	t.Setenv("PATH", t.TempDir())
	if status, _, errors := invoke(t, "check", filepath.Join(root, "ms.toml")); status != 0 {
		t.Fatalf("scaffold does not check: %d %s", status, errors)
	}
}

func TestInitNeverOverwrites(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "test.ms"), []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	status, _, errors := invoke(t, "init", root)
	if status != 1 || !strings.Contains(errors, "already exists") {
		t.Fatalf("init over existing file: %d %q", status, errors)
	}
	if data, _ := os.ReadFile(filepath.Join(root, "test.ms")); string(data) != "keep" {
		t.Fatal("existing file was overwritten")
	}
	if _, err := os.Stat(filepath.Join(root, "ms.toml")); err == nil {
		t.Fatal("init wrote files before detecting the conflict")
	}
	if status, _, _ := invoke(t, "init", "a", "b"); status != 2 {
		t.Fatalf("two directories: %d", status)
	}
}

func TestInitAppendsToExistingGitignore(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, ".gitignore")
	if err := os.WriteFile(path, []byte("bin"), 0o644); err != nil {
		t.Fatal(err)
	}
	if status, _, errors := invoke(t, "init", root); status != 0 {
		t.Fatal(status, errors)
	}
	if data, _ := os.ReadFile(path); string(data) != "bin\n.ms-cache/\n" {
		t.Fatalf("gitignore %q", data)
	}
}

func TestInitDiagnosesBadDirectories(t *testing.T) {
	status, _, errors := invoke(t, "init", "")
	if status != 2 || !strings.Contains(errors, "directory is empty") {
		t.Fatalf("empty directory: %d %q", status, errors)
	}
	file := filepath.Join(t.TempDir(), "file")
	if err := os.WriteFile(file, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	status, _, errors = invoke(t, "init", file)
	if status != 1 || !strings.Contains(errors, "ms init: cannot create project in") {
		t.Fatalf("file as directory: %d %q", status, errors)
	}
	root := filepath.Join(t.TempDir(), "my app")
	_, output, _ := invoke(t, "init", root)
	if !strings.Contains(output, "'"+filepath.Join(root, "ms.toml")+"'") {
		t.Fatalf("next command is not paste-safe: %q", output)
	}
}
