package tooling

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/syntax"
	"sort"
	"strings"
)

type Span struct {
	File   string `json:"file"`
	Start  int    `json:"start"`
	End    int    `json:"end"`
	Line   int    `json:"line"`
	Column int    `json:"column"`
}
type Source struct {
	File   string `json:"file"`
	SHA256 string `json:"sha256"`
}
type Entity struct {
	ID       string   `json:"id"`
	GoID     string   `json:"go_id,omitempty"`
	Kind     string   `json:"kind"`
	Name     string   `json:"name"`
	Type     string   `json:"type,omitempty"`
	Span     Span     `json:"span"`
	Exported bool     `json:"exported"`
	Effects  []string `json:"effects,omitempty"`
}
type CallSite struct {
	ID     string `json:"id"`
	Owner  string `json:"owner"`
	Target string `json:"target"`
	Kind   string `json:"kind"`
	Span   Span   `json:"span"`
}
type Local struct {
	GoID string `json:"go_id"`
	Name string `json:"name"`
	Type string `json:"type"`
	Span Span   `json:"span"`
}
type Inspection struct {
	Locals     []Local    `json:"locals"`
	Format     int        `json:"format"`
	BuildID    string     `json:"build_id"`
	Sources    []Source   `json:"sources"`
	Entities   []Entity   `json:"entities"`
	Calls      []CallSite `json:"calls"`
	Statements []Span     `json:"statements"`
}

