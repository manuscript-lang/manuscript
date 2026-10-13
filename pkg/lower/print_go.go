package lower

import (
	"bytes"
	"fmt"
	"go/ast"
	"go/format"
	"go/token"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Go statements have no comment attachment slot. A private label anchors each
// source directive to its statement through printing, including nested closures.
// Only the output boundary replaces these labels with column-one directives.
// Labels use a separate counter so source mapping never changes temporary IDs.
func (g *generator) locatedStatement(pos syntax.Position, statement ast.Stmt) ast.Stmt {
	name := "manuscriptSourceLine" + strconv.Itoa(len(g.sourceLines))
	if g.sourceLines == nil {
		g.sourceLines = map[string]syntax.Position{}
	}
	g.sourceLines[name] = pos
	return &ast.LabeledStmt{Label: ident(name), Stmt: statement}
}

func sourceDirective(pos syntax.Position) string {
	filename := strings.NewReplacer("\n", "_", "\r", "_").Replace(pos.File)
	return fmt.Sprintf("//line %s:%d", filename, pos.Line)
}

// printGo is the sole source serialization boundary of checked Go lowering.
// Formatting owns Go spelling and precedence; the only textual emission here is
// source directives, whose payload is metadata rather than executable syntax.
func (g *generator) printGo(file *ast.File) (string, error) {
	var out bytes.Buffer
	if err := format.Node(&out, token.NewFileSet(), file); err != nil {
		return "", fmt.Errorf("printing generated Go: %w", err)
	}
	lines := strings.Split(out.String(), "\n")
	seen := make(map[string]bool, len(g.sourceLines))
	for i, line := range lines {
		name, label := strings.CutSuffix(strings.TrimSpace(line), ":")
		if pos, ok := g.sourceLines[name]; label && ok {
			if seen[name] {
				return "", fmt.Errorf("duplicate generated source marker %s", name)
			}
			seen[name] = true
			lines[i] = sourceDirective(pos)
		}
	}
	if len(seen) != len(g.sourceLines) {
		return "", fmt.Errorf("lost generated source directives: printed %d of %d", len(seen), len(g.sourceLines))
	}
	return strings.Join(lines, "\n"), nil
}
