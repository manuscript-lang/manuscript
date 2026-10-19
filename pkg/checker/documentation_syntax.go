package checker

import (
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// documentDeclaration keeps source names and declaration order, omitting function
// bodies. Native declarations use the same declaration-only syntax as stdlib/*.ms.
func documentDeclaration(d *syntax.Declaration, keyword, name string, source ...string) string {
	if d.Kind == syntax.KindFn {
		prefix := "fn "
		if d.Mutating {
			prefix = "var fn "
		}
		return prefix + name + documentTypeParameters(d.TypeParams) + documentParameters(d.Params, source...) + " " + documentType(d.Result) + ":\n"
	}
	var b strings.Builder
	b.WriteString(keyword + " " + name + documentTypeParameters(d.TypeParams))
	b.WriteString(":\n")
	for _, field := range d.Fields {
		b.WriteString("    " + field.Name + ": " + documentType(field.Type))
		if field.Default != nil {
			b.WriteString(" = " + documentDefault(field, source...))
		}
		b.WriteByte('\n')
	}
	for _, c := range d.Cases {
		b.WriteString("    case " + c.Name)
		if len(c.Fields) > 0 {
			b.WriteString(documentParameters(c.Fields))
		}
		b.WriteByte('\n')
	}
	if keyword == "type" && len(d.Methods) > 0 {
		// A type's own methods are written in an `impl Type:` block.
		b.WriteString("\nimpl " + name + documentTypeArguments(d.TypeParams) + ":\n")
	}
	for _, method := range d.Methods {
		header := documentDeclaration(method, "fn", method.Name, source...)
		if keyword == "interface" {
			header = strings.TrimSuffix(header, ":\n") + "\n"
		}
		b.WriteString("    " + header)
	}
	return b.String()
}

// documentTypeArguments writes the type's own parameters as the arguments of
// its impl receiver, without bounds or defaults.
func documentTypeArguments(parameters []syntax.TypeParameter) string {
	if len(parameters) == 0 {
		return ""
	}
	var names []string
	for _, p := range parameters {
		names = append(names, p.Name)
	}
	return "[" + strings.Join(names, ", ") + "]"
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
		if p.Default != nil {
			value += " = " + documentType(p.Default)
		}
		values = append(values, value)
	}
	return "[" + strings.Join(values, ", ") + "]"
}

func documentParameters(parameters []syntax.Parameter, source ...string) string {
	var values []string
	for _, p := range parameters {
		value := p.Name + ": " + documentType(p.Type)
		if p.Var {
			value = "var " + value
		}
		if p.Default != nil {
			value += " = " + documentDefault(p, source...)
		}
		values = append(values, value)
	}
	return "(" + strings.Join(values, ", ") + ")"
}

func documentType(t *syntax.Type) string {
	if t.Name == "fn" {
		return "fn" + documentParameters(t.Params) + " " + documentType(t.Result)
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
	if parameter.Default != nil && parameter.Default.Kind == syntax.KindName {
		return parameter.Default.Text
	}
	if len(source) == 0 {
		if parameter.Default != nil && parameter.Default.Kind == syntax.KindName {
			return parameter.Default.Text
		}
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
			case ",", lexer.Newline:
				if depth == 0 {
					return strings.TrimSpace(source[0][start:next.Pos.Offset])
				}
			}
		}
		break
	}
	return "..."
}
