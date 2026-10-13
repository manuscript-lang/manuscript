package checker

import (
	"github.com/manuscript-lang/manuscript/pkg/syntax"
	"sort"
	"strings"
)

// Effects are conservative potential effects, including nested closure bodies.
// An indirect or unclassified operation contributes unknown rather than claiming purity.
func (c *checker) effectSummaries() {
	type node struct {
		decl    *syntax.Declaration
		effects map[string]bool
		edges   map[string]bool
	}
	nodes := map[string]*node{}
	for _, module := range c.Modules {
		for _, declaration := range module.Declarations {
			if declaration.Kind == syntax.KindFn || declaration.Kind == syntax.KindRecord {
				symbol := c.Symbols[module.File][declaration.Name]
				nodes[symbol.ID] = &node{declaration, map[string]bool{}, map[string]bool{}}
			}
		}
	}
	for _, method := range c.Methods {
		nodes[method.ID] = &node{method.Decl, map[string]bool{}, map[string]bool{}}
	}
	add := func(n *node, effects ...string) {
		for _, effect := range effects {
			n.effects[effect] = true
		}
	}
	for _, n := range nodes {
		syntax.Visitor{
			Statement: func(statement *syntax.Statement) {
				if statement.Target != nil {
					add(n, "write")
				}
				if statement.Kind != syntax.KindWith {
					return
				}
				method := c.Cleanups[statement]
				if method != nil && method.ID != "" {
					n.edges[method.ID] = true
				} else if method != nil && std(method.Receiver, "SynchronizedGuard") {
					add(n, "write")
				} else {
					add(n, "unknown")
				}
			},
			Expression: func(expression *syntax.Expression) {
				if info := c.Expressions[expression]; info != nil && info.Native == "index" {
					add(n, "read")
				}
				if expression.Kind == syntax.KindMember {
					if receiver := c.Expressions[expression.Left]; receiver != nil && receiver.Type.Kind == syntax.KindRecord && c.Expressions[expression].Method == nil {
						add(n, "read")
					}
				}
				if expression.Kind == syntax.KindMap && len(expression.Elements) > 2 {
					// Duplicate-key insertion may dispatch user-defined equality.
					add(n, "unknown")
				}
				if expression.Kind != syntax.KindCall {
					return
				}
				info := c.Expressions[expression]
				if info == nil {
					add(n, "unknown")
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
				if info.Native == "toString" || info.Native == "clone" {
					add(n, "read")
					return
				}
				if info.Symbol != nil {
					if info.Symbol.Native == "" {
						n.edges[info.Symbol.ID] = true
						return
					}
					switch info.Symbol.Native {
					case "panic", "check_cancelled":
						return
					case "sleep":
						add(n, "read")
						return
					default:
						add(n, "unknown")
						return
					}
				}
				if info.Method != nil {
					method := info.Method
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
						add(n, "read")
					case "@std/Files", "@std/File", "@std/ReadStream":
						add(n, "external-call", "read")
						if name == "close" {
							add(n, "write")
						}
					case "@std/WriteStream":
						add(n, "external-call", "write")
					case "@std/Network", "@std/HttpServer", "@std/Commands":
						add(n, "external-call", "read", "write")
					case "@std/SynchronizedGuard":
						if name == "get" {
							add(n, "read")
						} else {
							add(n, "write")
						}
					case "@std/Synchronized":
						add(n, "write")
					case "@std/Queue":
						if name != "enqueue" {
							add(n, "read")
						}
						if name == "enqueue" || name == "dequeue" {
							add(n, "write")
						}
					case "@std/List", "@std/Map", "@std/Set":
						add(n, "read")
						if collectionMutation(receiver, name) {
							add(n, "write")
						}
						for _, param := range method.Type.Params {
							if param.Type.Kind == "function" {
								add(n, "unknown")
							}
						}
					case "@std/Scheduler", "@std/TaskGroup", "@std/Task":
						add(n, "write", "unknown")
					default:
						if strings.HasSuffix(receiver.Name, "Builder") {
							add(n, "write")
						} else if receiver.Kind == "contract" || receiver.Kind == "variable" {
							add(n, "unknown")
						}
					}
					return
				}
				add(n, "unknown")
			},
		}.Walk(n.decl)
	}
	changed := true
	for changed {
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
