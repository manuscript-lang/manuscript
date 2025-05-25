package ast

// ManuscriptVisitor defines a generic visitor interface that can return any type T
// Implementers only need to define visit methods for node types they care about
type ManuscriptVisitor[T any] interface {
	// Declaration visitors
	VisitProgram(node *Program) T
	VisitImportDecl(node *ImportDecl) T
	VisitExportDecl(node *ExportDecl) T
	VisitExternDecl(node *ExternDecl) T
	VisitLetDecl(node *LetDecl) T
	VisitTypeDecl(node *TypeDecl) T
	VisitInterfaceDecl(node *InterfaceDecl) T
	VisitFnDecl(node *FnDecl) T
	VisitMethodsDecl(node *MethodsDecl) T

	// Statement visitors
	VisitCodeBlock(node *CodeBlock) T
	VisitLoopBody(node *LoopBody) T
	VisitExprStmt(node *ExprStmt) T
	VisitReturnStmt(node *ReturnStmt) T
	VisitYieldStmt(node *YieldStmt) T
	VisitDeferStmt(node *DeferStmt) T
	VisitBreakStmt(node *BreakStmt) T
	VisitContinueStmt(node *ContinueStmt) T
	VisitCheckStmt(node *CheckStmt) T
	VisitTryStmt(node *TryStmt) T
	VisitIfStmt(node *IfStmt) T
	VisitForStmt(node *ForStmt) T
	VisitWhileStmt(node *WhileStmt) T
	VisitPipedStmt(node *PipedStmt) T

	// For loop specific visitors
	VisitForTrinityLoop(node *ForTrinityLoop) T
	VisitForInLoop(node *ForInLoop) T
	VisitForInitLet(node *ForInitLet) T

	// Piped statement visitors
	VisitPipedCall(node *PipedCall) T
	VisitPipedArg(node *PipedArg) T

	// Expression visitors
	VisitIdentifier(node *Identifier) T
	VisitBinaryExpr(node *BinaryExpr) T
	VisitUnaryExpr(node *UnaryExpr) T
	VisitCallExpr(node *CallExpr) T
	VisitIndexExpr(node *IndexExpr) T
	VisitDotExpr(node *DotExpr) T
	VisitArrayLiteral(node *ArrayLiteral) T
	VisitObjectLiteral(node *ObjectLiteral) T
	VisitMapLiteral(node *MapLiteral) T
	VisitSetLiteral(node *SetLiteral) T
	VisitFnExpr(node *FnExpr) T
	VisitTernaryExpr(node *TernaryExpr) T
	VisitAssignmentExpr(node *AssignmentExpr) T
	VisitParenExpr(node *ParenExpr) T
	VisitVoidExpr(node *VoidExpr) T
	VisitNullExpr(node *NullExpr) T
	VisitTryExpr(node *TryExpr) T
	VisitMatchExpr(node *MatchExpr) T
	VisitStructInitExpr(node *StructInitExpr) T

	// Match expression visitors
	VisitCaseClause(node *CaseClause) T
	VisitDefaultClause(node *DefaultClause) T
	VisitCaseExpr(node *CaseExpr) T
	VisitCaseBlock(node *CaseBlock) T

	// Struct init visitors
	VisitStructField(node *StructField) T

	// Object literal visitors
	VisitObjectField(node *ObjectField) T

	// Map literal visitors
	VisitMapField(node *MapField) T

	// Literal visitors
	VisitStringLiteral(node *StringLiteral) T
	VisitNumberLiteral(node *NumberLiteral) T
	VisitBooleanLiteral(node *BooleanLiteral) T
	VisitNullLiteral(node *NullLiteral) T
	VisitVoidLiteral(node *VoidLiteral) T

	// String part visitors
	VisitStringContent(node *StringContent) T
	VisitStringInterpolation(node *StringInterpolation) T

	// Type annotation visitors
	VisitTypeSpec(node *TypeSpec) T

	// Let declaration subtype visitors
	VisitLetSingle(node *LetSingle) T
	VisitLetBlock(node *LetBlock) T
	VisitLetBlockItemSingle(node *LetBlockItemSingle) T
	VisitLetBlockItemDestructuredObj(node *LetBlockItemDestructuredObj) T
	VisitLetBlockItemDestructuredArray(node *LetBlockItemDestructuredArray) T
	VisitLetDestructuredObj(node *LetDestructuredObj) T
	VisitLetDestructuredArray(node *LetDestructuredArray) T
	VisitTypedID(node *TypedID) T

	// Type declaration subtype visitors
	VisitTypeDefBody(node *TypeDefBody) T
	VisitTypeAlias(node *TypeAlias) T
	VisitFieldDecl(node *FieldDecl) T
	VisitInterfaceMethod(node *InterfaceMethod) T

	// Import/Export subtype visitors
	VisitDestructuredImport(node *DestructuredImport) T
	VisitTargetImport(node *TargetImport) T
	VisitImportItem(node *ImportItem) T

	// Function parameter and method visitors
	VisitParameter(node *Parameter) T
	VisitMethodImpl(node *MethodImpl) T

	// Object field subtype visitors
	VisitObjectFieldID(node *ObjectFieldID) T
	VisitObjectFieldString(node *ObjectFieldString) T
}

