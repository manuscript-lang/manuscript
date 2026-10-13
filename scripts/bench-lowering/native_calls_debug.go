package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

// This builds an actual opt-in pilot artifact without adding a supported CLI
// flag or a debugger-specific representation. The adapter's prebuilt launch
// checks the usual metadata/inspection against these source and binary hashes.
func nativeCallDebugFixture(output string, enabled bool) error {
	directory, err := filepath.Abs(output)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}
	filename := filepath.Join(directory, "main.ms")
	source := "fn add(left: Int, right: Int) -> Int:\n    let total = left + right\n    return total + 1\nexport fn main() -> Int:\n    return add(1, 2) - 4\n"
	if err := os.WriteFile(filename, []byte(source), 0644); err != nil {
		return err
	}
	r := compiler.CompileFileForBuild(filename, compiler.Options{Entry: true, ExperimentalNativeCalls: enabled}, compiler.Debug)
	if !r.Success() {
		return fmt.Errorf("native DAP fixture: %v", r.Diagnostics)
	}
	if _, err := compiler.BuildCheckedWithType(r, filepath.Join(directory, "program"), "", compiler.Debug); err != nil {
		return err
	}
	inspection, err := json.MarshalIndent(tooling.Inspect(r.Program), "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(directory, "inspection.json"), inspection, 0644); err != nil {
		return err
	}
	fmt.Println("Native call Debug fixture:", directory)
	return nil
}
