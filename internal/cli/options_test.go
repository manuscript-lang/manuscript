package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSplitValueOption(t *testing.T) {
	for _, tc := range []struct {
		arg, name, value string
		inline           bool
	}{
		{"--output=a=b.go", "--output", "a=b.go", true},
		{"--filter=name=x=y", "--filter", "name=x=y", true},
		{"--output=", "--output", "", true},
		{"--output", "--output", "", false},
		{"--unknown=x=y", "--unknown=x=y", "", false},
		{"--json=true", "--json=true", "", false},
		{"-o=x", "-o=x", "", false},
		{"a=b.ms", "a=b.ms", "", false},
	} {
		name, value, inline := splitValueOption(tc.arg, valueOptions...)
		if name != tc.name || value != tc.value || inline != tc.inline {
			t.Fatalf("%q: %q, %q, %v", tc.arg, name, value, inline)
		}
	}
}

func TestCLIValueSpellingsAndErrors(t *testing.T) {
	file := sourceFile(t, "export fn main() -> Int:\n    return 0\n")
	for _, command := range []string{"emit", "inspect", "diagram", "doc"} {
		for _, inline := range []bool{false, true} {
			output := filepath.Join(t.TempDir(), "output=a=b")
			args := []string{command, file, "--output", output}
			if inline {
				args = []string{command, file, "--output=" + output}
			}
			status, stdout, stderr := invoke(t, args...)
			data, err := os.ReadFile(output)
			if status != 0 || stdout != "" || stderr != "" || err != nil || len(data) == 0 {
				t.Fatalf("%v: %d, %q, %q, %v", args, status, stdout, stderr, err)
			}
		}
	}
	for _, flag := range []string{"--output", "--build-type", "--timeout", "--filter", "--cpu-profile", "--heap-profile", "--trace", "-o"} {
		for _, suffix := range [][]string{{flag}, {flag, ""}, {flag + "="}} {
			if flag == "-o" && len(suffix) == 1 && suffix[0] == "-o=" {
				continue
			}
			args := append([]string{"run", file}, suffix...)
			status, stdout, stderr := invoke(t, args...)
			if status != 2 || stdout != "" || !strings.Contains(stderr, flag+" requires") {
				t.Fatalf("missing value %v: %d, %q, %q", args, status, stdout, stderr)
			}
		}
	}
	for _, command := range []string{"check", "doc", "fmt"} {
		for _, flag := range []string{"--unknown=x=y", "--json=true", "-o=x"} {
			status, _, stderr := invoke(t, command, file, flag)
			if status != 2 || !strings.Contains(stderr, "unknown option "+flag+" for ms "+command) {
				t.Fatalf("original token %s %s: %d, %q", command, flag, status, stderr)
			}
		}
	}
	for _, command := range []string{"check", "lint", "run", "test", "debug", "lock"} {
		for _, suffix := range [][]string{{"-o", "unused"}, {"--output", "unused"}, {"--output=unused"}} {
			status, _, stderr := invoke(t, append([]string{command, file}, suffix...)...)
			if status != 2 || !strings.Contains(stderr, "-o and --output are valid only for") || !strings.Contains(stderr, "not ms "+command) {
				t.Fatalf("unsupported output %s %v: %d, %q", command, suffix, status, stderr)
			}
		}
	}
	for _, flag := range []string{"-o", "--output"} {
		for _, suffix := range [][]string{{flag}, {flag, ""}, {flag + "="}} {
			if suffix[0] == "-o=" {
				continue
			}
			status, _, stderr := invoke(t, append([]string{"doc", file}, suffix...)...)
			if status != 2 || !strings.Contains(stderr, "requires a path argument") {
				t.Fatalf("doc missing value %v: %d, %q", suffix, status, stderr)
			}
		}
	}
}

func TestCLIInlineValuesKeepValidationAndForwarding(t *testing.T) {
	for _, tc := range []struct {
		args []string
		want string
	}{
		{[]string{"build", "missing.ms", "--build-type=Debug", "--build-type", "Release"}, "may only be specified once"},
		{[]string{"build", "missing.ms", "--build-type=invalid"}, "unknown build type"},
		{[]string{"debug", "missing.ms", "--build-type=Release"}, "debug requires build type Debug"},
		{[]string{"check", "missing.ms", "--build-type=Debug"}, "--build-type requires build"},
		{[]string{"check", "missing.ms", "--filter=name=value"}, "valid only for ms test"},
		{[]string{"test", "missing.ms", "--timeout=-1s"}, "invalid --timeout"},
		{[]string{"test", "missing.ms", "--timeout=bad=value"}, "invalid --timeout \"bad=value\""},
		{[]string{"test", "missing.ms", "--cpu-profile=cpu=1.pprof"}, "require run, not test"},
		{[]string{"profile", "missing.ms", "--trace=trace=1.out"}, "unknown option --trace=trace=1.out for ms profile"},
		{[]string{"run", "missing.ms", "--watch", "--trace=trace=1.out"}, "--watch cannot be combined"},
	} {
		status, _, stderr := invoke(t, tc.args...)
		if status != 2 || !strings.Contains(stderr, tc.want) {
			t.Fatalf("%v: %d, %q (want %q)", tc.args, status, stderr, tc.want)
		}
	}
	for _, args := range [][]string{
		{"run", "missing.ms", "--", "--output=", "--help"},
		{"test", "missing.ms", "--filter", "--help"},
		{"test", "missing.ms", "--filter=--help"},
		{"emit", "missing.ms", "--output=--help"},
	} {
		status, stdout, stderr := invoke(t, args...)
		if status != 1 || stdout != "" || !strings.Contains(stderr, "file not found") {
			t.Fatalf("values/arguments consumed as help %v: %d, %q, %q", args, status, stdout, stderr)
		}
	}
}

