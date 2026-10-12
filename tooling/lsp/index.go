package lsp

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/compiler"
	"github.com/manuscript-lang/manuscript/lexer"
	"github.com/manuscript-lang/manuscript/syntax"
	"sort"
	"strings"
)

type occurrence struct {
	key, name          string
	pos                syntax.Position
	end                int
	declaration, write bool
	info               *checker.Info
}

func symbolKey(s *checker.Symbol) string {
	if s == nil {
		return ""
	}
	if s.Decl != nil {
		return fmt.Sprintf("symbol:%s:%d", s.Decl.Pos.File, s.Decl.Pos.Offset)
	}
	return "native:" + s.ID
}
func bindingKey(b *checker.Binding) string {
	if b == nil {
		return ""
	}
	return "binding:" + b.ID
}
func methodKey(m *checker.Method) string {
	if m == nil {
		return ""
	}
	if m.Decl != nil && m.Contract != nil && m.Contract.Def != nil && m.Contract.Def.Symbol != nil && m.Contract.Def.Symbol.Decl != nil {
		decl := m.Contract.Def.Symbol.Decl
		return fmt.Sprintf("operation:%s:%d:%s", decl.Pos.File, decl.Pos.Offset, m.Decl.Name)
	}
	if m.Decl != nil {
		return fmt.Sprintf("method:%s:%d", m.Decl.Pos.File, m.Decl.Pos.Offset)
	}
	return ""
}
func sourceIndex(result compiler.Result) []occurrence {
	index := []occurrence{}
	if result.Program == nil {
		return index
	}
	program := result.Program
	bindingKeys := map[*checker.Binding]string{}
	for decl, bindings := range program.Parameters {
		for index, b := range bindings {
			if b == nil {
				continue
			}
			bindingKeys[b] = fmt.Sprintf("parameter:%s:%d:%d", decl.Pos.File, decl.Pos.Offset, index)
		}
	}
	localKey := func(b *checker.Binding) string {
		if key := bindingKeys[b]; key != "" {
			return key
		}
		return bindingKey(b)
	}
	tokens := map[string][]lexer.Token{}
	seen := map[string]bool{}
	for _, m := range sourceModules(result) {
		lexed, e := lexer.Lex(m.File, m.Source)
		if e == nil {
			tokens[m.File] = lexed
		}
	}
	add := func(key, name string, pos syntax.Position, decl, write bool, info *checker.Info) {
		if key == "" || name == "" {
			return
		}
		id := fmt.Sprintf("%s:%d:%s", pos.File, pos.Offset, key)
		if seen[id] {
			return
		}
		seen[id] = true
		index = append(index, occurrence{key, name, pos, pos.Offset + len(name), decl, write, info})
	}
	header := func(pos syntax.Position, name string) syntax.Position {
		for _, token := range tokens[pos.File] {
			if token.Pos.Offset < pos.Offset {
				continue
			}
			if token.Kind == lexer.Newline {
				if token.Pos.Offset == pos.Offset {
					continue
				}
				break
			}
			if token.Kind == lexer.Name && token.Text == name {
				return token.Pos
			}
		}
		return pos
	}
	for _, m := range sourceModules(result) {
		for _, decl := range m.Declarations {
			if symbol := sourceSymbols(result, m.File)[decl.Name]; symbol != nil && symbol.Decl == decl {
				add(symbolKey(symbol), symbol.Name, header(decl.Pos, symbol.Name), true, false, &checker.Info{Type: symbol.Type, Symbol: symbol})
			}
		}
		for _, decl := range m.Declarations {
			symbol := sourceSymbols(result, m.File)[decl.Name]
			if symbol == nil || symbol.Decl != decl || symbol.Type == nil || symbol.Type.Def == nil {
				continue
			}
			for _, field := range decl.Fields {
				for _, typed := range checker.Fields(symbol.Type) {
					if typed.Name == field.Name {
						add("field:"+symbolKey(symbol)+":"+field.Name, field.Name, field.Pos, true, false, &checker.Info{Type: typed.Type})
					}
				}
			}
			for _, cs := range decl.Cases {
				add("case:"+symbolKey(symbol)+":"+cs.Name, cs.Name, cs.Pos, true, false, &checker.Info{Type: symbol.Type, Constructor: symbol.Type, Case: cs.Name})
			}
			if symbol.Type.Kind == "contract" || strings.HasPrefix(m.File, "@std/") {
				for _, method := range decl.Methods {
					for _, op := range symbol.Type.Def.Operations {
						if method.Name == op.Name {
							checked := &checker.Method{Decl: method, Receiver: symbol.Type, Type: op.Type}
							if symbol.Type.Kind == "contract" {
								checked.Contract = symbol.Type
								checked.Native = "contract"
							}
							add(methodKey(checked), method.Name, header(method.Pos, method.Name), true, false, &checker.Info{Type: op.Type, Method: checked})
						}
					}
				}
			}
		}
		for _, imp := range m.Imports {
			symbols := sourceSymbols(result, m.File)
			if strings.HasPrefix(m.File, "@std/") {
				symbols = checker.StandardExports(imp.Path)
			}
			if symbol := symbols[imp.Name]; symbol != nil {
				add(symbolKey(symbol), imp.Name, imp.NamePos, false, false, &checker.Info{Type: symbol.Type, Symbol: symbol})
			}
		}
	}
	for pattern, b := range program.Bindings {
		if b == nil {
			continue
		}
		add(localKey(b), b.Name, pattern.Pos, true, false, &checker.Info{Type: b.Type, Binding: b})
	}
	for decl, bindings := range program.Parameters {
		for i, b := range bindings {
			if b == nil {
				continue
			}
			if i < len(decl.Params) {
				add(localKey(b), b.Name, decl.Params[i].Pos, true, false, &checker.Info{Type: b.Type, Binding: b})
			}
		}
	}
	for e, bindings := range program.LambdaParameters {
		for i, b := range bindings {
			if b == nil {
				continue
			}
			if i < len(e.Params) {
				add(localKey(b), b.Name, e.Params[i].Pos, true, false, &checker.Info{Type: b.Type, Binding: b})
			}
		}
	}
	for stmt, b := range program.LoopBindings {
		if b == nil {
			continue
		}
		add(localKey(b), b.Name, header(stmt.Pos, b.Name), true, false, &checker.Info{Type: b.Type, Binding: b})
	}
	for arm, bindings := range program.ArmBindings {
		for _, b := range bindings {
			if b == nil {
				continue
			}
			add(localKey(b), b.Name, header(arm.Pos, b.Name), true, false, &checker.Info{Type: b.Type, Binding: b})
		}
	}
	for _, method := range program.Methods {
		if method.Decl != nil {
			add(methodKey(method), method.Decl.Name, header(method.Decl.Pos, method.Decl.Name), true, false, &checker.Info{Type: method.Type, Method: method})
		}
	}
	for _, refs := range []map[*syntax.Type]*checker.Type{program.TypeReferences, checker.StandardTypeReferences()} {
		for typ, resolved := range refs {
			if resolved != nil && resolved.Def != nil && resolved.Def.Symbol != nil {
				symbol := resolved.Def.Symbol
				add(symbolKey(symbol), typ.Name, typ.Pos, false, false, &checker.Info{Type: resolved, Symbol: symbol})
			}
		}
	}
	for e, info := range program.Expressions {
		if e == nil || info == nil {
			continue
		}
		if e.Kind == "name" {
			if info.Binding != nil {
				add(localKey(info.Binding), e.Text, e.Pos, false, false, info)
			} else if info.Symbol != nil {
				add(symbolKey(info.Symbol), e.Text, e.Pos, false, false, info)
			}
		}
		if e.Kind == "member" && info.Method == nil && e.Left != nil {
			if receiver := program.Expressions[e.Left]; receiver != nil && receiver.Type != nil && receiver.Type.Kind == "record" && receiver.Type.Def != nil {
				parent := receiver.Type.Def.Symbol
				add("field:"+symbolKey(parent)+":"+e.Text, e.Text, e.Pos, false, false, info)
			}
		}
		if info.Constructor != nil && info.Case != "" {
			parent := info.Constructor.Def
			if parent != nil && parent.Symbol != nil {
				left := e
				if e.Kind == "call" {
					left = e.Left
				}
				add("case:"+symbolKey(parent.Symbol)+":"+info.Case, info.Case, left.Pos, false, false, info)
				if left.Kind == "member" {
					root := left.Left
					for root != nil && root.Kind == "apply" {
						root = root.Left
					}
					if root != nil && root.Kind == "name" {
						add(symbolKey(parent.Symbol), root.Text, root.Pos, false, false, &checker.Info{Type: info.Constructor, Symbol: parent.Symbol})
					}
				}
			}
		}
		if e.Kind == "call" && info.Constructor != nil && info.Constructor.Kind == "record" && info.Constructor.Def != nil {
			parent := info.Constructor.Def.Symbol
			for _, arg := range e.Args {
				for _, field := range checker.Fields(info.Constructor) {
					if field.Name == arg.Name {
						add("field:"+symbolKey(parent)+":"+field.Name, field.Name, arg.Pos, false, false, &checker.Info{Type: field.Type})
					}
				}
			}
		}
		if e.Kind == "member" && info.Method != nil {
			add(methodKey(info.Method), e.Text, e.Pos, false, false, info)
		}
		if e.Kind == "call" && info.Constructor != nil && info.Constructor.Def != nil && e.Left != nil {
			left := e.Left
			for left.Kind == "apply" {
				left = left.Left
			}
			if left.Kind == "name" {
				symbol := info.Constructor.Def.Symbol
				add(symbolKey(symbol), left.Text, left.Pos, false, false, &checker.Info{Type: info.Constructor, Symbol: symbol})
			}
		}
		if e.Kind == "call" {
			var decl *syntax.Declaration
			if called := program.Expressions[e.Left]; called != nil {
				if called.Symbol != nil {
					decl = called.Symbol.Decl
				}
				if called.Method != nil {
					decl = called.Method.Decl
				}
			}
			if decl != nil {
				for _, arg := range e.Args {
					for i, param := range decl.Params {
						if param.Name == arg.Name && i < len(program.Parameters[decl]) {
							b := program.Parameters[decl][i]
							add(localKey(b), b.Name, arg.Pos, false, false, &checker.Info{Type: b.Type, Binding: b})
						}
					}
				}
			}
		}
	}
	visitor := syntax.Visitor{Statement: func(s *syntax.Statement) {
		if s.Kind == "assign" {
			if b := program.Assignments[s.Value]; b != nil {
				add(localKey(b), s.Name, s.Pos, false, true, &checker.Info{Type: b.Type, Binding: b})
			}
		}
	}}
	for _, m := range sourceModules(result) {
		for _, decl := range m.Declarations {
			visitor.Walk(decl)
		}
	}

	sort.Slice(index, func(i, j int) bool {
		a, b := index[i], index[j]
		if a.pos.File != b.pos.File {
			return a.pos.File < b.pos.File
		}
		if a.pos.Offset != b.pos.Offset {
			return a.pos.Offset < b.pos.Offset
		}
		return a.key < b.key
	})
	return index
}
func occurrenceAt(result compiler.Result, d document, p position, index []occurrence) *occurrence {
	offset, err := Offset(d.Text, p)
	if err != nil {
		return nil
	}
	file := moduleFile(result, d)
	for _, entry := range index {
		if entry.pos.File == file && offset >= entry.pos.Offset && offset < entry.end {
			copy := entry
			return &copy
		}
	}
	return nil
}
func occurrenceLocation(result compiler.Result, entry occurrence) any {
	for _, m := range sourceModules(result) {
		if m.File == entry.pos.File {
			return map[string]any{"uri": sourceURI(result, m.File), "range": span{Position(m.Source, entry.pos.Offset), Position(m.Source, entry.end)}}
		}
	}
	return nil
}
