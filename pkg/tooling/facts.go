package tooling

import (
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// Fact is what a review compares for one callable or type: facts the checker
// established, never text. Key is stable across edits (file, kind, name).
type Fact struct {
	Key      string   `json:"key"`
	File     string   `json:"file"`
	Kind     string   `json:"kind"`
	Name     string   `json:"name"`
	Type     string   `json:"type,omitempty"`
	Exported bool     `json:"exported"`
	Line     int      `json:"line"`
	Effects  []string `json:"effects,omitempty"`
	Error    string   `json:"error,omitempty"`
	Tries    int      `json:"tries,omitempty"`
	Withs    int      `json:"withs,omitempty"`
	Calls    []string `json:"calls,omitempty"` // keys of project entities called
	External []string `json:"external,omitempty"`
	// first and last are the entity's head-side line range, for mapping a diff.
	First int `json:"-"`
	Last  int `json:"-"`
}

// Facts is the fact model of one checked program.
type Facts struct {
	Entities map[string]*Fact    `json:"entities"`
	Imports  map[string][]string `json:"imports"` // file -> imported module paths
	// flows holds each callable's ordered significant steps, for the flow and scope views.
	flows map[string][]*Node
}

func factKey(file, kind, name string) string { return file + "#" + kind + "#" + name }

// CollectFacts derives the review fact model from a checked program.
func CollectFacts(program *checker.Program) Facts {
	inspection := Inspect(program)
	facts := Facts{Entities: map[string]*Fact{}, Imports: map[string][]string{}, flows: map[string][]*Node{}}
	idToKey := map[string]string{}
	for _, e := range inspection.Entities {
		fact := &Fact{Key: factKey(e.Span.File, e.Kind, e.Name), File: e.Span.File, Kind: e.Kind, Name: e.Name,
			Type: e.Type, Exported: e.Exported, Line: e.Span.Line, Effects: e.Effects}
		fact.Error = errorType(e.Type)
		facts.Entities[fact.Key] = fact
		idToKey[e.ID] = fact.Key
	}
	owners := map[string]*Fact{}
	for _, e := range inspection.Entities {
		owners[e.ID] = facts.Entities[factKey(e.Span.File, e.Kind, e.Name)]
	}
	for _, call := range inspection.Calls {
		owner := owners[call.Owner]
		if owner == nil {
			continue
		}
		if key, ok := idToKey[call.Target]; ok {
			owner.Calls = appendUnique(owner.Calls, key)
		} else {
			owner.External = appendUnique(owner.External, call.Target)
		}
	}
	sites := map[string]CallSite{}
	for _, call := range inspection.Calls {
		sites[call.ID] = call
	}
	for _, module := range program.Modules {
		for _, imp := range module.Imports {
			facts.Imports[module.File] = appendUnique(facts.Imports[module.File], imp.Path)
		}
		flow := &flowBuilder{module: module, lines: strings.Split(module.Source, "\n"), sites: sites, keys: idToKey}
		collectBodies(facts, module, flow)
	}
	for _, fact := range facts.Entities {
		sort.Strings(fact.Calls)
		sort.Strings(fact.External)
		sort.Strings(fact.Effects)
	}
	for file := range facts.Imports {
		sort.Strings(facts.Imports[file])
	}
	return facts
}

func appendUnique(list []string, value string) []string {
	for _, existing := range list {
		if existing == value {
			return list
		}
	}
	return append(list, value)
}

// collectBodies counts try and with sites and records each entity's line range.
func collectBodies(facts Facts, module *syntax.Module, flow *flowBuilder) {
	total := strings.Count(module.Source, "\n") + 1
	declarations := module.Declarations
	for index, declaration := range declarations {
		last := total
		if index+1 < len(declarations) {
			last = declarations[index+1].Pos.Line - 1
		}
		name := declaration.Name
		kind := declaration.Kind
		if declaration.Constant {
			kind = "constant"
		}
		if declaration.Kind == syntax.KindImpl {
			name = declaration.ImplName()
		}
		if fact := facts.Entities[factKey(module.File, kind, name)]; fact != nil {
			fact.First, fact.Last = declaration.Pos.Line, last
			fact.Tries, fact.Withs = countSites(declaration)
			facts.flows[fact.Key] = flow.body(declaration.Body)
		}
		for i, method := range declaration.Methods {
			end := last
			if i+1 < len(declaration.Methods) {
				end = declaration.Methods[i+1].Pos.Line - 1
			}
			if fact := facts.Entities[factKey(module.File, "method", name+"."+method.Name)]; fact != nil {
				fact.First, fact.Last = method.Pos.Line, end
				fact.Tries, fact.Withs = countSites(method)
				facts.flows[fact.Key] = flow.body(method.Body)
			}
		}
	}
}

// countSites counts try expressions and with statements in one body. A
// declaration with methods reports only its own body; each method counts its own.
func countSites(declaration *syntax.Declaration) (tries, withs int) {
	own := &syntax.Declaration{Params: declaration.Params, Body: declaration.Body}
	syntax.Visitor{
		Expression: func(e *syntax.Expression) {
			if e.Kind == syntax.KindUnary && e.Text == "try" {
				tries++
			}
		},
		Statement: func(s *syntax.Statement) {
			if s.Kind == syntax.KindWith {
				withs++
			}
		},
	}.Walk(own)
	return tries, withs
}

// errorType extracts E from a function type whose result is Result[T, E].
func errorType(signature string) string {
	params, ok := strings.CutPrefix(signature, "fn(")
	if !ok {
		return ""
	}
	end, depth := 0, 1
	for end < len(params) && depth > 0 {
		switch params[end] {
		case '(':
			depth++
		case ')':
			depth--
		}
		end++
	}
	result := strings.TrimSpace(params[end:])
	if depth != 0 || !strings.HasPrefix(result, "Result[") {
		return ""
	}
	inner := strings.TrimSuffix(strings.TrimPrefix(result, "Result["), "]")
	depth = 0
	for i := 0; i < len(inner); i++ {
		switch inner[i] {
		case '[', '(':
			depth++
		case ']', ')':
			depth--
		case ',':
			if depth == 0 {
				return strings.TrimSpace(inner[i+1:])
			}
		}
	}
	return ""
}
