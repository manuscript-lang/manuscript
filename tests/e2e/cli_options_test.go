package e2e_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCLIInlineValueOptions(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "main=a=b.ms")
	code := `import arguments from "@std/process.ms"
import stdout from "@std/io.ms"
import stderr from "@std/io.ms"

fn write_line(text: String) Result[Unit, Error]:
    try stdout().write(data: "{text}\n")
    return ok(unit)

fn exercise() Result[Int, Error]:
    let args = arguments()
    var index = 0
    while index < args.length():
        try write_line(args[index])
        index = index + 1
    return ok(0)

export fn main() Int:
    match exercise():
        ok(status): return status
        error(cause):
            let written = stderr().write("{cause.message()}\n")
            return 1

test "selected=a=b":
    try write_line("selected")

test "unselected":
    write_line("unselected")
`
	if err := os.WriteFile(source, []byte(code), 0600); err != nil {
		t.Fatal(err)
	}
	for _, inline := range []bool{false, true} {
		t.Run(map[bool]string{false: "split", true: "inline"}[inline], func(t *testing.T) {
			value := func(flag, text string) []string {
				if inline {
					return []string{flag + "=" + text}
				}
				return []string{flag, text}
			}
			output := filepath.Join(t.TempDir(), "program=a=b")
			args := append([]string{"build", source}, value("--output", output)...)
			args = append(args, value("--build-type", "dEbUg")...)
			if data, err := commandOutput(t, cliBinary, args...); err != nil {
				t.Fatalf("build: %v\n%s", err, data)
			}
			metadata, err := os.ReadFile(output + ".ms-build.json")
			var build struct {
				BuildType string `json:"build_type"`
			}
			if err != nil || json.Unmarshal(metadata, &build) != nil || build.BuildType != "Debug" {
				t.Fatalf("build type: %v, %s", err, metadata)
			}
			args = append([]string{"test", source}, value("--filter", "selected=a=b")...)
			args = append(args, value("--timeout", "0")...)
			if data, err := commandOutput(t, cliBinary, args...); err != nil || !strings.Contains(string(data), "selected\n") || strings.Contains(string(data), "::unselected") || !strings.Contains(string(data), "1 tests, 0 failed") {
				t.Fatalf("filter/timeout: %v\n%s", err, data)
			}
		})
	}
	profiles := t.TempDir()
	cpu := filepath.Join(profiles, "cpu=a=b.pprof")
	heap := filepath.Join(profiles, "heap=a=b.pprof")
	trace := filepath.Join(profiles, "trace=a=b.out")
	forwarded := []string{"--output=", "--unknown=a=b", "--help", "a=b=c"}
	args := []string{"run", source, "--cpu-profile=" + cpu, "--heap-profile=" + heap, "--trace=" + trace, "--"}
	args = append(args, forwarded...)
	if data, err := commandOutput(t, cliBinary, args...); err != nil || string(data) != strings.Join(forwarded, "\n")+"\n" {
		t.Fatalf("profile paths/forwarding: %v\n%s", err, data)
	}
	for _, file := range []string{cpu, heap, trace} {
		if info, err := os.Stat(file); err != nil || info.Size() == 0 {
			t.Fatalf("profile %s: %v", file, err)
		}
	}
	// Viewer arguments bypass Manuscript's value parser, including their own
	// equals syntax and profile filenames containing equals signs.
	if data, err := commandOutput(t, cliBinary, "pprof", "-top", "-unit=bytes", heap); err != nil || !strings.Contains(string(data), "Type: inuse_space") {
		t.Fatalf("pprof passthrough: %v\n%s", err, data)
	}
	if data, err := commandOutput(t, cliBinary, "trace", "-d=parsed", trace); err != nil || !strings.Contains(string(data), "StateTransition") {
		t.Fatalf("trace passthrough: %v\n%s", err, data)
	}
	bundle := filepath.Join(t.TempDir(), "bundle=a=b")
	if data, err := commandOutput(t, cliBinary, "profile", source, "--out-dir="+bundle, "--build-type=Release", "--", "--filter=a=b"); err != nil || string(data) != "--filter=a=b\n" {
		t.Fatalf("bundle directory/forwarding: %v\n%s", err, data)
	}
	if _, err := os.Stat(filepath.Join(bundle, "manifest.json")); err != nil {
		t.Fatal(err)
	}
}
