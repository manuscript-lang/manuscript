package format

import (
	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"sort"
	"strings"
	"unicode/utf8"
)

const formatWidth = 88
const formatComment = "#comment"

// Keep the original tokens and comment text. The concrete delimiter tree gives
// expressions safe continuation boundaries; the AST identifies calls, literals,
// parameters, and statement values rather than guessing from token spellings.
type layoutNode struct {
	token lexer.Token
	group *layoutGroup
	space bool
}

type layoutGroup struct {
	open, close lexer.Token
	nodes       []layoutNode
	force       bool
	parameters  bool
	items       bool
	list        bool
}

type expressionLayout struct {
	lines  []string
	byOpen map[int]*layoutGroup
	byItem map[int]*layoutGroup
}

func formatExpressionLayout(filename, source string) (string, error) {
	source, err := groupStatementExpressions(filename, source)
	if err != nil {
		return "", err
	}
	module, err := parseFormatSource(filename, source)
	if err != nil {
		return "", err
	}
	tokens, err := lexer.Lex(filename, source)
	if err != nil {
		return "", err
	}
	layout := &expressionLayout{
		lines:  strings.Split(source, "\n"),
		byOpen: map[int]*layoutGroup{}, byItem: map[int]*layoutGroup{},
	}
	nodes := layout.tree(layoutTokens(source, tokens))
	visitor := syntax.Visitor{Expression: func(e *syntax.Expression) {
		switch e.Kind {
		case syntax.KindCall:
			if len(e.Args) == 0 {
				return
			}
			g := layout.byItem[e.Args[0].Pos.Offset]
			if g == nil {
				return // Interpolation is part of one atomic string token.
			}
			g.items = true
			for _, arg := range e.Args {
				if blockLambda(arg.Value) {
					g.force = true
				}
			}
		case syntax.KindList:
			if g := layout.byOpen[e.Pos.Offset]; g != nil {
				g.list = true
			}
		case syntax.KindLambda:
			layout.parameters(e.Params)
		}
	}}
	var declaration func(*syntax.Declaration)
	declaration = func(d *syntax.Declaration) {
		layout.parameters(d.Params)
		layout.typ(d.Result)
		for _, field := range d.Fields {
			layout.typ(field.Type)
		}
		for _, c := range d.Cases {
			layout.parameters(c.Fields)
		}
		for _, method := range d.Methods {
			declaration(method)
		}
	}
	for _, d := range module.Declarations {
		declaration(d)
		visitor.Walk(d)
	}
	var output strings.Builder
	offset := 0
	for _, node := range nodes {
		if node.group == nil {
			continue
		}
		g := node.group
		output.WriteString(source[offset:g.open.Pos.Offset])
		line := output.String()
		if at := strings.LastIndexByte(line, '\n'); at >= 0 {
			line = line[at+1:]
		}
		indent := len(line) - len(strings.TrimLeft(line, " "))
		output.WriteString(layout.group(g, indent, utf8.RuneCountInString(line), 0))
		offset = g.close.Pos.Offset + len(g.close.Text)
	}
	output.WriteString(source[offset:])
	return output.String(), nil
}

// blockLambda reports a lambda whose body is a suite of several statements;
// a one-expression lambda stays inline when the call fits the line.
func blockLambda(e *syntax.Expression) bool {
	return e.Kind == syntax.KindLambda && len(e.Body) > 1
}

func (l *expressionLayout) parameters(params []syntax.Parameter) {
	if len(params) > 0 {
		if g := l.byItem[params[0].Pos.Offset]; g != nil {
			g.parameters = true
			g.items = true
		}
	}
	for _, param := range params {
		l.typ(param.Type)
	}
}

func (l *expressionLayout) typ(t *syntax.Type) {
	if t == nil {
		return
	}
	l.parameters(t.Params)
	for _, arg := range t.Args {
		l.typ(arg)
	}
	l.typ(t.Result)
}

