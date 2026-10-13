package msruntime

import (
	"strings"
	"time"
	"unicode/utf8"

	xhtml "golang.org/x/net/html"
)

func init() {
	p := func(name, typ string) LibraryParam { return LibraryParam{name, typ} }
	variables := []LibraryParam{p("T", "")}
	libraryGeneric("toml", "same_list", "Bool", variables, []LibraryParam{p("left", "List[T]"), p("right", "List[T]")}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		return args[0].(*List) == args[1].(*List)
	})
	libraryGeneric("toml", "same_table", "Bool", variables, []LibraryParam{p("left", "Map[String][T]"), p("right", "Map[String][T]")}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		return args[0].(*Map) == args[1].(*Map)
	})
	libraryAdd("html", "stringify", libraryResult("String", "HtmlError"), []LibraryParam{p("value", "HtmlNode"), p("limits", "Optional[HtmlLimits]")}, libraryHTMLStringify)
	libraryAdd("time", "timestamp_format", "String", []LibraryParam{p("value", "Timestamp"), p("layout", "String")}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		text := args[0].(libraryTimestamp).t.UTC().Format(args[1].(string))
		CheckCancelled(ctx)
		return text
	})
	libraryAdd("time", "parse_timestamp_format", libraryResult("Timestamp", "TimeError"), []LibraryParam{p("text", "String"), p("layout", "String")}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		text, layout := args[0].(string), args[1].(string)
		if layout == "" {
			return libraryError(result, "InvalidInput", "")
		}
		value, err := time.Parse(layout, text)
		CheckCancelled(ctx)
		if err != nil {
			return libraryError(result, "InvalidData", "")
		}
		value = value.UTC()
		if value.Year() < 1 || value.Year() > 9999 {
			return libraryError(result, "OutOfRange", "")
		}
		return libraryOK(result, libraryTimestamp{value})
	})
}

