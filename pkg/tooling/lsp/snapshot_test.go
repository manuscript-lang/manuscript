package lsp

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func snapshotFiles(t testing.TB, files map[string]string) (string, map[string]document) {
	t.Helper()
	root := t.TempDir()
	docs := map[string]document{}
	for name, text := range files {
		path := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(text), 0600); err != nil {
			t.Fatal(err)
		}
		if filepath.Ext(name) == ".ms" {
			docs[name] = document{URI: fileURI(path), Text: text, Version: 1}
		}
	}
	return root, docs
}

func snapshotServer(docs ...document) *server {
	s := &server{transport: &transport{pending: map[string]bool{}}, output: io.Discard, docs: map[string]document{}, cache: map[string]compiler.Result{}}
	for _, d := range docs {
		s.docs[d.URI] = d
	}
	return s
}

func TestSnapshotEquivalentFilenameURIsKeepTheirRequestedText(t *testing.T) {
	_, files := snapshotFiles(t, map[string]string{
		"ms.toml": "[project]\nname = \"uris\"\nsource = \".\"\nentry = \"main.ms\"\n",
		"main.ms": "fn answer() Int: 1\n",
	})
	real := files["main.ms"]
	alias := real
	alias.URI = strings.TrimSuffix(real.URI, "main.ms") + "%6dain.ms"
	alias.Text = "fn answer() Int: \"wrong\"\n"
	if filename(real.URI) != filename(alias.URI) {
		t.Fatal("negative-control URI did not decode to the same filename")
	}
	for _, order := range [][]document{{real, alias}, {alias, real}} {
		s := snapshotServer(real, alias)
		for _, d := range order {
			snapshotEquivalent(t, s, d)
		}
		if !s.checkedDocument(real).Success() || s.checkedDocument(alias).Success() {
			t.Fatal("equivalent filename URI lost per-request overlay precedence")
		}
	}
}

func TestSnapshotSymlinkedFilesDoNotMergeDifferentRoots(t *testing.T) {
	for _, manifest := range []bool{false, true} {
		t.Run(map[bool]string{false: "standalone", true: "manifest"}[manifest], func(t *testing.T) {
			a, b := t.TempDir(), t.TempDir()
			source := "fn answer() Int: 1\n"
			write := func(path, text string) {
				t.Helper()
				if err := os.WriteFile(path, []byte(text), 0600); err != nil {
					t.Fatal(err)
				}
			}
			write(filepath.Join(b, "real.ms"), source)
			linked := filepath.Join(a, "link.ms")
			if manifest {
				write(filepath.Join(b, "ms.toml"), "[project]\nname = \"linked\"\nsource = \".\"\nentry = \"real.ms\"\n")
				if err := os.Symlink(filepath.Join(b, "ms.toml"), filepath.Join(a, "ms.toml")); err != nil {
					t.Skipf("symlinks unavailable: %v", err)
				}
				linked = filepath.Join(a, "real.ms")
				write(linked, "fn answer() Int: \"wrong\"\n")
			} else if err := os.Symlink(filepath.Join(b, "real.ms"), linked); err != nil {
				t.Skipf("symlinks unavailable: %v", err)
			}
			data, err := os.ReadFile(linked)
			if err != nil {
				t.Fatal(err)
			}
			real := document{URI: fileURI(filepath.Join(b, "real.ms")), Text: source, Version: 1}
			alias := document{URI: fileURI(linked), Text: string(data), Version: 1}
			for _, order := range [][]document{{real, alias}, {alias, real}} {
				s := snapshotServer(real, alias)
				for _, d := range order {
					snapshotEquivalent(t, s, d)
				}
				if !s.checkedDocument(real).Success() || s.checkedDocument(alias).Success() {
					t.Fatal("different source-root success/error states were collapsed")
				}
			}
		})
	}
}

