package e2e_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInvalidBoundsProduceDiagnosticsWithoutExecutable(t *testing.T) {
	source := "type Box[Error: Error]:\n    cause: Error\nimpl Error for Box[Error]:\n    fn message() String: self.cause.message()\nexport fn main() Int: 0\n"
	file := filepath.Join(t.TempDir(), "bounds.ms")
	if err := os.WriteFile(file, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	for _, mode := range []string{"check", "lint", "inspect"} {
		output, _ := commandOutput(t, cliBinary, mode, file)
		if !strings.Contains(string(output), "a bound must be an interface") || strings.Contains(string(output), "fatal error") {
			t.Fatalf("%s: %s", mode, output)
		}
	}
	outputFile := filepath.Join(t.TempDir(), "invalid")
	output, err := commandOutput(t, cliBinary, "build", file, "-o", outputFile)
	if err == nil || !strings.Contains(string(output), "a bound must be an interface") {
		t.Fatalf("%v: %s", err, output)
	}
	if _, err := os.Stat(outputFile); !os.IsNotExist(err) {
		t.Fatalf("invalid bound produced executable: %v", err)
	}
}
