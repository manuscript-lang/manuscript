package ast

import (
	"fmt"
	"reflect"
	"strings"
)

// Utility functions for creating AST nodes

// NewPosition creates a new Position
func NewPosition(line, column, offset int) Position {
	return Position{
		Line:   line,
		Column: column,
		Offset: offset,
	}
}

// NewBaseNode creates a new BaseNode
func NewBaseNode(pos Position) BaseNode {
	return BaseNode{Position: pos}
}

// NewNamedNode creates a new NamedNode
func NewNamedNode(name string, pos Position) NamedNode {
	return NamedNode{
		BaseNode: BaseNode{Position: pos},
		Name:     name,
	}
}

// NewProgram creates a new Program node
func NewProgram(declarations []Declaration, pos Position) *Program {
	return &Program{
		BaseNode:     BaseNode{Position: pos},
		Declarations: declarations,
	}
}

// NewIdentifier creates a new Identifier node
func NewIdentifier(name string, pos Position) *Identifier {
	return &Identifier{
		NamedNode: NewNamedNode(name, pos),
	}
}

// NewTypedID creates a new TypedID node
func NewTypedID(name string, typ TypeAnnotation, pos Position) *TypedID {
	return &TypedID{
		NamedNode: NewNamedNode(name, pos),
		Type:      typ,
	}
}

// NewStringLiteral creates a new StringLiteral node
func NewStringLiteral(parts []StringPart, kind StringKind, pos Position) *StringLiteral {
	return &StringLiteral{
		TypedNode: TypedNode{BaseNode: BaseNode{Position: pos}},
		Parts:     parts,
		Kind:      kind,
	}
}

// NewNumberLiteral creates a new NumberLiteral node
func NewNumberLiteral(value string, kind NumberKind, pos Position) *NumberLiteral {
	return &NumberLiteral{
		TypedNode: TypedNode{BaseNode: BaseNode{Position: pos}},
		Value:     value,
		Kind:      kind,
	}
}

// NewBooleanLiteral creates a new BooleanLiteral node
func NewBooleanLiteral(value bool, pos Position) *BooleanLiteral {
	return &BooleanLiteral{
		TypedNode: TypedNode{BaseNode: BaseNode{Position: pos}},
		Value:     value,
	}
}

// NewBinaryExpr creates a new BinaryExpr node
func NewBinaryExpr(left Expression, op BinaryOp, right Expression, pos Position) *BinaryExpr {
	return &BinaryExpr{
		TypedNode: TypedNode{BaseNode: BaseNode{Position: pos}},
		Left:      left,
		Op:        op,
		Right:     right,
	}
}

// NewCallExpr creates a new CallExpr node
func NewCallExpr(fn Expression, args []Expression, pos Position) *CallExpr {
	return &CallExpr{
		TypedNode: TypedNode{BaseNode: BaseNode{Position: pos}},
		Func:      fn,
		Args:      args,
	}
}

// NewCodeBlock creates a new CodeBlock node
func NewCodeBlock(stmts []Statement, pos Position) *CodeBlock {
	return &CodeBlock{
		BaseNode: BaseNode{Position: pos},
		Stmts:    stmts,
	}
}

// Helper functions for checking node types

// IsLiteral checks if an expression is a literal
func IsLiteral(expr Expression) bool {
	switch expr.(type) {
	case *StringLiteral, *NumberLiteral, *BooleanLiteral, *NullLiteral, *VoidLiteral,
		*ArrayLiteral, *ObjectLiteral, *MapLiteral, *SetLiteral, *TaggedBlockString:
		return true
	default:
		return false
	}
}

// IsStatement checks if a node implements Statement
func IsStatement(node Node) bool {
	_, ok := node.(Statement)
	return ok
}

// IsExpression checks if a node implements Expression
func IsExpression(node Node) bool {
	_, ok := node.(Expression)
	return ok
}