func hash(data string) string { sum := sha256.Sum256([]byte(data)); return hex.EncodeToString(sum[:]) }
func sourceSpan(module *syntax.Module, pos syntax.Position) Span {
	start := pos.Offset
	end := start
	for end < len(module.Source) && module.Source[end] != '\n' && module.Source[end] != '\r' {
		end++
	}
	return Span{module.File, start, end, pos.Line, pos.Column}
}
func Inspect(program *checker.Program) Inspection {
	result := Inspection{Format: 1, Sources: []Source{}, Entities: []Entity{}, Calls: []CallSite{}, Statements: []Span{}}
	result.Locals = []Local{}
	modules := map[string]*syntax.Module{}
	for _, module := range program.Modules {
		modules[module.File] = module
	}
	local := func(binding *checker.Binding, pos syntax.Position) {
		if binding == nil {
			return
		}
		module := modules[pos.File]
		if module == nil {
			return
		}
		result.Locals = append(result.Locals, Local{binding.ID, binding.Name, binding.Type.String(), sourceSpan(module, pos)})
	}
	for declaration, binding := range program.Self {
		local(binding, declaration.Pos)
	}
	for pattern, binding := range program.Bindings {
		local(binding, pattern.Pos)
	}
	for statement, binding := range program.LoopBindings {
		local(binding, statement.Pos)
	}
	for declaration, bindings := range program.Parameters {
		for index, binding := range bindings {
			if index < len(declaration.Params) {
				local(binding, declaration.Params[index].Pos)
			}
		}
	}
	for expression, bindings := range program.LambdaParameters {
		for index, binding := range bindings {
			if index < len(expression.Params) {
				local(binding, expression.Params[index].Pos)
			}
		}
	}
	for arm, bindings := range program.ArmBindings {
		for _, binding := range bindings {
			local(binding, arm.Pos)
		}
	}
	sort.Slice(result.Locals, func(i, j int) bool { return result.Locals[i].GoID < result.Locals[j].GoID })
	symbolIDs := map[*checker.Symbol]string{}
	methodIDs := map[string]string{}
	methods := map[*syntax.Declaration]*checker.Method{}
	for _, method := range program.Methods {
		if method.Decl == nil {
			continue
		}
		methods[method.Decl] = method
		methodIDs[method.ID] = fmt.Sprintf("%s#method#%d", method.Decl.Pos.File, method.Decl.Pos.Offset)
	}
	for _, module := range program.Modules {
		for _, declaration := range module.Declarations {
			if declaration.Kind == syntax.KindTest || declaration.Kind == syntax.KindImpl {
				continue
			}
			symbol := program.Symbols[module.File][declaration.Name]
			symbolIDs[symbol] = module.File + "#" + declaration.Kind + "#" + declaration.Name
		}
	}
	for _, module := range program.Modules {
		result.Sources = append(result.Sources, Source{module.File, hash(module.Source)})
		for _, declaration := range module.Declarations {
			id := module.File + "#" + declaration.Kind + "#" + declaration.Name
			entity := Entity{ID: id, Kind: declaration.Kind, Name: declaration.Name, Span: sourceSpan(module, declaration.Pos), Exported: declaration.Export}
			if symbol := program.Symbols[module.File][declaration.Name]; symbol != nil && symbol.Decl == declaration {
				entity.GoID = symbol.ID
				entity.Type = symbol.Type.String()
				entity.Effects = program.Effects[symbol.ID]
			}
			if declaration.Kind == syntax.KindImpl {
				entity.ID = fmt.Sprintf("%s#impl#%d", module.File, declaration.Pos.Offset)
				entity.Name = declaration.Contract.Name + " for " + declaration.Receiver.Name
			}
			result.Entities = append(result.Entities, entity)
			visitor := syntax.Visitor{Expression: func(e *syntax.Expression) {
				if e.Kind == syntax.KindCall {
					site := CallSite{ID: fmt.Sprintf("%s#call#%d", module.File, e.Pos.Offset), Owner: entity.ID, Target: "indirect", Kind: "function", Span: sourceSpan(module, e.Pos)}
					info := program.Expressions[e]
					if info != nil {
						if info.Symbol != nil {
							site.Target = symbolIDs[info.Symbol]
							if site.Target == "" {
								site.Target = info.Symbol.Module + "#" + info.Symbol.Name
							}
						}
						if info.Method != nil {
							site.Kind = "operation"
							site.Target = methodIDs[info.Method.ID]
							if site.Target == "" {
								site.Target = info.Method.Receiver.String() + "." + e.Left.Text
							}
						}
						if info.Constructor != nil {
							site.Kind = "construct"
							site.Target = info.Constructor.String()
						}
						if info.Native == "parallel" || info.Native == "background" || info.Native == "background_start" || info.Native == "http_serve" {
							site.Kind = info.Native
							site.Target = info.Native
						}
					}
					result.Calls = append(result.Calls, site)
				}
			}, Statement: func(s *syntax.Statement) {
				result.Statements = append(result.Statements, sourceSpan(module, s.Pos))
				if s.Kind == syntax.KindWith {
					target := "indirect.close"
					if method := program.Cleanups[s]; method != nil {
						target = methodIDs[method.ID]
						if target == "" {
							target = method.Receiver.String() + ".close"
						}
					}
					result.Calls = append(result.Calls, CallSite{ID: fmt.Sprintf("%s#cleanup#%d", module.File, s.Pos.Offset), Owner: entity.ID, Target: target, Kind: "cleanup", Span: sourceSpan(module, s.Pos)})
				}
			}}
			visitor.Callable(declaration.Params, declaration.Body)
			implementation := entity
			for _, method := range declaration.Methods {
				if len(method.Body) > 0 {
					checked := methods[method]
					entity = Entity{ID: methodIDs[checked.ID], GoID: checked.ID, Kind: "method", Name: implementation.Name + "." + method.Name, Type: checked.Type.String(), Span: sourceSpan(module, method.Pos), Effects: program.Effects[checked.ID]}
					result.Entities = append(result.Entities, entity)
					visitor.Callable(method.Params, method.Body)
				}
			}
		}
	}
	sort.Slice(result.Sources, func(i, j int) bool { return result.Sources[i].File < result.Sources[j].File })
	sort.Slice(result.Entities, func(i, j int) bool { return result.Entities[i].ID < result.Entities[j].ID })
	sort.Slice(result.Calls, func(i, j int) bool { return result.Calls[i].ID < result.Calls[j].ID })
	identity, _ := json.Marshal(result)
	result.BuildID = hash(string(identity))
	return result
}
func Diagram(inspection Inspection) string {
	var output strings.Builder
	output.WriteString("flowchart TD\n")
	nodes := map[string]string{}
	node := func(id, label string) string {
		key := "n" + hash(id)[:16]
		if nodes[id] == "" {
			nodes[id] = key
			label = strings.NewReplacer("&", "&amp;", "\"", "&quot;", "<", "&lt;", ">", "&gt;", "\n", " ").Replace(label)
			fmt.Fprintf(&output, "    %s[\"%s\"]\n", key, label)
		}
		return key
	}
	for _, entity := range inspection.Entities {
		node(entity.ID, entity.Span.File+"::"+entity.Name)
	}
	for _, call := range inspection.Calls {
		owner := node(call.Owner, call.Owner)
		target := node(call.Target, call.Target)
		fmt.Fprintf(&output, "    %s -->|%s| %s\n", owner, call.Kind, target)
	}
	return output.String()
}
