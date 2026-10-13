package compiler

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

type loopLabel struct {
	name    string
	used    bool
	depth   int
	escaped bool
}

// generator carries checked identities and lexical state through Go lowering.
// Function lowering saves and restores cleanup/loop state for nested closures.
type generator struct {
	program         *checker.Program
	booleans        map[*syntax.Expression]bool
	module          string
	serial          int
	expressionDepth int
	cleanups        []string
	loopCleanup     []int
	loopLabels      []*loopLabel
	captures        map[*checker.Binding]string
}

func quote(s string) string { return strconv.Quote(s) }
func stringsGo(values []string) string {
	var entries []string
	for _, v := range values {
		entries = append(entries, quote(v))
	}
	return "[]string{" + strings.Join(entries, ",") + "}"
}
func (g *generator) temp() string { g.serial++; return fmt.Sprintf("temporary%d", g.serial) }
func (g *generator) key(t *checker.Type) string {
	key := quote(checker.TypeKey(t))
	if !hasTypeVariable(t) {
		return key
	}
	return "rt.ResolveType(" + key + ", typeArgs)"
}

// Only the structure encoded by TypeKey needs substitution. Definitions and
// bounds can be recursive and do not participate in the runtime key.
func hasTypeVariable(t *checker.Type) bool {
	if t == nil {
		return false
	}
	if t.Kind == "variable" {
		return true
	}
	for _, arg := range t.Args {
		if hasTypeVariable(arg) {
			return true
		}
	}
	if t.Kind == "function" {
		for _, param := range t.Params {
			if hasTypeVariable(param.Type) {
				return true
			}
		}
		return hasTypeVariable(t.Result)
	}
	return false
}

func (g *generator) typeScope(t *checker.Type) string {
	if t.Kind == "variable" {
		return "typeScopes[" + quote(t.ID) + "]"
	}
	var args []string
	for _, arg := range t.Args {
		args = append(args, g.typeScope(arg))
	}
	return "rt.TypeScope{Module:" + quote(g.module) + ",Args:[]rt.TypeScope{" + strings.Join(args, ",") + "}}"
}

func (g *generator) specialize(symbol *checker.Symbol, args []*checker.Type) string {
	var types, scopes []string
	for _, arg := range args {
		types = append(types, g.key(arg))
		scopes = append(scopes, g.typeScope(arg))
	}
	return "rt.Specialize(" + symbol.ID + ",[]string{" + strings.Join(types, ",") + "},[]rt.TypeScope{" + strings.Join(scopes, ",") + "}...)"
}
func (g *generator) binding(b *checker.Binding) string {
	if name := g.captures[b]; name != "" {
		return name
	}
	return b.ID
}
