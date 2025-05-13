// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript

import "github.com/antlr4-go/antlr/v4"

// BaseManuscriptListener is a complete listener for a parse tree produced by Manuscript.
type BaseManuscriptListener struct{}

var _ ManuscriptListener = &BaseManuscriptListener{}

// VisitTerminal is called when a terminal node is visited.
func (s *BaseManuscriptListener) VisitTerminal(node antlr.TerminalNode) {}

// VisitErrorNode is called when an error node is visited.
func (s *BaseManuscriptListener) VisitErrorNode(node antlr.ErrorNode) {}

// EnterEveryRule is called when any rule is entered.
func (s *BaseManuscriptListener) EnterEveryRule(ctx antlr.ParserRuleContext) {}

// ExitEveryRule is called when any rule is exited.
func (s *BaseManuscriptListener) ExitEveryRule(ctx antlr.ParserRuleContext) {}

// EnterProgram is called when production program is entered.
func (s *BaseManuscriptListener) EnterProgram(ctx *ProgramContext) {}

// ExitProgram is called when production program is exited.
func (s *BaseManuscriptListener) ExitProgram(ctx *ProgramContext) {}

// EnterProgramItem is called when production programItem is entered.
func (s *BaseManuscriptListener) EnterProgramItem(ctx *ProgramItemContext) {}

// ExitProgramItem is called when production programItem is exited.
func (s *BaseManuscriptListener) ExitProgramItem(ctx *ProgramItemContext) {}

// EnterImportStmt is called when production importStmt is entered.
func (s *BaseManuscriptListener) EnterImportStmt(ctx *ImportStmtContext) {}

// ExitImportStmt is called when production importStmt is exited.
func (s *BaseManuscriptListener) ExitImportStmt(ctx *ImportStmtContext) {}

// EnterImportItem is called when production importItem is entered.
func (s *BaseManuscriptListener) EnterImportItem(ctx *ImportItemContext) {}

// ExitImportItem is called when production importItem is exited.
func (s *BaseManuscriptListener) ExitImportItem(ctx *ImportItemContext) {}

// EnterExternStmt is called when production externStmt is entered.
func (s *BaseManuscriptListener) EnterExternStmt(ctx *ExternStmtContext) {}

// ExitExternStmt is called when production externStmt is exited.
func (s *BaseManuscriptListener) ExitExternStmt(ctx *ExternStmtContext) {}

// EnterExternItem is called when production externItem is entered.
func (s *BaseManuscriptListener) EnterExternItem(ctx *ExternItemContext) {}

// ExitExternItem is called when production externItem is exited.
func (s *BaseManuscriptListener) ExitExternItem(ctx *ExternItemContext) {}

// EnterExportStmt is called when production exportStmt is entered.
func (s *BaseManuscriptListener) EnterExportStmt(ctx *ExportStmtContext) {}

// ExitExportStmt is called when production exportStmt is exited.
func (s *BaseManuscriptListener) ExitExportStmt(ctx *ExportStmtContext) {}

// EnterLetDecl is called when production letDecl is entered.
func (s *BaseManuscriptListener) EnterLetDecl(ctx *LetDeclContext) {}

// ExitLetDecl is called when production letDecl is exited.
func (s *BaseManuscriptListener) ExitLetDecl(ctx *LetDeclContext) {}

// EnterLetAssignment is called when production letAssignment is entered.
func (s *BaseManuscriptListener) EnterLetAssignment(ctx *LetAssignmentContext) {}

// ExitLetAssignment is called when production letAssignment is exited.
func (s *BaseManuscriptListener) ExitLetAssignment(ctx *LetAssignmentContext) {}

// EnterLetPattern is called when production letPattern is entered.
func (s *BaseManuscriptListener) EnterLetPattern(ctx *LetPatternContext) {}

// ExitLetPattern is called when production letPattern is exited.
func (s *BaseManuscriptListener) ExitLetPattern(ctx *LetPatternContext) {}

