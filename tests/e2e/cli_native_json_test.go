package e2e_test

import (
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type nativeJSONDocument struct {
	Format                 int
	Command                string
	BuildType              string `json:"build_type"`
	SourceRoot             string `json:"source_root"`
	Output, Reason, Stdout string
	StdoutBase64           string `json:"stdout_base64"`
	Completed              bool
	ExitCode               int `json:"exit_code"`
	Artifacts              []struct{ Kind, Path, State string }
	Diagnostics            []struct {
		Code, Phase, Message string
		Position             struct {
			File                 string
			Line, Column, Offset int
		}
	}
}

func decodeNativeJSON(t *testing.T, output []byte) nativeJSONDocument {
	t.Helper()
	var document nativeJSONDocument
	if err := json.Unmarshal(output, &document); err != nil || document.Format != 1 {
		t.Fatalf("invalid native document: %v: %s", err, output)
	}
	return document
}

func TestCLIBuildJSONSuccessAndPartialArtifacts(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "main=a=b.ms")
	if err := os.WriteFile(source, []byte("export fn main() Int:\n    return 0\n"), 0600); err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(root, "program=a=b")
	status, stdout, stderr := cliStreams(t, "build", source, "--json", "--build-type=Debug", "--output="+output)
	document := decodeNativeJSON(t, stdout)
	if status != 0 || stderr != "" || document.Command != "build" || document.BuildType != "Debug" || !document.Completed || document.ExitCode != 0 || document.Output != output || document.Stdout != "" || len(document.Diagnostics) != 0 || len(document.Artifacts) != 2 {
		t.Fatalf("successful build: %d, %s, %s", status, stdout, stderr)
	}
	for _, artifact := range document.Artifacts {
		if artifact.State != "verified" {
			t.Fatalf("successful artifact not verified: %+v", artifact)
		}
		if _, err := os.Stat(artifact.Path); err != nil {
			t.Fatal(err)
		}
	}
	// The native builder publishes the executable before the metadata. An
	// existing directory at the metadata path causes a real partial failure.
	partial := filepath.Join(root, "partial=a=b")
	if err := os.Mkdir(partial+".ms-build.json", 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(partial+".ms-build.json", "keep"), []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	status, stdout, stderr = cliStreams(t, "build", source, "--json", "--output="+partial)
	document = decodeNativeJSON(t, stdout)
	if status != 1 || stderr == "" || document.Completed || document.ExitCode != 1 || document.Reason != "build_error" || len(document.Diagnostics) != 1 || document.Diagnostics[0].Code != "MSN001" || document.Artifacts[0].State != "written" || document.Artifacts[1].State != "unavailable" {
		t.Fatalf("partial build: %d, %s, %s", status, stdout, stderr)
	}
	if data, err := commandOutput(t, partial); err != nil || len(data) != 0 {
		t.Fatalf("partial executable not usable: %v, %s", err, data)
	}
}

const nativeProfileSource = `import arguments from "@std/process.ms"
import {stdout, stderr} from "@std/io.ms"

export fn main() Int:
    let args = arguments()
    if args.length() > 0 and args[0] == "binary":
        let _raw = stdout().write(data: "x".to_bytes().with_value(index: 0, value: 255))
        return 0
    let _out = stdout().write(data: "stdout\n".to_bytes())
    let _err = stderr().write(data: "stderr\n".to_bytes())
    var index = 0
    while index < args.length():
        let _arg = stdout().write(data: "arg={args[index].get()}\n".to_bytes())
        index = index + 1
    if args.length() > 0 and args[0] == "fail":
        return 23
    return 0
`

func TestCLIProfileJSONCollectorsForwardingAndStreams(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "profile=a=b.ms")
	if err := os.WriteFile(source, []byte(nativeProfileSource), 0600); err != nil {
		t.Fatal(err)
	}
	for _, trace := range []bool{false, true} {
		output := filepath.Join(t.TempDir(), "capture=a=b")
		args := []string{"profile", source, "--json", "--out-dir=" + output}
		if trace {
			args = append(args, "--trace")
		}
		args = append(args, "--", "fail", "--out-dir=application-value", "--json")
		status, stdout, stderr := cliStreams(t, args...)
		document := decodeNativeJSON(t, stdout)
		if status != 23 || document.ExitCode != 23 || !document.Completed || document.Reason != "program_exit" || document.Command != "profile" || document.BuildType != "RelWithDebInfo" || document.Stdout != "stdout\narg=fail\narg=--out-dir=application-value\narg=--json\n" || document.StdoutBase64 != "" || stderr != "stderr\n" || len(document.Diagnostics) != 0 {
			t.Fatalf("profile streams/status: %d, %s, %s", status, stdout, stderr)
		}
		want := 6
		if trace {
			want++
		}
		if len(document.Artifacts) != want {
			t.Fatalf("collector inventory: %s", stdout)
		}
		for _, artifact := range document.Artifacts {
			info, err := os.Stat(artifact.Path)
			if err != nil || !info.Mode().IsRegular() || info.Size() == 0 || artifact.State == "missing" || artifact.State == "preserved" {
				t.Fatalf("unwritten profile artifact: %+v, %v", artifact, err)
			}
		}
		manifest, err := os.ReadFile(filepath.Join(output, "manifest.json"))
		if err != nil || strings.Contains(string(manifest), `"trace"`) != trace {
			t.Fatalf("collector manifest: %v, %s", err, manifest)
		}
	}
	output := filepath.Join(t.TempDir(), "binary-capture")
	status, stdout, stderr := cliStreams(t, "profile", source, "--json", "--out-dir", output, "--", "binary")
	document := decodeNativeJSON(t, stdout)
	decoded, err := base64.StdEncoding.DecodeString(document.StdoutBase64)
	if status != 0 || stderr != "" || !document.Completed || document.Stdout != "" || err != nil || len(decoded) != 1 || decoded[0] != 255 {
		t.Fatalf("profile binary stdout: %d, %s, %s, %v", status, stdout, stderr, err)
	}
}

func TestCLIProfileJSONPreservesExistingDirectory(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "main.ms")
	if err := os.WriteFile(source, []byte("export fn main() Int:\n    return 0\n"), 0600); err != nil {
		t.Fatal(err)
	}
	output := t.TempDir()
	existing := filepath.Join(output, "cpu.pprof")
	if err := os.WriteFile(existing, []byte("keep previous profile"), 0600); err != nil {
		t.Fatal(err)
	}
	status, stdout, stderr := cliStreams(t, "profile", source, "--json", "--out-dir", output)
	document := decodeNativeJSON(t, stdout)
	after, err := os.ReadFile(existing)
	if status != 1 || stderr == "" || document.Completed || document.Reason != "artifact_error" || len(document.Diagnostics) != 1 || err != nil || string(after) != "keep previous profile" {
		t.Fatalf("existing capture was changed: %d, %s, %s, %s, %v", status, stdout, stderr, after, err)
	}
	for _, artifact := range document.Artifacts {
		if artifact.Kind == "cpu_profile" && artifact.State != "preserved" {
			t.Fatalf("claimed ownership of old profile: %+v", artifact)
		}
	}
}
