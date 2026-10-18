package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFormatJSONChecksAndPartialFailures(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	t.Setenv("PATH", t.TempDir())
	for name, source := range map[string]string{
		"clean.ms":   "fn value() Int:\n    return 0\n",
		"drift=a.ms": "fn value() Int:   \n    return 0   \n",
		"invalid.ms": "fn broken(\n",
	} {
		if err := os.WriteFile(name, []byte(source), 0640); err != nil {
			t.Fatal(err)
		}
	}
	before, _ := os.ReadFile("drift=a.ms")
	beforeInfo, err := os.Stat("drift=a.ms")
	if err != nil {
		t.Fatal(err)
	}
	status, output, stderr := invoke(t, "fmt", "invalid.ms", "missing.ms", "clean.ms", "drift=a.ms", "--check", "--json")
	var result formatResult
	if status != 1 || stderr != "" || json.Unmarshal([]byte(output), &result) != nil || result.Format != 1 || len(result.Files) != 3 || len(result.Diagnostics) != 3 {
		t.Fatalf("format JSON: %d %q %q", status, output, stderr)
	}
	for i, want := range []formatFileResult{{"clean.ms", "clean"}, {"drift=a.ms", "needs_formatting"}, {"invalid.ms", "error"}} {
		if result.Files[i] != want {
			t.Fatalf("file %d: %+v", i, result.Files[i])
		}
	}
	if result.Diagnostics[0].Code != "MSF001" || result.Diagnostics[1].Phase != "parse" || result.Diagnostics[1].Position.File != "invalid.ms" || result.Diagnostics[1].Position.Line != 2 || result.Diagnostics[1].Position.Column != 1 || result.Diagnostics[2].Position.File != "missing.ms" {
		t.Fatalf("diagnostics lost paths/order/positions: %+v", result.Diagnostics)
	}
	after, _ := os.ReadFile("drift=a.ms")
	if string(after) != string(before) {
		t.Fatal("JSON check rewrote source")
	}
	if info, err := os.Stat("drift=a.ms"); err != nil || info.Mode().Perm() != beforeInfo.Mode().Perm() {
		t.Fatal("check changed permissions", err)
	}
	status, output, stderr = invoke(t, "fmt", "clean.ms", "--check", "--json")
	if status != 0 || stderr != "" || !strings.Contains(output, `"diagnostics": []`) {
		t.Fatalf("clean JSON: %d %q %q", status, output, stderr)
	}
	status, output, stderr = invoke(t, "fmt", t.TempDir(), "--check", "--json")
	if status != 0 || stderr != "" || !strings.Contains(output, `"files": []`) {
		t.Fatalf("empty JSON: %d %q %q", status, output, stderr)
	}
	status, output, stderr = invoke(t, "fmt", "clean.ms", "--json")
	if status != 2 || output != "" || !strings.Contains(stderr, "--json requires ms fmt --check") {
		t.Fatalf("unsupported mutation JSON: %d %q %q", status, output, stderr)
	}
}

func TestFormatPathsMatchAcrossSelectionForms(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	if err := os.Mkdir("src", 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile("src/value.ms", []byte("fn value() Int:   \n    return 0   \n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile("ms.toml", []byte("[project]\nname = \"format\"\nsource = \"src\"\nentry = \"src/value.ms\"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	wantPath := filepath.Join("src", "value.ms")
	var document string
	for _, target := range []string{wantPath, filepath.Join(root, wantPath), "src", "ms.toml", "."} {
		status, output, stderr := invoke(t, "fmt", target, "--check", "--json")
		if status != 1 || stderr != "" {
			t.Fatalf("%s: %d %q %q", target, status, output, stderr)
		}
		if document == "" {
			document = output
		} else if output != document {
			t.Fatalf("different display for %s: %s != %s", target, output, document)
		}
		status, output, stderr = invoke(t, "fmt", target, "--check")
		if status != 1 || output != "" || !strings.Contains(stderr, "Formatting needed: "+wantPath+";") || strings.Contains(stderr, root) {
			t.Fatalf("human path %s: %d %q %q", target, status, output, stderr)
		}
	}
	if err := os.Symlink(wantPath, "linked.ms"); err == nil {
		status, output, stderr := invoke(t, "fmt", "linked.ms", wantPath, "--check", "--json")
		if status != 1 || stderr != "" || output != document {
			t.Fatalf("physical dedup/display: %d %q %q", status, output, stderr)
		}
	}
}

func TestFormatJSONPreservesManifestLocation(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	if err := os.Mkdir("project", 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join("project", "ms.toml"), []byte("[project]\nname = \"ok\"\nsource = 2\n"), 0600); err != nil {
		t.Fatal(err)
	}
	status, output, stderr := invoke(t, "fmt", filepath.Join(root, "project", "ms.toml"), "--check", "--json")
	var result formatResult
	if status != 1 || stderr != "" || json.Unmarshal([]byte(output), &result) != nil || len(result.Diagnostics) != 1 {
		t.Fatalf("manifest: %d %q %q", status, output, stderr)
	}
	issue := result.Diagnostics[0]
	if issue.Phase != "resolution" || issue.Position.File != filepath.Join("project", "ms.toml") || issue.Position.Line != 3 || issue.Position.Column == 0 {
		t.Fatalf("manifest location: %+v", issue)
	}
}