// EnterArrayPattn is called when production arrayPattn is entered.
func (s *BaseManuscriptListener) EnterArrayPattn(ctx *ArrayPattnContext) {}

// ExitArrayPattn is called when production arrayPattn is exited.
func (s *BaseManuscriptListener) ExitArrayPattn(ctx *ArrayPattnContext) {}

// EnterObjectPattn is called when production objectPattn is entered.
func (s *BaseManuscriptListener) EnterObjectPattn(ctx *ObjectPattnContext) {}

// ExitObjectPattn is called when production objectPattn is exited.
func (s *BaseManuscriptListener) ExitObjectPattn(ctx *ObjectPattnContext) {}

// EnterFnDecl is called when production fnDecl is entered.
func (s *BaseManuscriptListener) EnterFnDecl(ctx *FnDeclContext) {}

// ExitFnDecl is called when production fnDecl is exited.
func (s *BaseManuscriptListener) ExitFnDecl(ctx *FnDeclContext) {}

// EnterParameters is called when production parameters is entered.
func (s *BaseManuscriptListener) EnterParameters(ctx *ParametersContext) {}

// ExitParameters is called when production parameters is exited.
func (s *BaseManuscriptListener) ExitParameters(ctx *ParametersContext) {}

// EnterParam is called when production param is entered.
func (s *BaseManuscriptListener) EnterParam(ctx *ParamContext) {}

// ExitParam is called when production param is exited.
func (s *BaseManuscriptListener) ExitParam(ctx *ParamContext) {}

// EnterTypeDecl is called when production typeDecl is entered.
func (s *BaseManuscriptListener) EnterTypeDecl(ctx *TypeDeclContext) {}

// ExitTypeDecl is called when production typeDecl is exited.
func (s *BaseManuscriptListener) ExitTypeDecl(ctx *TypeDeclContext) {}

// EnterFieldDecl is called when production fieldDecl is entered.
func (s *BaseManuscriptListener) EnterFieldDecl(ctx *FieldDeclContext) {}

// ExitFieldDecl is called when production fieldDecl is exited.
func (s *BaseManuscriptListener) ExitFieldDecl(ctx *FieldDeclContext) {}

// EnterIfaceDecl is called when production ifaceDecl is entered.
func (s *BaseManuscriptListener) EnterIfaceDecl(ctx *IfaceDeclContext) {}

// ExitIfaceDecl is called when production ifaceDecl is exited.
func (s *BaseManuscriptListener) ExitIfaceDecl(ctx *IfaceDeclContext) {}

// EnterMethodDecl is called when production methodDecl is entered.
func (s *BaseManuscriptListener) EnterMethodDecl(ctx *MethodDeclContext) {}

// ExitMethodDecl is called when production methodDecl is exited.
func (s *BaseManuscriptListener) ExitMethodDecl(ctx *MethodDeclContext) {}

// EnterMethodBlockDecl is called when production methodBlockDecl is entered.
func (s *BaseManuscriptListener) EnterMethodBlockDecl(ctx *MethodBlockDeclContext) {}

// ExitMethodBlockDecl is called when production methodBlockDecl is exited.
func (s *BaseManuscriptListener) ExitMethodBlockDecl(ctx *MethodBlockDeclContext) {}

// EnterMethodImpl is called when production methodImpl is entered.
func (s *BaseManuscriptListener) EnterMethodImpl(ctx *MethodImplContext) {}

// ExitMethodImpl is called when production methodImpl is exited.
func (s *BaseManuscriptListener) ExitMethodImpl(ctx *MethodImplContext) {}

// EnterTypeAnnotation is called when production typeAnnotation is entered.
func (s *BaseManuscriptListener) EnterTypeAnnotation(ctx *TypeAnnotationContext) {}

