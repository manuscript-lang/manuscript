package cli

import (
	"encoding/json"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestProjectCheckFindsUnimportedErrors(t *testing.T) {
	root := t.TempDir()
	for name, source := range map[string]string{
		"ms.toml":       "[project]\nname = \"check\"\nsource = \"src\"\nentry = \"src/main.ms\"\n",
		"src/main.ms":   "export fn main() -> Int:\n    return 0\n",
		"src/report.ms": "fn number() -> Int:\n    return \"wrong\"\n\nfn text() -> String:\n    return 1\n",
	} {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	status, output, errors := invoke(t, "check", filepath.Join(root, "ms.toml"))
	if status != 1 || strings.Contains(output, "Checked") || !strings.Contains(errors, "report.ms:2:") || !strings.Contains(errors, "report.ms:5:") {
		t.Fatalf("project check skipped unimported errors: %d, %q, %q", status, output, errors)
	}
}

func TestProjectCheckDiscoveryAndReporting(t *testing.T) {
	t.Setenv("MANUSCRIPT_GO", filepath.Join(t.TempDir(), "missing-go"))
	for _, sourceDir := range []string{"src", "."} {
		t.Run(sourceDir, func(t *testing.T) {
			root := t.TempDir()
			write := func(name, source string) {
				t.Helper()
				path := filepath.Join(root, name)
				if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(path, []byte(source), 0600); err != nil {
					t.Fatal(err)
				}
			}
			write("ms.toml", "[project]\nname = \"check\"\nsource = \""+sourceDir+"\"\nentry = \"main.ms\"\n[aliases]\n\"@lib\" = \"lib\"\n")
			write("main.ms", "import value from \"./lib/value.ms\"\nexport fn main() -> Int:\n    return value()\n")
			write("lib/value.ms", "export fn value() -> Int: return 0\n")
			// Both entry reachability and discovery lead to value.ms; count it once.
			write("src/nested/report.ms", "import value from \"@lib/value.ms\"\nfn report() -> Int: return value()\n")
			write("test.ms", "import panic from \"@std/faults.ms\"\ntest \"never execute\":\n    return panic(\"check executed code\")\n")
			write("tests/report_test.ms", "test \"valid\":\n    let n = 1\n")
			for _, dir := range []string{".hidden", "vendor", "node_modules", "src/.hidden", "src/vendor", "src/node_modules"} {
				write(dir+"/broken.ms", "invalid source!")
				write(dir+"/test.ms", "invalid source!")
			}
			write("src/notes.txt", "invalid source!")
			manifest := filepath.Join(root, "ms.toml")
			status, output, errors := invoke(t, "check", manifest)
			if status != 0 || errors != "" || !strings.Contains(output, "(5 modules)") {
				t.Fatalf("discovery/count/exclusions: %d, %q, %q", status, output, errors)
			}
			for _, name := range []string{"lib/value.ms", "src/nested/report.ms", "test.ms", "tests/report_test.ms"} {
				t.Run(name, func(t *testing.T) {
					path := filepath.Join(root, name)
					previous, err := os.ReadFile(path)
					if err != nil {
						t.Fatal(err)
					}
					defer write(name, string(previous))
					write(name, string(previous)+"\nfn broken() -> Int: return \"bad\"\n")
					status, output, errors := invoke(t, "check", manifest, "--json")
					var result struct {
						Format      int                 `json:"format"`
						Diagnostics []syntax.Diagnostic `json:"diagnostics"`
					}
					if status != 1 || errors != "" || json.Unmarshal([]byte(output), &result) != nil || result.Format != 1 || len(result.Diagnostics) != 1 || result.Diagnostics[0].Position.File != name || result.Diagnostics[0].Position.Line == 0 {
						t.Fatalf("missing/doubled project diagnostic: %d, %q, %q", status, output, errors)
					}
				})
			}
			write("src/nested/report.ms", "fn broken(\n")
			status, output, errors = invoke(t, "check", manifest)
			if status != 1 || strings.Contains(output, "Checked") || !strings.Contains(errors, "report.ms") {
				t.Fatalf("parse error: %d, %q, %q", status, output, errors)
			}
			status, output, errors = invoke(t, "check", filepath.Join(root, "main.ms"))
			if status != 0 || errors != "" || output != "Checked "+filepath.Join(root, "main.ms")+"\n" {
				t.Fatalf("file input changed: %d, %q, %q", status, output, errors)
			}
			if _, err := os.Stat(filepath.Join(root, ".ms-cache")); !os.IsNotExist(err) {
				t.Fatalf("check created native artifacts: %v", err)
			}
		})
	}
}

func TestProjectCheckIgnoresUnrelatedSourceOutsideSourceDirectory(t *testing.T) {
	root := t.TempDir()
	for name, source := range map[string]string{
		"ms.toml":           "[project]\nname = \"check\"\nsource = \"src\"\nentry = \"main.ms\"\n",
		"main.ms":           "export fn main() -> Int: return 0\n",
		"src/library.ms":    "fn value() -> Int: return 1\n",
		"scratch/broken.ms": "invalid source!",
	} {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	status, output, errors := invoke(t, "check", filepath.Join(root, "ms.toml"))
	if status != 0 || errors != "" || !strings.Contains(output, "(2 modules)") {
		t.Fatalf("%d, %q, %q", status, output, errors)
	}
}

func TestProjectCheckDiscoveredSymlinks(t *testing.T) {
	root := t.TempDir()
	for name, source := range map[string]string{
		"ms.toml": "[project]\nname = \"check\"\nsource = \".\"\nentry = \"main.ms\"\n",
		"main.ms": "export fn main() -> Int: return 0\n",
	} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	link := filepath.Join(root, "alias.ms")
	if err := os.Symlink(filepath.Join(root, "main.ms"), link); err != nil {
		t.Skip(err)
	}
	status, output, errors := invoke(t, "check", filepath.Join(root, "ms.toml"))
	if status != 0 || errors != "" || !strings.Contains(output, "(1 module)") {
		t.Fatalf("alias duplicate: %d, %q, %q", status, output, errors)
	}
	if err := os.Remove(link); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(sourceFile(t, "fn value() -> Int: return 0\n"), link); err != nil {
		t.Fatal(err)
	}
	status, output, errors = invoke(t, "check", filepath.Join(root, "ms.toml"))
	if status != 1 || strings.Contains(output, "Checked") || !strings.Contains(errors, "escapes project root") {
		t.Fatalf("escape accepted: %d, %q, %q", status, output, errors)
	}
}
