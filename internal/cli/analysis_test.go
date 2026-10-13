package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func analysisFiles(t *testing.T, root string, files map[string]string) {
	t.Helper()
	for name, source := range files {
		path := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(source), 0644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestAnalysisIndependentInputsAndPartialErrors(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	t.Setenv("PATH", t.TempDir())
	analysisFiles(t, root, map[string]string{
		"left/main.ms":  "export fn main() -> Int:\n    return missing\n",
		"right/main.ms": "export fn main() -> Int:\n    return \"wrong\"\n",
		"good/main.ms":  "export fn main() -> Int:\n    return 0\n",
		"other/main.ms": "export fn main() -> Int:\n    return 0\n",
	})
	status, stdout, stderr := invoke(t, "check", "other/main.ms", "good/main.ms")
	if status != 0 || stderr != "" || stdout != "Checked "+filepath.Join("good", "main.ms")+"\nChecked "+filepath.Join("other", "main.ms")+"\n" {
		t.Fatalf("independent main declarations: %d, %q, %q", status, stdout, stderr)
	}
	status, stdout, stderr = invoke(t, "check", "right/main.ms", "good/main.ms", "left/main.ms")
	if status != 1 || !strings.Contains(stdout, "Checked "+filepath.Join("good", "main.ms")) || !strings.Contains(stderr, "2 errors;") || strings.Index(stderr, filepath.Join("left", "main.ms")) > strings.Index(stderr, filepath.Join("right", "main.ms")) {
		t.Fatalf("partial independent checks: %d, %q, %q", status, stdout, stderr)
	}
	var previous string
	for _, targets := range [][]string{
		{"right/main.ms", "good/main.ms", "left/main.ms", "--json"},
		{filepath.Join(root, "left/main.ms"), "right/main.ms", "good/main.ms", "left/main.ms", "--json"},
	} {
		status, stdout, stderr := invoke(t, append([]string{"check"}, targets...)...)
		var document struct {
			Format      int
			Diagnostics []commandDiagnostic
		}
		if status != 1 || stderr != "" || json.Unmarshal([]byte(stdout), &document) != nil || document.Format != 1 || len(document.Diagnostics) != 2 || document.Diagnostics[0].Position.File != filepath.Join("left", "main.ms") || document.Diagnostics[1].Position.File != filepath.Join("right", "main.ms") || document.Diagnostics[0].Position.Line != 2 {
			t.Fatalf("collection JSON: %d, %q, %q", status, stdout, stderr)
		}
		if previous != "" && stdout != previous {
			t.Fatal("target order or equivalent spelling changed JSON")
		}
		previous = stdout
	}
	status, stdout, stderr = invoke(t, "check", "missing.ms", "left/main.ms", "--json")
	if status != 1 || stderr != "" || !strings.Contains(stdout, "missing.ms") || !strings.Contains(stdout, "left") {
		t.Fatalf("selection plus source errors: %d, %q, %q", status, stdout, stderr)
	}
}

func TestAnalysisLintAggregatesSourceAndHygiene(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	analysisFiles(t, root, map[string]string{
		"a.ms":      "import value from \"./shared.ms\"\nexport fn main() -> Int:\n    return value()\n",
		"b.ms":      "import value from \"./shared.ms\"\nexport fn main() -> Int:\n    return value()\n",
		"shared.ms": "export fn value() -> Int:\n    return 0   \n",
		"bad.ms":    "export fn broken() -> Int:\n    return missing\n",
	})
	status, stdout, stderr := invoke(t, "lint", "b.ms", "bad.ms", "a.ms", "--json")
	var document struct {
		Format      int
		Diagnostics []map[string]json.RawMessage
	}
	if status != 1 || stderr != "" || json.Unmarshal([]byte(stdout), &document) != nil || document.Format != 1 || len(document.Diagnostics) != 2 {
		t.Fatalf("mixed lint: %d, %q, %q", status, stdout, stderr)
	}
	if _, exists := document.Diagnostics[0]["phase"]; !exists {
		t.Fatal("compile diagnostic lost its phase")
	}
	if _, exists := document.Diagnostics[1]["phase"]; exists {
		t.Fatal("lint finding changed its existing JSON shape")
	}
	status, stdout, stderr = invoke(t, "lint", "a.ms", "b.ms")
	if status != 1 || stdout != "" || strings.Count(stderr, "MSL001") != 1 || !strings.Contains(stderr, "shared.ms:2:13") {
		t.Fatalf("shared imported finding was duplicated: %d, %q, %q", status, stdout, stderr)
	}
}

func TestAnalysisStandaloneDirectoryBoundariesAndEmpty(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	t.Setenv("PATH", t.TempDir())
	analysisFiles(t, root, map[string]string{
		"sources/a.ms":                "export fn main() -> Int:\n    return 0\n",
		"sources/sub/b.ms":            "export fn main() -> Int:\n    return 0\n",
		"sources/.hidden/invalid.ms":  "invalid source",
		"sources/vendor/invalid.ms":   "invalid source",
		"sources/node_modules/bad.ms": "invalid source",
		"sources/nested/ms.toml":      "malformed manifest",
		"sources/nested/invalid.ms":   "invalid source",
		"outside/invalid.ms":          "invalid source",
	})
	if err := os.Symlink(filepath.Join(root, "outside"), filepath.Join(root, "sources", "linked")); err != nil {
		t.Logf("directory symlink unavailable: %v", err)
	}
	for _, command := range []string{"check", "lint", "doc"} {
		status, stdout, stderr := invoke(t, command, "sources", "--json")
		if status != 0 || stderr != "" || strings.Contains(stdout, "invalid") {
			t.Fatalf("%s discovery: %d, %q, %q", command, status, stdout, stderr)
		}
		if command == "doc" && (!strings.Contains(stdout, "sources/a.ms") || !strings.Contains(stdout, "sources/sub/b.ms")) {
			t.Fatalf("missing independent docs: %s", stdout)
		}
	}
	status, stdout, stderr := invoke(t, "check", "sources", "sources/nested", "--json")
	if status != 1 || stderr != "" || !strings.Contains(stdout, "sources/nested/ms.toml") {
		t.Fatalf("explicit malformed nested manifest: %d, %q, %q", status, stdout, stderr)
	}
	if err := os.Mkdir("empty", 0755); err != nil {
		t.Fatal(err)
	}
	for _, command := range []string{"check", "lint", "doc"} {
		status, stdout, stderr := invoke(t, command, "empty", "--json")
		if status != 0 || stderr != "" || !strings.Contains(stdout, "[]") {
			t.Fatalf("%s empty: %d, %q, %q", command, status, stdout, stderr)
		}
	}
	// Selecting a directory must not widen each file's existing import root.
	analysisFiles(t, root, map[string]string{
		"sources/sub/b.ms": "import main from \"../a.ms\"\nexport fn value() -> Int:\n    return main()\n",
	})
	status, stdout, stderr = invoke(t, "check", "sources", "--json")
	if status != 1 || stderr != "" || !strings.Contains(stdout, "path escapes project root") {
		t.Fatalf("collection widened import root: %d, %q, %q", status, stdout, stderr)
	}
}

func TestAnalysisProjectScopesAndDocsAtomicFailure(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	for _, name := range []string{"left", "right"} {
		analysisFiles(t, root, map[string]string{
			name + "/ms.toml":        "[project]\nname = \"independent\"\nsource = \"src\"\nentry = \"src/main.ms\"\n[aliases]\n\"@lib\" = \"src/library.ms\"\n",
			name + "/src/main.ms":    "import value from \"@lib\"\nexport fn main() -> Int:\n    return value()\n",
			name + "/src/library.ms": "# Local value.\nexport fn value() -> Int:\n    return 0\n",
		})
	}
	for _, command := range []string{"check", "lint", "doc"} {
		status, stdout, stderr := invoke(t, command, "right", "left/ms.toml", "left", "--json")
		if status != 0 || stderr != "" {
			t.Fatalf("%s independent alias scopes: %d, %q, %q", command, status, stdout, stderr)
		}
		if command == "doc" {
			var document struct{ Modules []checker.APIModule }
			if json.Unmarshal([]byte(stdout), &document) != nil || len(document.Modules) != 4 || document.Modules[0].Path != "left/src/library.ms" || document.Modules[2].Path != "right/src/library.ms" {
				t.Fatalf("distinct module identity: %s", stdout)
			}
		}
	}
	status, stdout, stderr := invoke(t, "doc", "left", "left/src/library.ms", "--json")
	var document struct{ Modules []checker.APIModule }
	if status != 0 || stderr != "" || json.Unmarshal([]byte(stdout), &document) != nil || len(document.Modules) != 2 {
		t.Fatalf("overlapping module docs: %d, %q, %q", status, stdout, stderr)
	}
	analysisFiles(t, root, map[string]string{
		"left/src/library.ms":  "export fn value() -> Int:\n    return missing_left\n",
		"right/src/library.ms": "export fn value() -> Int:\n    return missing_right\n",
		"api.md":               "keep previous artifact\n",
	})
	status, stdout, stderr = invoke(t, "doc", "right", "left", "-o", "api.md")
	data, err := os.ReadFile("api.md")
	if status != 1 || stdout != "" || err != nil || string(data) != "keep previous artifact\n" || !strings.Contains(stderr, "missing_left") || !strings.Contains(stderr, "missing_right") {
		t.Fatalf("partial docs published: %d, %q, %q, %q, %v", status, stdout, stderr, data, err)
	}
}

func TestAnalysisLiteralTargetsAndNativeArity(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	analysisFiles(t, root, map[string]string{
		"-flag=a=b.ms": "export fn main() -> Int:\n    return 0\n",
		"plain.ms":     "export fn main() -> Int:\n    return 0\n",
	})
	for _, command := range []string{"check", "lint", "doc"} {
		status, _, stderr := invoke(t, command, "--", "-flag=a=b.ms", "plain.ms")
		if status != 0 || stderr != "" {
			t.Fatalf("%s literal targets: %d, %q", command, status, stderr)
		}
	}
	for _, command := range []string{"build", "run", "test", "emit", "profile", "debug", "inspect", "diagram"} {
		status, _, stderr := invoke(t, command, "plain.ms", "plain.ms")
		if status != 2 || !strings.Contains(stderr, "takes one file") {
			t.Fatalf("%s combined entrypoints: %d, %q", command, status, stderr)
		}
	}
}

func TestAnalysisCollectionRangesAndSymlinkConfinement(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	source := "fn update() -> Int:\r\n    var total = 0\r\n    total += 1\r\n    return total\r\n"
	analysisFiles(t, root, map[string]string{"ranges.ms": source, "sources/main.ms": "export fn main() -> Int:\n    return 0\n"})
	outside := t.TempDir()
	analysisFiles(t, outside, map[string]string{"bad.ms": "export fn value() -> Int:\n    return missing\n", "good.ms": "export fn value() -> Int:\n    return 0\n"})
	status, stdout, stderr := invoke(t, "check", "ranges.ms", filepath.Join(outside, "bad.ms"), "--json")
	var document struct{ Diagnostics []commandDiagnostic }
	if status != 1 || stderr != "" || json.Unmarshal([]byte(stdout), &document) != nil || len(document.Diagnostics) != 2 {
		t.Fatalf("range collection: %d, %q, %q", status, stdout, stderr)
	}
	canonical, err := filepath.EvalSymlinks(filepath.Join(outside, "bad.ms"))
	if err != nil {
		t.Fatal(err)
	}
	for _, issue := range document.Diagnostics {
		if issue.Position.File != "ranges.ms" {
			if issue.Position.File != canonical {
				t.Fatalf("outside diagnostic is not canonical: %+v", issue)
			}
			continue
		}
		if issue.Fix == nil || issue.End == nil || issue.Fix.Position.File != "ranges.ms" || issue.Fix.End.File != "ranges.ms" || issue.End.File != "ranges.ms" || source[issue.Fix.Position.Offset:issue.Fix.End.Offset] != "+=" || issue.Fix.Position.Offset != strings.Index(source, "+=") || issue.Fix.Position.Line != 3 {
			t.Fatalf("collection rebasing lost byte ranges: %+v", issue)
		}
	}
	if err := os.Symlink(filepath.Join(root, "ranges.ms"), "range-alias.ms"); err != nil {
		t.Skipf("file symlinks unavailable: %v", err)
	}
	status, duplicate, stderr := invoke(t, "check", "range-alias.ms", "ranges.ms", filepath.Join(outside, "bad.ms"), "--json")
	if status != 1 || stderr != "" || duplicate != stdout {
		t.Fatalf("symlink duplicate: %d, %q, %q", status, duplicate, stderr)
	}
	if err := os.Symlink(filepath.Join(outside, "good.ms"), filepath.Join("sources", "escape.ms")); err != nil {
		t.Fatal(err)
	}
	status, stdout, stderr = invoke(t, "check", "sources", "--json")
	if status != 1 || stderr != "" || !strings.Contains(stdout, "path escapes project root") {
		t.Fatalf("discovered symlink escaped: %d, %q, %q", status, stdout, stderr)
	}
	status, stdout, stderr = invoke(t, "check", "sources/main.ms", filepath.Join(outside, "good.ms"), "--json")
	if status != 0 || stderr != "" {
		t.Fatalf("explicit outside input rejected: %d, %q, %q", status, stdout, stderr)
	}
}

func TestAnalysisDocRejectsConflictingModuleSnapshots(t *testing.T) {
	root := t.TempDir()
	t.Chdir(root)
	analysisFiles(t, root, map[string]string{
		"shared.ms": "export type Item:\n    value: Int\n",
		"left.ms":   "import Item from \"./shared.ms\"\nexport interface Left:\n    fn left() -> Int\nimpl Left for Item:\n    fn left() -> Int:\n        return 0\n",
		"right.ms":  "import Item from \"./shared.ms\"\nexport interface Right:\n    fn right() -> Int\nimpl Right for Item:\n    fn right() -> Int:\n        return 0\n",
		"api.json":  "preserve previous reference",
	})
	for _, target := range []string{"left.ms", "right.ms"} {
		status, _, stderr := invoke(t, "doc", target, "--json")
		if status != 0 || stderr != "" {
			t.Fatalf("single %s snapshot: %d, %q", target, status, stderr)
		}
	}
	status, stdout, stderr := invoke(t, "doc", "right.ms", "left.ms", "--json", "-o", "api.json")
	data, err := os.ReadFile("api.json")
	if status != 1 || stdout != "" || !strings.Contains(stderr, "conflicting API descriptions for shared.ms") || err != nil || string(data) != "preserve previous reference" {
		t.Fatalf("silently selected one module context: %d, %q, %q, %s, %v", status, stdout, stderr, data, err)
	}
	// Equivalent complete graphs may load implementations in different orders.
	analysisFiles(t, root, map[string]string{
		"first.ms":  "import Left from \"./left.ms\"\nimport Right from \"./right.ms\"\nexport fn main() -> Int:\n    return 0\n",
		"second.ms": "import Right from \"./right.ms\"\nimport Left from \"./left.ms\"\nexport fn main() -> Int:\n    return 0\n",
	})
	status, stdout, stderr = invoke(t, "doc", "second.ms", "first.ms", "--json")
	var reference struct{ Modules []checker.APIModule }
	if status != 0 || stderr != "" || json.Unmarshal([]byte(stdout), &reference) != nil || len(reference.Modules) != 5 {
		t.Fatalf("equivalent graphs conflicted: %d, %q, %q", status, stdout, stderr)
	}
	shared := reference.Modules[4]
	if shared.Path != "shared.ms" || len(shared.Declarations) != 1 || len(shared.Declarations[0].Implements) != 2 {
		t.Fatalf("missing complete shared snapshot: %+v", shared)
	}
}