func TestDocProjectDirectoryAndUsage(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	root := t.TempDir()
	for name, text := range map[string]string{
		"ms.toml":      "[project]\nname = \"docs\"\nsource = \".\"\nentry = \"main=1.ms\"\n",
		"main=1.ms":    "import value from \"./library=2.ms\"\nexport fn main() -> Int:\n    return value()\n",
		"library=2.ms": "export fn value() -> Int:\n    return 0\n",
	} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(text), 0600); err != nil {
			t.Fatal(err)
		}
	}
	status, directoryDoc, stderr := invoke(t, "doc", root, "--json")
	manifestStatus, manifestDoc, manifestErr := invoke(t, "doc", filepath.Join(root, "ms.toml"), "--json")
	if status != 0 || manifestStatus != 0 || stderr != "" || manifestErr != "" || directoryDoc != manifestDoc || !strings.Contains(directoryDoc, "value") {
		t.Fatalf("directory docs: %d, %q, %q; manifest: %d, %q", status, directoryDoc, stderr, manifestStatus, manifestErr)
	}
	status, _, stderr = invoke(t, "doc", t.TempDir())
	if status != 0 || stderr != "" {
		t.Fatalf("plain directory: %d, %q", status, stderr)
	}
	for _, tc := range []struct {
		args []string
		want string
	}{
		{[]string{"doc"}, "missing the file argument"},
		{[]string{"doc", "--stdlib", root}, "ms doc --stdlib takes no input file"},
	} {
		status, _, stderr := invoke(t, tc.args...)
		if status != 2 || !strings.Contains(stderr, tc.want) {
			t.Fatalf("%v: %d, %q", tc.args, status, stderr)
		}
	}
	if err := os.WriteFile(filepath.Join(root, "main=1.ms"), []byte("export fn helper() -> Int:\n    return 0\n"), 0600); err != nil {
		t.Fatal(err)
	}
	status, _, stderr = invoke(t, "doc", root)
	if status != 1 || !strings.Contains(stderr, "entry must export") {
		t.Fatalf("directory skipped entry validation: %d, %q", status, stderr)
	}
	// An entryless library follows the current project contract: document all
	// source modules rather than requiring an application main function.
	if err := os.WriteFile(filepath.Join(root, "ms.toml"), []byte("[project]\nname = \"library\"\nsource = \".\"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	status, directoryDoc, stderr = invoke(t, "doc", root, "--json")
	manifestStatus, manifestDoc, manifestErr = invoke(t, "doc", filepath.Join(root, "ms.toml"), "--json")
	if status != 0 || manifestStatus != 0 || stderr != "" || manifestErr != "" || directoryDoc != manifestDoc || !strings.Contains(directoryDoc, "helper") || !strings.Contains(directoryDoc, "value") {
		t.Fatalf("library directory docs: %d, %q, %q; manifest: %d, %q", status, directoryDoc, stderr, manifestStatus, manifestErr)
	}
}

func TestStdlibDeclarationsAndInlineDocOutput(t *testing.T) {
	root := t.TempDir()
	docs := filepath.Join(root, "stdlib=a=b.json")
	status, stdout, stderr := invoke(t, "doc", "--output="+docs, "--stdlib", "--json")
	data, err := os.ReadFile(docs)
	if status != 0 || stdout != "" || stderr != "" || err != nil || !strings.Contains(string(data), `"modules"`) {
		t.Fatalf("stdlib docs: %d, %q, %q, %v", status, stdout, stderr, err)
	}
	declarations := filepath.Join(root, "declarations=a=b")
	status, _, stderr = invoke(t, "stdlib", declarations)
	if status != 0 || stderr != "" {
		t.Fatalf("stdlib declarations: %d, %q", status, stderr)
	}
	for _, name := range []string{"cli.ms", "bindings.json"} {
		if _, err := os.Stat(filepath.Join(declarations, name)); err != nil {
			t.Fatal(err)
		}
	}
}
