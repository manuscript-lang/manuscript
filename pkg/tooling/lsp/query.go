package lsp

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"unicode/utf16"

	"github.com/manuscript-lang/manuscript/pkg/project"
)

// SymbolInfo describes the symbol at one source position.
type SymbolInfo struct {
	Hover       string   // type and documentation, as Markdown
	Definition  string   // file:line:column, or empty when none
	References  []string // file:line:column, declaration included
	Diagnostics int      // errors in the checked file; a broken file gives partial answers
}

// QuerySymbol answers hover, definition, and references for a 1-based line and
// column (a column counts characters) in a file, using the same analysis as the server.
func QuerySymbol(path string, line, column int) (SymbolInfo, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return SymbolInfo{}, err
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return SymbolInfo{}, err
	}
	d := document{URI: fileURI(abs), Text: string(data)}
	p, err := characterPosition(d.Text, line, column)
	if err != nil {
		return SymbolInfo{}, err
	}
	checked := analyze(d, map[string]document{})
	if checked.Program == nil {
		return SymbolInfo{}, fmt.Errorf("cannot analyze %s; run check for diagnostics", path)
	}
	info := SymbolInfo{Diagnostics: len(checked.Diagnostics)}
	if hover, ok := navigation(checked, d, p, "textDocument/hover").(map[string]any); ok {
		if contents, ok := hover["contents"].(map[string]any); ok {
			info.Hover, _ = contents["value"].(string)
		}
	}
	for _, location := range locations(navigation(checked, d, p, "textDocument/definition")) {
		info.Definition = location
		break
	}
	info.References = locations(workspaceReferences(d, map[string]document{}, p, true))
	return info, nil
}

// characterPosition converts a 1-based line and character column to an LSP position.
func characterPosition(text string, line, column int) (position, error) {
	if line < 1 || column < 1 {
		return position{}, fmt.Errorf("line and column are 1-based")
	}
	lines := strings.Split(text, "\n")
	if line > len(lines) {
		return position{}, fmt.Errorf("line %d is past the end of the file (%d lines)", line, len(lines))
	}
	runes := []rune(strings.TrimSuffix(lines[line-1], "\r"))
	if column > len(runes)+1 {
		return position{}, fmt.Errorf("column %d is past the end of line %d", column, line)
	}
	return position{Line: line - 1, Character: len(utf16.Encode(runes[:column-1]))}, nil
}

// locations flattens LSP location results into file:line:column strings.
func locations(result any) []string {
	data, err := json.Marshal(result)
	if err != nil {
		return nil
	}
	var many []struct {
		URI   string `json:"uri"`
		Range span   `json:"range"`
	}
	if err := json.Unmarshal(data, &many); err != nil {
		var one struct {
			URI   string `json:"uri"`
			Range span   `json:"range"`
		}
		if json.Unmarshal(data, &one) != nil || one.URI == "" {
			return nil
		}
		many = append(many, one)
	}
	out := make([]string, 0, len(many))
	for _, l := range many {
		out = append(out, fmt.Sprintf("%s:%d:%d", filename(l.URI), l.Range.Start.Line+1, l.Range.Start.Character+1))
	}
	return out
}

// SymbolMatch is one project declaration found by name.
type SymbolMatch struct {
	Name        string
	Kind        string   // fn, type, const, or member
	Definition  string   // file:line:column
	Hover       string   // type and documentation, as Markdown
	References  []string // file:line:column, declaration included
	Diagnostics int
}

