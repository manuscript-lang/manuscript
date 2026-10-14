package e2e_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

type jsonTestDocument struct {
	Format     int    `json:"format"`
	SourceRoot string `json:"source_root"`
	Tests      []struct {
		Name    string `json:"name"`
		Status  string `json:"status"`
		Failure string `json:"failure"`
	} `json:"tests"`
	Summary      struct{ Available, Selected, Passed, Failed int } `json:"summary"`
	Completed    bool                                              `json:"completed"`
	ExitCode     int                                               `json:"exit_code"`
	Reason       string                                            `json:"reason"`
	Stdout       string                                            `json:"stdout"`
	StdoutBase64 string                                            `json:"stdout_base64"`
	Diagnostics  []struct {
		Code, Phase, Message string
		Position             syntax.Position
	} `json:"diagnostics"`
}

func cliStreams(t *testing.T, args ...string) (int, []byte, string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	command := exec.CommandContext(ctx, cliBinary, args...)
	var stdout, stderr bytes.Buffer
	command.Stdout, command.Stderr = &stdout, &stderr
	err := command.Run()
	status := 0
	if err != nil {
		var exit *exec.ExitError
		if !errors.As(err, &exit) {
			t.Fatal(err)
		}
		status = exit.ExitCode()
	}
	if ctx.Err() != nil {
		t.Fatalf("CLI timed out: %v\n%s\n%s", args, stdout.Bytes(), stderr.String())
	}
	return status, stdout.Bytes(), stderr.String()
}

func TestCLITestJSONPreservesOutputsFailuresAndLocations(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "test=a=b.ms")
	source := `import {stdout, stderr} from "@std/io.ms"
import panic from "@std/faults.ms"

test "first=pass":
    let _out = stdout().write(data: "PASS fake test\nuser stdout\n".to_bytes())
    let _err = stderr().write(data: "user stderr\n".to_bytes())

test "second=fails":
    return panic(message: "expected failure")

test "third=after":
    return unit
`
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	humanStatus, humanOut, humanErr := cliStreams(t, "test", path, "--timeout=0")
	status, output, stderr := cliStreams(t, "test", path, "--timeout=0", "--json")
	var doc jsonTestDocument
	if status != humanStatus || status != 1 || json.Unmarshal(output, &doc) != nil || doc.Format != 1 || !doc.Completed || doc.ExitCode != 1 || len(doc.Diagnostics) != 0 || len(doc.Tests) != 3 {
		t.Fatalf("test JSON: %d %s %s", status, output, stderr)
	}
	if doc.Stdout != string(humanOut) || stderr != humanErr || stderr != "user stderr\n" {
		t.Fatalf("streams changed: stdout=%q/%q stderr=%q/%q", doc.Stdout, humanOut, stderr, humanErr)
	}
	if doc.Summary.Available != 3 || doc.Summary.Selected != 3 || doc.Summary.Passed != 2 || doc.Summary.Failed != 1 || doc.Tests[0].Status != "passed" || doc.Tests[1].Status != "failed" || doc.Tests[2].Status != "passed" || !strings.Contains(doc.Tests[1].Failure, "expected failure") || !strings.Contains(doc.Tests[1].Failure, "test=a=b.ms:9") || doc.SourceRoot != root {
		t.Fatalf("outcomes/locations/order: %s", output)
	}
	for _, filter := range []string{"first=pass", "nothing=matches"} {
		status, output, stderr = cliStreams(t, "test", path, "--filter="+filter, "--json")
		if json.Unmarshal(output, &doc) != nil || !doc.Completed || doc.Summary.Available != 3 {
			t.Fatalf("filter: %d %s %s", status, output, stderr)
		}
		if filter == "first=pass" {
			if status != 0 || doc.Summary.Selected != 1 || doc.Tests[0].Status != "passed" {
				t.Fatalf("selected: %s", output)
			}
		} else if status != 1 || doc.Reason != "no_match" || len(doc.Tests) != 0 || doc.Summary.Selected != 0 {
			t.Fatalf("unmatched: %s", output)
		}
	}
}

func TestCLITestJSONEmptyCompileErrorAndTimeout(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tests.ms")
	for _, tc := range []struct {
		source string
		status int
		reason string
	}{
		{"export fn helper() -> Int: return 0\n", 0, "no_tests"},
		{"test \"bad\":\n    let x = unknown_name\n", 1, "compile_error"},
		{"import {sleep, duration} from \"@std/time.ms\"\n\ntest \"timeout\":\n    sleep(duration(nanoseconds: 1000000000))\n\ntest \"after\":\n    return unit\n", 1, ""},
	} {
		if err := os.WriteFile(path, []byte(tc.source), 0600); err != nil {
			t.Fatal(err)
		}
		status, output, stderr := cliStreams(t, "test", path, "--json", "--timeout=20ms")
		var doc jsonTestDocument
		if status != tc.status || json.Unmarshal(output, &doc) != nil || doc.ExitCode != status || doc.Reason != tc.reason || stderr != "" {
			t.Fatalf("%q: %d %s %s", tc.source, status, output, stderr)
		}
		if tc.reason == "compile_error" {
			if doc.Completed || len(doc.Tests) != 0 || len(doc.Diagnostics) == 0 || doc.Diagnostics[0].Phase != "resolution" || doc.Diagnostics[0].Position.Line != 2 || doc.Diagnostics[0].Position.File != "tests.ms" {
				t.Fatalf("compile diagnostics: %s", output)
			}
		} else if !doc.Completed {
			t.Fatalf("incomplete ordinary run: %s", output)
		}
		if tc.reason == "" && (len(doc.Tests) != 2 || doc.Tests[0].Status != "failed" || !strings.Contains(doc.Tests[0].Failure, "timed out after 20ms") || doc.Tests[1].Status != "passed") {
			t.Fatalf("timeout stopped later test: %s", output)
		}
	}
	status, output, stderr := cliStreams(t, "test", path, "--json", "--watch")
	if status != 2 || len(output) != 0 || !strings.Contains(stderr, "--json cannot be combined with --watch") {
		t.Fatalf("watch JSON: %d %s %s", status, output, stderr)
	}
}

func TestCLITestJSONPreservesBinaryStdout(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bytes.ms")
	source := "import stdout from \"@std/io.ms\"\nimport Bytes from \"@std/bytes.ms\"\n\ntest \"bytes\":\n    let data = \"x\".to_bytes().with_value(index: 0, value: 255)\n    let _out = stdout().write(data: data)\n"
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	status, human, _ := cliStreams(t, "test", path)
	jsonStatus, output, stderr := cliStreams(t, "test", path, "--json")
	var doc jsonTestDocument
	if status != 0 || jsonStatus != status || stderr != "" || json.Unmarshal(output, &doc) != nil || doc.Stdout != "" || doc.StdoutBase64 == "" {
		t.Fatalf("binary output: %d %s %s", jsonStatus, output, stderr)
	}
	decoded, err := base64.StdEncoding.DecodeString(doc.StdoutBase64)
	if err != nil || !bytes.Equal(decoded, human) {
		t.Fatalf("stdout bytes changed: %v %v != %v", err, decoded, human)
	}
}
