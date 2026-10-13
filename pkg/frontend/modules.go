package frontend

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/project"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// LoadFile resolves a module or manifest, then parses each reachable local
// module once. Standard declarations are supplied by the checker.
func LoadFile(filename string, options Options) Graph {
	config, manifest, err := sourceProject(filename)
	if err != nil {
		return Graph{Diagnostics: []syntax.Diagnostic{diagnostic(filename, "resolution", err)}}
	}
	graph := Graph{SourceRoot: config.Root, Imports: map[*syntax.Import]string{}}
	if manifest {
		graph.ProjectRoot, graph.Configuration = config.Root, config.Configuration
	}
	if options.Module != "" {
		config.Entry = options.Module
	}
	overlay, err := canonicalOverlay(config.Root, options.Overlay)
	if err != nil {
		graph.Diagnostics = []syntax.Diagnostic{diagnostic(config.Entry, "resolution", err)}
		return graph
	}
	entry, err := project.SourcePath(config.Root, config.Entry, overlay)
	if err != nil {
		graph.Diagnostics = []syntax.Diagnostic{diagnostic(filename, "resolution", err)}
		return graph
	}
	loader := moduleLoader{
		config: config, overlay: overlay, recover: options.Recover,
		graph: &graph, active: map[string]bool{}, loaded: map[string]string{},
	}
	graph.Entry, err = loader.visit(entry)
	if err != nil {
		// An incomplete strict graph cannot be checked. Recovered graphs retain
		// import failures inside visit and still contain the selected module.
		graph.Modules = nil
		graph.Diagnostics = append(graph.Diagnostics, diagnostic(filename, "resolution", err))
		return graph
	}
	if manifest && options.Tests {
		for _, test := range discoverTests(config.Root) {
			canonical, err := project.SourcePath(config.Root, test, overlay)
			if err == nil {
				_, err = loader.visit(canonical)
			}
			if err != nil {
				graph.Diagnostics = append(graph.Diagnostics, diagnostic(test, "resolution", err))
			}
		}
	}
	return graph
}

// discoverTests finds test.ms and *_test.ms files below a project root,
// skipping hidden and dependency directories.
func discoverTests(root string) []string {
	var found []string
	filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		name := entry.Name()
		if entry.IsDir() {
			if path != root && (strings.HasPrefix(name, ".") || name == "vendor" || name == "node_modules") {
				return filepath.SkipDir
			}
			return nil
		}
		if name == "test.ms" || strings.HasSuffix(name, "_test.ms") {
			found = append(found, path)
		}
		return nil
	})
	return found
}

func sourceProject(filename string) (project.Project, bool, error) {
	absolute, err := filepath.Abs(filename)
	if err != nil {
		return project.Project{}, false, err
	}
	if filepath.Base(absolute) == "ms.toml" {
		config, err := project.ReadProject(absolute)
		return config, true, err
	}
	root, err := filepath.EvalSymlinks(filepath.Dir(absolute))
	return project.Project{Root: root, Entry: absolute, Aliases: map[string]string{}}, false, err
}

// Canonicalize editor snapshots exactly as filesystem reads and imports are
// canonicalized. Two spellings of one file cannot select conflicting content.
func canonicalOverlay(root string, overlay map[string]string) (map[string]string, error) {
	normalized := make(map[string]string, len(overlay))
	for filename, source := range overlay {
		canonical, err := project.SourcePath(root, filename, overlay)
		if err != nil {
			// Documents outside this project never enter its module graph.
			continue
		}
		if previous, ok := normalized[canonical]; ok && previous != source {
			return nil, fmt.Errorf("conflicting editor overlays for %s; two spellings of one path carry different unsaved contents, so send a single snapshot per file", canonical)
		}
		normalized[canonical] = source
	}
	return normalized, nil
}

type moduleLoader struct {
	config  project.Project
	overlay map[string]string
	recover bool
	graph   *Graph
	active  map[string]bool
	loaded  map[string]string
}

// visit accepts an already resolved canonical path. Resolution happens at the
// graph's edges, never again during traversal or checking.
func (l *moduleLoader) visit(canonical string) (string, error) {
	logical, err := filepath.Rel(l.config.Root, canonical)
	if err != nil {
		return "", err
	}
	logical = filepath.ToSlash(logical)
	if l.active[canonical] {
		return "", fmt.Errorf("cyclic module dependency at %s; modules cannot import each other in a loop, so move the shared declarations into a third module that both import", logical)
	}
	if key, ok := l.loaded[canonical]; ok {
		return key, nil
	}
	l.active[canonical] = true
	defer delete(l.active, canonical)

	source, err := l.read(canonical)
	if err != nil {
		return "", err
	}
	module, issues := Parse(logical, source, l.recover)
	if module == nil {
		return "", issues[0]
	}
	l.graph.Diagnostics = append(l.graph.Diagnostics, issues...)
	for _, item := range module.Imports {
		if strings.HasPrefix(item.Path, "@std/") {
			continue
		}
		key, err := l.importModule(canonical, item)
		if err != nil {
			if !l.recover {
				return "", err
			}
			l.graph.Diagnostics = append(l.graph.Diagnostics, diagnostic(logical, "resolution", err))
			continue
		}
		l.graph.Imports[item] = key
	}
	l.loaded[canonical] = logical
	l.graph.Modules = append(l.graph.Modules, module)
	return logical, nil
}

func (l *moduleLoader) read(filename string) (string, error) {
	if source, ok := l.overlay[filename]; ok {
		return source, nil
	}
	source, err := os.ReadFile(filename)
	return string(source), err
}

func (l *moduleLoader) importModule(filename string, item *syntax.Import) (string, error) {
	target, err := project.ResolveImport(l.config, filename, item.Path, l.overlay)
	if err != nil {
		return "", syntax.Diagnostic{Position: item.Pos, Phase: "resolution", Message: explainPathError(err, item.Path)}
	}
	key, err := l.visit(target)
	if err != nil {
		if issue, ok := err.(syntax.Diagnostic); ok {
			return "", issue
		}
		return "", syntax.Diagnostic{Position: item.Pos, Phase: "resolution", Message: err.Error()}
	}
	return key, nil
}