// ExitTypeAnnotation is called when production typeAnnotation is exited.
func (s *BaseManuscriptListener) ExitTypeAnnotation(ctx *TypeAnnotationContext) {}

// EnterBaseTypeAnnotation is called when production baseTypeAnnotation is entered.
func (s *BaseManuscriptListener) EnterBaseTypeAnnotation(ctx *BaseTypeAnnotationContext) {}

// ExitBaseTypeAnnotation is called when production baseTypeAnnotation is exited.
func (s *BaseManuscriptListener) ExitBaseTypeAnnotation(ctx *BaseTypeAnnotationContext) {}

// EnterFunctionType is called when production functionType is entered.
func (s *BaseManuscriptListener) EnterFunctionType(ctx *FunctionTypeContext) {}

// ExitFunctionType is called when production functionType is exited.
func (s *BaseManuscriptListener) ExitFunctionType(ctx *FunctionTypeContext) {}

// EnterStmt is called when production stmt is entered.
func (s *BaseManuscriptListener) EnterStmt(ctx *StmtContext) {}

// ExitStmt is called when production stmt is exited.
func (s *BaseManuscriptListener) ExitStmt(ctx *StmtContext) {}

// EnterExprStmt is called when production exprStmt is entered.
func (s *BaseManuscriptListener) EnterExprStmt(ctx *ExprStmtContext) {}

// ExitExprStmt is called when production exprStmt is exited.
func (s *BaseManuscriptListener) ExitExprStmt(ctx *ExprStmtContext) {}

// EnterReturnStmt is called when production returnStmt is entered.
func (s *BaseManuscriptListener) EnterReturnStmt(ctx *ReturnStmtContext) {}

// ExitReturnStmt is called when production returnStmt is exited.
func (s *BaseManuscriptListener) ExitReturnStmt(ctx *ReturnStmtContext) {}

// EnterYieldStmt is called when production yieldStmt is entered.
func (s *BaseManuscriptListener) EnterYieldStmt(ctx *YieldStmtContext) {}

// ExitYieldStmt is called when production yieldStmt is exited.
func (s *BaseManuscriptListener) ExitYieldStmt(ctx *YieldStmtContext) {}

// EnterIfStmt is called when production ifStmt is entered.
func (s *BaseManuscriptListener) EnterIfStmt(ctx *IfStmtContext) {}

// ExitIfStmt is called when production ifStmt is exited.
func (s *BaseManuscriptListener) ExitIfStmt(ctx *IfStmtContext) {}

// EnterForStmt is called when production forStmt is entered.
func (s *BaseManuscriptListener) EnterForStmt(ctx *ForStmtContext) {}

// ExitForStmt is called when production forStmt is exited.
func (s *BaseManuscriptListener) ExitForStmt(ctx *ForStmtContext) {}

// EnterForInitPattn is called when production forInitPattn is entered.
func (s *BaseManuscriptListener) EnterForInitPattn(ctx *ForInitPattnContext) {}

// ExitForInitPattn is called when production forInitPattn is exited.
func (s *BaseManuscriptListener) ExitForInitPattn(ctx *ForInitPattnContext) {}

// EnterLoopPattern is called when production loopPattern is entered.
func (s *BaseManuscriptListener) EnterLoopPattern(ctx *LoopPatternContext) {}

// ExitLoopPattern is called when production loopPattern is exited.
func (s *BaseManuscriptListener) ExitLoopPattern(ctx *LoopPatternContext) {}

// EnterWhileStmt is called when production whileStmt is entered.
func (s *BaseManuscriptListener) EnterWhileStmt(ctx *WhileStmtContext) {}

// ExitWhileStmt is called when production whileStmt is exited.
func (s *BaseManuscriptListener) ExitWhileStmt(ctx *WhileStmtContext) {}

// EnterCodeBlock is called when production codeBlock is entered.
func (s *BaseManuscriptListener) EnterCodeBlock(ctx *CodeBlockContext) {}