func snapshotEquivalent(t testing.TB, s *server, d document) compiler.Result {
	t.Helper()
	got, want := s.checkedDocument(d), analyze(d, s.docs)
	view := func(result compiler.Result) any {
		modules := map[string]string{}
		if result.Program != nil {
			for _, m := range result.Program.Modules {
				modules[m.File] = m.Source
			}
		}
		diagnostics := make([]string, 0, len(result.Diagnostics))
		for _, diagnostic := range result.Diagnostics {
			encoded, err := json.Marshal(diagnostic)
			if err != nil {
				t.Fatal(err)
			}
			diagnostics = append(diagnostics, string(encoded))
		}
		sort.Strings(diagnostics)
		return struct {
			Program                 bool
			ProjectRoot, SourceRoot string
			Modules                 map[string]string
			Diagnostics             []string
		}{result.Program != nil, result.ProjectRoot, result.SourceRoot, modules, diagnostics}
	}
	if a, b := view(got), view(want); !reflect.DeepEqual(a, b) {
		t.Fatalf("cached result for %s differs from uncached analysis:\ngot: %+v\nwant: %+v", d.URI, a, b)
	}
	return got
}

func snapshotReplace(t *testing.T, s *server, d document, source string) document {
	t.Helper()
	d.Version++
	d.Text = source
	r := &request{Method: "textDocument/didChange"}
	params, err := json.Marshal(map[string]any{"textDocument": d, "contentChanges": []any{map[string]any{"text": source}}})
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(params, &r.params); err != nil {
		t.Fatal(err)
	}
	if _, rpcErr, err := s.handle(r); err != nil || rpcErr != nil {
		t.Fatalf("edit failed: %v %v", rpcErr, err)
	}
	if got := s.docs[d.URI]; got.Text != source || got.Version != d.Version {
		t.Fatalf("edit not accepted: %+v", got)
	}
	return d
}

func TestSnapshotReachableGenerationAndDerivedReuse(t *testing.T) {
	_, docs := snapshotFiles(t, map[string]string{
		"ms.toml": "[project]\nname = \"snapshots\"\nsource = \".\"\nentry = \"main.ms\"\n",
		"main.ms": "import value from \"./dep.ms\"\nexport fn main() Int: value()\n",
		"dep.ms":  "export fn value() Int:\n    let unused = 1\n    return 2\n",
	})
	s := snapshotServer(docs["main.ms"], docs["dep.ms"])
	main := snapshotEquivalent(t, s, docs["main.ms"])
	dep := snapshotEquivalent(t, s, docs["dep.ms"])
	if !main.Success() || main.Program == nil || main.Program != dep.Program {
		t.Fatalf("reachable documents did not share one checked program: %v", main.Diagnostics)
	}
	index := s.documentIndex(main)
	if len(index) == 0 || &index[0] != &s.documentIndex(dep)[0] {
		t.Fatal("reachable aliases did not reuse the occurrence index")
	}
	if lint := s.programLint(main); len(lint) == 0 || !reflect.DeepEqual(lint, tooling.LintProgram(main.Program)) || &lint[0] != &s.programLint(dep)[0] {
		t.Fatal("shared lint lost the unused-local finding or differs from uncached lint")
	}
	original := docs["dep.ms"]
	broken := snapshotReplace(t, s, original, "export fn value() Int: \"wrong\"\n")
	bad := snapshotEquivalent(t, s, docs["main.ms"])
	if len(bad.Diagnostics) == 0 || bad.Program == main.Program {
		t.Fatal("accepted edit reused an old program or hid the new type error")
	}
	if len(s.programLint(bad)) != 0 {
		t.Fatal("shared lint ignored graph-level diagnostic suppression")
	}
	_ = snapshotReplace(t, s, broken, original.Text)
	restored := snapshotEquivalent(t, s, docs["main.ms"])
	if !restored.Success() || restored.Program == bad.Program || restored.Program == main.Program || len(s.programLint(restored)) == 0 {
		t.Fatal("reverting an edit retained stale diagnostics, program, or lint")
	}
	// Caller-private repaired snapshots must not read or overwrite the live URI cache.
	private := s.docs[original.URI]
	private.Text = "export fn value() Int: \"private error\"\n"
	if got := snapshotEquivalent(t, s, private); len(got.Diagnostics) == 0 || got.Program == restored.Program {
		t.Fatal("private source was replaced by the live cached snapshot")
	}
	if got := s.checkedDocument(s.docs[original.URI]); got.Program != restored.Program {
		t.Fatal("private analysis poisoned the live generation")
	}
}