// SearchSymbols finds declarations in the project containing dir whose name fuzzily
// matches query, ignoring case: exact names rank first, then prefixes, substrings,
// ordered subsequences, and near-misses of five or more letters. At most limit
// matches are described; total counts every match found.
func SearchSymbols(dir, query string, limit int) (matches []SymbolMatch, total int, err error) {
	root, err := filepath.Abs(dir)
	if err != nil {
		return nil, 0, err
	}
	if manifest, ok := projectManifest(root); ok {
		root = filepath.Dir(manifest)
	}
	type candidate struct {
		name, kind, location string
		rank                 int
	}
	var found []candidate
	for _, symbol := range workspaceSymbols(map[string]document{}, []string{root}, "") {
		entry, ok := symbol.(map[string]any)
		if !ok {
			continue
		}
		where := locations(entry["location"])
		name, _ := entry["name"].(string)
		if len(where) == 0 || name == "" {
			continue
		}
		rank := nameRank(name, query)
		if rank < 0 {
			continue
		}
		kind := "fn"
		switch entry["kind"] {
		case 5:
			kind = "type"
		case 14:
			kind = "const"
		case 7:
			kind = "member"
		}
		found = append(found, candidate{name, kind, where[0], rank})
	}
	sort.SliceStable(found, func(i, j int) bool {
		if found[i].rank != found[j].rank {
			return found[i].rank < found[j].rank
		}
		return found[i].name < found[j].name
	})
	for _, c := range found[:min(len(found), limit)] {
		file, line, column, ok := splitLocation(c.location)
		if !ok {
			continue
		}
		info, err := QuerySymbol(file, line, column)
		if err != nil {
			continue
		}
		matches = append(matches, SymbolMatch{c.name, c.kind, c.location, info.Hover, info.References, info.Diagnostics})
	}
	return matches, len(found), nil
}

func splitLocation(location string) (file string, line, column int, ok bool) {
	i := strings.LastIndex(location, ":")
	if i < 0 {
		return "", 0, 0, false
	}
	columnText, rest := location[i+1:], location[:i]
	j := strings.LastIndex(rest, ":")
	if j < 0 {
		return "", 0, 0, false
	}
	line, lineErr := strconv.Atoi(rest[j+1:])
	column, columnErr := strconv.Atoi(columnText)
	return rest[:j], line, column, lineErr == nil && columnErr == nil
}

func projectManifest(dir string) (string, bool) {
	return project.FindManifest(filepath.Join(dir, "x.ms"))
}

// nameRank scores how well name matches query: 0 exact, 1 prefix, 2 substring,
// 3 ordered subsequence, 4 near miss; -1 means no match. Case and underscores
// are ignored, and a member matches on its own name as well as its qualified one.
func nameRank(name, query string) int { return NameRank(name, query) }

// NameRank is the exported form of the fuzzy name ranking, for other symbol sources.
func NameRank(name, query string) int {
	best := -1
	candidates := []string{name}
	if i := strings.LastIndex(name, "."); i >= 0 {
		candidates = append(candidates, name[i+1:])
	}
	for _, candidate := range candidates {
		if rank := looseRank(fold(candidate), fold(query)); rank >= 0 && (best < 0 || rank < best) {
			best = rank
		}
	}
	return best
}

func fold(s string) string {
	return strings.NewReplacer("_", "", ".", "", " ", "").Replace(strings.ToLower(s))
}

func looseRank(name, query string) int {
	switch {
	case query == "":
		return -1
	case name == query:
		return 0
	case strings.HasPrefix(name, query):
		return 1
	case strings.Contains(name, query):
		return 2
	case len(query) >= 3 && name[0] == query[0] && isSubsequence(query, name):
		return 3
	case len(query) >= 5 && (editDistanceAtMost(name, query, 2) || len(name) > len(query) && editDistanceAtMost(name[:len(query)], query, 2)):
		return 4
	}
	return -1
}

func isSubsequence(needle, haystack string) bool {
	i := 0
	for j := 0; j < len(haystack) && i < len(needle); j++ {
		if haystack[j] == needle[i] {
			i++
		}
	}
	return i == len(needle)
}

// editDistanceAtMost reports whether a and b differ by at most limit single-byte edits.
func editDistanceAtMost(a, b string, limit int) bool {
	if d := len(a) - len(b); d > limit || -d > limit {
		return false
	}
	prev := make([]int, len(b)+1)
	before := make([]int, len(b)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(a); i++ {
		row := make([]int, len(b)+1)
		row[0] = i
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			row[j] = min(prev[j]+1, row[j-1]+1, prev[j-1]+cost)
			if i > 1 && j > 1 && a[i-1] == b[j-2] && a[i-2] == b[j-1] {
				row[j] = min(row[j], before[j-2]+1)
			}
		}
		before, prev = prev, row
	}
	return prev[len(b)] <= limit
}