// Visit is the central dispatch function that routes to appropriate visit methods
// This handles all the type switching so implementers don't have to
func (visitor *BaseManuscriptVisitor[T]) Visit(node Node) T {
	return DispatchVisit(visitor, node)
}

// DispatchVisit is a generic dispatch function that can be used by any visitor implementation
func DispatchVisit[T any](visitor ManuscriptVisitor[T], node Node) T {
	if node == nil {
		var zero T
		return zero
	}

	// Dispatch to appropriate visit method based on node type
	switch n := node.(type) {
	// Program
	case *Program:
		return visitor.VisitProgram(n)

	// Declaration visitors
	case *ImportDecl:
		return visitor.VisitImportDecl(n)
	case *ExportDecl:
		return visitor.VisitExportDecl(n)
	case *ExternDecl:
		return visitor.VisitExternDecl(n)
	case *LetDecl:
		return visitor.VisitLetDecl(n)
	case *TypeDecl:
		return visitor.VisitTypeDecl(n)
	case *InterfaceDecl:
		return visitor.VisitInterfaceDecl(n)
	case *FnDecl:
		return visitor.VisitFnDecl(n)
	case *MethodsDecl:
		return visitor.VisitMethodsDecl(n)

	// Statement visitors
	case *CodeBlock:
		return visitor.VisitCodeBlock(n)
	case *LoopBody:
		return visitor.VisitLoopBody(n)
	case *ExprStmt:
		return visitor.VisitExprStmt(n)
	case *ReturnStmt:
		return visitor.VisitReturnStmt(n)
	case *YieldStmt:
		return visitor.VisitYieldStmt(n)
	case *DeferStmt:
		return visitor.VisitDeferStmt(n)
	case *BreakStmt:
		return visitor.VisitBreakStmt(n)
	case *ContinueStmt:
		return visitor.VisitContinueStmt(n)
	case *CheckStmt:
		return visitor.VisitCheckStmt(n)
	case *TryStmt:
		return visitor.VisitTryStmt(n)

	// Control flow statements
	case *IfStmt:
		return visitor.VisitIfStmt(n)
	case *ForStmt:
		return visitor.VisitForStmt(n)
	case *WhileStmt:
		return visitor.VisitWhileStmt(n)

	// For loop specific visitors
	case *ForTrinityLoop:
		return visitor.VisitForTrinityLoop(n)
	case *ForInLoop:
		return visitor.VisitForInLoop(n)
	case *ForInitLet:
		return visitor.VisitForInitLet(n)

	// Piped statement visitors
	case *PipedStmt:
		return visitor.VisitPipedStmt(n)
	case *PipedCall:
		return visitor.VisitPipedCall(n)
	case *PipedArg:
		return visitor.VisitPipedArg(n)

	// Primary expressions
	case *Identifier:
		return visitor.VisitIdentifier(n)
	case *ParenExpr:
		return visitor.VisitParenExpr(n)
	case *VoidExpr:
		return visitor.VisitVoidExpr(n)
	case *NullExpr:
		return visitor.VisitNullExpr(n)

	// Binary and unary expressions
	case *BinaryExpr:
		return visitor.VisitBinaryExpr(n)
	case *UnaryExpr:
		return visitor.VisitUnaryExpr(n)
	case *TernaryExpr:
		return visitor.VisitTernaryExpr(n)
	case *AssignmentExpr:
		return visitor.VisitAssignmentExpr(n)

	// Postfix expressions
	case *CallExpr:
		return visitor.VisitCallExpr(n)
	case *IndexExpr:
		return visitor.VisitIndexExpr(n)
	case *DotExpr:
		return visitor.VisitDotExpr(n)

	// Literal expressions
	case *ArrayLiteral:
		return visitor.VisitArrayLiteral(n)
	case *ObjectLiteral:
		return visitor.VisitObjectLiteral(n)
	case *MapLiteral:
		return visitor.VisitMapLiteral(n)
	case *SetLiteral:
		return visitor.VisitSetLiteral(n)
	case *StringLiteral:
		return visitor.VisitStringLiteral(n)
	case *NumberLiteral:
		return visitor.VisitNumberLiteral(n)
	case *BooleanLiteral:
		return visitor.VisitBooleanLiteral(n)
	case *NullLiteral:
		return visitor.VisitNullLiteral(n)
	case *VoidLiteral:
		return visitor.VisitVoidLiteral(n)

	// Complex expressions
	case *FnExpr:
		return visitor.VisitFnExpr(n)
	case *TryExpr:
		return visitor.VisitTryExpr(n)
	case *MatchExpr:
		return visitor.VisitMatchExpr(n)
	case *StructInitExpr:
		return visitor.VisitStructInitExpr(n)

	// Match expression components
	case *CaseClause:
		return visitor.VisitCaseClause(n)
	case *DefaultClause:
		return visitor.VisitDefaultClause(n)
	case *CaseExpr:
		return visitor.VisitCaseExpr(n)
	case *CaseBlock:
		return visitor.VisitCaseBlock(n)

	// Literal component visitors
	case *StructField:
		return visitor.VisitStructField(n)
	case *ObjectField:
		return visitor.VisitObjectField(n)
	case *MapField:
		return visitor.VisitMapField(n)

	// String literal components
	case *StringContent:
		return visitor.VisitStringContent(n)
	case *StringInterpolation:
		return visitor.VisitStringInterpolation(n)

	// Type annotation visitors
	case *TypeSpec:
		return visitor.VisitTypeSpec(n)

	// Let declaration components
	case *LetSingle:
		return visitor.VisitLetSingle(n)
	case *LetBlock:
		return visitor.VisitLetBlock(n)
	case *LetBlockItemSingle:
		return visitor.VisitLetBlockItemSingle(n)
	case *LetBlockItemDestructuredObj:
		return visitor.VisitLetBlockItemDestructuredObj(n)
	case *LetBlockItemDestructuredArray:
		return visitor.VisitLetBlockItemDestructuredArray(n)
	case *LetDestructuredObj:
		return visitor.VisitLetDestructuredObj(n)
	case *LetDestructuredArray:
		return visitor.VisitLetDestructuredArray(n)
	case *TypedID:
		return visitor.VisitTypedID(n)

	// Type declaration components
	case *TypeDefBody:
		return visitor.VisitTypeDefBody(n)
	case *TypeAlias:
		return visitor.VisitTypeAlias(n)
	case *FieldDecl:
		return visitor.VisitFieldDecl(n)
	case *InterfaceMethod:
		return visitor.VisitInterfaceMethod(n)

	// Import/Export components
	case *DestructuredImport:
		return visitor.VisitDestructuredImport(n)
	case *TargetImport:
		return visitor.VisitTargetImport(n)
	case *ImportItem:
		return visitor.VisitImportItem(n)

	// Function parameter and method visitors
	case *Parameter:
		return visitor.VisitParameter(n)
	case *MethodImpl:
		return visitor.VisitMethodImpl(n)

	// Object field subtype visitors
	case *ObjectFieldID:
		return visitor.VisitObjectFieldID(n)
	case *ObjectFieldString:
		return visitor.VisitObjectFieldString(n)

	default:
		var zero T
		return zero
	}
}