// Recover comment trivia only outside lexer tokens, so "#" and interpolation
// inside strings never become formatter instructions or break opportunities.
func layoutTokens(source string, tokens []lexer.Token) []lexer.Token {
	var comments []lexer.Token
	lines := strings.Split(source, "\n")
	last := map[int]int{}
	for _, token := range tokens {
		if !layoutToken(token.Kind) {
			last[token.Pos.Line] = token.Pos.Column - 1 + len(token.Text)
		}
	}
	offset := 0
	for index, line := range lines {
		tail := last[index+1]
		if at := strings.IndexByte(line[tail:], '#'); at >= 0 {
			column := tail + at
			comments = append(comments, lexer.Token{
				Kind: formatComment, Text: strings.TrimRight(line[column:], " \t"),
				Pos: syntax.Position{Line: index + 1, Column: column + 1, Offset: offset + column},
			})
		}
		offset += len(line) + 1
	}
	var result []lexer.Token
	comment := 0
	for _, token := range tokens {
		for comment < len(comments) && comments[comment].Pos.Offset <= token.Pos.Offset {
			result = append(result, comments[comment])
			comment++
		}
		result = append(result, token)
	}
	return result
}

func layoutToken(kind string) bool {
	switch kind {
	case lexer.Newline, lexer.Indent, lexer.Dedent, lexer.EOF:
		return true
	}
	return false
}

func (l *expressionLayout) tree(tokens []lexer.Token) []layoutNode {
	at := 0
	var code []lexer.Token
	var sequence func(string) []layoutNode
	sequence = func(close string) []layoutNode {
		var nodes []layoutNode
		for at < len(tokens) && tokens[at].Kind != close {
			token := tokens[at]
			at++
			node := layoutNode{token: token}
			if !layoutToken(token.Kind) && token.Kind != formatComment {
				code = append(code, token)
				node.space = len(code) > 1 && tokenSpace(code, len(code)-1)
			}
			end := ""
			switch token.Kind {
			case "(":
				end = ")"
			case "[":
				end = "]"
			case "{":
				end = "}"
			}
			if end != "" {
				g := &layoutGroup{open: token}
				g.items = token.Kind != "("
				if len(code) > 1 {
					switch code[len(code)-2].Kind {
					case lexer.Name, ")", "]", "fn":
						g.items = true
					}
				}
				g.nodes = sequence(end)
				g.close = tokens[at]
				code = append(code, g.close)
				at++
				// Only a nested suite keeps a group multi-line; authored line
				// breaks otherwise collapse when the group fits.
				for _, child := range g.nodes {
					g.force = g.force || child.token.Kind == lexer.Newline
				}
				l.byOpen[token.Pos.Offset] = g
				for _, child := range g.nodes {
					if !layoutToken(child.token.Kind) && child.token.Kind != formatComment {
						l.byItem[child.token.Pos.Offset] = g
						break
					}
				}
				node.group = g
			}
			nodes = append(nodes, node)
		}
		return nodes
	}
	return sequence("")
}

func flatLayout(nodes []layoutNode) string {
	var output strings.Builder
	for _, node := range nodes {
		if layoutToken(node.token.Kind) || node.token.Kind == formatComment {
			continue
		}
		if output.Len() > 0 && node.space {
			output.WriteByte(' ')
		}
		if node.group != nil {
			output.WriteString(node.group.open.Text)
			output.WriteString(flatLayout(node.group.nodes))
			output.WriteString(node.group.close.Text)
		} else {
			output.WriteString(node.token.Text)
		}
	}
	return output.String()
}