// ExitCodeBlock is called when production codeBlock is exited.
func (s *BaseManuscriptListener) ExitCodeBlock(ctx *CodeBlockContext) {}

// EnterExpr is called when production expr is entered.
func (s *BaseManuscriptListener) EnterExpr(ctx *ExprContext) {}

// ExitExpr is called when production expr is exited.
func (s *BaseManuscriptListener) ExitExpr(ctx *ExprContext) {}

// EnterAssignmentExpr is called when production assignmentExpr is entered.
func (s *BaseManuscriptListener) EnterAssignmentExpr(ctx *AssignmentExprContext) {}

// ExitAssignmentExpr is called when production assignmentExpr is exited.
func (s *BaseManuscriptListener) ExitAssignmentExpr(ctx *AssignmentExprContext) {}

// EnterLogicalOrExpr is called when production logicalOrExpr is entered.
func (s *BaseManuscriptListener) EnterLogicalOrExpr(ctx *LogicalOrExprContext) {}

// ExitLogicalOrExpr is called when production logicalOrExpr is exited.
func (s *BaseManuscriptListener) ExitLogicalOrExpr(ctx *LogicalOrExprContext) {}

// EnterLogicalAndExpr is called when production logicalAndExpr is entered.
func (s *BaseManuscriptListener) EnterLogicalAndExpr(ctx *LogicalAndExprContext) {}

// ExitLogicalAndExpr is called when production logicalAndExpr is exited.
func (s *BaseManuscriptListener) ExitLogicalAndExpr(ctx *LogicalAndExprContext) {}

// EnterEqualityExpr is called when production equalityExpr is entered.
func (s *BaseManuscriptListener) EnterEqualityExpr(ctx *EqualityExprContext) {}

// ExitEqualityExpr is called when production equalityExpr is exited.
func (s *BaseManuscriptListener) ExitEqualityExpr(ctx *EqualityExprContext) {}

// EnterComparisonExpr is called when production comparisonExpr is entered.
func (s *BaseManuscriptListener) EnterComparisonExpr(ctx *ComparisonExprContext) {}

// ExitComparisonExpr is called when production comparisonExpr is exited.
func (s *BaseManuscriptListener) ExitComparisonExpr(ctx *ComparisonExprContext) {}

// EnterAdditiveExpr is called when production additiveExpr is entered.
func (s *BaseManuscriptListener) EnterAdditiveExpr(ctx *AdditiveExprContext) {}

// ExitAdditiveExpr is called when production additiveExpr is exited.
func (s *BaseManuscriptListener) ExitAdditiveExpr(ctx *AdditiveExprContext) {}

// EnterMultiplicativeExpr is called when production multiplicativeExpr is entered.
func (s *BaseManuscriptListener) EnterMultiplicativeExpr(ctx *MultiplicativeExprContext) {}

// ExitMultiplicativeExpr is called when production multiplicativeExpr is exited.
func (s *BaseManuscriptListener) ExitMultiplicativeExpr(ctx *MultiplicativeExprContext) {}

// EnterUnaryExpr is called when production unaryExpr is entered.
func (s *BaseManuscriptListener) EnterUnaryExpr(ctx *UnaryExprContext) {}

// ExitUnaryExpr is called when production unaryExpr is exited.
func (s *BaseManuscriptListener) ExitUnaryExpr(ctx *UnaryExprContext) {}

// EnterAwaitExpr is called when production awaitExpr is entered.
func (s *BaseManuscriptListener) EnterAwaitExpr(ctx *AwaitExprContext) {}

// ExitAwaitExpr is called when production awaitExpr is exited.
func (s *BaseManuscriptListener) ExitAwaitExpr(ctx *AwaitExprContext) {}

// EnterPostfixExpr is called when production postfixExpr is entered.
func (s *BaseManuscriptListener) EnterPostfixExpr(ctx *PostfixExprContext) {}

