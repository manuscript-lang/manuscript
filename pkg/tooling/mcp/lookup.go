package mcp

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

func firstBlock(s string) string {
	if before, _, found := strings.Cut(s, "\n\n"); found {
		return before
	}
	return s
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

// Match is one ranked lookup result.
type Match struct {
	Module, Name, Kind, Signature, Doc string
	Score                              int
}

// Lookup ranks standard declarations and members against a loose query.
// Every query word must match somewhere, tolerating prefixes, subsequences,
// and small typos, so "read file", "jsn parse", and "fs.read" all find APIs.
func Lookup(query string, limit int) []Match {
	tokens := splitWords(query)
	if len(tokens) == 0 {
		return nil
	}
	if limit <= 0 {
		limit = 8
	}
	var matches []Match
	for _, e := range standardIndex() {
		total := 0
		for _, token := range tokens {
			score := scoreToken(token, e)
			if score == 0 {
				total = 0
				break
			}
			total += score
		}
		if total > 0 {
			// Shorter names read as more central, so break ties toward them.
			total = total*10 + nameCoverage(tokens, e) - min(len(e.name), 9)
			matches = append(matches, Match{e.module, e.name, e.kind, e.signature, firstSentence(e.doc), total})
		}
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

func scoreToken(token string, e entry) int {
	best := 0
	for _, word := range e.words {
		best = max(best, scoreWord(token, word, 100))
	}
	for _, word := range e.moduleWords {
		best = max(best, scoreWord(token, word, 60))
	}
	for _, word := range e.docWords {
		if len(token) >= 3 {
			best = max(best, scoreWord(token, word, 20))
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
	case len(token) >= 3 && isSubsequence(token, word):
		return weight * 3 / 10
	case len(token) >= 4 && editDistance(token, word) <= allowedTypos(len(token)):
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

func firstSentence(doc string) string {
	doc = strings.Join(strings.Fields(doc), " ")
	if i := strings.Index(doc, ". "); i >= 0 {
		return doc[:i+1]
	}
	return doc
}

func formatMatches(query string, matches []Match) string {
	if len(matches) == 0 {
		return fmt.Sprintf("No standard-library match for %q. Try fewer or broader words, or read the manuscript://stdlib resource for the module list.", query)
	}
	var b strings.Builder
	for i, m := range matches {
		if i > 0 {
			b.WriteString("\n")
		}
		fmt.Fprintf(&b, "%s · %s `%s`\n", m.Module, m.Kind, m.Name)
		if m.Signature != "" {
			fmt.Fprintf(&b, "```manuscript\n%s\n```\n", strings.TrimRight(m.Signature, "\n"))
		}
		if m.Doc != "" {
			fmt.Fprintf(&b, "%s\n", m.Doc)
		}
	}
	return b.String()
}