// IsDeclaration checks if a node implements Declaration
func IsDeclaration(node Node) bool {
	_, ok := node.(Declaration)
	return ok
}

// Visitor helper functions
// Walk traverses the AST using the visitor pattern
func Walk(root Node, visitor Visitor) {
	if root != nil {
		root.Accept(visitor)
	}
}

// SimpleVisitor is a helper visitor that calls a function on each node
type SimpleVisitor struct {
	Fn func(Node)
}

func (v *SimpleVisitor) Visit(node Node) Visitor {
	v.Fn(node)
	return v
}

// NewSimpleVisitor creates a visitor that calls fn on each node
func NewSimpleVisitor(fn func(Node)) *SimpleVisitor {
	return &SimpleVisitor{Fn: fn}
}

// Inspect is a convenience function for walking the tree with a simple function
func Inspect(root Node, fn func(Node)) {
	Walk(root, NewSimpleVisitor(fn))
}

// PrintAST prints the AST with proper indentation for readability
func PrintAST(root Node) string {
	if root == nil {
		return ""
	}

	var result strings.Builder
	printer := &ASTPrinter{builder: &result}
	Walk(root, printer)
	return result.String()
}

type ASTPrinter struct {
	builder *strings.Builder
	depth   int
}

func (p *ASTPrinter) Visit(node Node) Visitor {
	if node == nil {
		return p
	}

	indent := strings.Repeat("  ", p.depth)
	nodeType := fmt.Sprintf("%T", node)
	// Remove package prefix for cleaner output
	if idx := strings.LastIndex(nodeType, "."); idx != -1 {
		nodeType = nodeType[idx+1:]
	}

	p.builder.WriteString(indent)
	p.builder.WriteString(nodeType)

	// Use reflection to extract useful information generically
	p.addNodeInfo(node)
	p.builder.WriteString(fmt.Sprintf(" @%s\n", node.Pos().String()))

	// Create new visitor with increased depth for children
	return &ASTPrinter{
		builder: p.builder,
		depth:   p.depth + 1,
	}
}

func (p *ASTPrinter) addNodeInfo(node Node) {
	v := reflect.ValueOf(node)
	if v.Kind() == reflect.Ptr {
		v = v.Elem()
	}
	if v.Kind() != reflect.Struct {
		return
	}

	t := v.Type()
	var info []string

	for i := 0; i < v.NumField(); i++ {
		field := v.Field(i)
		fieldType := t.Field(i)
		fieldName := fieldType.Name

		// Skip unexported fields and base fields
		if !field.CanInterface() || fieldName == "BaseNode" || fieldName == "NamedNode" {
			continue
		}

		switch fieldName {
		case "Name":
			if field.Kind() == reflect.String && field.String() != "" {
				info = append(info, fmt.Sprintf("name='%s'", field.String()))
			}
		case "Value":
			if field.Kind() == reflect.String {
				info = append(info, fmt.Sprintf("value='%s'", field.String()))
			} else if field.Kind() == reflect.Bool {
				info = append(info, fmt.Sprintf("value=%t", field.Bool()))
			}
		case "Op", "Operator":
			info = append(info, fmt.Sprintf("op=%s", p.getOpString(field)))
		case "Kind":
			info = append(info, fmt.Sprintf("kind=%s", p.getKindString(field)))
		case "Content":
			if field.Kind() == reflect.String && field.String() != "" {
				info = append(info, fmt.Sprintf("content='%s'", field.String()))
			}
		case "TypeName":
			if field.Kind() == reflect.String && field.String() != "" {
				info = append(info, fmt.Sprintf("type='%s'", field.String()))
			}
		case "Interface":
			if field.Kind() == reflect.String && field.String() != "" {
				info = append(info, fmt.Sprintf("interface='%s'", field.String()))
			}
		}

		// Handle slice fields to show counts
		if field.Kind() == reflect.Slice {
			count := field.Len()
			sliceName := strings.ToLower(fieldName)
			if strings.HasSuffix(sliceName, "s") {
				sliceName = sliceName[:len(sliceName)-1] // Remove trailing 's'
			}
			if count > 0 {
				info = append(info, fmt.Sprintf("(%d %ss)", count, sliceName))
			}
		}
	}

	if len(info) > 0 {
		p.builder.WriteString(" ")
		p.builder.WriteString(strings.Join(info, " "))
	}
}

