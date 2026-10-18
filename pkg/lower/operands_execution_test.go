package lower_test

import (
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestOperandCapturesExecuteInSourceOrder(t *testing.T) {
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
		t.Run(string(kind), func(t *testing.T) {
			result := compiler.CompileFileForBuild("testdata/operand-captures.ms", compiler.Options{Tests: true}, kind)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			binary := filepath.Join(t.TempDir(), "captures")
			if _, err := build.BuildCheckedWithType(result, binary, kind); err != nil {
				t.Fatal(err)
			}
			if output, err := exec.Command(binary).CombinedOutput(); err != nil {
				t.Fatalf("capture order: %v\n%s", err, output)
			}
		})
	}
}
