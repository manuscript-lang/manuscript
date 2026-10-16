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
	for _, command := range []string{"emit", "inspect", "diagram"} {
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
	for _, command := range []string{"check", "fmt"} {
		for _, flag := range []string{"--unknown=x=y", "--json=true", "-o=x"} {
			status, _, stderr := invoke(t, command, file, flag)
			if status != 2 || !strings.Contains(stderr, "unknown option "+flag+" for ms "+command) {
				t.Fatalf("original token %s %s: %d, %q", command, flag, status, stderr)
			}
		}
	}
	for _, command := range []string{"check", "lint", "run", "test", "debug"} {
		for _, suffix := range [][]string{{"-o", "unused"}, {"--output", "unused"}, {"--output=unused"}} {
			status, _, stderr := invoke(t, append([]string{command, file}, suffix...)...)
			if status != 2 || !strings.Contains(stderr, "-o and --output are valid only for") || !strings.Contains(stderr, "not ms "+command) {
				t.Fatalf("unsupported output %s %v: %d, %q", command, suffix, status, stderr)
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
		{[]string{"run", "missing.ms", "--break=main"}, "--script and --break are valid only for ms debug, not ms run"},
		{[]string{"check", "missing.ms", "--script=commands.txt"}, "--script and --break are valid only for ms debug, not ms check"},
		{[]string{"debug", "missing.ms", "--script", "commands.txt", "--break", "main"}, "--script and --break cannot be combined"},
		{[]string{"debug", "missing.ms", "--json"}, "ms debug --json requires --script or --break"},
		{[]string{"debug", "missing.ms", "--break"}, "--break requires file:line or a function name"},
		{[]string{"debug", "missing.ms", "--script="}, "--script requires a file of debugger commands"},
		{[]string{"check", "missing.ms", "--build-type=Debug"}, "--build-type requires build"},
		{[]string{"check", "missing.ms", "--filter=name=value"}, "valid only for ms test"},
		{[]string{"test", "missing.ms", "--timeout=-1s"}, "invalid --timeout"},
		{[]string{"test", "missing.ms", "--timeout=bad=value"}, "invalid --timeout \"bad=value\""},
		{[]string{"check", "missing.ms", "--cpu-profile=cpu=1.pprof"}, "require run or test, not check"},
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

func TestTestProfilePathsUseInvocationDirectory(t *testing.T) {
	inv, status, ok := parseInvocation([]string{"test", "missing.ms", "--heap-profile=heap.pprof"})
	if !ok {
		t.Fatalf("parse status %d", status)
	}
	plan, status, ok := inv.validate()
	if !ok || status != 0 {
		t.Fatalf("validate status %d", status)
	}
	want, err := filepath.Abs("heap.pprof")
	if err != nil {
		t.Fatal(err)
	}
	if plan.options.HeapProfile != want {
		t.Fatalf("profile path %q want %q", plan.options.HeapProfile, want)
	}
}
