package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestVersionAliasAndArgumentErrors(t *testing.T) {
	status, original, stderr := invoke(t, "--version")
	if status != 0 || stderr != "" {
		t.Fatalf("version flag: %d, %q", status, stderr)
	}
	status, alias, stderr := invoke(t, "version")
	if status != 0 || alias != original || stderr != "" {
		t.Fatalf("version alias: %d, %q, %q", status, alias, stderr)
	}
	for _, args := range [][]string{{"version", "extra"}, {"version", "--json"}, {"version", "--", "argument"}, {"version", "extra", "--help"}, {"version", "--help", "extra"}, {"--version", "extra"}, {"--version", "--help"}} {
		status, stdout, stderr := invoke(t, args...)
		if status != 2 || stdout != "" || !strings.Contains(stderr, "takes no arguments") {
			t.Fatalf("extra version arguments %v: %d, %q, %q", args, status, stdout, stderr)
		}
	}
	for _, args := range [][]string{{"help", "version"}, {"version", "--help"}} {
		status, stdout, stderr := invoke(t, args...)
		if status != 0 || stderr != "" || !strings.Contains(stdout, "Usage: ms version") {
			t.Fatalf("version help %v: %d, %q, %q", args, status, stdout, stderr)
		}
	}
}

func TestNativeJSONCompileFailuresPreserveOutputs(t *testing.T) {
	file := sourceFile(t, "export fn main() Int:\n    return unknown_name\n")
	for _, command := range []string{"build", "profile"} {
		output := filepath.Join(t.TempDir(), "output=a=b")
		if command == "build" {
			if err := os.WriteFile(output, []byte("previous executable"), 0600); err != nil {
				t.Fatal(err)
			}
		}
		status, stdout, stderr := invoke(t, command, file, "--json", "--output="+output)
		var document nativeResult
		if status != 1 || stderr != "" || json.Unmarshal([]byte(stdout), &document) != nil || document.Format != 1 || document.Command != command || document.Completed || document.ExitCode != 1 || document.Reason != "compile_error" || document.Output != output || len(document.Diagnostics) != 1 || document.Diagnostics[0].Position.Line != 2 || len(document.Artifacts) == 0 {
			t.Fatalf("%s compile result: %d, %s, %q", command, status, stdout, stderr)
		}
		if command == "build" {
			data, err := os.ReadFile(output)
			if err != nil || string(data) != "previous executable" || document.Artifacts[0].State != "preserved" {
				t.Fatalf("source failure replaced existing output: %s, %v, %+v", data, err, document.Artifacts)
			}
		} else if _, err := os.Stat(output); !os.IsNotExist(err) {
			t.Fatalf("failed checking created profile directory: %v", err)
		}
	}
}

func TestProfileOutDirSpellingsUsageAndHelp(t *testing.T) {
	file := sourceFile(t, "export fn main() Int:\n    return unknown_name\n")
	output := filepath.Join(t.TempDir(), "capture=a=b")
	var previous string
	for _, values := range [][]string{{"--out-dir", output}, {"--out-dir=" + output}, {"--output", output}, {"-o", output}} {
		status, stdout, stderr := invoke(t, append([]string{"profile", file, "--json"}, values...)...)
		if status != 1 || stderr != "" || previous != "" && stdout != previous {
			t.Fatalf("profile aliases %v: %d, %q, %q", values, status, stdout, stderr)
		}
		previous = stdout
	}
	for _, values := range [][]string{{"--out-dir"}, {"--out-dir", ""}, {"--out-dir="}} {
		status, stdout, stderr := invoke(t, append([]string{"profile", file}, values...)...)
		if status != 2 || stdout != "" || !strings.Contains(stderr, "--out-dir requires a path") {
			t.Fatalf("empty out-dir %v: %d, %q, %q", values, status, stdout, stderr)
		}
	}
	status, stdout, stderr := invoke(t, "profile", "missing.ms", "--out-dir", "--help")
	if status != 1 || stdout != "" || !strings.Contains(stderr, "file not found") {
		t.Fatalf("out-dir value consumed as help: %d, %q, %q", status, stdout, stderr)
	}
	for _, command := range []string{"build", "run", "test", "check", "lint", "inspect", "diagram", "debug"} {
		status, stdout, stderr := invoke(t, command, file, "--out-dir="+output)
		if status != 2 || stdout != "" || !strings.Contains(stderr, "valid only for ms profile") {
			t.Fatalf("unsupported out-dir %s: %d, %q, %q", command, status, stdout, stderr)
		}
	}
}

func TestNativeArtifactInventoryDistinguishesPartialAndPreservedFiles(t *testing.T) {
	output := filepath.Join(t.TempDir(), "program")
	if err := os.WriteFile(output, []byte("preserve"), 0600); err != nil {
		t.Fatal(err)
	}
	snapshots := nativeArtifactSnapshots("build", output, false)
	document := nativeResult{}
	document.inventory(snapshots, nil)
	if document.Artifacts[0].State != "preserved" || document.Artifacts[1].State != "missing" {
		t.Fatalf("baseline inventory: %+v", document.Artifacts)
	}
	if err := os.WriteFile(output, []byte("partial executable publication"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(output+".ms-build.json", 0700); err != nil {
		t.Fatal(err)
	}
	document.inventory(snapshots, nil)
	if document.Artifacts[0].State != "written" || document.Artifacts[1].State != "unavailable" {
		t.Fatalf("partial inventory: %+v", document.Artifacts)
	}
}