// Render only after constructing a fresh native tree. Active source identities
// distinguish a cycle from a shared subtree, which renders at every occurrence.
func libraryHTMLStringify(ctx *Execution, result string, args []Value) Value {
	limits := args[1].(Record).Fields
	maxBytes, maxDepth, maxNodes := limits["max_bytes"].(int64), limits["max_depth"].(int64), limits["max_nodes"].(int64)
	if maxBytes < 0 || maxDepth < 0 || maxNodes < 0 {
		return libraryError(result, "InvalidInput", "")
	}
	type frame struct {
		value    Value
		parent   *xhtml.Node
		depth    int64
		identity equalityIdentity
		leave    bool
	}
	stack := []frame{{value: args[0]}}
	active := map[equalityIdentity]bool{}
	count := int64(0)
	var root *xhtml.Node
	invalid := func() Value { return libraryError(result, "InvalidData", "") }
	for len(stack) > 0 {
		CheckCancelled(ctx)
		current := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		if current.leave {
			delete(active, current.identity)
			continue
		}
		if current.depth > maxDepth || count >= maxNodes {
			return libraryError(result, "LimitExceeded", "")
		}
		count++
		value, ok := current.value.(Alternative)
		if !ok || value.Type != "@std/HtmlNode" {
			return invalid()
		}
		node := &xhtml.Node{}
		var children *List
		switch value.Tag {
		case "Document":
			if len(value.Fields) != 1 || current.parent != nil {
				return invalid()
			}
			node.Type = xhtml.DocumentNode
			children, ok = value.Fields[0].(*List)
			if !ok {
				return invalid()
			}
		case "Element":
			if len(value.Fields) != 4 {
				return invalid()
			}
			node.Type = xhtml.ElementNode
			node.Data, ok = value.Fields[0].(string)
			if !ok || !libraryHTMLName(node.Data) {
				return invalid()
			}
			node.Namespace, ok = value.Fields[1].(string)
			if !ok || node.Namespace != "" && !libraryHTMLName(node.Namespace) {
				return invalid()
			}
			attributes, valid := value.Fields[2].(*List)
			if !valid {
				return invalid()
			}
			for _, item := range attributes.Items {
				CheckCancelled(ctx)
				attribute, valid := item.(Record)
				if !valid || attribute.Type != "@std/HtmlAttribute" {
					return invalid()
				}
				key, keyOK := attribute.Fields["name"].(string)
				namespace, namespaceOK := attribute.Fields["namespace"].(string)
				text, textOK := attribute.Fields["value"].(string)
				if !keyOK || !namespaceOK || !textOK || !libraryHTMLName(key) || namespace != "" && !libraryHTMLName(namespace) || !libraryHTMLText(text) {
					return invalid()
				}
				node.Attr = append(node.Attr, xhtml.Attribute{Namespace: namespace, Key: key, Val: text})
			}
			children, ok = value.Fields[3].(*List)
			if !ok {
				return invalid()
			}
		case "Text", "Comment":
			if len(value.Fields) != 1 {
				return invalid()
			}
			node.Data, ok = value.Fields[0].(string)
			if !ok || !libraryHTMLText(node.Data) {
				return invalid()
			}
			node.Type = xhtml.TextNode
			if value.Tag == "Comment" {
				node.Type = xhtml.CommentNode
			}
		case "Doctype":
			if len(value.Fields) != 3 || current.parent != nil && current.parent.Type != xhtml.DocumentNode {
				return invalid()
			}
			node.Type = xhtml.DoctypeNode
			node.Data, ok = value.Fields[0].(string)
			publicID, publicOK := value.Fields[1].(string)
			systemID, systemOK := value.Fields[2].(string)
			if !ok || !publicOK || !systemOK || !libraryHTMLName(node.Data) || !libraryHTMLIdentifier(publicID) || !libraryHTMLIdentifier(systemID) {
				return invalid()
			}
			node.Attr = []xhtml.Attribute{{Key: "public", Val: publicID}, {Key: "system", Val: systemID}}
		default:
			return invalid()
		}
		if current.parent == nil {
			root = node
		} else {
			current.parent.AppendChild(node)
		}
		if children != nil {
			identity, _ := equalityID(children)
			if active[identity] {
				return invalid()
			}
			active[identity] = true
			stack = append(stack, frame{identity: identity, leave: true})
			for index := len(children.Items) - 1; index >= 0; index-- {
				stack = append(stack, frame{value: children.Items[index], parent: node, depth: current.depth + 1})
			}
		}
	}
	writer := &libraryHTMLRenderWriter{ctx: ctx, libraryLimitedWriter: libraryLimitedWriter{max: maxBytes}}
	if err := xhtml.Render(writer, root); err != nil {
		if writer.overflow {
			return libraryError(result, "LimitExceeded", "")
		}
		return invalid()
	}
	CheckCancelled(ctx)
	return libraryOK(result, writer.String())
}

func libraryHTMLText(text string) bool {
	return utf8.ValidString(text) && !strings.ContainsRune(text, 0)
}

func libraryHTMLName(text string) bool {
	return text != "" && libraryHTMLText(text) && !strings.ContainsAny(text, " \t\n\r\f<>/='\"")
}

func libraryHTMLIdentifier(text string) bool {
	// Quoted doctype identifiers still terminate at '>'; rendering leaves it
	// literal. The native renderer also cannot escape both quote delimiters.
	return libraryHTMLText(text) && !strings.ContainsRune(text, '>') && !(strings.ContainsRune(text, '\'') && strings.ContainsRune(text, '"'))
}

type libraryHTMLRenderWriter struct {
	ctx *Execution
	libraryLimitedWriter
}

func (writer *libraryHTMLRenderWriter) Write(data []byte) (int, error) {
	total := 0
	for len(data) > 0 {
		CheckCancelled(writer.ctx)
		size := min(len(data), 4096)
		n, err := writer.libraryLimitedWriter.Write(data[:size])
		total += n
		if err != nil {
			return total, err
		}
		data = data[size:]
	}
	if total == 0 {
		CheckCancelled(writer.ctx)
	}
	return total, nil
}

func (writer *libraryHTMLRenderWriter) WriteByte(value byte) error {
	_, err := writer.Write([]byte{value})
	return err
}

func (writer *libraryHTMLRenderWriter) WriteString(text string) (int, error) {
	total := 0
	for len(text) > 0 {
		size := min(len(text), 4096)
		n, err := writer.Write([]byte(text[:size]))
		total += n
		if err != nil {
			return total, err
		}
		text = text[size:]
	}
	CheckCancelled(writer.ctx)
	return total, nil
}
