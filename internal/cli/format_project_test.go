package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFormatTargets(t *testing.T) {
	t.Setenv("MANUSCRIPT_GO", filepath.Join(t.TempDir(), "missing-go"))
	for _, mode := range []string{"manifest", "directory", "files"} {
		t.Run(mode, func(t *testing.T) {
			root := t.TempDir()
			original := "fn value() -> Int:   \n    return 3   \n"
			clean := "fn value() -> Int:\n    return 3\n"
			files := []string{"src/a.ms", "src/nested/b.ms", "test.ms", "tests/value_test.ms"}
			excluded := []string{"src/.hidden/skip.ms", "src/vendor/skip.ms", "src/node_modules/skip.ms", "notes.txt"}
			for _, name := range append(append([]string{}, files...), excluded...) {
				path := filepath.Join(root, name)
				if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(path, []byte(original), 0640); err != nil {
					t.Fatal(err)
				}
			}
			manifest := filepath.Join(root, "ms.toml")
			if err := os.WriteFile(manifest, []byte("[project]\nname = \"format\"\nsource = \"src\"\nentry = \"src/a.ms\"\n"), 0644); err != nil {
				t.Fatal(err)
			}
			args := []string{"fmt"}
			switch mode {
			case "manifest":
				args = append(args, manifest)
			case "directory":
				args = append(args, root)
			case "files":
				for i := len(files) - 1; i >= 0; i-- {
					args = append(args, filepath.Join(root, files[i]))
				}
				args = append(args, filepath.Join(root, files[0]))
			}
			status, _, diagnostics := invoke(t, append(args, "--check")...)
			if status != 1 {
				t.Fatalf("check status %d: %s", status, diagnostics)
			}
			last := -1
			for _, name := range files {
				path := filepath.Join(root, name)
				marker := "Formatting needed: " + path + ";"
				index := strings.Index(diagnostics, marker)
				if index <= last || strings.Count(diagnostics, marker) != 1 {
					t.Fatalf("missing, repeated or unsorted %s: %s", name, diagnostics)
				}
				last = index
				data, _ := os.ReadFile(path)
				if string(data) != original {
					t.Fatal("--check changed file")
				}
			}
			if status, _, diagnostics := invoke(t, args...); status != 0 {
				t.Fatalf("format: %d %s", status, diagnostics)
			}
			if status, _, diagnostics := invoke(t, append(args, "--check")...); status != 0 {
				t.Fatalf("second check: %d %s", status, diagnostics)
			}
			for _, name := range files {
				path := filepath.Join(root, name)
				data, _ := os.ReadFile(path)
				if string(data) != clean {
					t.Fatalf("%s: %q", name, data)
				}
			}
			for _, name := range excluded {
				data, _ := os.ReadFile(filepath.Join(root, name))
				if string(data) != original {
					t.Fatalf("formatted excluded %s", name)
				}
			}
		})
	}
}

func TestFormatReportsAllFailures(t *testing.T) {
	good := sourceFile(t, "fn value() -> Int:   \n    return 3   \n")
	bad := sourceFile(t, "fn broken(\n")
	missing := filepath.Join(t.TempDir(), "missing.ms")
	for _, check := range []bool{true, false} {
		args := []string{"fmt", bad, missing, good}
		if check {
			args = append(args, "--check")
		}
		status, _, diagnostics := invoke(t, args...)
		if status != 1 || !strings.Contains(diagnostics, bad) || !strings.Contains(diagnostics, missing) {
			t.Fatalf("%d: %s", status, diagnostics)
		}
		data, _ := os.ReadFile(good)
		if check {
			if !strings.Contains(diagnostics, "Formatting needed: "+good) || !strings.Contains(string(data), "   ") {
				t.Fatal("check missed drift or wrote source")
			}
		} else if strings.Contains(string(data), "   \n") {
			t.Fatal("failed to format valid file after errors")
		}
		data, _ = os.ReadFile(bad)
		if string(data) != "fn broken(\n" {
			t.Fatal("invalid source changed")
		}
	}
}

