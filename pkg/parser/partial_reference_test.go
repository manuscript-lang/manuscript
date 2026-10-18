package parser

import (
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Frozen recovery splitter from 95ec85602c3d08a8de6d96de45df89e80bbd2d2a.
// Keep the old algorithm independent of continuation parse reuse so tests can
// compare complete trees, spans, omitted names, fixes, and diagnostics.
func legacyParsePartial(file, source string) (*syntax.Module, []syntax.Diagnostic) {
	if module, err := Parse(file, source); err == nil {
		return module, nil
	}
	module := &syntax.Module{File: file, Source: source}
	diagnostics := []syntax.Diagnostic{}
	starts := []int{}
	offset := 0
	for _, line := range strings.SplitAfter(source, "\n") {
		trimmed := strings.TrimSpace(line)
		if len(line) > 0 && line[0] != ' ' && line[0] != '\t' && trimmed != "" && !strings.HasPrefix(trimmed, "#") {
			declaration := false
			for _, keyword := range []string{"import ", "export ", "fn ", "type ", "interface ", "impl ", "test "} {
				declaration = declaration || strings.HasPrefix(trimmed, keyword)
			}
			// A fresh declaration synchronizes even after an unmatched opener.
			// Other column-zero lines can still belong to a continued header,
			// import, or expression. Let the lexer handle strings and comments
			// rather than counting delimiter characters in source text.
			if !declaration && len(starts) > 0 {
				_, err := lexer.Lex(file, source[starts[len(starts)-1]:offset])
				if issue, ok := err.(syntax.Diagnostic); ok && strings.HasPrefix(issue.Message, "unterminated delimiter") {
					offset += len(line)
					continue
				}
			}
			starts = append(starts, offset)
		}
		offset += len(line)
	}
	if len(starts) == 0 {
		_, err := Parse(file, source)
		if issue, ok := err.(syntax.Diagnostic); ok {
			diagnostics = append(diagnostics, issue)
		}
		return module, diagnostics
	}
	starts[0] = 0
	starts = append(starts, len(source))
	lineOffset := 0
	previous := 0
	for index := 0; index < len(starts)-1; index++ {
		start, end := starts[index], starts[index+1]
		lineOffset += strings.Count(source[previous:start], "\n")
		previous = start
		chunk := source[start:end]
		parsed, err := Parse(file, chunk)
		var recovered []syntax.Diagnostic
		if err != nil {
			parsed, recovered = recoverStatements(file, chunk, err)
		}
		if err != nil {
			rebased := func(issue syntax.Diagnostic) syntax.Diagnostic {
				issue.Message = shiftOpened(issue.Message, lineOffset)
				issue.Position.Offset += start
				issue.Position.Line += lineOffset
				if issue.End != nil {
					end := *issue.End
					end.Offset += start
					end.Line += lineOffset
					issue.End = &end
				}
				if issue.Fix != nil {
					fix := *issue.Fix
					fix.Position.Offset += start
					fix.Position.Line += lineOffset
					fix.End.Offset += start
					fix.End.Line += lineOffset
					issue.Fix = &fix
				}
				return issue
			}
			if parsed == nil {
				if name := declaredName(chunk); name != "" {
					module.Omitted = append(module.Omitted, name)
				}
				if issue, ok := err.(syntax.Diagnostic); ok {
					diagnostics = append(diagnostics, rebased(issue))
				}
				continue
			}
			sort.SliceStable(recovered, func(i, j int) bool { return recovered[i].Position.Offset < recovered[j].Position.Offset })
			for _, issue := range recovered {
				diagnostics = append(diagnostics, rebased(issue))
			}
			module.Recovered = append(module.Recovered, syntax.Span{Start: start, End: end})
		}
		rebase(parsed, start, lineOffset)
		module.Imports = append(module.Imports, parsed.Imports...)
		module.Declarations = append(module.Declarations, parsed.Declarations...)
	}
	return module, diagnostics
}
