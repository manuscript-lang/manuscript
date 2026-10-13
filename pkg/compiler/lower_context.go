package compiler

import (
	"fmt"
	"go/ast"

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
	program          *checker.Program
	booleans         map[*syntax.Expression]bool
	module           string
	serial           int
	expressionDepth  int
	resultKey        ast.Expr // result type key of the function being lowered
	cleanups         []string
	needsCleanup     bool
	loopCleanup      []int
	loopLabels       []*loopLabel
	captures         map[*checker.Binding]string
	sourceLines      map[string]syntax.Position
	hoisted          []string          // package-level Lazy variables for static specializations
	hoistedByKey     map[string]string // call-site identity to Lazy variable
	defaultExpansion map[*syntax.Declaration]bool
	loweringError    error
	sites            []string // package-level MethodSite variables, one per direct method call
	debugLiterals    bool
	literalData      []ast.Decl // immutable scalar input, never source collection storage
}

func (g *generator) temp() string { g.serial++; return fmt.Sprintf("temporary%d", g.serial) }
func (g *generator) key(t *checker.Type) ast.Expr {
	key := textLiteral(checker.TypeKey(t))
	if !hasTypeVariable(t) {
		return key
	}
	return runtimeCall("ResolveType", key, ident("typeArgs"))
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

func (g *generator) typeScope(t *checker.Type) ast.Expr {
	if t.Kind == "variable" {
		return index(ident("typeScopes"), textLiteral(t.ID))
	}
	var args []ast.Expr
	for _, arg := range t.Args {
		args = append(args, g.typeScope(arg))
	}
	return composite(runtimeName("TypeScope"), keyed("Module", textLiteral(g.module)), keyed("Args", sliceLiteral(runtimeName("TypeScope"), args...)))
}
func (g *generator) specialize(symbol *checker.Symbol, args []*checker.Type) ast.Expr {
	var types, scopes []ast.Expr
	for _, arg := range args {
		types = append(types, g.key(arg))
		scopes = append(scopes, g.typeScope(arg))
	}
	result := runtimeCall("Specialize", ident(symbol.ID), sliceLiteral(ident("string"), types...), sliceLiteral(runtimeName("TypeScope"), scopes...))
	result.Ellipsis = 1
	static := true
	identity := g.module + "\x00" + symbol.ID
	for _, arg := range args {
		static = static && !hasTypeVariable(arg)
		identity += "\x00" + checker.TypeKey(arg)
	}
	if !static {
		return result
	}
	return g.lazyValue(identity, result)
}

func (g *generator) lazyValue(identity string, result ast.Expr) ast.Expr {
	// Static type arguments specialize once per program. The Lazy has no
	// initializer, so recursive generics create no Go initialization cycle.
	name, ok := g.hoistedByKey[identity]
	if !ok {
		name = fmt.Sprintf("specialized%d", len(g.hoisted)+1)
		if g.hoistedByKey == nil {
			g.hoistedByKey = map[string]string{}
		}
		g.hoistedByKey[identity] = name
		g.hoisted = append(g.hoisted, name)
	}
	return call(selector(ident(name), "Get"), closure(nil, runtimeName("Value"), returned(result)))
}
func (g *generator) binding(b *checker.Binding) ast.Expr {
	if name := g.captures[b]; name != "" {
		return ident(name)
	}
	return ident(b.ID)
}