func splitLayout(nodes []layoutNode, separator string) [][]layoutNode {
	var parts [][]layoutNode
	start := 0
	for i, node := range nodes {
		matches := node.token.Kind == separator
		switch separator {
		case "+", "-":
			matches = node.token.Kind == "+" || node.token.Kind == "-"
		case "*", "/", "%":
			matches = node.token.Kind == "*" || node.token.Kind == "/" || node.token.Kind == "%"
		}
		if node.group != nil || !matches {
			continue
		}
		end := i
		if separator == "," {
			end++
			// A trailing comment explains the item before this comma.
			for end < len(nodes) && nodes[end].token.Kind == formatComment &&
				nodes[end].token.Pos.Line == node.token.Pos.Line {
				end++
			}
		}
		if end > start {
			parts = append(parts, nodes[start:end])
		}
		start = end
	}
	if start < len(nodes) {
		parts = append(parts, nodes[start:])
	}
	return parts
}

func layoutOperators(nodes []layoutNode) (string, int) {
	precedence := map[string]int{"or": 1, "and": 2, "==": 3, "!=": 3, "<": 3, ">": 3, "<=": 3, ">=": 3, "+": 4, "-": 4, "*": 5, "/": 5, "%": 5, ".": 6}
	selected, level, count := "", 7, 0
	for _, node := range nodes {
		if node.token.Kind == lexer.Newline || node.token.Kind == "fn" {
			return "", 0 // Operators here belong to a callable body or type.
		}
		if node.group != nil {
			continue
		}
		if p, ok := precedence[node.token.Kind]; ok {
			if p < level {
				selected, level, count = node.token.Kind, p, 1
			} else if p == level {
				count++
			}
		}
	}
	return selected, count
}

func (l *expressionLayout) group(g *layoutGroup, indent, column, following int) string {
	g = trimTrailingComma(g)
	flat := g.open.Text + flatLayout(g.nodes) + g.close.Text
	suffix := following
	if g.parameters {
		tail := l.lines[g.close.Pos.Line-1][g.close.Pos.Column-1+len(g.close.Text):]
		// A callback body and enclosing arguments do not belong to its signature,
		// and neither do sibling parameters after a function-typed parameter.
		suffix = utf8.RuneCountInString(signatureTail(tail))
	}
	force := g.force || column+utf8.RuneCountInString(flat)+suffix > formatWidth
	operator, count := layoutOperators(g.nodes)
	booleans := 0
	for _, node := range g.nodes {
		if node.group == nil && (node.token.Kind == "and" || node.token.Kind == "or") {
			booleans++
		}
	}
	if g.items || (operator == "." && count < 2) {
		operator = ""
	}
	switch operator {
	case "==", "!=", "<", ">", "<=", ">=":
		operator = "" // Keep each comparison together as one operand.
	}
	for _, node := range g.nodes {
		force = force || node.token.Kind == formatComment
	}
	parts := splitLayout(g.nodes, ",")
	if len(parts) == 0 {
		return flat
	}
	if !force {
		// A child's complexity or width can expand the containing argument.
		trial := l.sequence(g.nodes, indent, column+len(g.open.Text), false)
		if !strings.Contains(trial, "\n") {
			return g.open.Text + trial + g.close.Text
		}
		force = true
	}
	if force && len(parts) == 1 && operator != "" {
		parts = splitLayout(g.nodes, operator)
	}
	if g.list && !g.force && simpleLayoutItems(parts) {
		return packedLayout(g, parts, indent)
	}
	// Keep an opener's trailing comment on its original line.
	opening := g.open.Text
	if len(g.nodes) > 0 && g.nodes[0].token.Kind == formatComment &&
		g.nodes[0].token.Pos.Line == g.open.Pos.Line {
		opening += "  " + g.nodes[0].token.Text
		remaining := g.nodes[1:]
		parts = splitLayout(remaining, ",")
		if len(parts) == 1 && operator != "" {
			parts = splitLayout(remaining, operator)
		}
	}
	var output strings.Builder
	output.WriteString(opening)
	for _, part := range parts {
		text := l.sequence(part, indent+4, indent+4, true)
		if text != "" {
			output.WriteByte('\n')
			output.WriteString(text)
		}
	}
	output.WriteByte('\n')
	output.WriteString(strings.Repeat(" ", indent))
	output.WriteString(g.close.Text)
	return output.String()
}

