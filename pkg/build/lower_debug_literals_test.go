package build

import (
	"crypto/sha256"
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func debugLiteralSource() string {
	return "import List from \"@std/collections.ms\"\nfn values() -> List[Int]:\n    return [" + strings.TrimSuffix(strings.Repeat("7, ", 1100), ", ") + "]\nexport fn main() -> Int:\n    return values().length() - 1100\n"
}

func TestDebugLiteralBuildSelection(t *testing.T) {
	r := compiler.CompileSource("literal.ms", debugLiteralSource(), compiler.Options{Entry: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	original := r.Source
	// Freeze the original boxed constructor independently of production
	// lowering. Its bee671d4 hash remains unchanged as Release now uses a
	// primitive table. The native compatibility test exercises both layouts.
	constructor, err := os.ReadFile("testdata/debug-literals/baseline-constructor.go.txt")
	if err != nil {
		t.Fatal(err)
	}
	if got := fmt.Sprintf("%x", sha256.Sum256(constructor)); got != "14f056a0e496cbba6ff77959a189419ceed5206a63a9ece9b49aa07aae677362" {
		t.Fatal("independent baseline changed", got)
	}
	if !strings.Contains(original, "scalarLiteralData1") || !strings.Contains(original, "rt.NewIntList(") {
		t.Fatal("Release literal was not specialized")
	}
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.RelWithDebInfo, compiler.MinSizeRel} {
		got := compiler.CompileSourceForBuild("literal.ms", debugLiteralSource(), compiler.Options{Entry: true}, kind)
		if !got.Success() || got.Source != original {
			t.Fatalf("%s changed default source: %v", kind, got.Diagnostics)
		}
	}
	debug := compiler.CompileSourceForBuild("literal.ms", debugLiteralSource(), compiler.Options{Entry: true}, compiler.Debug)
	if !debug.Success() || !strings.Contains(debug.Source, "debugLiteralData1") || strings.Contains(original, "debugLiteralData") {
		t.Fatal("incorrect mode selection", debug.Diagnostics)
	}
	sourceOnly := func(source string) []string {
		var directives []string
		for _, line := range sourceDirectives(source) {
			if !strings.Contains(line, "manuscript.generated.go") {
				directives = append(directives, line)
			}
		}
		return directives
	}
	if !reflect.DeepEqual(sourceOnly(debug.Source), sourceOnly(original)) {
		t.Fatal("source directive order changed")
	}
	again := compiler.CompileSourceForBuild("literal.ms", debugLiteralSource(), compiler.Options{Entry: true}, compiler.Debug)
	if !again.Success() || again.Source != debug.Source || r.Source != original {
		t.Fatal("nondeterministic lowering or result mutation")
	}
	invalid := compiler.CompileSourceForBuild("literal.ms", debugLiteralSource(), compiler.Options{Entry: true}, "Fast")
	if invalid.Success() || len(invalid.Diagnostics) != 1 || !strings.Contains(invalid.Diagnostics[0].Message, "unknown build type") {
		t.Fatal("invalid kind was accepted", invalid.Diagnostics)
	}
}

func TestDebugLiteralBoundaryAndIneligibleSource(t *testing.T) {
	for _, n := range []int{1024, 1025} {
		source := strings.Replace(debugLiteralSource(), strings.Repeat("7, ", 1099)+"7", strings.Repeat("7, ", n-1)+"7", 1)
		r := compiler.CompileSource("literal.ms", source, compiler.Options{Entry: true})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		debug := compiler.CompileSourceForBuild("literal.ms", source, compiler.Options{Entry: true}, compiler.Debug)
		if !debug.Success() || strings.Contains(debug.Source, "debugLiteralData") != (n > 1024) { // lower.debugListThreshold
			t.Fatal("incorrect boundary", n, debug.Diagnostics)
		}
	}
	// One effectful entry leaves the entire flat list on the existing ordered
	// lowering path. No calls move to initialization or to a copy helper.
	source := strings.Replace(debugLiteralSource(), "fn values()", "fn tick() -> Int: 7\nfn values()", 1)
	source = strings.Replace(source, "return [7,", "return [tick(),", 1)
	r := compiler.CompileSource("literal.ms", source, compiler.Options{Entry: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if debug := compiler.CompileSourceForBuild("literal.ms", source, compiler.Options{Entry: true}, compiler.Debug); !debug.Success() || debug.Source != r.Source {
		t.Fatal("effectful list changed", debug.Diagnostics)
	}
}

func TestDebugLiteralEligibility(t *testing.T) {
	for _, tc := range []struct {
		typ, element, extra string
		table               bool
	}{
		{"Int", "7", "", true}, {"Int", "-7", "", false},
		{"Float", "1.25", "", true}, {"Float", "-1.25", "", false}, {"Float", "-0.0", "", false},
		{"Bool", "true", "", true}, {"String", `"λ\n\""`, "", true},
		{"Int", "value", "", false}, {"Box", "Box(7)", "type Box:\n    value: Int\n", false},
		{"List[Int]", "[7]", "", false},
	} {
		t.Run(tc.typ+tc.element, func(t *testing.T) {
			s := "import List from \"@std/collections.ms\"\n" + tc.extra + "fn values(value: Int) -> List[" + tc.typ + "]:\n    return [" + strings.TrimSuffix(strings.Repeat(tc.element+", ", 1100), ", ") + "]\n"
			r := compiler.CompileSource("literal.ms", s, compiler.Options{})
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			debug := compiler.CompileSourceForBuild("literal.ms", s, compiler.Options{}, compiler.Debug)
			if !debug.Success() || strings.Contains(debug.Source, "debugLiteralData") != tc.table {
				t.Fatal("eligibility mismatch", debug.Diagnostics)
			}
			if strings.Contains(r.Source, "debugLiteralData") {
				t.Fatal("default lowering changed")
			}
		})
	}
}

func TestDebugLiteralNativeCompatibility(t *testing.T) {
	source := debugLiteralSource()
	r := compiler.CompileSource("literal.ms", source, compiler.Options{Entry: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	root := t.TempDir()
	cache := filepath.Join(root, "cache")
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug, compiler.RelWithDebInfo, compiler.MinSizeRel} {
		selected := compiler.CompileSourceForBuild("literal.ms", source, compiler.Options{Entry: true}, kind)
		if !selected.Success() {
			t.Fatal(selected.Diagnostics)
		}
		binary := filepath.Join(root, string(kind))
		meta, err := BuildCheckedWithType(selected, binary, cache, kind)
		if err != nil {
			t.Fatal(err)
		}
		if data, err := exec.Command(binary).CombinedOutput(); err != nil {
			t.Fatalf("%s: %v\n%s", kind, err, data)
		}
		restored := filepath.Join(root, string(kind)+"-restored")
		copy, err := BuildCheckedWithType(selected, restored, cache, kind)
		if err != nil || copy.BuildID != meta.BuildID || copy.ExecutableSHA256 != meta.ExecutableSHA256 {
			t.Fatal("cache did not retain build mode", err)
		}
	}
	// CompileSource -> the existing boolean Debug API needs no new options.
	if _, err := BuildChecked(r, filepath.Join(root, "boolean-debug"), cache, true); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(r.Source, "debugLiteralData") {
		t.Fatal("legacy compiler representation changed")
	}
	manual := compiler.Result{SourceRoot: r.SourceRoot, Program: r.Program, Source: r.Source}
	if _, err := BuildChecked(manual, filepath.Join(root, "manual-debug"), cache, true); err != nil {
		t.Fatal(err)
	}
	for _, original := range []compiler.Result{r, compiler.CompileSourceForBuild("literal.ms", source, compiler.Options{Entry: true}, compiler.Debug)} {
		changed := original
		changed.Source += "\nfunc init() { os.Exit(17) }\n"
		binary := filepath.Join(root, "edited-debug")
		if _, err := BuildCheckedWithType(changed, binary, "", compiler.Debug); err != nil {
			t.Fatal(err)
		}
		err := exec.Command(binary).Run()
		if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 17 {
			t.Fatal("edited source behavior lost", err)
		}
		if changed.Source != original.Source+"\nfunc init() { os.Exit(17) }\n" {
			t.Fatal("builder changed supplied Source")
		}
	}
}

func TestDebugLiteralFreshStorageAndFaultOrder(t *testing.T) {
	source := "import List from \"@std/collections.ms\"\nimport panic from \"@std/faults.ms\"\nfn values() -> List[Int]:\n    return [" + strings.TrimSuffix(strings.Repeat("7, ", 1100), ", ") + "]\n"
	source += "fn defaults(items: List[Int] = [" + strings.TrimSuffix(strings.Repeat("9, ", 1100), ", ") + "]) -> List[Int]: items\n"
	source += `test "fresh Debug data":
    let first = values()
    let second = values()
    let alias = first
    let copied = first.clone()
    first.with_value(index: 0, value: 99)
    alias.append(42)
    if alias.length() != 1101 or second.length() != 1100 or copied.length() != 1100:
        return panic("outer storage is shared across evaluations")
    if second.at(0).unwrap() != 7 or copied.at(0).unwrap() != 7 or values().at(0).unwrap() != 7:
        return panic("data table or clone was mutated")
    let first_default = defaults()
    first_default.with_value(index: 0, value: 17)
    if defaults().at(0).unwrap() != 9:
        return panic("defaults share mutable storage")
`
	r := compiler.CompileSource("debug-fresh.ms", source, compiler.Options{Tests: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
		r = compiler.CompileSourceForBuild("debug-fresh.ms", source, compiler.Options{Tests: true}, kind)
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		binary := filepath.Join(t.TempDir(), "program")
		if _, err := BuildCheckedWithType(r, binary, "", kind); err != nil {
			t.Fatal(err)
		}
		data, err := exec.Command(binary).CombinedOutput()
		if err != nil || !strings.Contains(string(data), "1 tests, 0 failed") {
			t.Fatalf("%s: %v\n%s", kind, err, data)
		}
	}
	fault := "import List from \"@std/collections.ms\"\nfn fail() -> Int:\n    return 1 / 0\nexport fn main() -> Int:\n    let data = [" + strings.TrimSuffix(strings.Repeat("7, ", 1100), ", ") + "]\n    return fail()\n"
	r = compiler.CompileSource("debug-fault.ms", fault, compiler.Options{Entry: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	var transcripts []string
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
		r = compiler.CompileSourceForBuild("debug-fault.ms", fault, compiler.Options{Entry: true}, kind)
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		binary := filepath.Join(t.TempDir(), "program")
		if _, err := BuildCheckedWithType(r, binary, "", kind); err != nil {
			t.Fatal(err)
		}
		data, err := exec.Command(binary).CombinedOutput()
		if err == nil {
			t.Fatal("expected fault")
		}
		transcripts = append(transcripts, string(data))
	}
	if transcripts[0] != transcripts[1] || !strings.Contains(transcripts[1], "debug-fault.ms:3:14 in fail") || !strings.Contains(transcripts[1], "debug-fault.ms:6:12 in main") {
		t.Fatalf("fault order changed: %q", transcripts)
	}
}

func TestDebugLiteralLauncherOptions(t *testing.T) {
	r := compiler.CompileSourceForBuild("profile.ms", debugLiteralSource(), compiler.Options{Entry: true, CPUProfile: "cpu.pprof", HeapProfile: "heap.pprof", Trace: "trace.out"}, compiler.Debug)
	if !r.Success() || !strings.Contains(r.Source, `rt.Profile("cpu.pprof", "heap.pprof", "trace.out"`) || !strings.Contains(r.Source, "debugLiteralData1") {
		t.Fatal("profile launcher lost", r.Diagnostics)
	}
	analyzed := compiler.CompileSourceForBuild("check.ms", debugLiteralSource(), compiler.Options{AnalyzeOnly: true}, compiler.Debug)
	if !analyzed.Success() || analyzed.Source != "" {
		t.Fatal("source-only checking generated Go")
	}
}