// ExitPostfixExpr is called when production postfixExpr is exited.
func (s *BaseManuscriptListener) ExitPostfixExpr(ctx *PostfixExprContext) {}

// EnterPrimaryExpr is called when production primaryExpr is entered.
func (s *BaseManuscriptListener) EnterPrimaryExpr(ctx *PrimaryExprContext) {}

// ExitPrimaryExpr is called when production primaryExpr is exited.
func (s *BaseManuscriptListener) ExitPrimaryExpr(ctx *PrimaryExprContext) {}

// EnterFnExpr is called when production fnExpr is entered.
func (s *BaseManuscriptListener) EnterFnExpr(ctx *FnExprContext) {}

// ExitFnExpr is called when production fnExpr is exited.
func (s *BaseManuscriptListener) ExitFnExpr(ctx *FnExprContext) {}

// EnterLambdaExpr is called when production lambdaExpr is entered.
func (s *BaseManuscriptListener) EnterLambdaExpr(ctx *LambdaExprContext) {}

// ExitLambdaExpr is called when production lambdaExpr is exited.
func (s *BaseManuscriptListener) ExitLambdaExpr(ctx *LambdaExprContext) {}

// EnterTryBlockExpr is called when production tryBlockExpr is entered.
func (s *BaseManuscriptListener) EnterTryBlockExpr(ctx *TryBlockExprContext) {}

// ExitTryBlockExpr is called when production tryBlockExpr is exited.
func (s *BaseManuscriptListener) ExitTryBlockExpr(ctx *TryBlockExprContext) {}

// EnterMatchExpr is called when production matchExpr is entered.
func (s *BaseManuscriptListener) EnterMatchExpr(ctx *MatchExprContext) {}

// ExitMatchExpr is called when production matchExpr is exited.
func (s *BaseManuscriptListener) ExitMatchExpr(ctx *MatchExprContext) {}

// EnterCaseClause is called when production caseClause is entered.
func (s *BaseManuscriptListener) EnterCaseClause(ctx *CaseClauseContext) {}

// ExitCaseClause is called when production caseClause is exited.
func (s *BaseManuscriptListener) ExitCaseClause(ctx *CaseClauseContext) {}

// EnterSingleQuotedString is called when production singleQuotedString is entered.
func (s *BaseManuscriptListener) EnterSingleQuotedString(ctx *SingleQuotedStringContext) {}

// ExitSingleQuotedString is called when production singleQuotedString is exited.
func (s *BaseManuscriptListener) ExitSingleQuotedString(ctx *SingleQuotedStringContext) {}

// EnterMultiQuotedString is called when production multiQuotedString is entered.
func (s *BaseManuscriptListener) EnterMultiQuotedString(ctx *MultiQuotedStringContext) {}

// ExitMultiQuotedString is called when production multiQuotedString is exited.
func (s *BaseManuscriptListener) ExitMultiQuotedString(ctx *MultiQuotedStringContext) {}

// EnterStringPart is called when production stringPart is entered.
func (s *BaseManuscriptListener) EnterStringPart(ctx *StringPartContext) {}

// ExitStringPart is called when production stringPart is exited.
func (s *BaseManuscriptListener) ExitStringPart(ctx *StringPartContext) {}

// EnterInterpolation is called when production interpolation is entered.
func (s *BaseManuscriptListener) EnterInterpolation(ctx *InterpolationContext) {}

// ExitInterpolation is called when production interpolation is exited.
func (s *BaseManuscriptListener) ExitInterpolation(ctx *InterpolationContext) {}

// EnterLiteral is called when production literal is entered.
func (s *BaseManuscriptListener) EnterLiteral(ctx *LiteralContext) {}

// ExitLiteral is called when production literal is exited.
func (s *BaseManuscriptListener) ExitLiteral(ctx *LiteralContext) {}

