package build_test

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestVerifyBuildRejectsStaleArtifacts(t *testing.T) {
	hash := func(value string) string {
		sum := sha256.Sum256([]byte(value))
		return hex.EncodeToString(sum[:])
	}
	for _, kind := range []string{"valid", "missing metadata", "invalid metadata", "wrong format", "missing executable", "changed executable", "missing source", "changed source", "changed configuration"} {
		t.Run(kind, func(t *testing.T) {
			root := t.TempDir()
			binary := filepath.Join(root, "program")
			metadata := build.BuildMetadata{
				BuildPin:         build.BuildPin{Format: 1},
				Sources:          map[string]string{"main.ms": hash("source"), "ms.toml": hash("configuration")},
				ExecutableSHA256: hash("executable"),
			}
			sources := map[string]string{"main.ms": "source", "ms.toml": "configuration"}
			contents := "executable"
			switch kind {
			case "wrong format":
				metadata.Format = 2
			case "changed executable":
				contents = "different executable"
			case "missing source":
				delete(sources, "main.ms")
			case "changed source":
				sources["main.ms"] = "different source"
			case "changed configuration":
				sources["ms.toml"] = "different configuration"
			}
			if kind != "missing executable" {
				if err := os.WriteFile(binary, []byte(contents), 0600); err != nil {
					t.Fatal(err)
				}
			}
			if kind != "missing metadata" {
				data, err := json.Marshal(metadata)
				if err != nil {
					t.Fatal(err)
				}
				if kind == "invalid metadata" {
					data = []byte("{")
				}
				if err := os.WriteFile(binary+".ms-build.json", data, 0600); err != nil {
					t.Fatal(err)
				}
			}
			err := build.VerifyBuild(binary, sources)
			if (err == nil) != (kind == "valid") {
				t.Fatalf("%s: %v", kind, err)
			}
		})
	}
}

func TestLockRejectsMalformedAndUnknownFields(t *testing.T) {
	for _, contents := range []string{"{", "null", `{"format":1,"surprise":true}`, `{"format":1} {"format":1}`, `{"format":1} trailing`} {
		t.Run(contents, func(t *testing.T) {
			root := t.TempDir()
			if err := os.WriteFile(filepath.Join(root, "ms.lock"), []byte(contents), 0600); err != nil {
				t.Fatal(err)
			}
			if err := build.CheckPin(root); err == nil {
				t.Fatal("accepted invalid lock")
			}
		})
	}
}

func TestUnsavedModuleImportAndStrictRecoveryBoundary(t *testing.T) {
	root := t.TempDir()
	write(t, root, "main.ms", "import value from \"./new.ms\"\nfn read() -> Int:\n    return value()\n")
	overlay := map[string]string{filepath.Join(root, "new.ms"): "export fn value() -> Int:\n    return 3\n"}
	for _, options := range []compiler.Options{{Overlay: overlay}, {Overlay: overlay, Recover: true, AnalyzeOnly: true}} {
		result := compiler.CompileFile(filepath.Join(root, "main.ms"), options)
		if !result.Success() || len(result.Program.Modules) != 2 {
			t.Fatal(result.Diagnostics)
		}
	}
	if result := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{}); result.Success() {
		t.Fatal("unsaved module leaked to filesystem")
	}
	overlay[filepath.Join(root, "new.ms")] = "export fn value() -> Int:\n    return 3\nfn broken(\n"
	for _, options := range []compiler.Options{{Overlay: overlay}, {Overlay: overlay, Recover: true}, {Overlay: overlay, Recover: true, AnalyzeOnly: true}} {
		result := compiler.CompileFile(filepath.Join(root, "main.ms"), options)
		if result.Success() || result.Source != "" {
			t.Fatal("generated executable source from malformed overlay")
		}
		if options.AnalyzeOnly && (result.Program == nil || !strings.Contains(result.Program.Modules[0].Source, "value")) {
			t.Fatal("editor recovery lost valid source")
		}
	}
}

func TestEditorOverlaysUseCanonicalFileIdentity(t *testing.T) {
	root := t.TempDir()
	write(t, root, "src/main.ms", "import value from \"./new.ms\"\nfn read() -> Int:\n    return value()\n")
	alias := filepath.Join(root, "workspace")
	if err := os.Symlink(filepath.Join(root, "src"), alias); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	newFile := filepath.Join(alias, "new.ms")
	overlay := map[string]string{newFile: "export fn value() -> Int:\n    return 3\n"}
	result := compiler.CompileFile(filepath.Join(alias, "main.ms"), compiler.Options{Overlay: overlay})
	if !result.Success() || len(result.Program.Modules) != 2 {
		t.Fatal("unsaved source lost through symlinked workspace", result.Diagnostics)
	}
	selected := compiler.CompileFile(filepath.Join(alias, "main.ms"), compiler.Options{AnalyzeOnly: true, Module: newFile, Overlay: overlay})
	if !selected.Success() || len(selected.Program.Modules) != 1 || selected.Program.Modules[0].File != "new.ms" {
		t.Fatal("unsaved editor selection lost through symlinked workspace", selected.Diagnostics)
	}
	canonicalRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		t.Fatal(err)
	}
	overlay[filepath.Join(canonicalRoot, "src", "new.ms")] = "export fn value() -> Int:\n    return 4\n"
	result = compiler.CompileFile(filepath.Join(alias, "main.ms"), compiler.Options{Overlay: overlay})
	if result.Success() || result.Source != "" || !strings.Contains(result.Diagnostics[0].Message, "conflicting editor overlays") {
		t.Fatal("conflicting identities selected an arbitrary overlay", result.Diagnostics)
	}
}

func TestAnalysisChecksEntryWithoutGeneratingGo(t *testing.T) {
	root := t.TempDir()
	write(t, root, "ms.toml", "[project]\nname = \"analysis\"\nsource = \".\"\nentry = \"main.ms\"\n")
	write(t, root, "main.ms", "fn helper() -> Int:\n    return 1\n")
	manifest := filepath.Join(root, "ms.toml")
	result := compiler.CompileFile(manifest, compiler.Options{AnalyzeOnly: true, Entry: true})
	if result.Success() || result.Source != "" || !strings.Contains(result.Diagnostics[0].Message, "entry must export") {
		t.Fatal("analysis skipped the requested entry contract", result.Diagnostics)
	}
	if editor := compiler.CompileFile(manifest, compiler.Options{AnalyzeOnly: true}); !editor.Success() {
		t.Fatal("editor analysis incorrectly required an application entry", editor.Diagnostics)
	}
	write(t, root, "main.ms", "export fn main() -> Int:\n    return 0\n")
	result = compiler.CompileFile(manifest, compiler.Options{AnalyzeOnly: true, Entry: true})
	if !result.Success() || result.Program == nil || result.Source != "" {
		t.Fatal("checked analysis performed lowering", result.Diagnostics)
	}
}
