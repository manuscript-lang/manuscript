package e2e_test

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"github.com/manuscript-lang/manuscript/compiler"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestCoreConformance(t *testing.T) {
	files, err := filepath.Glob("testdata/accept/*.ms")
	if err != nil {
		t.Fatal(err)
	}
	if len(files) < 18 {
		t.Fatal("missing fixtures")
	}
	for _, file := range files {
		t.Run(filepath.Base(file), func(t *testing.T) {
			result := compiler.CompileFile(file, compiler.Options{Tests: true})
			for _, d := range result.Diagnostics {
				t.Error(d)
			}
			if !result.Success() {
				return
			}
			binary := filepath.Join(t.TempDir(), "program")
			if err := compiler.Build(result.Source, binary); err != nil {
				t.Fatal(err)
			}
			data, err := exec.Command(binary).CombinedOutput()
			if err != nil {
				t.Fatalf("execution failed: %v\n%s", err, data)
			}
			if !strings.Contains(string(data), "0 failed") {
				t.Fatalf("test runner did not verify checks: %s", data)
			}
		})
	}
}
func TestRejectedFixture(t *testing.T) {
	result := compiler.CompileFile("testdata/reject/cl-03-2.ms", compiler.Options{})
	if result.Success() {
		t.Fatal("accepted private type in public surface")
	}
	if result.Diagnostics[0].Phase != "type" {
		t.Fatal(result.Diagnostics)
	}
}
func TestStandaloneHasNoRuntimeDependency(t *testing.T) {
	result := compiler.CompileSource("standalone.ms", "import panic from \"@std/faults.ms\"\n\ntest \"arithmetic\":\n    if not (2 + 3 == 5):\n        return panic(message: \"check failed\")\n", compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	source, err := compiler.Standalone(result.Source)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(source, "github.com/manuscript-lang/manuscript/runtime") {
		t.Fatal("retained runtime import")
	}
	if err := os.WriteFile(filepath.Join(t.TempDir(), "main.go"), []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
}

func TestCLIEntryAndNativeBuild(t *testing.T) {
	result := compiler.CompileFile("../../examples/hello/ms.toml", compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	executable := filepath.Join(t.TempDir(), "hello")
	if err := compiler.Build(result.Source, executable); err != nil {
		t.Fatal(err)
	}
	data, err := exec.Command(executable, "first", "second").CombinedOutput()
	if err != nil || string(data) != "Arguments: 2\n" {
		t.Fatalf("entry transcript %q, error %v", data, err)
	}
}
func TestRuntimeFaults(t *testing.T) {
	for name, source := range map[string]string{
		"failed check":  "import panic from \"@std/faults.ms\"\ntest \"fault\":\n    if 2 + 3 != 6:\n        return panic(message: \"arithmetic check failed\")\n",
		"overflow":      "fn sum(value: Int) -> Int:\n    return value + 1\ntest \"fault\":\n    let impossible = sum(value: 9223372036854775807)\n",
		"division":      "fn divide(value: Int, divisor: Int) -> Int:\n    return value / divisor\ntest \"fault\":\n    let impossible = divide(value: 3, divisor: 0)\n",
		"destructuring": "import List from \"@std/collections.ms\"\nfn difference(values: List[Int]) -> Int:\n    let [first, second] = values\n    return first - second\ntest \"fault\":\n    let impossible = difference(values: [1])\n",
	} {
		t.Run(name, func(t *testing.T) {
			result := compiler.CompileSource(name+".ms", source, compiler.Options{Tests: true})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			binary := filepath.Join(t.TempDir(), "program")
			if err := compiler.Build(result.Source, binary); err != nil {
				t.Fatal(err)
			}
			data, err := exec.Command(binary).CombinedOutput()
			if err == nil || !strings.Contains(string(data), "1 failed") {
				t.Fatalf("expected runtime fault, got %v, %s", err, data)
			}
		})
	}
}
func TestCLICommands(t *testing.T) {
	tool := os.Getenv("MANUSCRIPT_GO")
	if tool == "" {
		tool = "go"
	}
	binary := filepath.Join(t.TempDir(), "ms")
	command := exec.Command(tool, "build", "-o", binary, "../../cmd/ms")
	if data, err := command.CombinedOutput(); err != nil {
		t.Fatalf("build CLI: %v %s", err, data)
	}
	project := t.TempDir()
	for _, name := range []string{"ms.toml", "src/main.ms"} {
		data, err := os.ReadFile(filepath.Join("../../examples/hello", name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.MkdirAll(filepath.Dir(filepath.Join(project, name)), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(project, name), data, 0644); err != nil {
			t.Fatal(err)
		}
	}
	manifest := filepath.Join(project, "ms.toml")
	for _, args := range [][]string{{"check", "testdata/accept/cl-01.ms"}, {"test", "testdata/accept/cl-01.ms"}, {"lock", manifest}, {"run", manifest, "--", "a", "b"}} {
		command := exec.Command(binary, args...)
		data, err := command.CombinedOutput()
		if err != nil {
			t.Fatalf("%v: %v\n%s", args, err, data)
		}
		if args[0] == "run" && string(data) != "Arguments: 2\n" {
			t.Fatalf("run transcript %q", data)
		}
	}
	bundle := filepath.Join(project, "profile")
	if data, err := exec.Command(binary, "profile", manifest, "-o", bundle).CombinedOutput(); err != nil {
		t.Fatalf("profile bundle: %v %s", err, data)
	}
	for _, name := range []string{"program", "program.ms-build.json", "inspection.json", "manifest.json", "cpu.pprof", "heap.pprof", "trace.out"} {
		info, err := os.Stat(filepath.Join(bundle, name))
		if err != nil || info.Size() == 0 {
			t.Fatalf("missing profile artifact %s: %v", name, err)
		}
	}
	if err := exec.Command(binary, "profile", manifest, "-o", bundle).Run(); err == nil {
		t.Fatal("profile bundle overwrote existing directory")
	}

	if err := exec.Command(binary, "check", "testdata/reject/cl-03-2.ms").Run(); err == nil {
		t.Fatal("invalid source returned successful CLI status")
	}
	output := filepath.Join(t.TempDir(), "main.go")
	if data, err := exec.Command(binary, "emit", "testdata/accept/cl-01.ms", "-o", output).CombinedOutput(); err != nil {
		t.Fatalf("emit: %v %s", err, data)
	}
	if _, err := os.Stat(output); err != nil {
		t.Fatal(err)
	}
}

func TestEvaluationOrderAndEveryCleanupExit(t *testing.T) {
	result := compiler.CompileFile("testdata/projects/lifecycle/main.ms", compiler.Options{Entry: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "program")
	if err := compiler.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	data, err := exec.Command(binary).CombinedOutput()
	if err != nil {
		t.Fatalf("execution: %v %s", err, data)
	}
	expected := "callable\nsecond\nfirst\npair second\npair first\nclose normal\nafter normal\nclose iteration\nclose iteration\niterable\nclose break\nclose propagation\nreturn value\nclose inner\nclose outer\nfinished\n"
	if string(data) != expected {
		t.Fatalf("transcript mismatch\ngot:\n%s\nwant:\n%s", data, expected)
	}
}

func TestSignalCancelsJoinsAndCleansUp(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX signal shutdown")
	}
	result := compiler.CompileFile("testdata/projects/signal/main.ms", compiler.Options{Entry: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "program")
	if err := compiler.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	t.Run("native", func(t *testing.T) { checkSignalShutdown(t, binary) })
	t.Run("launcher", func(t *testing.T) {
		tool := os.Getenv("MANUSCRIPT_GO")
		if tool == "" {
			tool = "go"
		}
		launcher := filepath.Join(t.TempDir(), "ms")
		if data, err := exec.Command(tool, "build", "-o", launcher, "../../cmd/ms").CombinedOutput(); err != nil {
			t.Fatalf("build launcher: %v %s", err, data)
		}
		checkSignalShutdown(t, launcher, "run", "testdata/projects/signal/main.ms")
	})
}

func checkSignalShutdown(t *testing.T, binary string, args ...string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, binary, args...)
	var stderr bytes.Buffer
	command.Stderr = &stderr
	stdout, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	lines := make(chan string, 8)
	go func() {
		defer close(lines)
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			lines <- scanner.Text()
		}
	}()
	select {
	case line := <-lines:
		if line != "ready" {
			cancel()
			command.Wait()
			t.Fatalf("child was not ready: %q, %s", line, stderr.String())
		}
	case <-ctx.Done():
		command.Wait()
		t.Fatal("child did not become ready")
	}
	if err := command.Process.Signal(syscall.SIGTERM); err != nil {
		cancel()
		command.Wait()
		t.Fatal(err)
	}
	var transcript []string
	for line := range lines {
		transcript = append(transcript, line)
	}
	err = command.Wait()
	exit, ok := err.(*exec.ExitError)
	if !ok || exit.ExitCode() != 143 || strings.Join(transcript, "\n") != "close child\nclose parent" || stderr.Len() != 0 {
		t.Fatalf("signal shutdown: error %v, transcript %q, stderr %s", err, transcript, stderr.String())
	}
}

func TestNativeHTTPHost(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX signal lifecycle")
	}
	result := compiler.CompileFile("testdata/projects/http/main.ms", compiler.Options{Entry: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "server")
	if err := compiler.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, binary)
	var stderr bytes.Buffer
	command.Stderr = &stderr
	stdout, err := command.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	address := make(chan string, 1)
	go func() {
		reader := bufio.NewReader(stdout)
		line, _ := reader.ReadString('\n')
		address <- strings.TrimSpace(line)
	}()
	var listening string
	select {
	case listening = <-address:
	case <-ctx.Done():
		command.Wait()
		t.Fatal("HTTP host did not start")
	}
	if listening == "" {
		cancel()
		command.Wait()
		t.Fatalf("no HTTP address: %s", stderr.String())
	}
	client := &http.Client{Timeout: 2 * time.Second}
	response, err := client.Get("http://" + listening + "/world")
	if err != nil {
		cancel()
		command.Wait()
		t.Fatal(err)
	}
	output, err := io.ReadAll(response.Body)
	response.Body.Close()
	if err != nil || response.StatusCode != 200 || string(output) != "hello /world" {
		cancel()
		command.Wait()
		t.Fatalf("HTTP response %d %q error %v", response.StatusCode, output, err)
	}
	if err := command.Process.Signal(syscall.SIGTERM); err != nil {
		cancel()
		command.Wait()
		t.Fatal(err)
	}
	exit, ok := command.Wait().(*exec.ExitError)
	if !ok || exit.ExitCode() != 143 || stderr.Len() != 0 {
		t.Fatalf("HTTP shutdown: %v, %s", exit, stderr.String())
	}
}
func TestNativeSubprocessCapability(t *testing.T) {
	if _, err := os.Stat("/bin/printf"); err != nil {
		t.Skip("requires POSIX printf")
	}
	result := compiler.CompileFile("testdata/projects/command/main.ms", compiler.Options{Entry: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "program")
	if err := compiler.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	output, err := exec.Command(binary).CombinedOutput()
	if err != nil || string(output) != "hello" {
		t.Fatalf("subprocess transcript %q error %v", output, err)
	}
}
func TestCLISourceTools(t *testing.T) {
	tool := os.Getenv("MANUSCRIPT_GO")
	if tool == "" {
		tool = "go"
	}
	root := t.TempDir()
	binary := filepath.Join(root, "ms")
	if output, err := exec.Command(tool, "build", "-o", binary, "../../cmd/ms").CombinedOutput(); err != nil {
		t.Fatalf("build: %v %s", err, output)
	}
	filename := filepath.Join(root, "source.ms")
	source := "fn one( )->Int:\n    return 1 # keep\n"
	if err := os.WriteFile(filename, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	if err := exec.Command(binary, "fmt", filename, "--check").Run(); err == nil {
		t.Fatal("uncanonical formatting passed")
	}
	if output, err := exec.Command(binary, "fmt", filename).CombinedOutput(); err != nil {
		t.Fatalf("format: %v %s", err, output)
	}
	if err := exec.Command(binary, "fmt", filename, "--check").Run(); err != nil {
		t.Fatal(err)
	}
	output, err := exec.Command(binary, "inspect", filename).CombinedOutput()
	if err != nil {
		t.Fatal(err, string(output))
	}
	var inspection map[string]any
	if err := json.Unmarshal(output, &inspection); err != nil || inspection["build_id"] == "" {
		t.Fatal("invalid inspection", err)
	}
	output, err = exec.Command(binary, "diagram", filename).CombinedOutput()
	if err != nil || !strings.Contains(string(output), "flowchart TD") {
		t.Fatal(err, string(output))
	}
	invalid := "fn wrong() -> Int:\n    return missing\n"
	os.WriteFile(filename, []byte(invalid), 0600)
	output, err = exec.Command(binary, "check", filename, "--json").CombinedOutput()
	if err == nil || !strings.Contains(string(output), "MS2001") {
		t.Fatal(err, string(output))
	}
	os.WriteFile(filename, []byte("fn wrong():\n  return\n"), 0600)
	before, _ := os.ReadFile(filename)
	if err := exec.Command(binary, "fmt", filename).Run(); err == nil {
		t.Fatal("invalid input formatted")
	}
	after, _ := os.ReadFile(filename)
	if !bytes.Equal(before, after) {
		t.Fatal("invalid source was rewritten")
	}
}

func TestNominalIdentityEscapesPathDelimiters(t *testing.T) {
	result := compiler.CompileSource("data[0]:&.ms", `import panic from "@std/faults.ms"

interface Read:
    fn get() -> Int
type Box[T]:
    value: T
impl Read for Box[T]:
    fn get() -> Int:
        return 3
test "encoded nominal identity":
    let box = Box(value: 1)
    let view = Read(value: box)
    if not (view.get() == 3):
        return panic(message: "check failed")
`, compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "program")
	if err := compiler.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	output, err := exec.Command(binary).CombinedOutput()
	if err != nil || !strings.Contains(string(output), "0 failed") {
		t.Fatal(err, string(output))
	}
}

func TestExpandedLibraryCLICapabilities(t *testing.T) {
	result := compiler.CompileFile("testdata/projects/library/main.ms", compiler.Options{Entry: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	directory := t.TempDir()
	binary := filepath.Join(directory, "library")
	if runtime.GOOS == "windows" {
		binary += ".exe"
	}
	if err := compiler.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	dataPath := filepath.Join(directory, "data")
	output, err := exec.Command(binary, dataPath).CombinedOutput()
	if err != nil {
		t.Fatalf("%v: %s", err, output)
	}
	if _, err := os.Stat(dataPath); !os.IsNotExist(err) {
		t.Fatal("filesystem cleanup failed", err)
	}
}

func TestNetworkingStreamingAndWebSocket(t *testing.T) {
	result := compiler.CompileFile("testdata/projects/networking/main.ms", compiler.Options{Entry: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "networking")
	if err := compiler.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	data, err := exec.CommandContext(ctx, binary).CombinedOutput()
	if err != nil {
		t.Fatalf("%v: %s", err, data)
	}
}

func TestDefaultArgumentsAcrossModules(t *testing.T) {
	root := t.TempDir()
	library := `fn private_value() -> Int:
    return 7
export fn defaulted(value: Int = private_value()) -> Int:
    return value
`
	main := `import defaulted from "./library.ms"
import panic from "@std/faults.ms"
fn private_value() -> Int:
    return 99
test "defaults use their declaration module":
    let copy = defaulted
    if defaulted() != 7 or copy() != 7 or defaulted(0) != 0:
        return panic("incorrect default scope")
`
	for name, source := range map[string]string{"library.ms": library, "main.ms": main} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	result := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{Tests: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(root, "program")
	if err := compiler.Build(result.Source, binary); err != nil {
		t.Fatal(err)
	}
	data, err := exec.Command(binary).CombinedOutput()
	if err != nil || !strings.Contains(string(data), "1 tests, 0 failed") {
		t.Fatalf("%v: %s", err, data)
	}
}
