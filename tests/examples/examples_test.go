// Complete tutorial modules are checked from the actual published Markdown.
package examples_test

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/manuscript-lang/manuscript/compiler"
)

type example struct {
	Mode   string   `json:"mode"`
	Args   []string `json:"args"`
	Stdout string   `json:"stdout"`
}

var blocks = regexp.MustCompile("(?s)(?:<!-- manuscript-example: (.*?) -->\\s*)?```manuscript\\n(.*?)```")
var complete = regexp.MustCompile(`(?m)^(export fn main\(|test ")`)

func TestTutorialExamples(t *testing.T) {
	files, err := filepath.Glob("../../documentation/learn/*.md")
	if err != nil {
		t.Fatal(err)
	}
	files = append(files, "../../documentation/getting-started.md")
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
				if spec.Mode != "test" && spec.Mode != "run" {
					t.Fatalf("unsupported example mode %q", spec.Mode)
				}
				options := compiler.Options{Entry: spec.Mode == "run", Tests: spec.Mode == "test", AnalyzeOnly: true}
				result := compiler.CompileSource("example.ms", block[2], options)
				if !result.Success() {
					t.Fatal(result.Diagnostics)
				}
				if os.Getenv("MANUSCRIPT_EXAMPLES_NATIVE") != "1" {
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
				ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
				defer cancel()
				output, err := exec.CommandContext(ctx, binary, spec.Args...).CombinedOutput()
				if err != nil {
					t.Fatalf("example failed: %v\n%s", err, output)
				}
				if spec.Mode == "run" && string(output) != spec.Stdout {
					t.Fatalf("got %q, want %q", output, spec.Stdout)
				}
				if spec.Mode == "test" && !strings.Contains(string(output), "0 failed") {
					t.Fatalf("test block did not complete: %s", output)
				}
			})
		}
	}
	if total < 4 {
		t.Fatal("missing complete tutorial examples")
	}
}
