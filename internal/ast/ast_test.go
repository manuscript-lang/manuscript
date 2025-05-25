package ast

import (
	"testing"
)

func TestBasicASTConstruction(t *testing.T) {
	pos := NewPosition(1, 1, 0)

	// Create a simple let declaration: let x: int = 42
	letDecl := &LetDecl{
		BaseNode: NewBaseNode(pos),
		Items: []LetItem{
			&LetSingle{
				BaseNode: NewBaseNode(pos),
				ID:       *NewTypedID("x", NewSimpleType("int"), pos),
				Value:    NewNumberLiteral("42", Integer, pos),
			},
		},
	}

	program := NewProgram([]Declaration{letDecl}, pos)

	// Test basic properties
	if program.Pos().Line != 1 {
		t.Errorf("Expected line 1, got %d", program.Pos().Line)
	}

	if len(program.Declarations) != 1 {
		t.Errorf("Expected 1 declaration, got %d", len(program.Declarations))
	}
}

func TestVisitorPattern(t *testing.T) {
	pos := NewPosition(1, 1, 0)

	// Create AST: let x: int = 42 + 10
	program := NewProgram([]Declaration{
		&LetDecl{
			BaseNode: NewBaseNode(pos),
			Items: []LetItem{
				&LetSingle{
					BaseNode: NewBaseNode(pos),
					ID:       *NewTypedID("x", NewSimpleType("int"), pos),
					Value: NewBinaryExpr(
						NewNumberLiteral("42", Integer, pos),
						Add,
						NewNumberLiteral("10", Integer, pos),
						pos,
					),
				},
			},
		},
	}, pos)

	// Test node counting
	nodeCount := 0
	Inspect(program, func(node Node) {
		nodeCount++
	})

	if nodeCount != 8 {
		t.Errorf("Expected nodes to be visited, got")
	}
}

func TestPrettyPrinter(t *testing.T) {
	pos := NewPosition(1, 1, 0)

	// Simple program with identifier
	NewProgram([]Declaration{
		&LetDecl{
			BaseNode: NewBaseNode(pos),
			Items: []LetItem{
				&LetSingle{
					BaseNode: NewBaseNode(pos),
					ID:       *NewTypedID("x", NewSimpleType("int"), pos),
					Value:    NewNumberLiteral("42", Integer, pos),
				},
			},
		},
	}, pos)

}

func TestBaseAndNamedNodes(t *testing.T) {
	pos := NewPosition(10, 5, 100)

	// Test BaseNode
	base := NewBaseNode(pos)
	if base.Pos().Line != 10 || base.Pos().Column != 5 || base.Pos().Offset != 100 {
		t.Errorf("BaseNode position not set correctly")
	}

	// Test NamedNode
	named := NewNamedNode("testName", pos)
	if named.Name != "testName" {
		t.Errorf("Expected name 'testName', got '%s'", named.Name)
	}
	if named.Pos().Line != 10 {
		t.Errorf("NamedNode position not inherited correctly")
	}
}

func TestConstructors(t *testing.T) {
	pos := NewPosition(1, 1, 0)

	// Test various constructors
	id := NewIdentifier("test", pos)
	if id.Name != "test" {
		t.Errorf("NewIdentifier failed")
	}

	num := NewNumberLiteral("123", Integer, pos)
	if num.Value != "123" || num.Kind != Integer {
		t.Errorf("NewNumberLiteral failed")
	}

	bool := NewBooleanLiteral(true, pos)
	if !bool.Value {
		t.Errorf("NewBooleanLiteral failed")
	}

	// Test that all created nodes implement Node interface
	var nodes []Node = []Node{id, num, bool}
	for i, node := range nodes {
		if node.Pos().Line != 1 {
			t.Errorf("Node %d does not implement Node interface correctly", i)
		}
		// Test GetNodeType instead of String() method
	}
}

func TestTypeAnnotations(t *testing.T) {
	// Test simple type
	intType := NewSimpleType("int")
	if !intType.IsSimple() {
		t.Errorf("Expected simple type")
	}
	if intType.GetTypeName() != "int" {
		t.Errorf("Expected type name 'int', got '%s'", intType.GetTypeName())
	}

	// Test array type
	arrayType := NewArrayType(NewSimpleType("string"))
	if arrayType.Kind != ArrayType {
		t.Errorf("Expected ArrayType")
	}
	if arrayType.GetTypeName() != "string[]" {
		t.Errorf("Expected type name 'string[]', got '%s'", arrayType.GetTypeName())
	}

	// Test optional type
	optionalType := NewOptionalType(NewSimpleType("int"))
	if !optionalType.IsOptional {
		t.Errorf("Expected optional type")
	}
	if !optionalType.IsSimple() {
		t.Errorf("Expected simple type under optional")
	}

	// Test throwing type
	throwingType := NewThrowingType(NewSimpleType("string"))
	if !throwingType.CanThrow {
		t.Errorf("Expected throwing type")
	}

	// Test function type
	fnType := NewFunctionType([]Parameter{}, NewSimpleType("int"))
	if !fnType.IsFunction() {
		t.Errorf("Expected function type")
	}
	if fnType.GetTypeName() != "fn" {
		t.Errorf("Expected type name 'fn', got '%s'", fnType.GetTypeName())
	}

	// Test void type
	voidType := NewVoidType()
	if !voidType.IsVoid() {
		t.Errorf("Expected void type")
	}
	if voidType.GetTypeName() != "void" {
		t.Errorf("Expected type name 'void', got '%s'", voidType.GetTypeName())
	}
}