// EnterStringLiteral is called when production stringLiteral is entered.
func (s *BaseManuscriptListener) EnterStringLiteral(ctx *StringLiteralContext) {}

// ExitStringLiteral is called when production stringLiteral is exited.
func (s *BaseManuscriptListener) ExitStringLiteral(ctx *StringLiteralContext) {}

// EnterNumberLiteral is called when production numberLiteral is entered.
func (s *BaseManuscriptListener) EnterNumberLiteral(ctx *NumberLiteralContext) {}

// ExitNumberLiteral is called when production numberLiteral is exited.
func (s *BaseManuscriptListener) ExitNumberLiteral(ctx *NumberLiteralContext) {}

// EnterBooleanLiteral is called when production booleanLiteral is entered.
func (s *BaseManuscriptListener) EnterBooleanLiteral(ctx *BooleanLiteralContext) {}

// ExitBooleanLiteral is called when production booleanLiteral is exited.
func (s *BaseManuscriptListener) ExitBooleanLiteral(ctx *BooleanLiteralContext) {}

// EnterArrayLiteral is called when production arrayLiteral is entered.
func (s *BaseManuscriptListener) EnterArrayLiteral(ctx *ArrayLiteralContext) {}

// ExitArrayLiteral is called when production arrayLiteral is exited.
func (s *BaseManuscriptListener) ExitArrayLiteral(ctx *ArrayLiteralContext) {}

// EnterObjectLiteral is called when production objectLiteral is entered.
func (s *BaseManuscriptListener) EnterObjectLiteral(ctx *ObjectLiteralContext) {}

// ExitObjectLiteral is called when production objectLiteral is exited.
func (s *BaseManuscriptListener) ExitObjectLiteral(ctx *ObjectLiteralContext) {}

// EnterObjectField is called when production objectField is entered.
func (s *BaseManuscriptListener) EnterObjectField(ctx *ObjectFieldContext) {}

// ExitObjectField is called when production objectField is exited.
func (s *BaseManuscriptListener) ExitObjectField(ctx *ObjectFieldContext) {}

// EnterMapLiteral is called when production mapLiteral is entered.
func (s *BaseManuscriptListener) EnterMapLiteral(ctx *MapLiteralContext) {}

// ExitMapLiteral is called when production mapLiteral is exited.
func (s *BaseManuscriptListener) ExitMapLiteral(ctx *MapLiteralContext) {}

// EnterMapField is called when production mapField is entered.
func (s *BaseManuscriptListener) EnterMapField(ctx *MapFieldContext) {}

// ExitMapField is called when production mapField is exited.
func (s *BaseManuscriptListener) ExitMapField(ctx *MapFieldContext) {}

// EnterSetLiteral is called when production setLiteral is entered.
func (s *BaseManuscriptListener) EnterSetLiteral(ctx *SetLiteralContext) {}

// ExitSetLiteral is called when production setLiteral is exited.
func (s *BaseManuscriptListener) ExitSetLiteral(ctx *SetLiteralContext) {}

// EnterTupleLiteral is called when production tupleLiteral is entered.
func (s *BaseManuscriptListener) EnterTupleLiteral(ctx *TupleLiteralContext) {}

// ExitTupleLiteral is called when production tupleLiteral is exited.
func (s *BaseManuscriptListener) ExitTupleLiteral(ctx *TupleLiteralContext) {}

// EnterImportStr is called when production importStr is entered.
func (s *BaseManuscriptListener) EnterImportStr(ctx *ImportStrContext) {}

// ExitImportStr is called when production importStr is exited.
func (s *BaseManuscriptListener) ExitImportStr(ctx *ImportStrContext) {}

// EnterTupleType is called when production tupleType is entered.
func (s *BaseManuscriptListener) EnterTupleType(ctx *TupleTypeContext) {}

// ExitTupleType is called when production tupleType is exited.
func (s *BaseManuscriptListener) ExitTupleType(ctx *TupleTypeContext) {}
