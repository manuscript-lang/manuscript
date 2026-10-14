package examples_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

// Check the actual application modules; native coverage runs their behavioral
// tests and the demo rather than maintaining a second copy of the agent.
func TestPiAgent(t *testing.T) {
	for _, example := range []struct {
		file string
		mode string
		want string
	}{
		{"test.ms", "test", ""},
		{"main.ms", "run", "Say hello\nHello from a native Manuscript tool\nDone.\n"},
	} {
		t.Run(example.file, func(t *testing.T) {
			path := filepath.Join("../../examples/pi-agent/src", example.file)
			options := compiler.Options{Tests: example.mode == "test", Entry: example.mode == "run", AnalyzeOnly: true}
			result := compiler.CompileFile(path, options)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			if os.Getenv("MANUSCRIPT_EXAMPLES_NATIVE") != "1" {
				return
			}
			options.AnalyzeOnly = false
			result = compiler.CompileFile(path, options)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			binary := filepath.Join(t.TempDir(), "pi-agent")
			if err := build.Build(result.Source, binary); err != nil {
				t.Fatal(err)
			}
			runExample(t, binary, example.mode, exampleRun{Stdout: example.want})
		})
	}
}
