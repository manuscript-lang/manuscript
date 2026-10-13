package cli

import (
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/project"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

type analysisInput struct{ path, display string }

type analysisSelection struct {
	inputs      []analysisInput
	diagnostics []syntax.Diagnostic
	cwd         string
	collection  bool
}

// A collection is a set of independent compiler requests, never a combined
// program. Keep the old single-file/project spelling and diagnostic roots.
func selectAnalysisInputs(targets []string) (analysisSelection, error) {
	cwd, err := formatCWD()
	if err != nil {
		return analysisSelection{}, err
	}
	selection := analysisSelection{cwd: cwd, collection: len(targets) > 1}
	seen := map[string]bool{}
	report := func(path string, err error) {
		selection.diagnostics = append(selection.diagnostics, syntax.Diagnostic{
			Position: syntax.Position{File: formatDisplay(cwd, path), Line: 1, Column: 1},
			Phase:    "resolution", Message: fileError(err),
		})
	}
	add := func(path string) {
		if !selection.collection {
			selection.inputs = append(selection.inputs, analysisInput{path, path})
			return
		}
		absolute, err := filepath.Abs(path)
		if err != nil {
			report(path, err)
			return
		}
		canonical, err := filepath.EvalSymlinks(absolute)
		if err != nil {
			report(path, err)
			return
		}
		identity := canonical
		if filepath.Base(path) == "ms.toml" {
			// Manifest configuration paths belong to its containing directory,
			// even if the manifest itself is a file symlink.
			parent, err := filepath.EvalSymlinks(filepath.Dir(absolute))
			if err != nil {
				report(path, err)
				return
			}
			canonical = filepath.Join(parent, "ms.toml")
			identity = canonical
		}
		if !seen[identity] {
			seen[identity] = true
			selection.inputs = append(selection.inputs, analysisInput{canonical, formatDisplay(cwd, canonical)})
		}
	}
	for _, target := range targets {
		info, err := os.Stat(target)
		if err != nil || !info.IsDir() {
			add(target)
			continue
		}
		manifest := filepath.Join(target, "ms.toml")
		if _, err := os.Stat(manifest); !os.IsNotExist(err) {
			add(manifest)
			continue
		}
		selection.collection = true
		root, err := filepath.Abs(target)
		if err == nil {
			root, err = filepath.EvalSymlinks(root)
		}
		if err != nil {
			report(target, err)
			continue
		}
		paths, err := standaloneAnalysisFiles(root)
		if err != nil {
			report(target, err)
		}
		for _, path := range paths {
			canonical, err := project.SourcePath(root, path, nil)
			if err != nil {
				report(path, err)
				continue
			}
			add(canonical)
		}
	}
	sort.Slice(selection.inputs, func(i, j int) bool { return selection.inputs[i].display < selection.inputs[j].display })
	return selection, nil
}

// Use the established directory exclusions without changing project or fmt
// discovery. A nested manifest starts another project and requires selection.
func standaloneAnalysisFiles(root string) ([]string, error) {
	var files []string
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		name := entry.Name()
		if entry.IsDir() {
			if path == root {
				return nil
			}
			if strings.HasPrefix(name, ".") || name == "vendor" || name == "node_modules" {
				return filepath.SkipDir
			}
			if _, err := os.Stat(filepath.Join(path, "ms.toml")); !os.IsNotExist(err) {
				if err != nil {
					return err
				}
				return filepath.SkipDir
			}
			return nil
		}
		if filepath.Ext(name) == ".ms" {
			files = append(files, path)
		}
		return nil
	})
	return files, err
}

func (s analysisSelection) position(root string, position syntax.Position) syntax.Position {
	if !s.collection || strings.HasPrefix(position.File, "@std/") {
		return position
	}
	if root != "" && !filepath.IsAbs(position.File) {
		position.File = filepath.Join(root, position.File)
	}
	position.File = formatDisplay(s.cwd, position.File)
	return position
}

func (s analysisSelection) diagnostic(root string, issue syntax.Diagnostic) syntax.Diagnostic {
	issue.Position = s.position(root, issue.Position)
	if issue.End != nil {
		end := s.position(root, *issue.End)
		issue.End = &end
	}
	if issue.Fix != nil {
		fix := *issue.Fix
		fix.Position = s.position(root, fix.Position)
		fix.End = s.position(root, fix.End)
		issue.Fix = &fix
	}
	return issue
}
