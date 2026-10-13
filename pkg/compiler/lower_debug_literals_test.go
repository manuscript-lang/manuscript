package compiler

import (
	"crypto/sha256"
	"fmt"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func debugLiteralSource() string {
	return "import List from \"@std/collections.ms\"\nfn values() -> List[Int]:\n    return [" + strings.TrimSuffix(strings.Repeat("7, ", 1100), ", ") + "]\nexport fn main() -> Int:\n    return values().length() - 1100\n"
}

func TestDebugLiteralBuildRecipe(t *testing.T) {
	r := CompileSource("literal.ms", debugLiteralSource(), Options{Entry: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	original := r.Source
	// Independently captured by the unchanged bee671d4 compiler. See the
	// provenance note; never regenerate this oracle using the implementation
	// under test. Existing pre-AST fixtures are left untouched.
	if got := fmt.Sprintf("%x", sha256.Sum256([]byte(original))); got != "c2086ef7502812b744c8db896855f9b0333bb8c210276db43334f7e241de356c" {
		t.Fatal("default lowering changed from the independent baseline", got)
	}
	for _, kind := range []BuildType{Release, RelWithDebInfo, MinSizeRel} {
		got, err := r.sourceForBuild(kind)
		if err != nil || got != original {
			t.Fatalf("%s changed default source: %v", kind, err)
		}
	}
	debug, err := r.sourceForBuild(Debug)
	if err != nil || !strings.Contains(debug, "debugLiteralData1") || strings.Contains(original, "debugLiteralData") {
		t.Fatal("incorrect mode selection", err)
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
	if !reflect.DeepEqual(sourceOnly(debug), sourceOnly(original)) {
		t.Fatal("source directive order changed")
	}
	again, err := r.sourceForBuild(Debug)
	if err != nil || again != debug || r.Source != original {
		t.Fatal("nondeterministic lowering or result mutation", err)
	}
	for _, source := range []string{original + "\n// caller edit\n", strings.Replace(original, "os.Exit(", "os.Exit(17 + ", 1)} {
		changed := r
		changed.Source = source
		got, err := changed.sourceForBuild(Debug)
		if err != nil || got != source {
			t.Fatal("caller-edited Go was discarded", err)
		}
	}
	manual := Result{Program: r.Program, Source: original}
	if got, err := manual.sourceForBuild(Debug); err != nil || got != original {
		t.Fatal("manual result was regenerated", err)
	}
	changedProgram := r
	changedProgram.Program = nil
	if got, err := changedProgram.sourceForBuild(Debug); err != nil || got != original {
		t.Fatal("replaced checked program was regenerated", err)
	}
}

func TestDebugLiteralBoundaryAndIneligibleSource(t *testing.T) {
	for _, n := range []int{1024, 1025} {
		source := strings.Replace(debugLiteralSource(), strings.Repeat("7, ", 1099)+"7", strings.Repeat("7, ", n-1)+"7", 1)
		r := CompileSource("literal.ms", source, Options{Entry: true})
		if !r.Success() {
			t.Fatal(r.Diagnostics)
		}
		debug, err := r.sourceForBuild(Debug)
		if err != nil || strings.Contains(debug, "debugLiteralData") != (n > debugListThreshold) {
			t.Fatal("incorrect boundary", n, err)
		}
	}
	// One effectful entry leaves the entire flat list on the existing ordered
	// lowering path. No calls move to initialization or to a copy helper.
	source := strings.Replace(debugLiteralSource(), "fn values()", "fn tick() -> Int: 7\nfn values()", 1)
	source = strings.Replace(source, "return [7,", "return [tick(),", 1)
	r := CompileSource("literal.ms", source, Options{Entry: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if debug, err := r.sourceForBuild(Debug); err != nil || debug != r.Source {
		t.Fatal("effectful list changed", err)
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
			r := CompileSource("literal.ms", s, Options{})
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			debug, err := r.sourceForBuild(Debug)
			if err != nil || strings.Contains(debug, "debugLiteralData") != tc.table {
				t.Fatal("eligibility mismatch", err)
			}
			if strings.Contains(r.Source, "debugLiteralData") {
				t.Fatal("default lowering changed")
			}
		})
	}
}

func TestDebugLiteralNativeCompatibility(t *testing.T) {
	source := debugLiteralSource()
	r := CompileSource("literal.ms", source, Options{Entry: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	root := t.TempDir()
	cache := filepath.Join(root, "cache")
	for _, kind := range []BuildType{Release, Debug, RelWithDebInfo, MinSizeRel} {
		binary := filepath.Join(root, string(kind))
		meta, err := BuildCheckedWithType(r, binary, cache, kind)
		if err != nil {
			t.Fatal(err)
		}
		if data, err := exec.Command(binary).CombinedOutput(); err != nil {
			t.Fatalf("%s: %v\n%s", kind, err, data)
		}
		restored := filepath.Join(root, string(kind)+"-restored")
		copy, err := BuildCheckedWithType(r, restored, cache, kind)
		if err != nil || copy.BuildID != meta.BuildID || copy.ExecutableSHA256 != meta.ExecutableSHA256 {
			t.Fatal("cache did not retain build mode", err)
		}
	}
	// CompileSource -> the existing boolean Debug API needs no new options.
	if _, err := BuildChecked(r, filepath.Join(root, "boolean-debug"), cache, true); err != nil {
		t.Fatal(err)
	}
	changed := r
	changed.Source += "\nfunc init() { os.Exit(17) }\n"
	binary := filepath.Join(root, "edited-debug")
	if _, err := BuildCheckedWithType(changed, binary, "", Debug); err != nil {
		t.Fatal(err)
	}
	err := exec.Command(binary).Run()
	if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 17 {
		t.Fatal("edited source behavior lost", err)
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
	r := CompileSource("debug-fresh.ms", source, Options{Tests: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, kind := range []BuildType{Release, Debug} {
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
	r = CompileSource("debug-fault.ms", fault, Options{Entry: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	var transcripts []string
	for _, kind := range []BuildType{Release, Debug} {
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

func TestDebugLiteralRecipeRetainsLauncherOptions(t *testing.T) {
	r := CompileSource("profile.ms", debugLiteralSource(), Options{Entry: true, CPUProfile: "cpu.pprof", HeapProfile: "heap.pprof", Trace: "trace.out"})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	debug, err := r.sourceForBuild(Debug)
	if err != nil || !strings.Contains(debug, `rt.Profile("cpu.pprof", "heap.pprof", "trace.out"`) {
		t.Fatal("profile launcher lost", err)
	}
	analyzed := CompileSource("check.ms", debugLiteralSource(), Options{AnalyzeOnly: true})
	if !analyzed.Success() || analyzed.Source != "" || analyzed.lowering != nil {
		t.Fatal("source-only checking retained executable recipe")
	}
}
