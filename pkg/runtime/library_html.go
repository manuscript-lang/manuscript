package msruntime

import (
	"strings"
	"unicode/utf8"

	xhtml "golang.org/x/net/html"
)

func init() {
	libraryAdd("html", "parse", libraryResult("HtmlNode", "HtmlError"), []LibraryParam{{"text", "String"}, {"limits", "Optional[HtmlLimits]"}}, libraryHTMLParse)
}

// Check cancellation while the HTML5 parser consumes even a single long token.
type libraryHTMLReader struct {
	ctx    *Execution
	reader *strings.Reader
}

func (r libraryHTMLReader) Read(p []byte) (int, error) {
	CheckCancelled(r.ctx)
	if len(p) > 4096 {
		p = p[:4096]
	}
	return r.reader.Read(p)
}

func libraryHTMLParse(ctx *Execution, result string, args []Value) Value {
	text := args[0].(string)
	limits := args[1].(Record).Fields
	maxBytes, maxDepth, maxNodes := nativeInteger(limits["max_bytes"]), nativeInteger(limits["max_depth"]), nativeInteger(limits["max_nodes"])
	if maxBytes < 0 || maxDepth < 0 || maxNodes < 0 {
		return libraryError(result, "InvalidInput", "")
	}
	if int64(len(text)) > maxBytes {
		return libraryError(result, "LimitExceeded", "")
	}
	if !utf8.ValidString(text) {
		return libraryError(result, "InvalidData", "")
	}
	doc, err := xhtml.Parse(libraryHTMLReader{ctx, strings.NewReader(text)})
	if err != nil {
		return libraryError(result, "InvalidData", "")
	}
	// Convert iteratively so deeply nested documents do not need recursive
	// runtime calls. The document is depth zero; all returned nodes count.
	type frame struct {
		node     *xhtml.Node
		next     *xhtml.Node
		children []Value
	}
	stack := []frame{{node: doc, next: doc.FirstChild}}
	count := int64(1)
	if count > maxNodes {
		return libraryError(result, "LimitExceeded", "")
	}
	for len(stack) > 0 {
		CheckCancelled(ctx)
		current := &stack[len(stack)-1]
		if child := current.next; child != nil {
			if int64(len(stack)) > maxDepth || count >= maxNodes {
				return libraryError(result, "LimitExceeded", "")
			}
			count++
			current.next = child.NextSibling
			stack = append(stack, frame{node: child, next: child.FirstChild})
			continue
		}
		node := current.node
		value := Alternative{Type: "@std/HtmlNode"}
		switch node.Type {
		case xhtml.DocumentNode:
			value.Tag = "Document"
			value.Fields = []Value{libraryList("@std/HtmlNode", current.children)}
		case xhtml.ElementNode:
			attributes := make([]Value, 0, len(node.Attr))
			for _, attr := range node.Attr {
				CheckCancelled(ctx)
				attributes = append(attributes, Record{Type: "@std/HtmlAttribute", Fields: map[string]Value{"name": attr.Key, "namespace": attr.Namespace, "value": attr.Val}})
			}
			value.Tag = "Element"
			value.Fields = []Value{node.Data, node.Namespace, libraryList("@std/HtmlAttribute", attributes), libraryList("@std/HtmlNode", current.children)}
		case xhtml.TextNode:
			value.Tag, value.Fields = "Text", []Value{node.Data}
		case xhtml.CommentNode:
			value.Tag, value.Fields = "Comment", []Value{node.Data}
		case xhtml.DoctypeNode:
			publicID, systemID := "", ""
			for _, attr := range node.Attr {
				if attr.Key == "public" {
					publicID = attr.Val
				} else if attr.Key == "system" {
					systemID = attr.Val
				}
			}
			value.Tag, value.Fields = "Doctype", []Value{node.Data, publicID, systemID}
		default:
			return libraryError(result, "InvalidData", "")
		}
		stack = stack[:len(stack)-1]
		if len(stack) == 0 {
			return libraryOK(result, value)
		}
		parent := &stack[len(stack)-1]
		parent.children = append(parent.children, value)
	}
	return libraryError(result, "InvalidData", "")
}
