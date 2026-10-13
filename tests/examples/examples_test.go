// Complete tutorial modules are checked from the actual published Markdown.
package examples_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

type example struct {
	Mode string `json:"mode"`
	exampleRun
	Cases []exampleRun `json:"cases"`
}

type exampleRun struct {
	Args      []string          `json:"args"`
	Stdin     string            `json:"stdin"`
	Stdout    string            `json:"stdout"`
	ExitCode  int               `json:"exit_code"`
	Files     map[string]string `json:"files"`
	WantFiles map[string]string `json:"want_files"`
	HTTP      *httpExample      `json:"http"`
}

type httpExample struct {
	Status int    `json:"status"`
	Body   string `json:"body"`
}

var blocks = regexp.MustCompile("(?s)(?:<!-- manuscript-example: (.*?) -->\\s*)?```manuscript\\n(.*?)```")
var complete = regexp.MustCompile(`(?m)^(export fn main\(|test ")`)

func TestTutorialExamples(t *testing.T) {
	files, err := filepath.Glob("../../documentation/learn/*.md")
	if err != nil {
		t.Fatal(err)
	}
	libraryFiles, err := filepath.Glob("../../documentation/standard-library/*.md")
	if err != nil {
		t.Fatal(err)
	}
	files = append(files, libraryFiles...)
	files = append(files, "../../documentation/core-language/types/records.md")
	files = append(files, "../../documentation/core-language/basics/numbers-and-booleans.md")
	files = append(files, "../../documentation/core-language/control-flow/loops.md")
	files = append(files, "../../documentation/concurrency/shutdown.md")
	total := 0
	for _, file := range files {
		text, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		for index, block := range blocks.FindAllStringSubmatch(string(text), -1) {
			if block[1] == "" {
				if complete.MatchString(block[2]) {
					t.Errorf("%s block %d: complete example needs a manuscript-example annotation", file, index+1)
				}
				continue
			}
			total++
			t.Run(fmt.Sprintf("%s/%d", filepath.Base(file), index+1), func(t *testing.T) {
				var spec example
				if err := json.Unmarshal([]byte(block[1]), &spec); err != nil {
					t.Fatal(err)
				}
				if spec.Mode != "test" && spec.Mode != "run" && spec.Mode != "signal" {
					t.Fatalf("unsupported example mode %q", spec.Mode)
				}
				options := compiler.Options{Entry: spec.Mode != "test", Tests: spec.Mode == "test", AnalyzeOnly: true}
				result := compiler.CompileSource("example.ms", block[2], options)
				if !result.Success() {
					t.Fatal(result.Diagnostics)
				}
				for _, finding := range tooling.LintProgram(result.Program) {
					if finding.Code == "MSL108" {
						t.Errorf("teaching example uses legacy standard name: %s", finding.Message)
					}
				}
				// Signal cookbook execution uses disposable children in tests/e2e.
				if spec.Mode == "signal" || os.Getenv("MANUSCRIPT_EXAMPLES_NATIVE") != "1" {
					return
				}
				options.AnalyzeOnly = false
				result = compiler.CompileSource("example.ms", block[2], options)
				if !result.Success() {
					t.Fatal(result.Diagnostics)
				}
				binary := filepath.Join(t.TempDir(), "example")
				if err := compiler.Build(result.Source, binary); err != nil {
					t.Fatal(err)
				}
				for index, run := range append([]exampleRun{spec.exampleRun}, spec.Cases...) {
					t.Run(fmt.Sprintf("execution-%d", index+1), func(t *testing.T) {
						runExample(t, binary, spec.Mode, run)
					})
				}
			})
		}
	}
	if total == 0 {
		t.Fatal("no complete tutorial examples found")
	}
}

func runExample(t *testing.T, binary, mode string, spec exampleRun) {
	t.Helper()
	root := t.TempDir()
	for path, contents := range spec.Files {
		if !filepath.IsLocal(path) {
			t.Fatalf("fixture path must stay inside the example directory: %q", path)
		}
		if err := os.MkdirAll(filepath.Dir(filepath.Join(root, path)), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(root, path), []byte(contents), 0644); err != nil {
			t.Fatal(err)
		}
	}
	args := append([]string(nil), spec.Args...)
	if spec.HTTP != nil {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method != http.MethodGet || r.URL.Path != "/" {
				t.Errorf("unexpected recipe request: %s %s", r.Method, r.URL.Path)
			}
			w.WriteHeader(spec.HTTP.Status)
			if _, err := w.Write([]byte(spec.HTTP.Body)); err != nil {
				t.Errorf("write recipe response: %v", err)
			}
		}))
		defer server.Close()
		for i, arg := range args {
			args[i] = strings.ReplaceAll(arg, "$HTTP_URL", server.URL)
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, binary, args...)
	command.Dir = root
	command.Stdin = strings.NewReader(spec.Stdin)
	output, err := command.CombinedOutput()
	if ctx.Err() != nil {
		t.Fatalf("example timed out: %s", output)
	}
	code := 0
	if err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			code = exit.ExitCode()
		} else {
			t.Fatalf("execute example: %v", err)
		}
	}
	if code != spec.ExitCode {
		t.Fatalf("exit code %d, want %d: %s", code, spec.ExitCode, output)
	}
	for path, want := range spec.WantFiles {
		if !filepath.IsLocal(path) {
			t.Fatalf("expected file path must stay inside the example directory: %q", path)
		}
		got, err := os.ReadFile(filepath.Join(root, path))
		if err != nil {
			t.Fatal(err)
		}
		if string(got) != want {
			t.Fatalf("file %s: got %q, want %q", path, got, want)
		}
	}
	if mode == "run" && string(output) != spec.Stdout {
		t.Fatalf("got %q, want %q", output, spec.Stdout)
	}
	if mode == "test" && !strings.Contains(string(output), "0 failed") {
		t.Fatalf("test block did not complete: %s", output)
	}
}
