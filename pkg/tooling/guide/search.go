// Package guide answers agent questions about the language: fuzzy standard-library
// search, the cheat sheet, and the standard-library index and module docs.
package guide

import (
	"fmt"
	"sort"
	"strings"
	"sync"
	"unicode"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

// entry is one searchable standard-library declaration or member.
type entry struct {
	module, qualified, name, kind, signature, doc string
	words, docWords                               []string
	moduleWords                                   []string
}

var (
	indexOnce sync.Once
	index     []entry
)

func standardIndex() []entry {
	indexOnce.Do(func() {
		for _, module := range checker.StandardLibrary() {
			short := strings.TrimSuffix(strings.TrimPrefix(module.Path, "@std/"), ".ms")
			for _, d := range module.Declarations {
				signature := strings.TrimSpace(d.Declaration)
				if signature == "" {
					signature = d.Type
				}
				index = append(index, newEntry(module.Path, short, d.Name, d.Kind, firstBlock(signature), d.Doc))
				for _, m := range d.Members {
					index = append(index, newEntry(module.Path, short, d.Name+"."+m.Name, m.Kind, m.Signature, m.Doc))
				}
			}
		}
	})
	return index
}

// firstBlock keeps the leading paragraph and at most 3 lines, so a native type
// with dozens of members cannot flood a result.
func firstBlock(s string) string {
	if before, _, found := strings.Cut(s, "\n\n"); found {
		s = before
	}
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(lines) > 3 {
		lines = append(lines[:3], "    ...")
	}
	return strings.Join(lines, "\n")
}

func newEntry(path, short, name, kind, signature, doc string) entry {
	return entry{
		module: path, qualified: short + "." + name, name: name, kind: kind, signature: signature, doc: doc,
		words: splitWords(name), docWords: splitWords(doc), moduleWords: splitWords(short),
	}
}

// splitWords lowercases text and splits on punctuation, underscores, and camelCase.
func splitWords(s string) []string {
	var words []string
	var current []rune
	flush := func() {
		if len(current) > 0 {
			words = append(words, strings.ToLower(string(current)))
			current = current[:0]
		}
	}
	runes := []rune(s)
	for i, r := range runes {
		switch {
		case unicode.IsLetter(r) || unicode.IsDigit(r):
			if unicode.IsUpper(r) && i > 0 && unicode.IsLower(runes[i-1]) {
				flush()
			}
			current = append(current, r)
		default:
			flush()
		}
	}
	flush()
	return words
}

var stopWords = map[string]bool{"a": true, "an": true, "the": true, "of": true, "to": true, "in": true, "for": true, "with": true, "by": true, "from": true, "and": true, "or": true, "how": true, "do": true, "i": true}

// significantWords drops filler so "sort by key" matches on "sort" and "key".
func significantWords(query string) []string {
	all := splitWords(query)
	var kept []string
	for _, w := range all {
		if !stopWords[w] {
			kept = append(kept, w)
		}
	}
	if len(kept) == 0 {
		return all
	}
	return kept
}

// Match is one ranked lookup result.
type Match struct {
	Module, Name, Kind, Signature, Doc string
	Path                               string // the `ms search_symbol` path, such as json.parse
	Score                              int
}

// Search ranks standard declarations and members against a loose query.
// Every query word must match somewhere, tolerating prefixes, subsequences,
// and small typos, so "read file", "jsn parse", and "fs.read" all find APIs.
func Search(query string, limit int) []Match {
	tokens := significantWords(query)
	if len(tokens) == 0 {
		return nil
	}
	if limit <= 0 {
		limit = 5
	}
	// Prefer entries matching every word; when none do, fall back to the
	// entries matching the most words so "read stdin lines" still finds help.
	var matches []Match
	best := 0
	for _, e := range standardIndex() {
		total, matched, strong := 0, 0, 0
		for _, token := range tokens {
			if score := scoreToken(token, e); score > 0 {
				total += score
				matched++
				if score >= strongScore {
					strong++
				}
			}
		}
		// A partial match must hinge on a name or module word, never on prose alone.
		if matched == 0 || matched < best || matched < len(tokens) && strong == 0 {
			continue
		}
		if matched > best {
			best, matches = matched, nil
		}
		// Shorter names read as more central, so break ties toward them.
		total = total*10 + nameCoverage(tokens, e) - min(len(e.name), 9)
		matches = append(matches, Match{e.module, e.name, e.kind, e.signature, firstLine(e.doc, 120), stdPath(e.module, e.name), total})
	}
	sort.SliceStable(matches, func(i, j int) bool {
		if matches[i].Score != matches[j].Score {
			return matches[i].Score > matches[j].Score
		}
		// The prelude spelling needs no import, so it wins a tie with a module re-export.
		if (matches[i].Module == "prelude") != (matches[j].Module == "prelude") {
			return matches[i].Module == "prelude"
		}
		return matches[i].Module+"."+matches[i].Name < matches[j].Module+"."+matches[j].Name
	})
	matches = dropDuplicates(matches)
	if len(matches) > limit {
		matches = matches[:limit]
	}
	return matches
}

// nameCoverage rewards names whose own words the query spells out and
// penalizes names with extra words the query never mentioned.
func nameCoverage(tokens []string, e entry) int {
	covered := 0
	for _, word := range e.words {
		for _, token := range tokens {
			if token == word {
				covered++
				break
			}
		}
	}
	return 15*covered - 10*(len(e.words)-covered)
}

// dropDuplicates removes repeats of one declaration that several modules expose.
func dropDuplicates(matches []Match) []Match {
	seen := map[string]bool{}
	out := matches[:0]
	for _, m := range matches {
		key := m.Name + "\x00" + m.Signature
		if !seen[key] {
			seen[key] = true
			out = append(out, m)
		}
	}
	return out
}

// strongScore separates name and module matches from matches in documentation prose.
const strongScore = 25

// synonyms maps common phrasing to the library's own words.
var synonyms = map[string][]string{
	"sort": {"sorted"}, "order": {"sorted"}, "uppercase": {"upper"}, "lowercase": {"lower"},
	"size": {"length", "count"}, "len": {"length"}, "delete": {"remove"}, "push": {"append"},
	"print": {"write", "stdout"}, "stdin": {"read_line"}, "concat": {"join", "concat"},
	"split": {"split", "lines"}, "env": {"environment"}, "random": {"random"},
}

func scoreToken(token string, e entry) int {
	best := scoreWords(token, e)
	for _, alias := range synonyms[token] {
		best = max(best, scoreWords(alias, e)*9/10)
	}
	return best
}

func scoreWords(token string, e entry) int {
	best := 0
	for _, word := range e.words {
		best = max(best, scoreWord(token, word, 100))
	}
	for _, word := range e.moduleWords {
		best = max(best, scoreWord(token, word, 60))
	}
	for _, word := range e.docWords {
		if len(token) >= 4 {
			best = max(best, scoreWord(token, word, 12))
		}
	}
	return best
}

// scoreWord scores one query word against a candidate word; weight scales the field.
func scoreWord(token, word string, weight int) int {
	switch {
	case token == word:
		return weight
	case strings.HasPrefix(word, token) && len(token) >= 2:
		return weight * 7 / 10
	case len(token) >= 3 && strings.Contains(word, token):
		return weight / 2
	case weight < 50:
		return 0 // prose matches must be exact words or prefixes
	case len(token) >= 3 && token[0] == word[0] && isSubsequence(token, word):
		return weight * 3 / 10
	case len(token) >= 5 && editDistance(token, word) <= allowedTypos(len(token)):
		return weight * 4 / 10
	}
	return 0
}

func allowedTypos(length int) int {
	if length >= 7 {
		return 2
	}
	return 1
}

func isSubsequence(small, large string) bool {
	i := 0
	for j := 0; j < len(large) && i < len(small); j++ {
		if small[i] == large[j] {
			i++
		}
	}
	return i == len(small)
}

// editDistance is the Damerau-Levenshtein distance with adjacent transpositions.
func editDistance(a, b string) int {
	if abs(len(a)-len(b)) > 2 {
		return 3
	}
	ra, rb := []rune(a), []rune(b)
	d := make([][]int, len(ra)+1)
	for i := range d {
		d[i] = make([]int, len(rb)+1)
		d[i][0] = i
	}
	for j := range d[0] {
		d[0][j] = j
	}
	for i := 1; i <= len(ra); i++ {
		for j := 1; j <= len(rb); j++ {
			cost := 1
			if ra[i-1] == rb[j-1] {
				cost = 0
			}
			d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1]+cost)
			if i > 1 && j > 1 && ra[i-1] == rb[j-2] && ra[i-2] == rb[j-1] {
				d[i][j] = min(d[i][j], d[i-2][j-2]+1)
			}
		}
	}
	return d[len(ra)][len(rb)]
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