// BaseManuscriptVisitor provides a default implementation that returns the zero value for type T
// Users can embed this and only override methods they need
type BaseManuscriptVisitor[T any] struct{}

func (v *BaseManuscriptVisitor[T]) VisitProgram(node *Program) T             { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitImportDecl(node *ImportDecl) T       { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitExportDecl(node *ExportDecl) T       { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitExternDecl(node *ExternDecl) T       { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitLetDecl(node *LetDecl) T             { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitTypeDecl(node *TypeDecl) T           { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitInterfaceDecl(node *InterfaceDecl) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitFnDecl(node *FnDecl) T               { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitMethodsDecl(node *MethodsDecl) T     { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitCodeBlock(node *CodeBlock) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitLoopBody(node *LoopBody) T           { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitExprStmt(node *ExprStmt) T           { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitReturnStmt(node *ReturnStmt) T       { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitYieldStmt(node *YieldStmt) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitDeferStmt(node *DeferStmt) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitBreakStmt(node *BreakStmt) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitContinueStmt(node *ContinueStmt) T   { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitCheckStmt(node *CheckStmt) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitTryStmt(node *TryStmt) T             { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitIfStmt(node *IfStmt) T               { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitForStmt(node *ForStmt) T             { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitWhileStmt(node *WhileStmt) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitPipedStmt(node *PipedStmt) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitForTrinityLoop(node *ForTrinityLoop) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitForInLoop(node *ForInLoop) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitForInitLet(node *ForInitLet) T       { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitPipedCall(node *PipedCall) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitPipedArg(node *PipedArg) T           { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitIdentifier(node *Identifier) T       { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitBinaryExpr(node *BinaryExpr) T       { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitUnaryExpr(node *UnaryExpr) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitCallExpr(node *CallExpr) T           { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitIndexExpr(node *IndexExpr) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitDotExpr(node *DotExpr) T             { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitArrayLiteral(node *ArrayLiteral) T   { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitObjectLiteral(node *ObjectLiteral) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitMapLiteral(node *MapLiteral) T       { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitSetLiteral(node *SetLiteral) T       { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitFnExpr(node *FnExpr) T               { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitTernaryExpr(node *TernaryExpr) T     { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitAssignmentExpr(node *AssignmentExpr) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitParenExpr(node *ParenExpr) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitVoidExpr(node *VoidExpr) T   { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitNullExpr(node *NullExpr) T   { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitTryExpr(node *TryExpr) T     { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitMatchExpr(node *MatchExpr) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitStructInitExpr(node *StructInitExpr) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitCaseClause(node *CaseClause) T       { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitDefaultClause(node *DefaultClause) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitCaseExpr(node *CaseExpr) T           { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitCaseBlock(node *CaseBlock) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitStructField(node *StructField) T     { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitObjectField(node *ObjectField) T     { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitMapField(node *MapField) T           { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitStringLiteral(node *StringLiteral) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitNumberLiteral(node *NumberLiteral) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitBooleanLiteral(node *BooleanLiteral) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitNullLiteral(node *NullLiteral) T     { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitVoidLiteral(node *VoidLiteral) T     { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitStringContent(node *StringContent) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitStringInterpolation(node *StringInterpolation) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitTypeSpec(node *TypeSpec) T   { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitLetSingle(node *LetSingle) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitLetBlock(node *LetBlock) T   { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitLetBlockItemSingle(node *LetBlockItemSingle) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitLetBlockItemDestructuredObj(node *LetBlockItemDestructuredObj) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitLetBlockItemDestructuredArray(node *LetBlockItemDestructuredArray) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitLetDestructuredObj(node *LetDestructuredObj) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitLetDestructuredArray(node *LetDestructuredArray) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitTypedID(node *TypedID) T         { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitTypeDefBody(node *TypeDefBody) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitTypeAlias(node *TypeAlias) T     { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitFieldDecl(node *FieldDecl) T     { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitInterfaceMethod(node *InterfaceMethod) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitDestructuredImport(node *DestructuredImport) T {
	var zero T
	return zero
}
func (v *BaseManuscriptVisitor[T]) VisitTargetImport(node *TargetImport) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitImportItem(node *ImportItem) T     { var zero T; return zero }

// Function parameter and method visitors
func (v *BaseManuscriptVisitor[T]) VisitParameter(node *Parameter) T   { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitMethodImpl(node *MethodImpl) T { var zero T; return zero }

// Object field subtype visitors
func (v *BaseManuscriptVisitor[T]) VisitObjectFieldID(node *ObjectFieldID) T { var zero T; return zero }
func (v *BaseManuscriptVisitor[T]) VisitObjectFieldString(node *ObjectFieldString) T {
	var zero T
	return zero
}