func (p *ASTPrinter) getOpString(field reflect.Value) string {
	// Handle different operator types generically
	if field.Kind() == reflect.Int {
		opVal := int(field.Int())
		// Try to convert common operator enums to strings
		switch field.Type().Name() {
		case "BinaryOp":
			return binaryOpString(BinaryOp(opVal))
		case "UnaryOp":
			return unaryOpString(UnaryOp(opVal))
		case "AssignmentOp":
			return assignmentOpString(AssignmentOp(opVal))
		}
	}
	return fmt.Sprintf("%v", field.Interface())
}

func (p *ASTPrinter) getKindString(field reflect.Value) string {
	// Handle different kind types generically
	if field.Kind() == reflect.Int {
		kindVal := int(field.Int())
		switch field.Type().Name() {
		case "NumberKind":
			return numberKindString(NumberKind(kindVal))
		case "StringKind":
			return stringKindString(StringKind(kindVal))
		}
	}
	return fmt.Sprintf("%v", field.Interface())
}

// Helper functions for enum to string conversion
func numberKindString(kind NumberKind) string {
	switch kind {
	case Integer:
		return "Integer"
	case Float:
		return "Float"
	case Hex:
		return "Hex"
	case Binary:
		return "Binary"
	case Octal:
		return "Octal"
	default:
		return "Unknown"
	}
}

func stringKindString(kind StringKind) string {
	switch kind {
	case SingleQuoted:
		return "SingleQuoted"
	case DoubleQuoted:
		return "DoubleQuoted"
	case MultiQuoted:
		return "MultiQuoted"
	case MultiDoubleQuoted:
		return "MultiDoubleQuoted"
	default:
		return "Unknown"
	}
}

func binaryOpString(op BinaryOp) string {
	switch op {
	case LogicalOr:
		return "||"
	case LogicalAnd:
		return "&&"
	case BitwiseXor:
		return "^"
	case BitwiseAnd:
		return "&"
	case Equal:
		return "=="
	case NotEqual:
		return "!="
	case Less:
		return "<"
	case LessEqual:
		return "<="
	case Greater:
		return ">"
	case GreaterEqual:
		return ">="
	case Add:
		return "+"
	case Subtract:
		return "-"
	case Multiply:
		return "*"
	case Divide:
		return "/"
	case Modulo:
		return "%"
	default:
		return "Unknown"
	}
}

func unaryOpString(op UnaryOp) string {
	switch op {
	case UnaryPlus:
		return "+"
	case UnaryMinus:
		return "-"
	case UnaryNot:
		return "!"
	default:
		return "Unknown"
	}
}

func assignmentOpString(op AssignmentOp) string {
	switch op {
	case AssignEq:
		return "="
	case AssignPlusEq:
		return "+="
	case AssignMinusEq:
		return "-="
	case AssignStarEq:
		return "*="
	case AssignSlashEq:
		return "/="
	case AssignModEq:
		return "%="
	case AssignCaretEq:
		return "^="
	default:
		return "Unknown"
	}
}

// TestGenericPrinter shows how the generic printer works with different node types
func TestGenericPrinter() {
	pos := NewPosition(1, 1, 0)

	// Test with a binary expression
	expr := NewBinaryExpr(
		NewNumberLiteral("42", Integer, pos),
		Add,
		NewIdentifier("x", pos),
		pos)

	fmt.Println("Generic printer test:")
	fmt.Print(PrintAST(expr))
}
