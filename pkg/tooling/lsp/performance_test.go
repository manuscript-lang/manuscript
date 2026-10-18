package lsp

import (
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func performanceProject(t testing.TB, modules, functions int) document {
	t.Helper()
	root := t.TempDir()
	write := func(name, text string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(root, name), []byte(text), 0600); err != nil {
			t.Fatal(err)
		}
	}
	write("ms.toml", "[project]\nname = \"editor_perf\"\nsource = \".\"\nentry = \"main.ms\"\n")
	var main strings.Builder
	for m := 0; m < modules; m++ {
		fmt.Fprintf(&main, "import f_%d_0 from \"./part_%d.ms\"\n", m, m)
		var source strings.Builder
		for f := 0; f < functions; f++ {
			fmt.Fprintf(&source, "export fn f_%d_%d(value: Int) Int: value + %d\n", m, f, f)
		}
		write(fmt.Sprintf("part_%d.ms", m), source.String())
	}
	main.WriteString("\nexport fn main() Int:\n    let result = f_0_0(1)\n    return result\n")
	write("main.ms", main.String())
	return document{URI: fileURI(filepath.Join(root, "main.ms")), Text: main.String(), Version: 1}
}

func semanticKindAt(data []int, want position) int {
	line, character := 0, 0
	for i := 0; i < len(data); i += 5 {
		if data[i] != 0 {
			character = 0
		}
		line += data[i]
		character += data[i+1]
		if (position{line, character}) == want {
			return data[i+3]
		}
	}
	return -1
}

func TestSemanticProjectModuleIdentity(t *testing.T) {
	d := performanceProject(t, 3, 4)
	checked := analyze(d, map[string]document{d.URI: d})
	if !checked.Success() || len(checked.Program.Modules) != 4 {
		t.Fatal(checked.Diagnostics)
	}
	data := semantic(d, checked)["data"].([]int)
	use := Position(d.Text, strings.LastIndex(d.Text, "f_0_0"))
	if len(data) == 0 || len(data)%5 != 0 || semanticKindAt(data, use) != 5 {
		t.Fatal("lost checked function classification", data)
	}
	// Negative control: lexical fallback cannot classify an imported call as a
	// function. A test that only checks nonempty output would miss lost analysis.
	if semanticKindAt(semantic(d)["data"].([]int), use) == 5 {
		t.Fatal("control unexpectedly had semantic function information")
	}
	part := filepath.Join(filepath.Dir(filename(d.URI)), "part_0.ms")
	source, err := os.ReadFile(part)
	if err != nil {
		t.Fatal(err)
	}
	parameter := document{URI: fileURI(part), Text: string(source), Version: 1}
	declaration := Position(parameter.Text, strings.Index(parameter.Text, "value"))
	if semanticKindAt(semantic(parameter, checked)["data"].([]int), declaration) != 8 {
		t.Fatal("lost parameter classification from the occurrence index")
	}
	if semanticKindAt(semantic(parameter)["data"].([]int), declaration) == 8 {
		t.Fatal("lexical negative control unexpectedly classified a parameter")
	}
	alias := filepath.Join(t.TempDir(), "project")
	if err := os.Symlink(filepath.Dir(filename(d.URI)), alias); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	d.URI = fileURI(filepath.Join(alias, "main.ms"))
	if got := semantic(d, checked)["data"].([]int); !reflect.DeepEqual(got, data) {
		t.Fatal("symlinked document lost semantic module identity")
	}
}

var performanceTokens map[string]any

func BenchmarkSemanticProject(b *testing.B) {
	d := performanceProject(b, 40, 20)
	checked := analyze(d, map[string]document{d.URI: d})
	if !checked.Success() || len(checked.Program.Modules) != 41 {
		b.Fatal(checked.Diagnostics)
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		performanceTokens = semantic(d, checked)
	}
}
