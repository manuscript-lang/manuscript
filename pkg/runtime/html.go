package msruntime

import (
	"html"
	"regexp"
	"strings"
	"unicode/utf8"

	xhtml "golang.org/x/net/html"
)

// Html_Escape escapes text and quoted attribute contexts; it is not a sanitizer.
func Html_Escape(_ *Execution, text string) string { return html.EscapeString(text) }

// Html_Unescape decodes HTML5 character references in one pass.
func Html_Unescape(ctx *Execution, text string) string {
	CheckCancelled(ctx)
	out := htmlUnescape(text)
	CheckCancelled(ctx)
	return out
}

// htmlHexNoDigits matches a hexadecimal character reference with no digits,
// which HTML5 leaves literal but Go's html.UnescapeString turns into U+FFFD.
var htmlHexNoDigits = regexp.MustCompile(`&#[xX];`)

// htmlUnescape decodes character references, leaving "&#x;" untouched. A
// reference cannot span the literal's leading '&', so decoding the pieces
// between occurrences is equivalent.
func htmlUnescape(text string) string {
	spans := htmlHexNoDigits.FindAllStringIndex(text, -1)
	if len(spans) == 0 {
		return html.UnescapeString(text)
	}
	var out strings.Builder
	last := 0
	for _, span := range spans {
		out.WriteString(html.UnescapeString(text[last:span[0]]))
		out.WriteString(text[span[0]:span[1]])
		last = span[1]
	}
	out.WriteString(html.UnescapeString(text[last:]))
	return out.String()
}

// htmlReader checks cancellation while the parser consumes even one long token.
type htmlReader struct {
	ctx    *Execution
	reader *strings.Reader
}

func (r htmlReader) Read(p []byte) (int, error) {
	CheckCancelled(r.ctx)
	if len(p) > 4096 {
		p = p[:4096]
	}
	return r.reader.Read(p)
}

// Html_Parse parses a document with the HTML5 algorithm and converts the tree
// iteratively, applying byte, depth and node limits.
func Html_Parse(ctx *Execution, text string, limits Option[*HtmlLimits]) Result[HtmlNode, HtmlError] {
	maxBytes, maxDepth, maxNodes := dfBudget(None[int]()), dfBudget(None[int]()), dfBudget(None[int]())
	if limits.Some {
		maxBytes, maxDepth, maxNodes = dfBudget(limits.Val.MaxBytes), dfBudget(limits.Val.MaxDepth), dfBudget(limits.Val.MaxNodes)
	}
	if maxBytes < 0 || maxDepth < 0 || maxNodes < 0 {
		return Fail[HtmlNode, HtmlError](HtmlError_InvalidInput{})
	}
	if len(text) > maxBytes {
		return Fail[HtmlNode, HtmlError](HtmlError_LimitExceeded{})
	}
	if !utf8.ValidString(text) {
		return Fail[HtmlNode, HtmlError](HtmlError_InvalidData{})
	}
	doc, err := xhtml.Parse(htmlReader{ctx, strings.NewReader(text)})
	if err != nil {
		return Fail[HtmlNode, HtmlError](HtmlError_InvalidData{})
	}
	type frame struct {
		node     *xhtml.Node
		next     *xhtml.Node
		children []HtmlNode
	}
	stack := []frame{{node: doc, next: doc.FirstChild}}
	count := 1
	if count > maxNodes {
		return Fail[HtmlNode, HtmlError](HtmlError_LimitExceeded{})
	}
	for len(stack) > 0 {
		CheckCancelled(ctx)
		current := &stack[len(stack)-1]
		if child := current.next; child != nil {
			if len(stack) > maxDepth || count >= maxNodes {
				return Fail[HtmlNode, HtmlError](HtmlError_LimitExceeded{})
			}
			count++
			current.next = child.NextSibling
			stack = append(stack, frame{node: child, next: child.FirstChild})
			continue
		}
		node := current.node
		var value HtmlNode
		switch node.Type {
		case xhtml.DocumentNode:
			value = HtmlNode_Document{Children: NewList(current.children...)}
		case xhtml.ElementNode:
			attributes := make([]*HtmlAttribute, 0, len(node.Attr))
			for _, attr := range node.Attr {
				CheckCancelled(ctx)
				attributes = append(attributes, &HtmlAttribute{Name: attr.Key, Namespace: attr.Namespace, Value: attr.Val})
			}
			value = HtmlNode_Element{Tag: node.Data, Namespace: node.Namespace, Attributes: NewList(attributes...), Children: NewList(current.children...)}
		case xhtml.TextNode:
			value = HtmlNode_Text{Text: node.Data}
		case xhtml.CommentNode:
			value = HtmlNode_Comment{Text: node.Data}
		case xhtml.DoctypeNode:
			publicID, systemID := "", ""
			for _, attr := range node.Attr {
				if attr.Key == "public" {
					publicID = attr.Val
				} else if attr.Key == "system" {
					systemID = attr.Val
				}
			}
			value = HtmlNode_Doctype{Name: node.Data, PublicId: publicID, SystemId: systemID}
		default:
			return Fail[HtmlNode, HtmlError](HtmlError_InvalidData{})
		}
		stack = stack[:len(stack)-1]
		if len(stack) == 0 {
			return Ok[HtmlNode, HtmlError](value)
		}
		parent := &stack[len(stack)-1]
		parent.children = append(parent.children, value)
	}
	return Fail[HtmlNode, HtmlError](HtmlError_InvalidData{})
}

// Errors_Message_HtmlError returns the fixed HTML diagnostic.
func Errors_Message_HtmlError(_ *Execution, e HtmlError) string {
	switch e.(type) {
	case HtmlError_InvalidInput:
		return dfMessage("HTML", reasonInvalidInput)
	case HtmlError_InvalidData:
		return dfMessage("HTML", reasonInvalidData)
	case HtmlError_LimitExceeded:
		return dfMessage("HTML", reasonLimitExceeded)
	}
	return dfMessage("HTML", "operation failed")
}