// signatureTail is the part of a source line after a parameter list that
// belongs to the same signature: the return type, up to the suite colon, or
// up to the comma or closing delimiter that ends an enclosing parameter.
func signatureTail(tail string) string {
	depth := 0
	for i := 0; i < len(tail); i++ {
		switch tail[i] {
		case '(', '[', '{':
			depth++
		case ')', ']', '}':
			if depth == 0 {
				return tail[:i]
			}
			depth--
		case ':', ',':
			if depth == 0 {
				return tail[:i]
			}
		}
	}
	return tail
}

// Pack atomic list values into rows using their printed width. Expressions,
// nested groups, comments, and suites keep their own structural boundaries.
func simpleLayoutItems(parts [][]layoutNode) bool {
	for _, part := range parts {
		values := 0
		for _, node := range part {
			if layoutToken(node.token.Kind) || node.token.Kind == "," {
				continue
			}
			if node.group != nil || node.token.Kind == formatComment {
				return false
			}
			values++
		}
		if values != 1 {
			return false
		}
	}
	return len(parts) > 1
}

func packedLayout(g *layoutGroup, parts [][]layoutNode, indent int) string {
	padding := strings.Repeat(" ", indent+4)
	var output strings.Builder
	output.WriteString(g.open.Text)
	column := 0
	for _, part := range parts {
		text := flatLayout(part)
		width := utf8.RuneCountInString(text)
		if column == 0 || column+1+width > formatWidth {
			output.WriteByte('\n')
			output.WriteString(padding)
			column = indent + 4
		} else {
			output.WriteByte(' ')
			column++
		}
		output.WriteString(text)
		column += width
	}
	output.WriteByte('\n')
	output.WriteString(strings.Repeat(" ", indent))
	output.WriteString(g.close.Text)
	return output.String()
}

func (l *expressionLayout) sequence(nodes []layoutNode, indent, column int, prefix bool) string {
	var output strings.Builder
	firstIndent := 0
	for _, node := range nodes {
		if !layoutToken(node.token.Kind) {
			firstIndent = l.lineIndent(node.token.Pos.Line)
			break
		}
	}
	pending, suite, lastLine := false, false, 0
	lineIndent := indent
	write := func(text string) {
		output.WriteString(text)
		if at := strings.LastIndexByte(text, '\n'); at >= 0 {
			tail := text[at+1:]
			column = utf8.RuneCountInString(tail)
			lineIndent = len(tail) - len(strings.TrimLeft(tail, " "))
		} else {
			column += utf8.RuneCountInString(text)
		}
	}
	for index, node := range nodes {
		if layoutToken(node.token.Kind) {
			pending = pending || node.token.Kind == lexer.Newline
			suite = suite || node.token.Kind == lexer.Newline
			continue
		}
		comment := node.token.Kind == formatComment
		if comment && lastLine != node.token.Pos.Line && output.Len() > 0 {
			pending = true
		}
		if output.Len() > 0 && !pending && !suite && lastLine != 0 && lastLine != node.token.Pos.Line {
			// An original line break joins this line to the output line. A suite
			// opened here is indented relative to the line that holds its header.
			firstIndent = l.lineIndent(node.token.Pos.Line)
		}
		if output.Len() == 0 || pending {
			if output.Len() > 0 {
				write("\n")
				for line := lastLine + 1; line < node.token.Pos.Line; line++ {
					if strings.TrimSpace(l.lines[line-1]) == "" {
						write("\n")
						break
					}
				}
			}
			lineIndent = indent
			if suite {
				lineIndent = max(0, indent+l.lineIndent(node.token.Pos.Line)-firstIndent)
			}
			if prefix || output.Len() > 0 {
				write(strings.Repeat(" ", lineIndent))
			}
		} else if comment {
			write("  ")
		} else if node.space {
			write(" ")
		}
		pending = false
		if node.group != nil {
			var tail []layoutNode
			for _, next := range nodes[index+1:] {
				if next.token.Kind == lexer.Newline || next.token.Kind == formatComment {
					break
				}
				if next.group != nil && len(next.group.nodes) > 0 {
					// The next group has its own continuation boundary. Its
					// contents must not force this group (such as a list before
					// a map callback) to expand as well.
					next.group = nil
					tail = append(tail, next)
					break
				}
				tail = append(tail, next)
			}
			following := utf8.RuneCountInString(flatLayout(tail))
			if len(tail) > 0 && tail[0].space {
				following++
			}
			write(l.group(node.group, lineIndent, column, following))
			lastLine = node.group.close.Pos.Line
		} else {
			write(node.token.Text)
			lastLine = node.token.Pos.Line
		}
		pending = comment
	}
	return output.String()
}

