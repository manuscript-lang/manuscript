package build

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestFilesystemDefaultCallableBoundaries(t *testing.T) {
	const imports = `import {filesystem, FileSystemError} from "@std/fs.ms"
import Bytes from "@std/bytes.ms"
fn forward[T](item: T) T: item
`
	for _, method := range []struct{ name, args, typ, flag string }{
		{"write_file", `"", "".to_bytes()`, "path: String, data: Bytes, replace: Bool", "replace"},
		{"copy_file", `"", ""`, "source: String, destination: String, replace: Bool, max_bytes: Optional[Int]", "replace"},
		{"copy_tree", `"", ""`, "source: String, destination: String, replace: Bool, max_entries: Optional[Int], max_bytes: Optional[Int]", "replace"},
		{"create_directory", `""`, "path: String, recursive: Bool", "recursive"},
		{"remove", `""`, "path: String, recursive: Bool", "recursive"},
	} {
		t.Run(method.name, func(t *testing.T) {
			for _, item := range []struct{ name, binding, extra, want string }{
				{"bound", "let call = filesystem()." + method.name, "", ""},
				{"false", "let call = filesystem()." + method.name, ", " + method.flag + ": false", ""},
				{"true", "let call = filesystem()." + method.name, ", " + method.flag + ": true", ""},
				{"none", "let call = filesystem()." + method.name, ", " + method.flag + ": none", "expected Bool"},
				{"mutable", "var call = filesystem()." + method.name, "", "missing argument " + method.flag},
				{"forwarded", "let call = forward(filesystem()." + method.name + ")", "", "missing argument " + method.flag},
				{"typed", "let call: fn(" + method.typ + ") Result[Unit, FileSystemError] = filesystem()." + method.name, "", "missing argument " + method.flag},
			} {
				t.Run(item.name, func(t *testing.T) {
					source := imports + "fn check() Unit:\n    " + item.binding + "\n    call(" + method.args + item.extra + ")\n"
					r := compiler.CompileSource("filesystem-boundary.ms", source, compiler.Options{AnalyzeOnly: true})
					got := fmt.Sprint(r.Diagnostics)
					if item.want == "" && !r.Success() || item.want != "" && (r.Success() || !strings.Contains(got, item.want)) {
						t.Fatalf("want %q: %s", item.want, got)
					}
				})
			}
		})
	}
}

func TestFilesystemExplicitFlagsKeepDirectDispatch(t *testing.T) {
	r := compiler.CompileSource("explicit-filesystem.ms", `import filesystem from "@std/fs.ms"
fn explicit() Unit:
    let fs = filesystem()
    fs.write_file("", "".to_bytes(), false)
    fs.copy_file("", "", true)
    fs.copy_tree("", "", false, max_entries: none, max_bytes: 3)
    fs.create_directory("", true)
    fs.remove("", false)
`, compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Contains(r.Source, "WithDefaults") || strings.Contains(r.Source, "PreparedDefaults") {
		t.Fatal("explicit filesystem flags emitted default preparation")
	}
}

func TestFilesystemImplementationDefaultsOverrideOnlyConcreteCalls(t *testing.T) {
	data, err := stdlib.Sources.ReadFile("fs.ms")
	if err != nil {
		t.Fatal(err)
	}
	module, err := parser.Parse("@std/fs.ms", string(data))
	if err != nil {
		t.Fatal(err)
	}
	var source strings.Builder
	for _, item := range module.Imports {
		fmt.Fprintf(&source, "import %s from %q\n", item.Name, item.Path)
	}
	var contract *syntax.Declaration
	for _, declaration := range module.Declarations {
		if declaration.Export && declaration.Kind != syntax.KindFn {
			fmt.Fprintf(&source, "import %s from \"@std/fs.ms\"\n", declaration.Name)
		}
		if declaration.Name == "FileSystem" {
			contract = declaration
		}
	}
	if contract == nil {
		t.Fatal("missing FileSystem contract")
	}
	source.WriteString("import panic from \"@std/faults.ms\"\ntype Override:\n    received: Bool\nimpl FileSystem for Override:\n")
	flags := map[string]string{"write_file": "replace", "copy_file": "replace", "copy_tree": "replace", "create_directory": "recursive", "remove": "recursive"}
	// Supply the other interface operations as inert expected failures, so the
	// five real standard methods can be exercised through a complete source impl.
	for _, method := range contract.Methods {
		fmt.Fprintf(&source, "    fn %s(", method.Name)
		for i, parameter := range method.Params {
			if i > 0 {
				source.WriteString(", ")
			}
			fmt.Fprintf(&source, "%s: %s", parameter.Name, filesystemFixtureType(parameter.Type))
			if flags[method.Name] == parameter.Name {
				source.WriteString(" = true")
			}
		}
		fmt.Fprintf(&source, ") %s:\n", filesystemFixtureType(method.Result))
		if flag := flags[method.Name]; flag != "" {
			fmt.Fprintf(&source, "        self.received = %s\n        return ok(unit)\n", flag)
		} else {
			source.WriteString("        return error(FileSystemError.Unsupported)\n")
		}
	}
	source.WriteString("test \"filesystem concrete overrides and interface defaults\":\n    let item = Override(false)\n    let view = FileSystem(item)\n")
	for _, method := range []struct{ name, args string }{
		{"write_file", `"", "".to_bytes()`}, {"copy_file", `"", ""`}, {"copy_tree", `"", ""`}, {"create_directory", `""`}, {"remove", `""`},
	} {
		fmt.Fprintf(&source, "    item.%s(%s)\n    if not item.received: return panic(\"concrete override %s\")\n", method.name, method.args, method.name)
		fmt.Fprintf(&source, "    view.%s(%s)\n    if item.received: return panic(\"interface default %s\")\n", method.name, method.args, method.name)
	}
	r := compiler.CompileSource("filesystem-overrides.ms", source.String(), compiler.Options{Tests: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "overrides")
	if err := Build(r.Source, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command(binary).CombinedOutput(); err != nil || !strings.Contains(string(output), "1 tests, 0 failed") {
		t.Fatalf("filesystem overrides: %v\n%s", err, output)
	}
}

func filesystemFixtureType(typ *syntax.Type) string {
	if typ.Result != nil {
		var params []string
		for _, parameter := range typ.Params {
			params = append(params, parameter.Name+": "+filesystemFixtureType(parameter.Type))
		}
		return "fn(" + strings.Join(params, ", ") + ") " + filesystemFixtureType(typ.Result)
	}
	var args []string
	for _, argument := range typ.Args {
		args = append(args, filesystemFixtureType(argument))
	}
	if len(args) != 0 {
		return typ.Name + "[" + strings.Join(args, ", ") + "]"
	}
	return typ.Name
}
