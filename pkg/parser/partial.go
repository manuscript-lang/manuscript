package parser

import (
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// ParsePartial retains independently valid declarations for editor analysis.
// Parse remains the strict build API. Recovered trees retain original positions
// and source text, and always carry the diagnostics from omitted declarations.
func ParsePartial(file, source string) (*syntax.Module, []syntax.Diagnostic) {
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

// recoverStatements retries a failed declaration chunk with each offending
// statement (and the block it opens) blanked to spaces, so every remaining
// statement keeps its original position. It returns nil when no bounded number
// of blankings parses, in which case the whole declaration is omitted.
func recoverStatements(file, chunk string, first error) (*syntax.Module, []syntax.Diagnostic) {
	issues := []syntax.Diagnostic{}
	lines := strings.SplitAfter(chunk, "\n")
	err := first
	for attempt := 0; attempt < 8; attempt++ {
		issue, ok := err.(syntax.Diagnostic)
		if !ok {
			return nil, nil
		}
		// An unterminated delimiter is reported at the end of the chunk; the
		// statement to drop is the one that opened it. Only the first failure
		// is redirected: a delimiter left open by an earlier blanking is a
		// cascade, and the declaration is omitted rather than reported twice.
		line := issue.Position.Line
		if opened := openedLine(issue.Message); opened > 0 && attempt == 0 {
			line = opened
		}
		// The header line (line 1) failing means the signature is unusable.
		if line < 2 || line > len(lines) {
			return nil, nil
		}
		issues = append(issues, issue)
		at := line - 1
		indent := leadingSpace(lines[at])
		if strings.TrimSpace(lines[at]) == "" || indent == 0 {
			return nil, nil
		}
		for index := at; index < len(lines); index++ {
			if index > at && strings.TrimSpace(lines[index]) != "" && leadingSpace(lines[index]) <= indent {
				break
			}
			lines[index] = blank(lines[index])
		}
		module, parseErr := Parse(file, strings.Join(lines, ""))
		if parseErr == nil {
			return module, issues
		}
		err = parseErr
	}
	return nil, nil
}

var openedAt = regexp.MustCompile(`^unterminated delimiter .* opened at line (\d+):`)

// openedLine reads the line an unterminated-delimiter diagnostic names, or 0.
func openedLine(message string) int {
	match := openedAt.FindStringSubmatch(message)
	if match == nil {
		return 0
	}
	line, _ := strconv.Atoi(match[1])
	return line
}

// shiftOpened rewrites the chunk-relative opener line in an
// unterminated-delimiter message to the file-relative line.
func shiftOpened(message string, lines int) string {
	match := openedAt.FindStringSubmatchIndex(message)
	if match == nil || lines == 0 {
		return message
	}
	line := openedLine(message) + lines
	return message[:match[2]] + strconv.Itoa(line) + message[match[3]:]
}

func leadingSpace(line string) int {
	return len(line) - len(strings.TrimLeft(line, " \t"))
}

// blank replaces every byte but line breaks with a space, keeping offsets.
func blank(line string) string {
	bytes := []byte(line)
	for index, b := range bytes {
		if b != '\r' && b != '\n' {
			bytes[index] = ' '
		}
	}
	return string(bytes)
}

// declaredName reads the name a declaration chunk introduces, for chunks that
// failed to parse.
func declaredName(chunk string) string {
	for _, line := range strings.Split(chunk, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		fields := strings.Fields(strings.TrimPrefix(trimmed, "export "))
		if len(fields) < 2 || (fields[0] != "fn" && fields[0] != "type" && fields[0] != "interface") {
			return ""
		}
		names := strings.FieldsFunc(fields[1], func(r rune) bool { return r == '(' || r == '[' || r == ':' })
		if len(names) == 0 {
			return ""
		}
		return names[0]
	}
	return ""
}
func rebase(module *syntax.Module, offset, lines int) {
	position := func(p *syntax.Position) { p.Offset += offset; p.Line += lines }
	var typ func(*syntax.Type)
	var expression func(*syntax.Expression)
	var body func([]*syntax.Statement)
	var pattern func(*syntax.Pattern)
	var declaration func(*syntax.Declaration)
	parameters := func(params []syntax.Parameter) {
		for i := range params {
			position(&params[i].Pos)
			typ(params[i].Type)
			expression(params[i].Default)
		}
	}
	typ = func(t *syntax.Type) {
		if t == nil {
			return
		}
		position(&t.Pos)
		for _, arg := range t.Args {
			typ(arg)
		}
		parameters(t.Params)
		typ(t.Result)
	}
	pattern = func(p *syntax.Pattern) {
		if p == nil {
			return
		}
		position(&p.Pos)
		for _, child := range p.Elements {
			pattern(child)
		}
		for i := range p.Fields {
			position(&p.Fields[i].Pos)
			pattern(p.Fields[i].Pattern)
		}
	}
	expression = func(e *syntax.Expression) {
		if e == nil {
			return
		}
		position(&e.Pos)
		expression(e.Left)
		expression(e.Right)
		for i := range e.Args {
			position(&e.Args[i].Pos)
			expression(e.Args[i].Value)
		}
		for _, t := range e.Types {
			typ(t)
		}
		for _, item := range e.Elements {
			expression(item)
		}
		for _, part := range e.Parts {
			expression(part.Value)
		}
		parameters(e.Params)
		typ(e.Result)
		body(e.Body)
		for i := range e.Arms {
			position(&e.Arms[i].Pos)
			for index := range e.Arms[i].NamePositions {
				position(&e.Arms[i].NamePositions[index])
			}
			expression(e.Arms[i].Path)
			body(e.Arms[i].Body)
			expression(e.Arms[i].Value)
		}
	}
	body = func(statements []*syntax.Statement) {
		for _, s := range statements {
			position(&s.Pos)
			pattern(s.Pattern)
			typ(s.Type)
			expression(s.Target)
			expression(s.Value)
			body(s.Body)
			body(s.Else)
		}
	}
	declaration = func(d *syntax.Declaration) {
		position(&d.Pos)
		for i := range d.TypeParams {
			position(&d.TypeParams[i].Pos)
			for _, bound := range d.TypeParams[i].Bounds {
				typ(bound)
			}
			if d.TypeParams[i].Default != nil {
				typ(d.TypeParams[i].Default)
			}
		}
		parameters(d.Fields)
		parameters(d.Params)
		for i := range d.Cases {
			position(&d.Cases[i].Pos)
			parameters(d.Cases[i].Fields)
		}
		typ(d.Result)
		typ(d.Contract)
		typ(d.Receiver)
		body(d.Body)
		for _, method := range d.Methods {
			declaration(method)
		}
	}
	for _, imp := range module.Imports {
		position(&imp.Pos)
		position(&imp.NamePos)
	}
	for _, decl := range module.Declarations {
		declaration(decl)
	}
}