func (l *expressionLayout) lineIndent(line int) int {
	text := l.lines[line-1]
	return len(text) - len(strings.TrimLeft(text, " "))
}

// Ordinary newlines cannot split ungrouped expressions. Add grouping only
// around a statement's complete value, retaining its precedence and inline suite.
func groupStatementExpressions(filename, source string) (string, error) {
	module, err := parseFormatSource(filename, source)
	if err != nil {
		return "", err
	}
	tokens, err := lexer.Lex(filename, source)
	if err != nil {
		return "", err
	}
	starts, pairs := map[int]int{}, map[int]int{}
	var stack []int
	for i, token := range tokens {
		starts[token.Pos.Offset] = i
		switch token.Kind {
		case "(", "[", "{":
			stack = append(stack, i)
		case ")", "]", "}":
			open := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			pairs[open] = i
		}
	}
	insert := map[int]string{}
	wrap := func(start int) int {
		end, booleans, dots, operators := start, 0, 0, 0
		for end < len(tokens) {
			if close, ok := pairs[end]; ok {
				end = close + 1
				continue
			}
			kind := tokens[end].Kind
			if layoutToken(kind) || kind == ":" || kind == "," ||
				kind == ")" || kind == "]" || kind == "}" {
				break
			}
			switch kind {
			case "and", "or":
				booleans++
			case ".":
				dots++
			case "+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">=":
				operators++
			}
			end++
		}
		if end == start {
			return end
		}
		from, to := tokens[start].Pos.Offset, tokens[end-1].Pos.Offset+len(tokens[end-1].Text)
		var flat strings.Builder
		var code []lexer.Token
		for _, token := range tokens[start:end] {
			if layoutToken(token.Kind) {
				continue
			}
			code = append(code, token)
			if len(code) > 1 && tokenSpace(code, len(code)-1) {
				flat.WriteByte(' ')
			}
			flat.WriteString(token.Text)
		}
		width := tokens[start].Pos.Column - 1 + utf8.RuneCountInString(flat.String())
		if end < len(tokens) && tokens[end].Kind == ":" {
			width++ // The condition's suite colon occupies a column too.
		}
		if width > formatWidth && (booleans+operators > 0 || dots >= 2) {
			insert[from] += "("
			insert[to] = ")" + insert[to]
		}
		return end
	}
	defaults := func(params []syntax.Parameter) {
		for _, param := range params {
			if param.Default == nil || suiteExpression(param.Default) {
				continue
			}
			start, ok := starts[param.Pos.Offset]
			if !ok {
				continue
			}
			for tokens[start].Kind != "=" {
				if end, ok := pairs[start]; ok {
					start = end
				}
				start++
			}
			wrap(start + 1)
		}
	}
	// A constant's synthetic statement starts at its initializer, which may be
	// text, so it bypasses the keyword and text-statement handling below.
	constants := map[*syntax.Statement]bool{}
	for _, d := range module.Declarations {
		if d.Constant {
			constants[d.Body[0]] = true
		}
	}
	visitor := syntax.Visitor{
		Statement: func(s *syntax.Statement) {
			if s.Value == nil || suiteExpression(s.Value) {
				return
			}
			start, ok := starts[s.Pos.Offset]
			if ok && constants[s] {
				wrap(start)
				return
			}
			if !ok || tokens[start].Kind == lexer.String {
				return
			}
			switch s.Kind {
			case syntax.KindIf, syntax.KindWhile:
				start++
				if s.Pattern != nil {
					// `if let name = value:` wraps only the value.
					for tokens[start].Kind != "=" {
						start++
					}
					start++
				}
			case syntax.KindReturn:
				if tokens[start].Kind == syntax.KindReturn {
					start++
				}
			case syntax.KindBind, syntax.KindAssign, syntax.KindWith, syntax.KindFor:
				target := "="
				if s.Kind == syntax.KindFor {
					target = "in"
				}
				for tokens[start].Kind != target {
					if end, ok := pairs[start]; ok {
						start = end
					}
					start++
				}
				start++
			}
			wrap(start)
		},
		Expression: func(e *syntax.Expression) {
			switch e.Kind {
			case syntax.KindLambda:
				defaults(e.Params)
				return
			case syntax.KindList:
				for _, element := range e.Elements {
					if suiteExpression(element) {
						return
					}
				}
				start, ok := starts[e.Pos.Offset]
				if !ok || tokens[start].Kind != "[" {
					return
				}
				start++
				for range e.Elements {
					end := wrap(start)
					if end == start || tokens[end].Kind != "," {
						break
					}
					start = end + 1
				}
				return
			case syntax.KindMap:
				start, ok := starts[e.Pos.Offset]
				if !ok || tokens[start].Kind != "{" {
					return
				}
				start++
				for at := 0; at < len(e.Elements); at += 2 {
					if suiteExpression(e.Elements[at]) || suiteExpression(e.Elements[at+1]) {
						return
					}
					end := wrap(start)
					if end == start || tokens[end].Kind != ":" {
						break
					}
					end = wrap(end + 1)
					if tokens[end].Kind != "," {
						break
					}
					start = end + 1
				}
				return
			case syntax.KindCall:
			default:
				return
			}
			for _, arg := range e.Args {
				if suiteExpression(arg.Value) {
					continue
				}
				start, ok := starts[arg.Pos.Offset]
				if !ok || tokens[start].Kind == lexer.String {
					continue
				}
				if arg.Name != "" {
					start += 2 // The argument label and colon stay together.
				}
				wrap(start)
			}
		},
	}
	var callable func(*syntax.Declaration)
	callable = func(d *syntax.Declaration) {
		defaults(d.Params)
		for _, method := range d.Methods {
			callable(method)
		}
	}
	for _, d := range module.Declarations {
		callable(d)
		visitor.Walk(d)
	}
	var offsets []int
	for offset := range insert {
		offsets = append(offsets, offset)
	}
	sort.Sort(sort.Reverse(sort.IntSlice(offsets)))
	for _, offset := range offsets {
		source = source[:offset] + insert[offset] + source[offset:]
	}
	return source, nil
}

func suiteExpression(e *syntax.Expression) bool {
	for e.Kind == syntax.KindUnary {
		e = e.Right
	}
	return e.Kind == syntax.KindLambda || e.Kind == syntax.KindMatch
}

// trimTrailingComma drops an authored trailing comma when the group has no
// comments or suites, so a group that collapses onto one line reads cleanly.
func trimTrailingComma(g *layoutGroup) *layoutGroup {
	last := len(g.nodes) - 1
	for last >= 0 && layoutToken(g.nodes[last].token.Kind) {
		last--
	}
	if last < 0 || g.nodes[last].group != nil || g.nodes[last].token.Kind != "," {
		return g
	}
	for _, node := range g.nodes {
		if node.token.Kind == formatComment {
			return g
		}
	}
	trimmed := *g
	trimmed.nodes = g.nodes[:last]
	return &trimmed
}