func TestFormatOptionsAndExplicitExcludedFile(t *testing.T) {
	for _, args := range [][]string{{"fmt"}, {"fmt", "--check"}, {"fmt", "--unknown"}, {"fmt", "a.ms", "-o", "b.ms"}} {
		status, _, _ := invoke(t, args...)
		if status != 2 {
			t.Fatalf("%v: %d", args, status)
		}
	}
	root := t.TempDir()
	path := filepath.Join(root, ".hidden", "explicit.ms")
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("fn value() -> Int:   \n    return 3   \n"), 0644); err != nil {
		t.Fatal(err)
	}
	if status, _, diagnostics := invoke(t, "fmt", "--check", path); status != 1 || !strings.Contains(diagnostics, "Formatting needed") {
		t.Fatalf("%d: %s", status, diagnostics)
	}
	if status, _, diagnostics := invoke(t, "fmt", "--", path); status != 0 {
		t.Fatalf("%d: %s", status, diagnostics)
	}
	if status, _, diagnostics := invoke(t, "fmt", t.TempDir(), "--check"); status != 0 {
		t.Fatalf("empty directory: %d: %s", status, diagnostics)
	}
}

func TestFormatSymlinkDiscovery(t *testing.T) {
	root := t.TempDir()
	outside := sourceFile(t, "fn value() -> Int:   \n    return 3   \n")
	link := filepath.Join(root, "linked.ms")
	if err := os.Symlink(outside, link); err != nil {
		t.Skip(err)
	}
	if status, _, diagnostics := invoke(t, "fmt", root); status != 1 || !strings.Contains(diagnostics, "escapes project root") {
		t.Fatalf("%d: %s", status, diagnostics)
	}
	data, _ := os.ReadFile(outside)
	if !strings.Contains(string(data), "   \n") {
		t.Fatal("directory formatting changed an external symlink target")
	}
	if status, _, diagnostics := invoke(t, "fmt", link, outside); status != 0 {
		t.Fatalf("explicit link: %d: %s", status, diagnostics)
	}
	if info, err := os.Lstat(link); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Fatal("format replaced the link")
	}
	if status, _, diagnostics := invoke(t, "fmt", outside, "--check"); status != 0 {
		t.Fatalf("%d: %s", status, diagnostics)
	}
}

func TestFormatManifestScopeAndTraversalFailure(t *testing.T) {
	root := t.TempDir()
	original := "fn value() -> Int:   \n    return 3   \n"
	for _, name := range []string{"src/module.ms", "entry.ms", "unrelated.ms", "tests/test.ms"} {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(original), 0644); err != nil {
			t.Fatal(err)
		}
	}
	manifest := filepath.Join(root, "ms.toml")
	if err := os.WriteFile(manifest, []byte("[project]\nname = \"format\"\nsource = \"src\"\nentry = \"entry.ms\"\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if status, _, diagnostics := invoke(t, "fmt", manifest); status != 0 {
		t.Fatalf("%d: %s", status, diagnostics)
	}
	for _, name := range []string{"src/module.ms", "entry.ms", "tests/test.ms"} {
		data, _ := os.ReadFile(filepath.Join(root, name))
		if string(data) == original {
			t.Fatalf("did not format %s", name)
		}
	}
	data, _ := os.ReadFile(filepath.Join(root, "unrelated.ms"))
	if string(data) != original {
		t.Fatal("manifest selected unrelated root source")
	}
	blocked := filepath.Join(root, "blocked")
	if err := os.Mkdir(blocked, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(blocked, 0); err != nil {
		t.Skip(err)
	}
	defer os.Chmod(blocked, 0700)
	if _, err := os.ReadDir(blocked); err == nil {
		t.Skip("directory permissions not enforced")
	}
	if status, _, diagnostics := invoke(t, "fmt", manifest, "--check"); status != 1 || !strings.Contains(diagnostics, "blocked") {
		t.Fatalf("partial discovery passed: %d: %s", status, diagnostics)
	}
}
