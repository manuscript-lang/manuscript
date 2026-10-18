package lsp

import (
	"context"
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
	return workspaceDocumentsWithCancel(d, docs, len(recursive) > 0 && recursive[0], nil)
}

func workspaceScope(d document, recursive bool) (string, bool) {
	path := filename(d.URI)
	root := filepath.Dir(path)
	if manifest, ok := project.FindManifest(path); ok {
		root = filepath.Dir(manifest)
		recursive = true
	}
	return root, recursive
}

func isCanceled(check func() bool) bool { return check != nil && check() }

func workspaceDocumentsWithCancel(d document, docs map[string]document, recursive bool, canceled func() bool) ([]document, error) {
	if isCanceled(canceled) {
		return nil, context.Canceled
	}
	path := filename(d.URI)
	root, includeNested := workspaceScope(d, recursive)

	files := map[string]document{}
	for _, open := range docs {
		if isCanceled(canceled) {
			return nil, context.Canceled
		}
		relative, e := filepath.Rel(root, filename(open.URI))
		if e == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
			files[filename(open.URI)] = open
		}
	}
	files[path] = d
	visit := func(file string, entry fs.DirEntry, err error) error {
		if isCanceled(canceled) {
			return context.Canceled
		}
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
	return workspaceReferencesChecked(result, sourceIndex(result), d, docs, p, include, nil)
}

func workspaceReferencesChecked(result compiler.Result, index []occurrence, d document, docs map[string]document, p position, include bool, canceled func() bool) []any {
	if isCanceled(canceled) {
		return nil
	}
	selected := occurrenceAt(result, d, p, index)
	if selected == nil {
		return []any{}
	}
	if selected.info != nil && selected.info.Binding != nil && strings.HasPrefix(selected.key, "binding:") {
		return referencesWithIndex(result, index, d, p, include)
	}
	documents, err := workspaceDocumentsWithCancel(d, docs, false, canceled)
	if err != nil {
		if isCanceled(canceled) {
			return nil
		}
		return referencesWithIndex(result, index, d, p, include)
	}
	locations := []any{}
	seen := map[string]bool{}
	for _, file := range documents {
		if isCanceled(canceled) {
			return nil
		}
		checked := workspaceAnalysis(file, docs)
		if isCanceled(canceled) {
			return nil
		}
		for _, entry := range sourceIndex(checked) {
			if isCanceled(canceled) {
				return nil
			}
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
	return workspaceSymbolsWithCancel(docs, roots, query, nil)
}

func workspaceSymbolsWithCancel(docs map[string]document, roots []string, query string, canceled func() bool) []any {
	result := []any{}
	seen := map[string]bool{}
	documents := []document{}
	type scope struct {
		root      string
		recursive bool
	}
	walked := map[scope]bool{}
	discover := func(d document, recursive bool) ([]document, error) {
		root, nested := workspaceScope(d, recursive)
		key := scope{root, nested}
		if walked[key] {
			return nil, nil
		}
		walked[key] = true
		return workspaceDocumentsWithCancel(d, docs, recursive, canceled)
	}
	for _, open := range docs {
		if isCanceled(canceled) {
			return nil
		}
		files, err := discover(open, false)
		if err == context.Canceled {
			return nil
		}
		if err == nil {
			documents = append(documents, files...)
		}
	}
	for _, root := range roots {
		if isCanceled(canceled) {
			return nil
		}
		dummy := document{URI: fileURI(filepath.Join(root, "__workspace_index.ms"))}
		files, err := discover(dummy, true)
		if err == context.Canceled {
			return nil
		}
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
		if isCanceled(canceled) {
			return nil
		}
		if analyzed[d.URI] {
			continue
		}
		analyzed[d.URI] = true
		checked := workspaceAnalysis(d, docs)
		if isCanceled(canceled) {
			return nil
		}
		for _, entry := range sourceIndex(checked) {
			if isCanceled(canceled) {
				return nil
			}
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
			if entry.info.Symbol != nil && entry.info.Symbol.Kind == "type" {
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
