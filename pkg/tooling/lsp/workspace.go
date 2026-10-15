package lsp

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/project"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func workspaceDocuments(d document, docs map[string]document, recursive ...bool) ([]document, error) {
	path := filename(d.URI)
	root := filepath.Dir(path)
	includeNested := len(recursive) > 0 && recursive[0]
	if manifest, ok := project.FindManifest(path); ok {
		root = filepath.Dir(manifest)
		includeNested = true
	}

	files := map[string]document{}
	for _, open := range docs {
		relative, e := filepath.Rel(root, filename(open.URI))
		if e == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
			files[filename(open.URI)] = open
		}
	}
	files[path] = d
	visit := func(file string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			if file != root && (!includeNested || strings.HasPrefix(entry.Name(), ".") || entry.Name() == "node_modules" || entry.Name() == "vendor") {
				return filepath.SkipDir
			}
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 || !strings.HasSuffix(file, ".ms") {
			return nil
		}
		if _, exists := files[file]; exists {
			return nil
		}
		data, e := os.ReadFile(file)
		if e != nil {
			return e
		}
		files[file] = document{URI: fileURI(file), Text: string(data)}
		return nil
	}
	if err := filepath.WalkDir(root, visit); err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	result := []document{}
	for _, file := range files {
		result = append(result, file)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].URI < result[j].URI })
	return result, nil
}
func workspaceAnalysis(d document, docs map[string]document) compiler.Result {
	return analyzeOptions(d, docs, compiler.Options{AnalyzeOnly: true, Module: filename(d.URI)})
}
func workspaceReferences(d document, docs map[string]document, p position, include bool) []any {
	result := analyze(d, docs)
	selected := occurrenceAt(result, d, p, sourceIndex(result))
	if selected == nil {
		return []any{}
	}
	if selected.info != nil && selected.info.Binding != nil && strings.HasPrefix(selected.key, "binding:") {
		return references(result, d, p, include)
	}
	documents, err := workspaceDocuments(d, docs)
	if err != nil {
		return references(result, d, p, include)
	}
	locations := []any{}
	seen := map[string]bool{}
	for _, file := range documents {
		checked := workspaceAnalysis(file, docs)
		for _, entry := range sourceIndex(checked) {
			if entry.key != selected.key || !include && entry.declaration {
				continue
			}
			location := occurrenceLocation(checked, entry)
			if location == nil {
				continue
			}
			mapLocation := location.(map[string]any)
			id := fmt.Sprint(mapLocation["uri"], mapLocation["range"])
			if !seen[id] {
				seen[id] = true
				locations = append(locations, location)
			}
		}
	}
	sort.Slice(locations, func(i, j int) bool { return fmt.Sprint(locations[i]) < fmt.Sprint(locations[j]) })
	return locations
}
func workspaceSymbols(docs map[string]document, roots []string, query string) []any {
	result := []any{}
	seen := map[string]bool{}
	documents := []document{}
	for _, open := range docs {
		files, err := workspaceDocuments(open, docs)
		if err == nil {
			documents = append(documents, files...)
		}
	}
	for _, root := range roots {
		dummy := document{URI: fileURI(filepath.Join(root, "__workspace_index.ms"))}
		files, err := workspaceDocuments(dummy, docs, true)
		if err == nil {
			for _, file := range files {
				if file.URI != dummy.URI {
					documents = append(documents, file)
				}
			}
		}
	}
	analyzed := map[string]bool{}
	for _, d := range documents {
		if analyzed[d.URI] {
			continue
		}
		analyzed[d.URI] = true
		checked := workspaceAnalysis(d, docs)
		for _, entry := range sourceIndex(checked) {
			if strings.HasPrefix(entry.pos.File, "@std/") || !entry.declaration || entry.info == nil || entry.info.Symbol == nil && entry.info.Method == nil || !strings.Contains(strings.ToLower(entry.name), strings.ToLower(query)) {
				continue
			}
			location := occurrenceLocation(checked, entry)
			if location == nil {
				continue
			}
			id := fmt.Sprint(location)
			if seen[id] {
				continue
			}
			seen[id] = true
			kind := 12
			if entry.info.Method != nil && entry.info.Method.Accessor {
				kind = 7
			} else if entry.info.Symbol != nil && entry.info.Symbol.Kind == "type" {
				kind = 5
			} else if entry.info.Symbol != nil && entry.info.Symbol.IsConstant() {
				kind = 14
			}
			result = append(result, map[string]any{"name": entry.name, "kind": kind, "location": location})
		}
	}
	sort.Slice(result, func(i, j int) bool { return fmt.Sprint(result[i]) < fmt.Sprint(result[j]) })
	return result
}
