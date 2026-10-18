package checker

import (
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"sort"
	"strings"
)

// Effects are conservative potential effects, including nested closure bodies.
// An indirect or unclassified operation contributes unknown rather than claiming purity.
func (c *checker) effectSummaries() {
	nodes := map[string]*effectNode{}
	for _, module := range c.Modules {
		for _, declaration := range module.Declarations {
			if declaration.Kind == syntax.KindFn || declaration.Kind == syntax.KindRecord {
				symbol := c.symbols[module.File][declaration.Name]
				nodes[symbol.ID] = newEffectNode(declaration)
			}
		}
	}
	for _, method := range c.Methods {
		nodes[method.ID] = newEffectNode(method.Decl)
	}
	for _, n := range nodes {
		syntax.Visitor{Statement: n.scanStatement, Expression: func(e *syntax.Expression) { n.scanExpression(e, nodes) }}.Walk(n.decl)
	}
	propagateEffects(nodes)
	c.Effects = map[string][]string{}
	for id, n := range nodes {
		effects := []string{}
		for effect := range n.effects {
			effects = append(effects, effect)
		}
		sort.Strings(effects)
		c.Effects[id] = effects
	}
}

// effectNode is one callable's own effects and the callables it reaches.
type effectNode struct {
	decl    *syntax.Declaration
	effects map[string]bool
	edges   map[string]bool
}

func newEffectNode(decl *syntax.Declaration) *effectNode {
	return &effectNode{decl, map[string]bool{}, map[string]bool{}}
}

func (n *effectNode) add(effects ...string) {
	for _, effect := range effects {
		n.effects[effect] = true
	}
}

func (n *effectNode) scanStatement(statement *syntax.Statement) {
	if statement.Target != nil {
		n.add("write")
	}
	if statement.Kind != syntax.KindWith {
		return
	}
	method := cleanupOf(statement)
	if method != nil && method.ID != "" {
		n.edges[method.ID] = true
	} else if method != nil && std(method.Receiver, "SynchronizedGuard") {
		n.add("write")
	} else {
		n.add("unknown")
	}
}

func (n *effectNode) scanExpression(expression *syntax.Expression, nodes map[string]*effectNode) {
	if info := infoOf(expression); info != nil && info.Native == "index" {
		n.add("read")
	}
	if expression.Kind == syntax.KindMember {
		if receiver := infoOf(expression.Left); receiver != nil && receiver.Type.Kind == syntax.KindRecord && infoOf(expression).Method == nil {
			n.add("read")
		}
	}
	if expression.Kind == syntax.KindMap && len(expression.Elements) > 2 {
		// Duplicate-key insertion may dispatch user-defined equality.
		n.add("unknown")
	}
	if expression.Kind == syntax.KindCall {
		n.scanCall(expression, nodes)
	}
}

func (n *effectNode) scanCall(expression *syntax.Expression, nodes map[string]*effectNode) {
	info := infoOf(expression)
	if info == nil {
		n.add("unknown")
		return
	}
	if info.Constructor != nil {
		if info.Constructor.Def != nil {
			s := info.Constructor.Def.Symbol
			if s != nil && nodes[s.ID] != nil {
				n.edges[s.ID] = true
			}
		}
		return
	}
	if info.Native == "to_string" || info.Native == "clone" {
		n.add("read")
		return
	}
	if info.Symbol != nil {
		if info.Symbol.Native == "" {
			n.edges[info.Symbol.ID] = true
			return
		}
		switch info.Symbol.Native {
		case "panic", "check_cancelled":
		case "sleep":
			n.add("read")
		default:
			n.add("unknown")
		}
		return
	}
	if info.Method != nil {
		n.scanMethodCall(expression, info.Method)
		return
	}
	n.add("unknown")
}

// scanMethodCall adds the effects of a method call: an edge for source
// methods, or the known effects of the native receiver.
func (n *effectNode) scanMethodCall(expression *syntax.Expression, method *Method) {
	if method.ID != "" {
		n.edges[method.ID] = true
		return
	}
	receiver := method.Receiver
	if method.Contract != nil && method.Contract.ID != "" {
		receiver = method.Contract
	}
	name := expression.Left.Text
	switch receiver.ID {
	case "@std/Clock":
		n.add("read")
	case "@std/Files", "@std/File", "@std/ReadStream":
		n.add("external-call", "read")
		if name == "close" {
			n.add("write")
		}
	case "@std/WriteStream":
		n.add("external-call", "write")
	case "@std/Network", "@std/HttpServer", "@std/Commands", "@std/Subprocess":
		n.add("external-call", "read", "write")
	case "@std/SynchronizedGuard":
		if name == "get" {
			n.add("read")
		} else {
			n.add("write")
		}
	case "@std/Synchronized":
		n.add("write")
	case "@std/BlockingQueue":
		n.add("read", "write")
	case "@std/Queue":
		if name != "enqueue" {
			n.add("read")
		}
		if name == "enqueue" || name == "dequeue" {
			n.add("write")
		}
	case "@std/List", "@std/Map", "@std/Set":
		n.add("read")
		if CollectionMutation(receiver, name) {
			n.add("write")
		}
		for _, param := range method.Type.Params {
			if param.Type.Kind == "function" {
				n.add("unknown")
			}
		}
	case "@std/Scheduler", "@std/TaskGroup", "@std/Task":
		n.add("write", "unknown")
	default:
		if strings.HasSuffix(receiver.Name, "Builder") {
			n.add("write")
		} else if receiver.Kind == "contract" || receiver.Kind == "variable" {
			n.add("unknown")
		}
	}
}

// propagateEffects folds each callee's effects into its callers until stable;
// a call to anything without a node is unknown.
func propagateEffects(nodes map[string]*effectNode) {
	for changed := true; changed; {
		changed = false
		for _, n := range nodes {
			for edge := range n.edges {
				callee := nodes[edge]
				if callee == nil {
					if !n.effects["unknown"] {
						n.effects["unknown"] = true
						changed = true
					}
					continue
				}
				for effect := range callee.effects {
					if !n.effects[effect] {
						n.effects[effect] = true
						changed = true
					}
				}
			}
		}
	}
}
