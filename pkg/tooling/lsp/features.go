package lsp

import (
	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"net/url"
	"path/filepath"
	"sort"
	"strings"
)

func signatureHelp(d document, docs map[string]document, p position) (any, error) {
	c, err := contextAt(d, p)
	if err != nil {
		return nil, err
	}
	if c.callOpen < 0 || c.literal || c.comment {
		return nil, nil
	}
	a := queryEditor(d, docs, c)
	call, t := queryCall(a)
	if call == nil || t == nil {
		return nil, nil
	}
	name := strings.TrimSpace(d.Text[c.calleeStart:c.calleeEnd])
	parameters := []any{}
	labels := []string{}
	for _, param := range t.Params {
		label := param.Name + ": " + param.Type.String()
		if t.Defaults[param.Name] {
			label += " = ..."
		}
		labels = append(labels, label)
		parameters = append(parameters, map[string]any{"label": label})
	}
	active := 0
	used := map[string]bool{}
	current := ""
	for _, arg := range call.Args {
		if arg.Name == a.marker {
			continue
		}
		if containsMarker(arg.Value, a.marker) {
			current = arg.Name
		} else {
			used[arg.Name] = true
		}
	}
	if current != "" {
		for index, param := range t.Params {
			if param.Name == current {
				active = index
				break
			}
		}
	} else {
		for index, param := range t.Params {
			if !used[param.Name] && strings.HasPrefix(param.Name, c.prefix) {
				active = index
				break
			}
		}
	}
	label := name + "(" + strings.Join(labels, ", ") + ") -> " + t.Result.String()
	var doc any
	if info := a.result.Program.Expressions[call.Left]; info != nil {
		if info.Symbol != nil {
			doc = description(a.result, info.Symbol.Decl)
		}
		if info.Method != nil {
			doc = description(a.result, info.Method.Decl)
		}
	}
	return map[string]any{"signatures": []any{map[string]any{"label": label, "parameters": parameters, "documentation": doc}}, "activeSignature": 0, "activeParameter": active}, nil
}
func fileURI(p string) string {
	p = filepath.ToSlash(p)
	if filepath.VolumeName(p) != "" && !strings.HasPrefix(p, "/") {
		p = "/" + p
	}
	return (&url.URL{Scheme: "file", Path: p}).String()
}
func inlayHints(result compiler.Result, d document, requested span) []any {
	hints := []any{}
	m := module(result, d)
	if m == nil {
		return hints
	}
	visitor := syntax.Visitor{Statement: func(s *syntax.Statement) {
		if s.Kind == syntax.KindBind && s.Type == nil && s.Pattern != nil && s.Pattern.Kind == syntax.KindName {
			if binding := result.Program.Bindings[s.Pattern]; binding != nil && binding.Type != nil && binding.Type.ID != "<invalid>" {
				p := Position(d.Text, s.Pattern.Pos.Offset+len(s.Pattern.Name))
				if (p.Line > requested.Start.Line || p.Line == requested.Start.Line && p.Character >= requested.Start.Character) && (p.Line < requested.End.Line || p.Line == requested.End.Line && p.Character <= requested.End.Character) {
					hints = append(hints, map[string]any{"position": p, "label": ": " + binding.Type.String(), "kind": 1, "paddingLeft": false, "paddingRight": false})
				}
			}
		}
	}}
	for _, decl := range m.Declarations {
		visitor.Walk(decl)
	}

	sort.Slice(hints, func(i, j int) bool {
		a, b := hints[i].(map[string]any)["position"].(position), hints[j].(map[string]any)["position"].(position)
		if a.Line != b.Line {
			return a.Line < b.Line
		}
		return a.Character < b.Character
	})
	return hints
}

// Folding is indentation-based, so it remains available before parsing succeeds.
func foldingRanges(d document) []any {
	result := []any{}
	lines := strings.Split(d.Text, "\n")
	for start, line := range lines {
		text := strings.TrimSpace(line)
		if !strings.HasSuffix(strings.SplitN(text, "#", 2)[0], ":") {
			continue
		}
		indent := len(line) - len(strings.TrimLeft(line, " "))
		end := start
		for next := start + 1; next < len(lines); next++ {
			content := strings.TrimSpace(lines[next])
			if content == "" {
				continue
			}
			depth := len(lines[next]) - len(strings.TrimLeft(lines[next], " "))
			if depth <= indent {
				break
			}
			end = next
		}
		if end > start {
			result = append(result, map[string]any{"startLine": start, "endLine": end, "kind": "region"})
		}
	}
	return result
}
func typeDefinition(result compiler.Result, d document, p position) any {
	_, info := at(result, d, p, sourceIndex(result))
	if info == nil || info.Type == nil || info.Type.Def == nil || info.Type.Def.Symbol == nil {
		return nil
	}
	return symbolLocation(result, info.Type.Def.Symbol)
}
func symbolLocation(result compiler.Result, s *checker.Symbol) any {
	if s == nil || s.Decl == nil {
		return nil
	}
	for _, m := range sourceModules(result) {
		if m.File == s.Decl.Pos.File {
			pos := Position(m.Source, s.Decl.Pos.Offset)
			return []any{map[string]any{"uri": sourceURI(result, m.File), "range": span{pos, pos}}}
		}
	}
	return nil
}
