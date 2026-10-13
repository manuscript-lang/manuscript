package compiler

import (
	"encoding/json"
	"github.com/manuscript-lang/manuscript/pkg/checker"
	msruntime "github.com/manuscript-lang/manuscript/pkg/runtime"
	"os/exec"
	"slices"
	"testing"
)

func TestRuntimeVariantFollowsStandardImports(t *testing.T) {
	for source, lean := range map[string]bool{
		"export fn main() -> Int:\n    return 0\n":                                                                           true,
		"import stdout from \"@std/io.ms\"\nexport fn main() -> Int:\n    return 0\n":                                        true,
		"import JsonValue from \"@std/json.ms\"\nexport fn main() -> Int:\n    return 0\n":                                   true,
		"import network from \"@std/net.ms\"\nexport fn main() -> Int:\n    return 0\n":                                      false,
		"import commands from \"@std/process.ms\"\nexport fn main() -> Int:\n    return 0\n":                                 false,
		"import HttpError from \"@std/http.ms\"\nexport fn main() -> Int:\n    return 0\n":                                   false,
		"import system from \"@std/system.ms\"\nimport stdout from \"@std/io.ms\"\nexport fn main() -> Int:\n    return 0\n": false,
	} {
		result := CompileSource("main.ms", source, Options{Entry: true})
		if !result.Success() {
			t.Fatal(source, result.Diagnostics)
		}
		if got := slices.Equal(runtimeTags(result.Program), []string{leanRuntimeTag}); got != lean {
			t.Errorf("lean runtime = %v for\n%s", got, source)
		}
	}
}

// The lean runtime must register every native function and receiver method of
// the standard modules that select it.
func TestLeanRuntimeImplementsLeanModules(t *testing.T) {
	declared := map[string]string{}
	for _, module := range checker.StandardModules() {
		for _, declaration := range module.Declarations {
			declared[declaration.Name] = module.File
		}
	}
	lean := func(module string) bool { return !fullRuntimeModules[module] }
	var functions, methods []string
	for _, spec := range msruntime.Library {
		if lean("@std/" + spec.Module + ".ms") {
			functions = append(functions, spec.Module+"/"+spec.Name)
		}
	}
	for _, spec := range msruntime.LibraryMethods {
		module, ok := declared[spec.Receiver]
		if !ok {
			t.Fatalf("receiver %s has no standard declaration", spec.Receiver)
		}
		if lean(module) {
			methods = append(methods, spec.Receiver+"."+spec.Name)
		}
	}
	source := `package main

import (
	"encoding/json"
	rt "github.com/manuscript-lang/manuscript/pkg/runtime"
	"os"
)

func main() {
	var functions, methods []string
	for _, spec := range rt.Library {
		functions = append(functions, spec.Module+"/"+spec.Name)
	}
	for _, spec := range rt.LibraryMethods {
		methods = append(methods, spec.Receiver+"."+spec.Name)
	}
	json.NewEncoder(os.Stdout).Encode([][]string{functions, methods})
}
`
	binary := executableName(t.TempDir(), "lean-inventory")
	if err := buildNative(source, binary, Release, []string{leanRuntimeTag}); err != nil {
		t.Fatal(err)
	}
	output, err := exec.Command(binary).Output()
	if err != nil {
		t.Fatal(err)
	}
	var inventory [][]string
	if err := json.Unmarshal(output, &inventory); err != nil || len(inventory) != 2 {
		t.Fatal(err, string(output))
	}
	if len(inventory[1]) >= len(msruntime.LibraryMethods) || len(functions) == 0 || len(methods) == 0 {
		t.Fatal("inventory does not distinguish the lean runtime")
	}
	for i, want := range [][]string{functions, methods} {
		for _, name := range want {
			if !slices.Contains(inventory[i], name) {
				t.Errorf("lean runtime lacks %s", name)
			}
		}
	}
}
