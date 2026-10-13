// distcheck exercises a packaged CLI without host tools or network downloads.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

func main() {
	if marker := os.Getenv("MS_TEST_POISON"); marker != "" {
		_ = os.WriteFile(marker, []byte(os.Args[0]), 0600)
		os.Exit(99)
	}
	if err := check(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println("Packaged compilation, source tooling, LSP, terminal/DAP debugging, and profiles passed using only ms, without system Go, dlv, or downloads (macOS uses system debugserver).")
}

func check() error {
	if len(os.Args) != 2 {
		return fmt.Errorf("usage: distcheck <extracted-distribution>")
	}
	distribution, err := filepath.Abs(os.Args[1])
	if err != nil {
		return err
	}
	suffix := ""
	if runtime.GOOS == "windows" {
		suffix = ".exe"
	}
	directory, err := os.MkdirTemp("", "manuscript-offline-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(directory)
	// Compiler metadata uses canonical source roots. In particular macOS /var
	// is a symlink to /private/var; DAP breakpoint paths must use the same identity.
	directory, err = filepath.EvalSymlinks(directory)
	if err != nil {
		return err
	}
	// Only the binary is installed: its SDK must come from its own contents.
	cli := filepath.Join(directory, "ms"+suffix)
	data, err := os.ReadFile(filepath.Join(distribution, "ms"+suffix))
	if err != nil {
		return err
	}
	if err := os.WriteFile(cli, data, 0755); err != nil {
		return err
	}
	project := filepath.Join(directory, "hello")
	for _, name := range []string{"ms.toml", "src/main.ms", "test.ms"} {
		data, err := os.ReadFile(filepath.Join(distribution, "examples", "hello", name))
		if err != nil {
			return err
		}
		filename := filepath.Join(project, name)
		if err := os.MkdirAll(filepath.Dir(filename), 0755); err != nil {
			return err
		}
		if err := os.WriteFile(filename, data, 0644); err != nil {
			return err
		}
	}
	poison, marker, err := poisonTools(directory, suffix)
	if err != nil {
		return err
	}
	// Deliberately conflicting host settings must not replace the bundled SDK.
	settings := map[string]string{
		"PATH": directory, "MANUSCRIPT_GO": filepath.Join(poison, "go"+suffix), "GOROOT": filepath.Join(directory, "missing-go"),
		"GOTOOLCHAIN": "auto", "GOENV": filepath.Join(directory, "missing-go-env"),
		"CGO_ENABLED": "1", "GOPROXY": "off", "GOSUMDB": "off", "GOFLAGS": "-toolexec=" + filepath.Join(poison, "cache-tool"+suffix),
		"GOCACHE": filepath.Join(directory, "cache"), "GOMODCACHE": filepath.Join(directory, "modules"),
		"MANUSCRIPT_CACHE_DIR": filepath.Join(directory, "user-cache"),
		"XDG_CONFIG_HOME":      filepath.Join(directory, "config"),
		"GOCACHEPROG":          filepath.Join(poison, "cache-tool"+suffix),
		"GOWORK":               filepath.Join(directory, "missing-workspace"),
		"MS_TEST_POISON":       marker,
	}
	// Delve's macOS backend requires Apple's separately installed debugserver.
	// Resolve the documented prerequisite before removing host tools from PATH.
	// This does not install tools, change signing, or weaken the isolation on
	// Linux/Windows, where only ms and its embedded native backend are needed.
	if runtime.GOOS == "darwin" {
		server, err := systemDebugserver()
		if err != nil {
			return err
		}
		settings["DELVE_DEBUGSERVER_PATH"] = server
		fmt.Println("macOS debugging uses installed Apple debugserver:", server)
	}
	var environment []string
	for _, entry := range os.Environ() {
		key, _, _ := strings.Cut(entry, "=")
		if _, replaced := settings[strings.ToUpper(key)]; !replaced {
			environment = append(environment, entry)
		}
	}
	for key, value := range settings {
		environment = append(environment, key+"="+value)
	}
	run := func(binary string, arguments ...string) (string, error) {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		command := exec.CommandContext(ctx, binary, arguments...)
		command.Dir = directory
		command.Env = environment
		data, err := command.CombinedOutput()
		if err != nil {
			return "", fmt.Errorf("%s %v: %w\n%s", binary, arguments, err, data)
		}
		return string(data), nil
	}
	library, err := libraryFixture(directory)
	if err != nil {
		return err
	}
	if err := checkLibrarySource(cli, library, run); err != nil {
		return err
	}
	manifest := filepath.Join(project, "ms.toml")
	output := filepath.Join(directory, "hello=program"+suffix)
	for _, arguments := range [][]string{
		{"--help"}, {"--version"}, {"check", manifest},
		{"fmt", filepath.Join(project, "src", "main.ms"), "--check"},
		{"emit", manifest, "--output=" + filepath.Join(directory, "main=v1.go")},
		{"inspect", manifest, "-o", filepath.Join(directory, "inspection.json")},
		{"diagram", manifest, "-o", filepath.Join(directory, "calls.mmd")},
		{"doc", project, "--output=" + filepath.Join(directory, "api=v1.md")},
		{"doc", "--stdlib", "--json", "--output=" + filepath.Join(directory, "stdlib=v1.json")},
		{"stdlib", filepath.Join(directory, "stdlib")},
		{"lint", filepath.Join(project, "test.ms"), "--json"},
	} {
		if _, err := run(cli, arguments...); err != nil {
			return err
		}
	}
	if err := checkLSP(cli, directory, environment); err != nil {
		return err
	}
	if _, err := os.Stat(settings["MANUSCRIPT_CACHE_DIR"]); !os.IsNotExist(err) {
		return fmt.Errorf("source-only commands unexpectedly prepared the native toolchain: %v", err)
	}
	for _, arguments := range [][]string{
		{"lock", manifest}, {"build", manifest, "-o", output},
		{"run", manifest, "--", "first", "second"}, {"test", filepath.Join(project, "test.ms")},
	} {
		data, err := run(cli, arguments...)
		if err != nil {
			return err
		}
		if arguments[0] == "run" && data != "Arguments: 2\n" {
			return fmt.Errorf("unexpected run output: %q", data)
		}
		if arguments[0] == "test" && !strings.Contains(data, "0 failed") {
			return fmt.Errorf("unexpected test output: %q", data)
		}
	}
	if err := checkLibraryNative(cli, library, run); err != nil {
		return err
	}
	data, err = os.ReadFile(filepath.Join(project, "ms.lock"))
	if err != nil {
		return err
	}
	var pin struct{ Toolchain map[string]string }
	if err := json.Unmarshal(data, &pin); err != nil {
		return err
	}
	if pin.Toolchain["CGO_ENABLED"] != "0" {
		return fmt.Errorf("lock did not use the bundled environment: %s", data)
	}
	if data, err := run(output, "first", "second"); err != nil {
		return err
	} else if data != "Arguments: 2\n" {
		return fmt.Errorf("unexpected native output: %q", data)
	}
	if data, err := run(cli, "run", manifest, "--debug", "--", "first", "second"); err != nil {
		return err
	} else if data != "Arguments: 2\n" {
		return fmt.Errorf("unexpected debug run output: %q", data)
	}
	for _, kind := range []string{"Debug", "Release", "RelWithDebInfo", "MinSizeRel"} {
		if _, err := run(cli, "build", manifest, "--build-type="+kind, "--output="+output); err != nil {
			return err
		}
		metadata, err := os.ReadFile(output + ".ms-build.json")
		if err != nil {
			return err
		}
		var recorded struct {
			BuildType string `json:"build_type"`
		}
		if err := json.Unmarshal(metadata, &recorded); err != nil {
			return err
		}
		if recorded.BuildType != kind {
			return fmt.Errorf("build type was not recorded: %s", metadata)
		}
		if data, err := run(output, "first", "second"); err != nil {
			return err
		} else if data != "Arguments: 2\n" {
			return fmt.Errorf("unexpected %s output: %q", kind, data)
		}
	}
	if err := checkDebugger(cli, directory, environment, run); err != nil {
		return err
	}
	profile := filepath.Join(directory, "profile")
	if data, err := run(cli, "profile", manifest, "-o", profile, "--trace", "--", "first", "second"); err != nil {
		return err
	} else if data != "Arguments: 2\n" {
		return fmt.Errorf("unexpected profile output: %q", data)
	}
	for _, name := range []string{"cpu.pprof", "heap.pprof", "trace.out", "manifest.json", "inspection.json", "program" + suffix, "program" + suffix + ".ms-build.json"} {
		info, err := os.Stat(filepath.Join(profile, name))
		if err != nil {
			return err
		}
		if info.Size() == 0 {
			return fmt.Errorf("empty profile artifact: %s", name)
		}
	}
	for _, arguments := range [][]string{
		{"pprof", "-top", filepath.Join(profile, "heap.pprof")},
		{"pprof", "-top", filepath.Join(profile, "cpu.pprof")},
		{"pprof", "-tags", filepath.Join(profile, "cpu.pprof")},
		{"trace", "-d=parsed", filepath.Join(profile, "trace.out")},
	} {
		if _, err := run(cli, arguments...); err != nil {
			return err
		}
	}
	defaultProfile := filepath.Join(directory, "default-profile")
	if _, err := run(cli, "profile", manifest, "-o", defaultProfile); err != nil {
		return err
	}
	if _, err := os.Stat(filepath.Join(defaultProfile, "trace.out")); !os.IsNotExist(err) {
		return fmt.Errorf("default profile unexpectedly captured a trace: %v", err)
	}
	defaultManifest, err := os.ReadFile(filepath.Join(defaultProfile, "manifest.json"))
	if err != nil {
		return err
	}
	var defaultArtifacts map[string]any
	if err := json.Unmarshal(defaultManifest, &defaultArtifacts); err != nil {
		return err
	}
	if _, ok := defaultArtifacts["trace"]; ok {
		return fmt.Errorf("default profile manifest advertises an unrequested trace")
	}
	// Repeat a cold native build with actual poison executables on PATH. Ambient
	// overrides already point to them in the first, ms-only PATH phase above.
	for i, entry := range environment {
		key, _, _ := strings.Cut(entry, "=")
		switch strings.ToUpper(key) {
		case "PATH":
			environment[i] = "PATH=" + poison
		case "MANUSCRIPT_CACHE_DIR":
			environment[i] = "MANUSCRIPT_CACHE_DIR=" + filepath.Join(directory, "second-cold-cache")
		}
	}
	if _, err := run(cli, "run", filepath.Join(project, "src", "main.ms"), "--", "first", "second"); err != nil {
		return err
	}
	if err := assertNoExternalTool(marker); err != nil {
		return err
	}
	profileManifest, err := os.ReadFile(filepath.Join(profile, "manifest.json"))
	if err != nil {
		return err
	}
	var recorded struct{ Executable string }
	if err := json.Unmarshal(profileManifest, &recorded); err != nil {
		return err
	}
	if recorded.Executable != "program"+suffix {
		return fmt.Errorf("profile manifest references the wrong executable: %s", profileManifest)
	}
	return nil
}

func checkLSP(cli, directory string, environment []string) error {
	var input strings.Builder
	for _, body := range []string{
		`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}`,
		`{"jsonrpc":"2.0","id":2,"method":"shutdown"}`,
		`{"jsonrpc":"2.0","method":"exit"}`,
	} {
		fmt.Fprintf(&input, "Content-Length: %d\r\n\r\n%s", len(body), body)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, cli, "lsp")
	command.Dir = directory
	command.Env = environment
	command.Stdin = strings.NewReader(input.String())
	data, err := command.CombinedOutput()
	if err != nil {
		return fmt.Errorf("packaged LSP handshake: %w\n%s", err, data)
	}
	if !strings.Contains(string(data), `"capabilities"`) || !strings.Contains(string(data), `"id":2`) {
		return fmt.Errorf("incomplete packaged LSP handshake: %s", data)
	}
	return nil
}
