package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/tooling/guide"
	"github.com/manuscript-lang/manuscript/pkg/tooling/lsp"
)

// Agents read these commands' output directly, so each prints only what is needed
// to act: ranked matches, one symbol, or one page of reference.

const stdHelp = `Usage: ms search_std [<words>... | <path>] [--limit n] [--json]

Search and read the bundled standard library. Output is short by design.
  ms search_std <words>       Fuzzy-search every function, type, and member
  ms search_std               Modules, each with a few of its names
  ms search_std <module>      One module: a line per declaration, with its import
  ms search_std <module>.<Name>
                              A type or function, with its members as signatures
  ms search_std <module>.<Name>.<member>
                              One member's full signature and doc

A single argument that names a module or declaration shows its page; anything
else searches. Paths accept json, @std/json.ms, json.parse, and
prelude.List.sorted. Search tolerates typos, partial words, synonyms, and any
word order; run it before calling a standard API you have not seen.

Options:
  --limit <n>  Maximum search matches (default 5, at most 15)
  --json       Always search, and emit versioned JSON matches
  -h, --help   Show this help

Examples:
  ms search_std read file lines
  ms search_std prelude.List.sorted
  ms search_std json
`

const searchSymbolHelp = `Usage: ms search_symbol <name> [--limit n] [--json]

Find declarations by name, ignoring case and tolerating partial names, small
typos and missing underscores. Project declarations print where they are defined,
their type, description, and uses; standard-library symbols (such as json.parse)
print their signature and the ms search_std path for details. Exact names rank
first. Run it from the project directory, or any folder under its ms.toml.

Options:
  --limit <n>  Maximum matches (default 5, at most 10)
  --json       Emit versioned JSON
  -h, --help   Show this help

Examples:
  ms search_symbol parse_config
  ms search_symbol Config --limit 3
`

const guideHelp = `Usage: ms guide

Print the language cheat sheet: syntax, types, errors, and a checked example
program. Standard-library lookups are in ms search_std.

Options:
  -h, --help  Show this help

Examples:
  ms guide
`

const (
	defaultSearchLimit = 5
	maxSearchLimit     = 15
)

func runStd(args []string, _ string) int {
	var words []string
	limit, structured := defaultSearchLimit, false
	for i := 1; i < len(args); i++ {
		flag, value, inline := splitValueOption(args[i], "--limit")
		switch flag {
		case "--json":
			structured = true
		case "--limit":
			text, ok := requiredValue(args, &i, value, inline)
			n, err := strconv.Atoi(text)
			if !ok || err != nil || n < 1 {
				return usageError("ms search_std: --limit needs a positive number, e.g. ms search_std read file --limit 3")
			}
			limit = min(n, maxSearchLimit)
		default:
			if strings.HasPrefix(flag, "-") {
				return usageError("unknown option %s for ms search_std; run 'ms help search_std' for its options", flag)
			}
			words = append(words, flag)
		}
	}
	if len(words) == 0 {
		fmt.Print(guide.Index())
		return 0
	}
	if len(words) == 1 && !structured {
		if page, err := guide.Page(words[0]); err == nil {
			fmt.Print(page)
			return 0
		}
	}
	return stdSearch(words, limit, structured)
}

func stdSearch(words []string, limit int, structured bool) int {
	query := strings.Join(words, " ")
	matches := guide.Search(query, limit)
	if structured {
		type match struct {
			Path      string `json:"path"`
			Module    string `json:"module"`
			Kind      string `json:"kind"`
			Signature string `json:"signature"`
			Doc       string `json:"doc,omitempty"`
		}
		out := struct {
			Format  int     `json:"format"`
			Query   string  `json:"query"`
			Matches []match `json:"matches"`
		}{1, query, []match{}}
		for _, m := range matches {
			out.Matches = append(out.Matches, match{m.Path, m.Module, m.Kind, m.Signature, m.Doc})
		}
		return emitJSON(out, 0)
	}
	fmt.Println(guide.FormatMatches(query, matches))
	return 0
}

const (
	defaultSymbolLimit = 5
	maxSymbolLimit     = 10
	maxSymbolUses      = 5
	symbolBudget       = 3500
)

