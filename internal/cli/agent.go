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

const searchSymbolHelp = `Usage: ms search_symbol [<name or words>... | <path>] [--limit n] [--json]

Find a symbol, in the project or the standard library. Matching ignores case
and tolerates partial names, small typos, missing underscores, and plain words
(read file lines). Exact names rank first.
  A project match prints its definition, type, description, and uses.
  A standard-library match prints its signature and a path for details.
  A lone module or declaration path shows its page, in bounded size:
    ms search_symbol                 Standard modules, each with a few names
    ms search_symbol json            One module: a line per declaration
    ms search_symbol prelude.List    A declaration with its members
    ms search_symbol prelude.List.sorted
                                     One member's signature and doc
Run it from the project directory, or any folder under its ms.toml.

Options:
  --limit <n>  Maximum matches (default 5, at most 10)
  --json       Always search, and emit versioned JSON
  -h, --help   Show this help

Examples:
  ms search_symbol parse_config
  ms search_symbol read file lines
  ms search_symbol json.parse
`

const guideHelp = `Usage: ms guide

Print the language cheat sheet: syntax, types, errors, and a checked example
program. Look symbols up with ms search_symbol.

Options:
  -h, --help  Show this help

Examples:
  ms guide
`

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
	if len(names) == 0 {
		fmt.Print(guide.Index())
		return 0
	}
	query := strings.Join(names, " ")
	matches, total, err := lsp.SearchSymbols(".", strings.Join(names, ""), limit)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ms search_symbol:", fileError(err))
		return 1
	}
	if len(names) == 1 && !structured && !hasExactName(matches, query) {
		if page, err := guide.Page(query); err == nil {
			fmt.Print(page)
			return 0
		}
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
	concept := guide.Search(query, 50)
	for _, m := range concept {
		rank := lsp.NameRank(m.Path, query)
		if own := lsp.NameRank(m.Name, query); own >= 0 && (rank < 0 || own < rank) {
			rank = own
		}
		if rank >= 0 {
			library = append(library, ranked{m, rank})
		}
	}
	if projectCount == 0 && (len(names) > 1 || len(library) == 0) {
		// Words rather than a name: top up with the meaning-based ranking, as for read file lines.
		seen := map[string]bool{}
		for _, r := range library {
			seen[r.match.Path] = true
		}
		for _, m := range concept {
			if !seen[m.Path] {
				library = append(library, ranked{m, 5})
			}
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
			out.WriteString("  details: ms search_symbol " + m.Name + "\n")
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
		return usageError("ms guide takes no arguments; use 'ms search_symbol' to look symbols up")
	}
	fmt.Print(guide.Cheatsheet())
	return 0
}

// hasExactName reports whether a project match is named exactly like the query, which then
// wins over a standard module or declaration of the same name.
func hasExactName(matches []lsp.SymbolMatch, query string) bool {
	for _, m := range matches {
		if lsp.NameRank(m.Name, query) == 0 {
			return true
		}
	}
	return false
}