func TestSnapshotFallbackDoesNotReplaceDefault(t *testing.T) {
	_, docs := snapshotFiles(t, map[string]string{
		"ms.toml":  "[project]\nname = \"fallback\"\nsource = \".\"\nentry = \"main.ms\"\n",
		"main.ms":  "import value from \"./good.ms\"\nexport fn main() Int: value()\n",
		"good.ms":  "export fn value() Int: 1\n",
		"other.ms": "import bad from \"./bad.ms\"\nexport fn other() Int: bad()\n",
		"bad.ms":   "export fn bad() Int: \"wrong\"\n",
		"alone.ms": "export fn alone() Int: 3\n",
	})
	s := snapshotServer(docs["main.ms"], docs["other.ms"], docs["alone.ms"], docs["bad.ms"])
	fallback := snapshotEquivalent(t, s, docs["other.ms"])
	bad := snapshotEquivalent(t, s, docs["bad.ms"])
	if bad.Program == nil || bad.Program == fallback.Program || len(bad.Program.Modules) != 1 {
		t.Fatal("fallback containment was substituted for an exact selected root")
	}
	alone := snapshotEquivalent(t, s, docs["alone.ms"])
	main := snapshotEquivalent(t, s, docs["main.ms"])
	if len(fallback.Diagnostics) == 0 || !alone.Success() || !main.Success() {
		t.Fatal("unreachable error changed the default/fallback diagnostic scopes")
	}
	if fallback.Program == main.Program || fallback.Program == alone.Program || alone.Program == main.Program {
		t.Fatal("distinct selected roots shared a program")
	}
	if module(main, docs["other.ms"]) != nil || module(fallback, docs["main.ms"]) != nil {
		t.Fatal("fallback and default graph membership was combined")
	}
	if again := s.checkedDocument(docs["main.ms"]); again.Program != main.Program {
		t.Fatal("fallback replaced the default snapshot")
	}
}

func TestSnapshotNilProgramPreservesDefaultFailure(t *testing.T) {
	_, docs := snapshotFiles(t, map[string]string{
		"ms.toml":  "[project]\nname = \"broken_entry\"\nsource = \".\"\nentry = \"missing.ms\"\n",
		"other.ms": "export fn other() Int: 1\n",
	})
	s := snapshotServer(docs["other.ms"])
	result := snapshotEquivalent(t, s, docs["other.ms"])
	if result.Program != nil || len(result.Diagnostics) == 0 {
		t.Fatal("invalid default entry unexpectedly selected the otherwise valid open file")
	}
}

func TestSnapshotNearestManifestIsolation(t *testing.T) {
	root, docs := snapshotFiles(t, map[string]string{
		"ms.toml":         "[project]\nname = \"parent\"\nsource = \".\"\nentry = \"main.ms\"\n[aliases]\n\"@local\" = \".\"\n",
		"main.ms":         "import value from \"@local/value.ms\"\nexport fn main() Int: value()\n",
		"value.ms":        "export fn value() Int: 1\n",
		"nested/ms.toml":  "[project]\nname = \"nested\"\nsource = \".\"\n[aliases]\n\"@local\" = \".\"\n",
		"nested/value.ms": "export fn value() Int: 2\n",
		"nested/use.ms":   "import value from \"@local/value.ms\"\nexport fn use() Int: value()\n",
	})
	s := snapshotServer(docs["main.ms"], docs["nested/use.ms"])
	parent := snapshotEquivalent(t, s, docs["main.ms"])
	nested := snapshotEquivalent(t, s, docs["nested/use.ms"])
	if !parent.Success() || !nested.Success() || parent.Program == nested.Program || parent.ProjectRoot == nested.ProjectRoot {
		t.Fatal("different nearest manifests/alias sets were merged")
	}
	if err := os.WriteFile(filepath.Join(root, "nested", "ms.toml"), []byte("invalid configuration\n"), 0600); err != nil {
		t.Fatal(err)
	}
	s.invalidate()
	invalid := snapshotEquivalent(t, s, docs["nested/use.ms"])
	if len(invalid.Diagnostics) == 0 || invalid.Program != nil {
		t.Fatal("malformed nested manifest inherited the parent snapshot")
	}
	if got := snapshotEquivalent(t, s, docs["main.ms"]); !got.Success() {
		t.Fatal("nested manifest failure poisoned the parent project")
	}
}

