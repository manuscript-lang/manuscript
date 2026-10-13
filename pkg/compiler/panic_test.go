package compiler

import (
	"strings"
	"testing"
)

func TestCompilerPanicBecomesDiagnostic(t *testing.T) {
	result := func() (result Result) {
		defer recoverCompilerBug("a.ms", &result)
		panic("boom")
	}()
	if result.Success() || len(result.Diagnostics) != 1 || result.Diagnostics[0].Position.File != "a.ms" || !strings.Contains(result.Diagnostics[0].Message, "boom") {
		t.Fatalf("%+v", result.Diagnostics)
	}
}
