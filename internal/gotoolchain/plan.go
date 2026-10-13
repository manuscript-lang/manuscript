package gotoolchain

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"go/build"
	"os"
	"path/filepath"
	"slices"

	"github.com/manuscript-lang/manuscript/internal/gotoolchain/internal/buildcfg"
)

// A plan records the dependency packages of a main package, so a rebuild
// whose main package has the same imports skips reading every package
// directory. Standard sources are fixed for an SDK release and module
// sources are identified by ModuleRoot, which callers keep immutable.
type plannedPackage struct {
	Path          string
	Dir           string
	Standard      bool
	Module        string         `json:",omitempty"`
	Imports       map[string]int `json:",omitempty"` // as written -> plan index
	GoFiles       []string
	SFiles        []string `json:",omitempty"`
	HFiles        []string `json:",omitempty"`
	EmbedPatterns []string `json:",omitempty"`
}

const planFormat = 1

func (b *builder) planFile(imports []string) string {
	identity, _ := json.Marshal(struct {
		Format                         int
		Version, GOROOT, GOOS, GOARCH  string
		ToolTags, Tags, Imports        []string
		ModuleRoot, ModulePath, MainGo string
	}{planFormat, Version(), b.GOROOT, buildcfg.GOOS, buildcfg.GOARCH, buildcfg.ToolTags, b.Tags, slices.Sorted(slices.Values(imports)), b.ModuleRoot, b.ModulePath, b.mainGo})
	sum := sha256.Sum256(identity)
	return filepath.Join(b.Cache, "plans", hex.EncodeToString(sum[:16])+".json")
}

// loadPlan registers every planned package, reporting false when no
// usable plan exists.
func (b *builder) loadPlan(file string) bool {
	data, err := os.ReadFile(file)
	if err != nil {
		return false
	}
	var planned []plannedPackage
	if json.Unmarshal(data, &planned) != nil {
		return false
	}
	modules := map[string]*vendoredModule{}
	for _, module := range b.modules {
		modules[module.path] = module
	}
	packages := make([]*pkg, len(planned))
	for i, entry := range planned {
		p := &pkg{path: entry.Path, dir: entry.Dir, standard: entry.Standard, imports: map[string]*pkg{},
			files: &build.Package{GoFiles: entry.GoFiles, SFiles: entry.SFiles, HFiles: entry.HFiles, EmbedPatterns: entry.EmbedPatterns}}
		if entry.Module != "" {
			if p.module = modules[entry.Module]; p.module == nil {
				return false
			}
		}
		for imported, index := range entry.Imports {
			if index < 0 || index >= i {
				return false
			}
			p.imports[imported] = packages[index]
		}
		packages[i] = p
	}
	for _, p := range packages {
		b.loaded[p.dir] = p
	}
	b.order = packages
	return true
}

// savePlan records the packages loaded before root. Failure only costs a
// later rebuild its shortcut.
func (b *builder) savePlan(file string, root *pkg) {
	index := map[*pkg]int{}
	var planned []plannedPackage
	for _, p := range b.order {
		if p == root {
			continue
		}
		entry := plannedPackage{Path: p.path, Dir: p.dir, Standard: p.standard, GoFiles: p.files.GoFiles,
			SFiles: p.files.SFiles, HFiles: p.files.HFiles, EmbedPatterns: p.files.EmbedPatterns, Imports: map[string]int{}}
		if p.module != nil {
			entry.Module = p.module.path
		}
		for imported, dependency := range p.imports {
			entry.Imports[imported] = index[dependency]
		}
		index[p] = len(planned)
		planned = append(planned, entry)
	}
	data, err := json.Marshal(planned)
	if err != nil {
		return
	}
	if err := os.MkdirAll(filepath.Dir(file), 0755); err != nil {
		return
	}
	temporary, err := os.CreateTemp(filepath.Dir(file), ".plan-")
	if err != nil {
		return
	}
	defer os.Remove(temporary.Name())
	if _, err := temporary.Write(data); err != nil {
		temporary.Close()
		return
	}
	if temporary.Close() == nil {
		os.Rename(temporary.Name(), file)
	}
}
