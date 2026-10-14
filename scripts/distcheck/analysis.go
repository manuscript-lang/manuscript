package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func checkAnalysisCollections(cli, directory string, environment []string) error {
	root := filepath.Join(directory, "analysis")
	for name, source := range map[string]string{
		"left/main.ms":   "export fn main() -> Int:\n    return 0\n",
		"right/main.ms":  "export fn main() -> Int:\n    return 0\n",
		"nested/ms.toml": "invalid nested manifest",
		"nested/bad.ms":  "invalid source",
		".hidden/bad.ms": "invalid source",
	} {
		file := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(file), 0700); err != nil {
			return err
		}
		if err := os.WriteFile(file, []byte(source), 0600); err != nil {
			return err
		}
	}
	run := func(arguments ...string) (int, []byte, string, error) {
		return runResultCommand(cli, directory, environment, arguments...)
	}
	for _, command := range []string{"check", "lint", "doc"} {
		status, output, stderr, err := run(command, "analysis", "--json")
		if err != nil || status != 0 || stderr != "" || !json.Valid(output) {
			return fmt.Errorf("standalone %s selection: %v, status %d, %s, stderr %s", command, err, status, output, stderr)
		}
		if command == "doc" {
			var reference struct {
				Format  int
				Modules []struct{ Path string }
			}
			if json.Unmarshal(output, &reference) != nil || reference.Format != 1 || len(reference.Modules) != 2 || reference.Modules[0].Path != "analysis/left/main.ms" || reference.Modules[1].Path != "analysis/right/main.ms" {
				return fmt.Errorf("independent documentation identities: %s", output)
			}
		}
		status, explicit, stderr, err := run(command, "analysis/right/main.ms", "analysis/left/main.ms", "analysis/left/main.ms", "--json")
		if err != nil || status != 0 || stderr != "" || !bytes.Equal(output, explicit) {
			return fmt.Errorf("explicit/discovered %s parity: %v, status %d, %s, stderr %s", command, err, status, explicit, stderr)
		}
	}
	if err := os.WriteFile(filepath.Join(root, "left/main.ms"), []byte("export fn main() -> Int:\n    return 0   \n"), 0600); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(root, "right/main.ms"), []byte("export fn main() -> Int:\n    return missing\n"), 0600); err != nil {
		return err
	}
	status, output, stderr, err := run("lint", "analysis", "--json")
	var report struct {
		Format      int
		Diagnostics []struct {
			Code     string
			Position struct {
				File string
				Line int
			}
		}
	}
	if err != nil || status != 1 || stderr != "" || json.Unmarshal(output, &report) != nil || report.Format != 1 || len(report.Diagnostics) != 2 || report.Diagnostics[0].Code != "MSL001" || report.Diagnostics[0].Position.File != filepath.Join("analysis", "left", "main.ms") || report.Diagnostics[1].Position.File != filepath.Join("analysis", "right", "main.ms") || report.Diagnostics[1].Position.Line != 2 {
		return fmt.Errorf("partial lint aggregation: %v, status %d, %s, stderr %s", err, status, output, stderr)
	}
	artifact := filepath.Join(directory, "analysis-api.json")
	if err := os.WriteFile(artifact, []byte("preserve artifact"), 0600); err != nil {
		return err
	}
	status, output, stderr, err = run("doc", "analysis", "--json", "--output="+artifact)
	after, readErr := os.ReadFile(artifact)
	if err != nil || status != 1 || len(output) != 0 || !strings.Contains(stderr, "missing") || readErr != nil || string(after) != "preserve artifact" {
		return fmt.Errorf("failed documentation preservation: %v, status %d, %s, stderr %s, artifact %s", err, status, output, stderr, after)
	}
	return nil
}
