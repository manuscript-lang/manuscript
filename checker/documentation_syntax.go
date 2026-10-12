package checker

import (
	"strings"

	"github.com/manuscript-lang/manuscript/lexer"
	"github.com/manuscript-lang/manuscript/syntax"
)

// documentDeclaration keeps source names and declaration order, omitting function
// bodies. Native declarations use the same declaration-only syntax as stdlib/*.ms.
func documentDeclaration(d *syntax.Declaration, keyword, name string, source ...string) string {
	if d.Kind == syntax.KindFn {
		// Compiler-bound calls such as parallel have no ordinary declaration.
		if d.Result == nil {
			return ""
		}
		return "fn " + name + documentTypeParameters(d.TypeParams) + documentParameters(d.Params, source...) + " -> " + documentType(d.Result) + "\n"
	}
	var b strings.Builder
	b.WriteString(keyword + " " + name + documentTypeParameters(d.TypeParams))
	if len(d.Fields)+len(d.Cases)+len(d.Methods) == 0 {
		b.WriteByte('\n')
		return b.String()
	}
	b.WriteString(":\n")
	for _, field := range d.Fields {
		b.WriteString("    " + field.Name + ": " + documentType(field.Type) + "\n")
	}
	for _, c := range d.Cases {
		b.WriteString("    case " + c.Name)
		if len(c.Fields) > 0 {
			b.WriteString(documentParameters(c.Fields))
		}
		b.WriteByte('\n')
	}
	for _, method := range d.Methods {
		b.WriteString("    " + documentDeclaration(method, "fn", method.Name, source...))
	}
	return b.String()
}

func documentTypeParameters(parameters []syntax.TypeParameter) string {
	if len(parameters) == 0 {
		return ""
	}
	var values []string
	for _, p := range parameters {
		value := p.Name
		if len(p.Bounds) > 0 {
			var bounds []string
			for _, bound := range p.Bounds {
				bounds = append(bounds, documentType(bound))
			}
			value += ": " + strings.Join(bounds, " & ")
		}
		values = append(values, value)
	}
	return "[" + strings.Join(values, ", ") + "]"
}

func documentParameters(parameters []syntax.Parameter, source ...string) string {
	var values []string
	for _, p := range parameters {
		value := p.Name + ": " + documentType(p.Type)
		if p.Default != nil {
			value += " = " + documentDefault(p, source...)
		}
		values = append(values, value)
	}
	return "(" + strings.Join(values, ", ") + ")"
}

func documentType(t *syntax.Type) string {
	if t.Name == "fn" {
		return "fn" + documentParameters(t.Params) + " -> " + documentType(t.Result)
	}
	value := t.Name
	if len(t.Args) > 0 {
		var args []string
		for _, arg := range t.Args {
			args = append(args, documentType(arg))
		}
		value += "[" + strings.Join(args, ", ") + "]"
	}
	return value
}

// Keep default expressions in their original source spelling, including calls,
// strings, and suite closures. Only the containing parameter's delimiters end it.
func documentDefault(parameter syntax.Parameter, source ...string) string {
	if len(source) == 0 {
		return "..."
	}
	tokens, err := lexer.Lex(parameter.Pos.File, source[0])
	if err != nil {
		return "..."
	}
	for i, token := range tokens {
		if token.Pos.Offset < parameter.Pos.Offset || token.Kind != "=" {
			continue
		}
		start := tokens[i+1].Pos.Offset
		depth := 0
		for _, next := range tokens[i+1:] {
			switch next.Kind {
			case "(", "[", "{":
				depth++
			case ")", "]", "}":
				if depth == 0 {
					return strings.TrimSpace(source[0][start:next.Pos.Offset])
				}
				depth--
			case ",":
				if depth == 0 {
					return strings.TrimSpace(source[0][start:next.Pos.Offset])
				}
			}
		}
		break
	}
	return "..."
}
