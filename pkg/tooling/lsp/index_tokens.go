package lsp

import (
	"strings"
	"sync"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

type indexTokenSource struct {
	source string
	once   sync.Once
	tokens []lexer.Token
	err    error
}

// This finite inventory owns only pinned source text and lexical tokens, never
// checked declarations or workspace inputs. Both the inventory and each token
// slice are initialized on demand and read-only after publication.
var pinnedIndexTokens = sync.OnceValue(func() map[string]*indexTokenSource {
	sources := map[string]*indexTokenSource{}
	for _, m := range checker.StandardModules() {
		sources[m.File] = &indexTokenSource{source: m.Source}
	}
	return sources
})

func indexTokens(m *syntax.Module) ([]lexer.Token, error) {
	if strings.HasPrefix(m.File, "@std/") {
		if pinned := pinnedIndexTokens()[m.File]; pinned != nil && pinned.source == m.Source {
			pinned.once.Do(func() { pinned.tokens, pinned.err = lexer.Lex(m.File, pinned.source) })
			return pinned.tokens, pinned.err
		}
	}
	return lexer.Lex(m.File, m.Source)
}
