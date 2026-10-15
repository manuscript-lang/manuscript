package cli

import (
	"fmt"
	"os"
	"path/filepath"
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

const symbolHelp = `Usage: ms symbol <file.ms>:<line>:<column> [--json]

Report the type, definition, and references of the symbol at a 1-based line and
column (a column counts characters). The file is analyzed with its project, the
same way the language server does. A file with errors can give partial answers.

Options:
  --json      Emit versioned JSON
  -h, --help  Show this help

Examples:
  ms symbol src/main.ms:5:18
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

// parseLocation splits file:line:column from the right, so a path may contain colons.
func parseLocation(text string) (file string, line, column int, ok bool) {
	rest, columnText, found := cutLast(text, ":")
	if !found {
		return "", 0, 0, false
	}
	file, lineText, found := cutLast(rest, ":")
	if !found || file == "" {
		return "", 0, 0, false
	}
	line, lineErr := strconv.Atoi(lineText)
	column, columnErr := strconv.Atoi(columnText)
	return file, line, column, lineErr == nil && columnErr == nil && line > 0 && column > 0
}

func cutLast(s, sep string) (before, after string, found bool) {
	i := strings.LastIndex(s, sep)
	if i < 0 {
		return s, "", false
	}
	return s[:i], s[i+len(sep):], true
}

func runSymbol(args []string, _ string) int {
	var location string
	structured := false
	for _, arg := range args[1:] {
		switch {
		case arg == "--json":
			structured = true
		case strings.HasPrefix(arg, "-"):
			return usageError("unknown option %s for ms symbol; run 'ms help symbol' for its options", arg)
		case location != "":
			return usageError("ms symbol takes one <file.ms>:<line>:<column>, got a second argument %s", arg)
		default:
			location = arg
		}
	}
	file, line, column, ok := parseLocation(location)
	if !ok {
		return usageError("ms symbol: pass <file.ms>:<line>:<column> with a 1-based line and column, e.g. ms symbol src/main.ms:5:18")
	}
	info, err := lsp.QuerySymbol(file, line, column)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ms symbol:", fileError(err))
		return 1
	}
	symbolType, docs := splitHover(info.Hover)
	if structured {
		return emitJSON(struct {
			Format     int      `json:"format"`
			Type       string   `json:"type,omitempty"`
			Doc        string   `json:"doc,omitempty"`
			Definition string   `json:"definition,omitempty"`
			References []string `json:"references"`
			Errors     int      `json:"errors"`
		}{1, symbolType, docs, info.Definition, append([]string{}, info.References...), info.Diagnostics}, 0)
	}
	if symbolType == "" {
		fmt.Println("no symbol at this position")
		return 0
	}
	fmt.Println("type: " + symbolType)
	if docs != "" {
		fmt.Println(docs)
	}
	if info.Definition != "" {
		fmt.Println("defined: " + displayPath(info.Definition))
	}
	if n := len(info.References); n > 0 {
		shown := make([]string, 0, min(n, 15))
		for _, ref := range info.References[:min(n, 15)] {
			shown = append(shown, displayPath(ref))
		}
		line := fmt.Sprintf("references (%d): %s", n, strings.Join(shown, ", "))
		if n > len(shown) {
			line += ", ..."
		}
		fmt.Println(line)
	}
	if info.Diagnostics > 0 {
		fmt.Printf("note: file has %d errors, results may be partial\n", info.Diagnostics)
	}
	return 0
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
