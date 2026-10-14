package checker

import (
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func (c *checker) redundantPreludeImport(module *syntax.Module, item *syntax.Import) {
	end := item.NamePos
	end.Column += len(item.Name)
	end.Offset += len(item.Name)
	c.Diagnostics = append(c.Diagnostics, syntax.Diagnostic{
		Position: item.NamePos, End: &end, Phase: "resolution",
		Message: "redundant prelude import " + item.Name + "; remove " + item.Name + " from this import and use its prelude declaration directly",
		Fix:     preludeImportFix(module, item),
	})
}

// Remove one binding, preserving comments, neighboring bindings and original
// line endings. This stays an exact source edit rather than formatting the file.
func preludeImportFix(module *syntax.Module, item *syntax.Import) *syntax.DiagnosticFix {
	tokens, err := lexer.Lex(module.File, module.Source)
	if err != nil {
		// A recovering editor snapshot can retain this valid import alongside
		// unrelated lexer errors. Lex only its complete declaration in that case.
		tokens = preludeImportTokens(module, item)
		if len(tokens) == 0 {
			return nil
		}
	}
	at := -1
	for i, token := range tokens {
		if token.Pos.Offset == item.NamePos.Offset {
			at = i
			break
		}
	}
	if at < 0 {
		return nil
	}
	count := 0
	for _, other := range module.Imports {
		if other.Pos.Offset == item.Pos.Offset {
			count++
		}
	}
	name := tokens[at]
	if count > 1 {
		if at+1 < len(tokens) && tokens[at+1].Kind == "," {
			comma := tokens[at+1]
			end := comma.End
			if at+2 < len(tokens) && tokens[at+2].Pos.Line == comma.End.Line {
				end = tokens[at+2].Pos
			}
			trivia := module.Source[name.End.Offset:comma.Pos.Offset]
			if !strings.Contains(trivia, "#") {
				trivia = ""
			}
			return &syntax.DiagnosticFix{Position: name.Pos, End: end, Replacement: trivia}
		}
		if at > 0 && tokens[at-1].Kind == "," {
			comma := tokens[at-1]
			end := name.End
			if at+1 < len(tokens) && tokens[at+1].Pos.Line == name.End.Line {
				end = tokens[at+1].Pos
			}
			trivia := module.Source[comma.End.Offset:name.Pos.Offset]
			if !strings.Contains(trivia, "#") {
				trivia = ""
			}
			return &syntax.DiagnosticFix{Position: comma.Pos, End: end, Replacement: trivia}
		}
		return nil
	}
	// Delete a singleton import, retaining any comments inside a multiline
	// group and any trailing comment after the path string.
	end := name.End
	var comments strings.Builder
	previous := item.Pos.Offset
	for _, token := range tokens {
		if token.Pos.Offset < item.Pos.Offset {
			continue
		}
		trivia := module.Source[previous:token.Pos.Offset]
		if strings.Contains(trivia, "#") {
			comments.WriteString(trivia)
		}
		previous = token.End.Offset
		if token.Kind == lexer.String {
			end = token.End
			break
		}
	}
	fix := &syntax.DiagnosticFix{Position: item.Pos, End: end, Replacement: comments.String()}
	if comments.Len() == 0 {
		tail := module.Source[end.Offset:]
		n := strings.IndexByte(tail, '\n')
		if n >= 0 && strings.TrimSpace(tail[:n]) == "" {
			fix.End.Offset += n + 1
			fix.End.Line++
			fix.End.Column = 1
		} else if strings.TrimSpace(tail) == "" {
			fix.End.Offset = len(module.Source)
			fix.End.Column += len(tail)
		}
	}
	return fix
}

func preludeImportTokens(module *syntax.Module, item *syntax.Import) []lexer.Token {
	start := item.Pos.Offset
	for end := start; end < len(module.Source); {
		lineEnd := strings.IndexByte(module.Source[end:], '\n')
		if lineEnd < 0 {
			end = len(module.Source)
		} else {
			end += lineEnd + 1
		}
		tokens, err := lexer.Lex(module.File, module.Source[start:end])
		if err != nil {
			continue
		}
		complete := false
		for _, token := range tokens {
			complete = complete || token.Kind == lexer.String
		}
		if !complete {
			continue
		}
		for i := range tokens {
			for _, pos := range []*syntax.Position{&tokens[i].Pos, &tokens[i].End} {
				if pos.Line == 1 {
					pos.Column += item.Pos.Column - 1
				}
				pos.Line += item.Pos.Line - 1
				pos.Offset += start
			}
		}
		return tokens
	}
	return nil
}
