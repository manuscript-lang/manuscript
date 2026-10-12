package compiler_test

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/compiler"
)

const extensionDomain = `export interface Read[T]:
    fn get() -> T
export type Box[T]:
    value: T
export fn invoke[T: Read[Int]](value: T) -> Int:
    return value.get()
`
const extensionImports = `import {Read, Box} from "./domain.ms"
`
const extensionImpl = `impl Read[T] for Box[T]:
    fn get() -> T:
        return self.value
`

func TestLocalExtensionBoundaries(t *testing.T) {
	for name, body := range map[string]string{
		"method": `fn use(value: Box[Int]) -> Int:
    return value.get()
`,
		"view": `fn use(value: Box[Int]) -> Read[Int]:
    return Read[Int](value: value)
`,
		"bound": `import invoke from "./domain.ms"
fn use(value: Box[Int]) -> Int:
    return invoke(value)
`,
		"cleanup": `fn use(value: Box[Int]) -> Unit:
    with resource = value:
        return
`,
	} {
		t.Run(name, func(t *testing.T) {
			root := t.TempDir()
			write(t, root, "domain.ms", extensionDomain)
			write(t, root, "extension.ms", extensionImports+extensionImpl+`import Closeable from "@std/cleanup.ms"
impl Closeable for Box[T]:
    fn close() -> Unit:
        return
export fn loaded() -> Int:
    return 1
`)
			write(t, root, "main.ms", "import loaded from \"./extension.ms\"\n"+extensionImports+body)
			result := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{})
			if result.Success() {
				t.Fatal("extension leaked into importing module")
			}
			for _, diagnostic := range result.Diagnostics {
				if diagnostic.Position.File != "main.ms" {
					t.Fatalf("fixture failed outside use site: %v", result.Diagnostics)
				}
			}
		})
	}
}

func TestLocalExtensionValidation(t *testing.T) {
	for _, tt := range []struct{ name, domain, source, message string }{
		{"duplicate", extensionDomain, extensionImports + extensionImpl + extensionImpl, "overlapping"},
		{"specialization overlap", extensionDomain, extensionImports + extensionImpl + `impl Read[Int] for Box[Int]:
    fn get() -> Int:
        return 0
`, "overlapping"},
		{"owner overlap", extensionDomain + extensionImpl, extensionImports + extensionImpl, "overlapping"},
		{"body", extensionDomain, extensionImports + `impl Read[T] for Box[T]:
    fn get() -> T:
        return missing
`, "unknown"},
		{"signature", extensionDomain, extensionImports + `impl Read[Int] for Box[Int]:
    fn get() -> String:
        return "wrong"
`, "signature"},
		{"missing method", extensionDomain, extensionImports + `impl Read[Int] for Box[Int]:
    fn extra() -> Int:
        return 0
`, "missing implementation"},
		{"intrinsic", extensionDomain, extensionImports + `impl Read[Int] for Int:
    fn get() -> Int:
        return self
`, "nominal source data"},
		{"native", extensionDomain, extensionImports + `import List from "@std/collections.ms"
impl Read[Int] for List[Int]:
    fn get() -> Int:
        return 0
`, "nominal source data"},
		{"interface receiver", extensionDomain, extensionImports + `impl Read[Int] for Read[Int]:
    fn get() -> Int:
        return 0
`, "nominal source data"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			root := t.TempDir()
			write(t, root, "domain.ms", tt.domain)
			write(t, root, "main.ms", tt.source)
			result := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{})
			for _, diagnostic := range result.Diagnostics {
				if strings.Contains(diagnostic.Message, tt.message) {
					return
				}
			}
			t.Fatalf("want %q diagnostic, got %v", tt.message, result.Diagnostics)
		})
	}
}

func TestLocalExtensionUsesResolvedReceiverBounds(t *testing.T) {
	root := t.TempDir()
	write(t, root, "domain.ms", `export interface Read:
    fn original() -> Int
export type Box[T: Read]:
    value: T
`)
	write(t, root, "main.ms", `import Box from "./domain.ms"
interface Read:
    fn get() -> Int
impl Read for Box[T]:
    fn get() -> Int:
        return self.value.original()
`)
	result := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
}

func TestLocalExtensionMembers(t *testing.T) {
	root := t.TempDir()
	write(t, root, "domain.ms", extensionDomain)
	write(t, root, "extension.ms", extensionImports+extensionImpl+`export fn read(value: Box[Int]) -> Int:
    return value.get()
`)
	write(t, root, "main.ms", `import read from "./extension.ms"
import Box from "./domain.ms"
`)
	result := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	receiver := result.Program.Symbols["extension.ms"]["read"].Type.Params[0].Type
	for _, module := range []string{"extension.ms", "main.ms", "domain.ms"} {
		found := false
		for _, member := range checker.Members(result.Program, receiver, module) {
			if member.Name == "get" {
				found = true
			}
		}
		if found != (module == "extension.ms") {
			t.Fatalf("get visibility in %s: %v", module, found)
		}
	}
}
