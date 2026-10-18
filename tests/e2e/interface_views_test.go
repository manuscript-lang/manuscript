package e2e_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

const interfaceViewRepro = `interface Read:
    fn read() Int
type Reader:
    operation: fn() Int
impl Read for Reader:
    fn read() Int:
        return self.operation()
export fn main() Int:
    let view = Read(Reader(fn() Int: 1))
    return view.read()
`

func TestInterfaceViewExactRepro(t *testing.T) {
	root := t.TempDir()
	file := filepath.Join(root, "main.ms")
	if err := os.WriteFile(file, []byte(interfaceViewRepro), 0600); err != nil {
		t.Fatal(err)
	}
	for _, command := range []string{"check", "emit"} {
		if output, err := commandOutput(t, cliBinary, command, file); err != nil {
			t.Fatalf("%s: %v\n%s", command, err, output)
		}
	}
	// The exact reported program intentionally returns 1.
	for _, level := range []string{"Debug", "Release"} {
		binary := filepath.Join(root, level)
		if output, err := commandOutput(t, cliBinary, "build", file, "--build-type", level, "-o", binary); err != nil {
			t.Fatalf("build %s: %v\n%s", level, err, output)
		}
		output, err := commandOutput(t, binary)
		exit, ok := err.(*exec.ExitError)
		if !ok || exit.ExitCode() != 1 || len(output) != 0 {
			t.Fatalf("%s: exact repro returned %v, %q; want exit 1", level, err, output)
		}
	}
}

func TestInterfaceViewFaultFrames(t *testing.T) {
	for name, source := range map[string]string{
		"callback":    strings.Replace(interfaceViewRepro, "Int: 1)", "Int: 1 / 0)", 1),
		"preparation": strings.Replace(interfaceViewRepro, "export fn main()", "fn prepare() fn() Int:\n    let invalid = 1 / 0\n    return fn() Int: 1\nexport fn main()", 1),
	} {
		t.Run(name, func(t *testing.T) {
			if name == "preparation" {
				source = strings.Replace(source, "Reader(fn() Int: 1)", "Reader(prepare())", 1)
			}
			output, err := execute(t, compiler.CompileSource("view-fault.ms", source, compiler.Options{Entry: true}))
			if err == nil || !strings.Contains(string(output), "division by zero") {
				t.Fatalf("expected source fault: %v\n%s", err, output)
			}
			frames := []string{"view-fault.ms:9 in <anonymous>", "view-fault.ms:7 in Reader.read", "view-fault.ms:10 in main"}
			if name == "preparation" {
				frames = []string{"view-fault.ms:9 in prepare", "view-fault.ms:12 in main"}
			}
			var actual []string
			for _, line := range strings.Split(string(output), "\n") {
				if frame, ok := strings.CutPrefix(line, "  at "); ok {
					actual = append(actual, frame)
				}
			}
			if !reflect.DeepEqual(actual, frames) {
				t.Fatalf("fault frames = %q, want %q\n%s", actual, frames, output)
			}
		})
	}
}
