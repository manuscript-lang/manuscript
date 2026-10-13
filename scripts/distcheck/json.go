package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// Check the machine-readable boundary using only the copied bundled CLI and
// the same poisoned/offline environment as the rest of distribution checking.
func runResultCommand(cli, directory string, environment []string, arguments ...string) (int, []byte, string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	command := exec.CommandContext(ctx, cli, arguments...)
	command.Dir, command.Env = directory, environment
	var stdout, stderr bytes.Buffer
	command.Stdout, command.Stderr = &stdout, &stderr
	err := command.Run()
	if ctx.Err() != nil {
		return 0, nil, "", fmt.Errorf("structured distribution command timed out: %v", arguments)
	}
	status := 0
	if exit, ok := err.(*exec.ExitError); ok {
		status = exit.ExitCode()
	} else if err != nil {
		return 0, nil, "", err
	}
	return status, stdout.Bytes(), stderr.String(), nil
}

func checkJSONResults(cli, directory string, environment []string) error {
	run := func(arguments ...string) (int, []byte, string, error) {
		return runResultCommand(cli, directory, environment, arguments...)
	}
	formatDir := filepath.Join(directory, "json-format")
	if err := os.Mkdir(formatDir, 0700); err != nil {
		return err
	}
	formatFile := filepath.Join(formatDir, "value=a=b.ms")
	original := []byte("fn value() -> Int:   \n    return 0   \n")
	if err := os.WriteFile(formatFile, original, 0600); err != nil {
		return err
	}
	var previous []byte
	for _, target := range []string{formatFile, "json-format"} {
		status, output, stderr, err := run("fmt", target, "--check", "--json")
		var document struct {
			Format      int
			Files       []struct{ Path, Status string }
			Diagnostics []json.RawMessage
		}
		if err != nil || status != 1 || stderr != "" || json.Unmarshal(output, &document) != nil || document.Format != 1 || len(document.Files) != 1 || document.Files[0].Path != filepath.Join("json-format", "value=a=b.ms") || document.Files[0].Status != "needs_formatting" || len(document.Diagnostics) != 1 {
			return fmt.Errorf("format JSON: %v, status %d, %s, stderr %s", err, status, output, stderr)
		}
		if previous != nil && !bytes.Equal(output, previous) {
			return fmt.Errorf("explicit/discovered JSON paths differ")
		}
		previous = output
	}
	if data, err := os.ReadFile(formatFile); err != nil || !bytes.Equal(data, original) {
		return fmt.Errorf("format JSON changed source: %v", err)
	}
	testFile := filepath.Join(directory, "json-tests.ms")
	source := `import {stdout, stderr} from "@std/io.ms"
import panic from "@std/faults.ms"

test "pass=a=b":
    let _out = stdout().write(data: "PASS fake\nstdout=a=b\n".to_bytes())
    let _err = stderr().write(data: "stderr=a=b\n".to_bytes())

test "fails":
    return panic(message: "distribution failure")

test "after":
    return unit
`
	if err := os.WriteFile(testFile, []byte(source), 0600); err != nil {
		return err
	}
	for _, filter := range []string{"pass=a=b", ""} {
		arguments := []string{"test", testFile, "--json", "--timeout=0"}
		if filter != "" {
			arguments = append(arguments, "--filter="+filter)
		}
		status, output, stderr, err := run(arguments...)
		var document struct {
			Format      int
			ExitCode    int `json:"exit_code"`
			Completed   bool
			Stdout      string
			Tests       []struct{ Name, Status, Failure string }
			Summary     struct{ Available, Selected, Passed, Failed int }
			Diagnostics []json.RawMessage
		}
		if err != nil || json.Unmarshal(output, &document) != nil || document.Format != 1 || !document.Completed || document.ExitCode != status || stderr != "stderr=a=b\n" || !strings.Contains(document.Stdout, "stdout=a=b\n") || document.Summary.Available != 3 || len(document.Diagnostics) != 0 {
			return fmt.Errorf("test JSON: %v, status %d, %s, stderr %s", err, status, output, stderr)
		}
		if filter != "" {
			if status != 0 || len(document.Tests) != 1 || document.Summary.Selected != 1 || document.Summary.Passed != 1 || document.Tests[0].Status != "passed" {
				return fmt.Errorf("filtered JSON outcomes: %s", output)
			}
		} else if status != 1 || len(document.Tests) != 3 || document.Summary.Passed != 2 || document.Summary.Failed != 1 || document.Tests[1].Status != "failed" || !strings.Contains(document.Tests[1].Failure, "distribution failure") || !strings.Contains(document.Tests[1].Failure, "json-tests.ms:9:") || document.Tests[2].Status != "passed" {
			return fmt.Errorf("failure JSON outcomes: %s", output)
		}
	}
	return nil
}