// FormatMatches renders matches as an `ms search_symbol` path, a signature, and a one-line doc.
func FormatMatches(query string, matches []Match) string {
	if len(matches) == 0 {
		return fmt.Sprintf("No standard-library match for %q. Try fewer or broader words, or list modules with `ms search_symbol`.", query)
	}
	var b strings.Builder
	for _, m := range matches {
		fmt.Fprintf(&b, "%s  (%s)\n%s\n", m.Path, m.Module, indent(strings.TrimRight(m.Signature, "\n"), "  "))
		if m.Doc != "" {
			fmt.Fprintf(&b, "  # %s\n", m.Doc)
		}
	}
	fmt.Fprintf(&b, "Details: ms search_symbol <path>, e.g. ms search_symbol %s", matches[0].Path)
	return clipText(b.String(), searchBudget)
}

// searchBudget bounds search output to roughly 800 tokens.
const searchBudget = 3000

func indent(text, prefix string) string {
	return prefix + strings.ReplaceAll(text, "\n", "\n"+prefix)
}

// clipText keeps the head and tail of long text, where errors and summaries usually sit.
func clipText(s string, limit int) string {
	if len(s) <= limit {
		return s
	}
	head, tail := limit*2/3, limit/3
	return s[:head] + fmt.Sprintf("\n[... %d bytes omitted ...]\n", len(s)-head-tail) + s[len(s)-tail:]
}
