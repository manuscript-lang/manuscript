package gotoolchain

import (
	"errors"
	"fmt"
	"go/build"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/internal/gotoolchain/internal/goversion"
)

type pkg struct {
	path     string // import path as compiled: "main", or "vendor/..." for std vendoring
	dir      string
	standard bool
	module   *vendoredModule // nil for standard and main-module packages
	files    *build.Package  // set once imports are loaded
	imports  map[string]*pkg // by import path as written in source
	key      string
	archive  string
	done     chan struct{}
	err      error
}

type vendoredModule struct {
	path, version, goVersion string
}

// loadMain loads the main package and every package it links, reusing a
// cached dependency plan when the main package's imports are unchanged.
func (b *builder) loadMain() (*pkg, error) {
	if err := b.readModules(); err != nil {
		return nil, err
	}
	files, err := b.context.ImportDir(b.Dir, 0)
	if err != nil {
		return nil, fmt.Errorf("load %s: %w", b.ImportPath, err)
	}
	plan := b.planFile(files.Imports)
	planned := b.loadPlan(plan)
	if !planned {
		// Every executable links the runtime, even when main does not import it.
		if _, err := b.load("runtime", filepath.Join(b.GOROOT, "src", "runtime"), true); err != nil {
			return nil, err
		}
	}
	root, err := b.loadFiles("main", b.Dir, false, files)
	if err != nil {
		return nil, err
	}
	if !planned {
		b.savePlan(plan, root)
	}
	return root, nil
}

// readModules records the main module's go version and each vendored module
// listed in vendor/modules.txt.
func (b *builder) readModules() error {
	data, err := os.ReadFile(filepath.Join(b.ModuleRoot, "go.mod"))
	if err != nil {
		return err
	}
	for _, line := range strings.Split(string(data), "\n") {
		if version, ok := strings.CutPrefix(strings.TrimSpace(line), "go "); ok {
			b.mainGo = strings.TrimSpace(version)
		}
	}
	data, err = os.ReadFile(filepath.Join(b.ModuleRoot, "vendor", "modules.txt"))
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	} else if err != nil {
		return err
	}
	var current *vendoredModule
	for _, line := range strings.Split(string(data), "\n") {
		switch {
		case strings.HasPrefix(line, "# "):
			// "# path version", or a replacement "# path => ..." we do not support.
			current = nil
			if fields := strings.Fields(line[2:]); len(fields) == 2 {
				current = &vendoredModule{path: fields[0], version: fields[1]}
				b.modules = append(b.modules, current)
			}
		case strings.HasPrefix(line, "## ") && current != nil:
			// "## explicit; go 1.23"
			for _, field := range strings.Split(line[3:], ";") {
				if version, ok := strings.CutPrefix(strings.TrimSpace(field), "go "); ok {
					current.goVersion = version
				}
			}
		}
	}
	// Longest paths first, so a nested module wins its packages.
	sort.Slice(b.modules, func(i, j int) bool { return len(b.modules[i].path) > len(b.modules[j].path) })
	return nil
}

// load reads a package and its imports depth first, appending each package
// to the build order after its dependencies.
func (b *builder) load(path, dir string, standard bool) (*pkg, error) {
	if p, ok := b.loaded[dir]; ok {
		if p.files == nil {
			return nil, fmt.Errorf("import cycle through %s", path)
		}
		return p, nil
	}
	files, err := b.context.ImportDir(dir, 0)
	if err != nil {
		return nil, fmt.Errorf("load %s: %w", path, err)
	}
	return b.loadFiles(path, dir, standard, files)
}

func (b *builder) loadFiles(path, dir string, standard bool, files *build.Package) (*pkg, error) {
	p := &pkg{path: path, dir: dir, standard: standard, imports: map[string]*pkg{}}
	b.loaded[dir] = p
	if len(files.CgoFiles) > 0 {
		return nil, fmt.Errorf("load %s: cgo is not supported", path)
	}
	if !standard && path != "main" && !b.inMainModule(path) {
		if p.module = b.vendored(path); p.module == nil {
			return nil, fmt.Errorf("load %s: package is not in vendor/modules.txt", path)
		}
	}
	for _, imported := range files.Imports {
		if imported == "unsafe" {
			continue
		}
		if imported == "C" {
			return nil, fmt.Errorf("load %s: cgo is not supported", path)
		}
		dependency, err := b.load(b.resolve(p, imported))
		if err != nil {
			return nil, err
		}
		p.imports[imported] = dependency
	}
	p.files = files
	b.order = append(b.order, p)
	return p, nil
}

func (b *builder) inMainModule(path string) bool {
	return path == b.ModulePath || strings.HasPrefix(path, b.ModulePath+"/")
}

func (b *builder) vendored(path string) *vendoredModule {
	for _, module := range b.modules {
		if path == module.path || strings.HasPrefix(path, module.path+"/") {
			return module
		}
	}
	return nil
}

// resolve maps an import in p to the compiled import path, directory, and
// standard-ness of the imported package.
func (b *builder) resolve(p *pkg, path string) (string, string, bool) {
	first, _, _ := strings.Cut(path, "/")
	switch {
	case !strings.Contains(first, "."):
		return path, filepath.Join(b.GOROOT, "src", filepath.FromSlash(path)), true
	case p.standard:
		// The standard library vendors its own golang.org/x dependencies.
		path = "vendor/" + path
		return path, filepath.Join(b.GOROOT, "src", filepath.FromSlash(path)), true
	case b.inMainModule(path):
		return path, filepath.Join(b.ModuleRoot, filepath.FromSlash(strings.TrimPrefix(path, b.ModulePath))), false
	default:
		return path, filepath.Join(b.ModuleRoot, "vendor", filepath.FromSlash(path)), false
	}
}

// lang is the -lang setting the go command derives from p's module.
func (b *builder) lang(p *pkg) string {
	version := fmt.Sprintf("1.%d", goversion.Version)
	switch {
	case p.standard:
	case p.module != nil:
		version = p.module.goVersion
		if version == "" {
			version = "1.16" // the go command's default for modules without one
		}
	default:
		version = b.mainGo
	}
	major, rest, _ := strings.Cut(version, ".")
	minor, _, _ := strings.Cut(rest, ".")
	return "go" + major + "." + minor
}

// embedFiles resolves p's //go:embed patterns. It returns the files by
// package-relative name and the names each pattern matched.
func (b *builder) embedFiles(p *pkg) (map[string]string, map[string][]string) {
	files := map[string]string{}
	patterns := map[string][]string{}
	for _, pattern := range p.files.EmbedPatterns {
		glob, all := strings.CutPrefix(pattern, "all:")
		matches, _ := filepath.Glob(filepath.Join(p.dir, filepath.FromSlash(glob)))
		for _, match := range matches {
			filepath.WalkDir(match, func(name string, entry fs.DirEntry, err error) error {
				if err != nil {
					return err
				}
				// Directory contents omit hidden names unless the pattern says all:.
				if hidden := strings.HasPrefix(entry.Name(), ".") || strings.HasPrefix(entry.Name(), "_"); hidden && name != match && !all {
					if entry.IsDir() {
						return filepath.SkipDir
					}
					return nil
				}
				if entry.IsDir() {
					return nil
				}
				relative, err := filepath.Rel(p.dir, name)
				if err != nil {
					return err
				}
				relative = filepath.ToSlash(relative)
				files[relative] = name
				patterns[pattern] = append(patterns[pattern], relative)
				return nil
			})
		}
	}
	return files, patterns
}
