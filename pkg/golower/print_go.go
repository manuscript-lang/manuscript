package golower

import (
	"bytes"
	"fmt"
	"go/ast"
	"go/format"
	"go/token"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Go statements have no comment attachment slot. A private label anchors each
// source directive to its statement through printing, including nested closures.
// Only the output boundary replaces these labels with column-one directives.
// Labels use a separate counter so source mapping never changes temporary IDs.
func (g *gen) locatedStatement(pos syntax.Position, statement ast.Stmt) ast.Stmt {
	label := ident("manuscriptSourceLine")
	top := g.stack[len(g.stack)-1]
	top.labels = append(top.labels, labelRef{id: label, pos: pos})
	return &ast.LabeledStmt{Label: label, Stmt: statement}
}

func sourceDirective(pos syntax.Position) string {
	filename := strings.NewReplacer("\n", "_", "\r", "_").Replace(pos.File)
	return fmt.Sprintf("//line %s:%d", filename, pos.Line)
}

// printGo is the sole source serialization boundary of checked Go lowering.
// Formatting owns Go spelling and precedence; the only textual emission here is
// source directives, whose payload is metadata rather than executable syntax.
func (g *gen) printGo(file *ast.File) (string, error) {
	var out bytes.Buffer
	if err := format.Node(&out, token.NewFileSet(), file); err != nil {
		return "", fmt.Errorf("printing generated Go: %w", err)
	}
	lines := strings.Split(out.String(), "\n")
	seen := make(map[string]bool, len(g.sourceLines))
	// A directive names the next physical line, so each later line of a
	// statement that Go prints over several lines, and each generated statement
	// that follows the marked one, would read as a later source line. Every
	// line that can hold a call therefore repeats the directive of the located
	// statement it belongs to, inline; the nesting of a line is its indentation.
	governing := map[int]string{}
	deepest := 0
	var printed []string
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		name, label := strings.CutSuffix(trimmed, ":")
		if pos, ok := g.sourceLines[name]; label && ok {
			if seen[name] {
				return "", fmt.Errorf("duplicate generated source marker %s", name)
			}
			seen[name] = true
			// The labeled statement is indented one level deeper than its label.
			depth := indentation(line) + 1
			for ; deepest > depth; deepest-- {
				delete(governing, deepest)
			}
			deepest = depth
			governing[depth] = sourceDirective(pos)
			printed = append(printed, governing[depth])
			continue
		}
		if trimmed != "" && !strings.HasPrefix(trimmed, "//") {
			depth := indentation(line)
			for ; deepest > depth; deepest-- {
				delete(governing, deepest)
			}
			for d := depth; d > 0 && strings.Contains(trimmed, "("); d-- {
				if directive, ok := governing[d]; ok {
					if len(printed) == 0 || printed[len(printed)-1] != directive {
						line = strings.Repeat("\t", depth) + inlineDirective(directive) + trimmed
					}
					break
				}
			}
		}
		printed = append(printed, line)
	}
	if len(seen) != len(g.sourceLines) {
		return "", fmt.Errorf("lost generated source directives: printed %d of %d", len(seen), len(g.sourceLines))
	}
	return strings.Join(printed, "\n"), nil
}

func indentation(line string) int {
	return len(line) - len(strings.TrimLeft(line, "\t"))
}

// inlineDirective is a //line directive in its /*line*/ form, which names the
// character after it rather than the next line.
func inlineDirective(directive string) string {
	return "/*" + strings.TrimPrefix(directive, "//") + "*/"
}