func TestSnapshotOverlayIdentityAndConfinement(t *testing.T) {
	root, docs := snapshotFiles(t, map[string]string{
		"ms.toml": "[project]\nname = \"overlays\"\nsource = \".\"\nentry = \"main.ms\"\n",
		"main.ms": "import value from \"./new.ms\"\nexport fn main() Int: value()\n",
	})
	unsaved := document{URI: fileURI(filepath.Join(root, "new.ms")), Text: "export fn value() Int: 7\n", Version: 1}
	outside := document{URI: fileURI(filepath.Join(t.TempDir(), "outside.ms")), Text: "invalid source!", Version: 1}
	s := snapshotServer(docs["main.ms"], unsaved, outside)
	main := snapshotEquivalent(t, s, docs["main.ms"])
	newFile := snapshotEquivalent(t, s, unsaved)
	if !main.Success() || main.Program != newFile.Program || module(main, unsaved) == nil {
		t.Fatal("confined new overlay was not in the shared checked graph")
	}
	if _, err := os.Stat(filename(unsaved.URI)); !os.IsNotExist(err) {
		t.Fatal("analysis wrote the unsaved overlay to disk")
	}
	aliasRoot := filepath.Join(t.TempDir(), "alias")
	if err := os.Symlink(root, aliasRoot); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	alias := docs["main.ms"]
	alias.URI = fileURI(filepath.Join(aliasRoot, "main.ms"))
	s.docs[alias.URI] = alias
	s.invalidate()
	if got := snapshotEquivalent(t, s, alias); !got.Success() {
		t.Fatal("equivalent symlink overlay lost the valid graph")
	}
	alias.Text = "export fn main() Int: 9\n"
	s.docs[alias.URI] = alias
	s.invalidate()
	conflict := snapshotEquivalent(t, s, docs["main.ms"])
	if len(conflict.Diagnostics) == 0 || !strings.Contains(conflict.Diagnostics[0].Message, "conflicting editor overlays") {
		t.Fatal("conflicting symlink snapshots were silently deduplicated", conflict.Diagnostics)
	}
	delete(s.docs, alias.URI)
	escaping := document{URI: fileURI(filepath.Join(root, "escape.ms")), Text: unsaved.Text, Version: 1}
	if err := os.Symlink(filepath.Join(t.TempDir(), "missing.ms"), filename(escaping.URI)); err != nil {
		t.Fatal(err)
	}
	s.docs[escaping.URI] = escaping
	importer := docs["main.ms"]
	importer.Text = strings.Replace(importer.Text, "./new.ms", "./escape.ms", 1)
	s.docs[importer.URI] = importer
	s.invalidate()
	if got := snapshotEquivalent(t, s, importer); len(got.Diagnostics) == 0 || module(got, escaping) != nil {
		t.Fatal("dangling external symlink admitted an unconfined new overlay", got.Diagnostics)
	}
}

func TestSnapshotLibraryDiscoversTests(t *testing.T) {
	_, docs := snapshotFiles(t, map[string]string{
		"ms.toml":             "[project]\nname = \"library\"\nsource = \"src\"\n",
		"src/value.ms":        "export fn value() Int: 1\n",
		"src/other.ms":        "export fn other() Int: 2\n",
		"tests/value_test.ms": "import value from \"../src/value.ms\"\ntest \"checks source\":\n    let invalid: Int = \"wrong\"\n",
	})
	s := snapshotServer(docs["src/value.ms"], docs["src/other.ms"])
	one := snapshotEquivalent(t, s, docs["src/value.ms"])
	two := snapshotEquivalent(t, s, docs["src/other.ms"])
	if one.Program == nil || one.Program != two.Program || len(one.Program.Modules) != 3 || len(one.Diagnostics) == 0 {
		t.Fatal("library snapshot lost discovered tests/source or duplicated the checked graph", one.Diagnostics)
	}
	found := false
	for _, diagnostic := range one.Diagnostics {
		found = found || diagnostic.Position.File == "tests/value_test.ms"
	}
	if !found {
		t.Fatal("bad discovered test did not produce a positioned diagnostic")
	}
}