func runSearchSymbol(args []string, _ string) int {
	var names []string
	limit, structured := defaultSymbolLimit, false
	for i := 1; i < len(args); i++ {
		flag, value, inline := splitValueOption(args[i], "--limit")
		switch flag {
		case "--json":
			structured = true
		case "--limit":
			text, ok := requiredValue(args, &i, value, inline)
			n, err := strconv.Atoi(text)
			if !ok || err != nil || n < 1 {
				return usageError("ms search_symbol: --limit needs a positive number, e.g. ms search_symbol Config --limit 3")
			}
			limit = min(n, maxSymbolLimit)
		default:
			if strings.HasPrefix(flag, "-") {
				return usageError("unknown option %s for ms search_symbol; run 'ms help search_symbol' for its options", flag)
			}
			names = append(names, flag)
		}
	}
	if len(names) != 1 {
		return usageError("ms search_symbol takes one name, e.g. ms search_symbol parse_config")
	}
	query := names[0]
	matches, total, err := lsp.SearchSymbols(".", query, limit)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ms search_symbol:", fileError(err))
		return 1
	}
	type match struct {
		Name       string   `json:"name"`
		Kind       string   `json:"kind"`
		Definition string   `json:"definition"`
		Type       string   `json:"type,omitempty"`
		Doc        string   `json:"doc,omitempty"`
		Uses       []string `json:"uses,omitempty"`
		Origin     string   `json:"origin"`
	}
	described := make([]match, 0, len(matches))
	projectCount, projectTotal := len(matches), total
	for _, m := range matches {
		symbolType, docs := splitHover(m.Hover)
		definition := displayPath(m.Definition)
		uses := []string{}
		for _, ref := range m.References {
			if ref != m.Definition {
				uses = append(uses, displayPath(ref))
			}
		}
		described = append(described, match{m.Name, m.Kind, definition, symbolType, docs, uses, "project"})
	}
	// Standard-library symbols follow, matched on names only and leaving room
	// for at least two even when the project fills the limit.
	type ranked struct {
		match guide.Match
		rank  int
	}
	var library []ranked
	for _, m := range guide.Search(query, 50) {
		rank := lsp.NameRank(m.Path, query)
		if own := lsp.NameRank(m.Name, query); own >= 0 && (rank < 0 || own < rank) {
			rank = own
		}
		if rank >= 0 {
			library = append(library, ranked{m, rank})
		}
	}
	sort.SliceStable(library, func(i, j int) bool { return library[i].rank < library[j].rank })
	for _, r := range library[:min(len(library), max(limit-projectCount, 2))] {
		m := r.match
		signature := strings.Join(strings.Fields(m.Signature), " ")
		described = append(described, match{m.Path, m.Kind, "std:" + m.Module, signature, m.Doc, nil, "std"})
	}
	if structured {
		return emitJSON(struct {
			Format  int     `json:"format"`
			Query   string  `json:"query"`
			Total   int     `json:"project_total"`
			Matches []match `json:"matches"`
		}{1, query, projectTotal, described}, 0)
	}
	if len(described) == 0 {
		fmt.Printf("No project or standard-library symbol like %q. Try a shorter name.\n", query)
		return 0
	}
	var out strings.Builder
	for _, m := range described {
		fmt.Fprintf(&out, "%s  %s  %s\n", m.Name, m.Kind, m.Definition)
		if m.Type != "" && m.Type != m.Name+": "+m.Name {
			out.WriteString("  " + clipRunes(m.Type, 200) + "\n")
		}
		if m.Doc != "" {
			out.WriteString("  # " + clipRunes(m.Doc, 160) + "\n")
		}
		if m.Origin == "std" {
			out.WriteString("  details: ms search_std " + m.Name + "\n")
			continue
		}
		shown := m.Uses[:min(len(m.Uses), maxSymbolUses)]
		line := fmt.Sprintf("  used (%d)", len(m.Uses))
		if len(shown) > 0 {
			line += ": " + strings.Join(shown, ", ")
		}
		if len(m.Uses) > len(shown) {
			line += ", ..."
		}
		out.WriteString(line + "\n")
	}
	if projectTotal > projectCount {
		fmt.Fprintf(&out, "+%d more project matches; use a longer name or --limit\n", projectTotal-projectCount)
	}
	text := out.String()
	if len(text) > symbolBudget {
		text = text[:symbolBudget] + "\n[... output cut; use a longer name ...]\n"
	}
	fmt.Print(text)
	return 0
}

func clipRunes(text string, limit int) string {
	if r := []rune(text); len(r) > limit {
		return string(r[:limit-1]) + "…"
	}
	return text
}

// splitHover separates the language server's hover Markdown into a type line and a description.
func splitHover(hover string) (symbolType, docs string) {
	hover = strings.TrimSpace(hover)
	if inner, rest, found := strings.Cut(strings.TrimPrefix(hover, "```manuscript\n"), "\n```"); found {
		hover, docs = inner, firstSentence(rest)
	}
	return strings.ReplaceAll(hover, "\n", " "), docs
}

func firstSentence(text string) string {
	text = strings.Join(strings.Fields(text), " ")
	if i := strings.Index(text, ". "); i >= 0 {
		return text[:i+1]
	}
	return text
}

// displayPath shortens an absolute file:line:column under the working directory.
func displayPath(path string) string {
	if !filepath.IsAbs(path) {
		return path
	}
	if wd, err := os.Getwd(); err == nil {
		if rel, err := filepath.Rel(wd, path); err == nil && !strings.HasPrefix(rel, "..") {
			return rel
		}
	}
	return path
}

func runGuide(args []string, _ string) int {
	if len(args) > 1 {
		return usageError("ms guide takes no arguments; for the standard library use 'ms search_std'")
	}
	fmt.Print(guide.Cheatsheet())
	return 0
}
