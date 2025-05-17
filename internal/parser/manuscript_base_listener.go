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

// EnterImportStr is called when production importStr is entered.
func (s *BaseManuscriptListener) EnterImportStr(ctx *ImportStrContext) {}

// ExitImportStr is called when production importStr is exited.
func (s *BaseManuscriptListener) ExitImportStr(ctx *ImportStrContext) {}

// EnterExternStmt is called when production externStmt is entered.
func (s *BaseManuscriptListener) EnterExternStmt(ctx *ExternStmtContext) {}

// ExitExternStmt is called when production externStmt is exited.
func (s *BaseManuscriptListener) ExitExternStmt(ctx *ExternStmtContext) {}

// EnterExportStmt is called when production exportStmt is entered.
func (s *BaseManuscriptListener) EnterExportStmt(ctx *ExportStmtContext) {}

// ExitExportStmt is called when production exportStmt is exited.
func (s *BaseManuscriptListener) ExitExportStmt(ctx *ExportStmtContext) {}

// EnterLetDecl is called when production letDecl is entered.
func (s *BaseManuscriptListener) EnterLetDecl(ctx *LetDeclContext) {}

// ExitLetDecl is called when production letDecl is exited.
func (s *BaseManuscriptListener) ExitLetDecl(ctx *LetDeclContext) {}

// EnterLetSingle is called when production letSingle is entered.
func (s *BaseManuscriptListener) EnterLetSingle(ctx *LetSingleContext) {}

// ExitLetSingle is called when production letSingle is exited.
func (s *BaseManuscriptListener) ExitLetSingle(ctx *LetSingleContext) {}

// EnterLetBlock is called when production letBlock is entered.
func (s *BaseManuscriptListener) EnterLetBlock(ctx *LetBlockContext) {}

// ExitLetBlock is called when production letBlock is exited.
func (s *BaseManuscriptListener) ExitLetBlock(ctx *LetBlockContext) {}

// EnterLetDestructuredObj is called when production letDestructuredObj is entered.
func (s *BaseManuscriptListener) EnterLetDestructuredObj(ctx *LetDestructuredObjContext) {}

// ExitLetDestructuredObj is called when production letDestructuredObj is exited.
func (s *BaseManuscriptListener) ExitLetDestructuredObj(ctx *LetDestructuredObjContext) {}

// EnterLetDestructuredArray is called when production letDestructuredArray is entered.
func (s *BaseManuscriptListener) EnterLetDestructuredArray(ctx *LetDestructuredArrayContext) {}

// ExitLetDestructuredArray is called when production letDestructuredArray is exited.
func (s *BaseManuscriptListener) ExitLetDestructuredArray(ctx *LetDestructuredArrayContext) {}

// EnterNamedID is called when production namedID is entered.
func (s *BaseManuscriptListener) EnterNamedID(ctx *NamedIDContext) {}

// ExitNamedID is called when production namedID is exited.
func (s *BaseManuscriptListener) ExitNamedID(ctx *NamedIDContext) {}

// EnterTypedID is called when production typedID is entered.
func (s *BaseManuscriptListener) EnterTypedID(ctx *TypedIDContext) {}

// ExitTypedID is called when production typedID is exited.
func (s *BaseManuscriptListener) ExitTypedID(ctx *TypedIDContext) {}

// EnterTypedIDList is called when production typedIDList is entered.
func (s *BaseManuscriptListener) EnterTypedIDList(ctx *TypedIDListContext) {}

// ExitTypedIDList is called when production typedIDList is exited.
func (s *BaseManuscriptListener) ExitTypedIDList(ctx *TypedIDListContext) {}

// EnterTypeList is called when production typeList is entered.
func (s *BaseManuscriptListener) EnterTypeList(ctx *TypeListContext) {}

// ExitTypeList is called when production typeList is exited.
func (s *BaseManuscriptListener) ExitTypeList(ctx *TypeListContext) {}

// EnterFnDecl is called when production fnDecl is entered.
func (s *BaseManuscriptListener) EnterFnDecl(ctx *FnDeclContext) {}

// ExitFnDecl is called when production fnDecl is exited.
func (s *BaseManuscriptListener) ExitFnDecl(ctx *FnDeclContext) {}

// EnterFnSignature is called when production fnSignature is entered.
func (s *BaseManuscriptListener) EnterFnSignature(ctx *FnSignatureContext) {}

// ExitFnSignature is called when production fnSignature is exited.
func (s *BaseManuscriptListener) ExitFnSignature(ctx *FnSignatureContext) {}

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

// EnterTypeDefBody is called when production typeDefBody is entered.
func (s *BaseManuscriptListener) EnterTypeDefBody(ctx *TypeDefBodyContext) {}

// ExitTypeDefBody is called when production typeDefBody is exited.
func (s *BaseManuscriptListener) ExitTypeDefBody(ctx *TypeDefBodyContext) {}

// EnterTypeAlias is called when production typeAlias is entered.
func (s *BaseManuscriptListener) EnterTypeAlias(ctx *TypeAliasContext) {}

// ExitTypeAlias is called when production typeAlias is exited.
func (s *BaseManuscriptListener) ExitTypeAlias(ctx *TypeAliasContext) {}

// EnterFieldDecl is called when production fieldDecl is entered.
func (s *BaseManuscriptListener) EnterFieldDecl(ctx *FieldDeclContext) {}

// ExitFieldDecl is called when production fieldDecl is exited.
func (s *BaseManuscriptListener) ExitFieldDecl(ctx *FieldDeclContext) {}

// EnterInterfaceDecl is called when production interfaceDecl is entered.
func (s *BaseManuscriptListener) EnterInterfaceDecl(ctx *InterfaceDeclContext) {}

// ExitInterfaceDecl is called when production interfaceDecl is exited.
func (s *BaseManuscriptListener) ExitInterfaceDecl(ctx *InterfaceDeclContext) {}

// EnterMethodsDecl is called when production methodsDecl is entered.
func (s *BaseManuscriptListener) EnterMethodsDecl(ctx *MethodsDeclContext) {}

// ExitMethodsDecl is called when production methodsDecl is exited.
func (s *BaseManuscriptListener) ExitMethodsDecl(ctx *MethodsDeclContext) {}

// EnterTypeAnnotation is called when production typeAnnotation is entered.
func (s *BaseManuscriptListener) EnterTypeAnnotation(ctx *TypeAnnotationContext) {}

// ExitTypeAnnotation is called when production typeAnnotation is exited.
func (s *BaseManuscriptListener) ExitTypeAnnotation(ctx *TypeAnnotationContext) {}

// EnterTupleType is called when production tupleType is entered.
func (s *BaseManuscriptListener) EnterTupleType(ctx *TupleTypeContext) {}

// ExitTupleType is called when production tupleType is exited.
func (s *BaseManuscriptListener) ExitTupleType(ctx *TupleTypeContext) {}

// EnterObjectTypeAnnotation is called when production objectTypeAnnotation is entered.
func (s *BaseManuscriptListener) EnterObjectTypeAnnotation(ctx *ObjectTypeAnnotationContext) {}

// ExitObjectTypeAnnotation is called when production objectTypeAnnotation is exited.
func (s *BaseManuscriptListener) ExitObjectTypeAnnotation(ctx *ObjectTypeAnnotationContext) {}

// EnterMapTypeAnnotation is called when production mapTypeAnnotation is entered.
func (s *BaseManuscriptListener) EnterMapTypeAnnotation(ctx *MapTypeAnnotationContext) {}

// ExitMapTypeAnnotation is called when production mapTypeAnnotation is exited.
func (s *BaseManuscriptListener) ExitMapTypeAnnotation(ctx *MapTypeAnnotationContext) {}

// EnterSetTypeAnnotation is called when production setTypeAnnotation is entered.
func (s *BaseManuscriptListener) EnterSetTypeAnnotation(ctx *SetTypeAnnotationContext) {}

// ExitSetTypeAnnotation is called when production setTypeAnnotation is exited.
func (s *BaseManuscriptListener) ExitSetTypeAnnotation(ctx *SetTypeAnnotationContext) {}

// EnterStmt is called when production stmt is entered.
func (s *BaseManuscriptListener) EnterStmt(ctx *StmtContext) {}

// ExitStmt is called when production stmt is exited.
func (s *BaseManuscriptListener) ExitStmt(ctx *StmtContext) {}

// EnterReturnStmt is called when production returnStmt is entered.
func (s *BaseManuscriptListener) EnterReturnStmt(ctx *ReturnStmtContext) {}

// ExitReturnStmt is called when production returnStmt is exited.
func (s *BaseManuscriptListener) ExitReturnStmt(ctx *ReturnStmtContext) {}

// EnterYieldStmt is called when production yieldStmt is entered.
func (s *BaseManuscriptListener) EnterYieldStmt(ctx *YieldStmtContext) {}

// ExitYieldStmt is called when production yieldStmt is exited.
func (s *BaseManuscriptListener) ExitYieldStmt(ctx *YieldStmtContext) {}

// EnterExprList is called when production exprList is entered.
func (s *BaseManuscriptListener) EnterExprList(ctx *ExprListContext) {}

// ExitExprList is called when production exprList is exited.
func (s *BaseManuscriptListener) ExitExprList(ctx *ExprListContext) {}

// EnterIfStmt is called when production ifStmt is entered.
func (s *BaseManuscriptListener) EnterIfStmt(ctx *IfStmtContext) {}

// ExitIfStmt is called when production ifStmt is exited.
func (s *BaseManuscriptListener) ExitIfStmt(ctx *IfStmtContext) {}

// EnterForStmt is called when production forStmt is entered.
func (s *BaseManuscriptListener) EnterForStmt(ctx *ForStmtContext) {}

// ExitForStmt is called when production forStmt is exited.
func (s *BaseManuscriptListener) ExitForStmt(ctx *ForStmtContext) {}

// EnterForLoop is called when production ForLoop is entered.
func (s *BaseManuscriptListener) EnterForLoop(ctx *ForLoopContext) {}

// ExitForLoop is called when production ForLoop is exited.
func (s *BaseManuscriptListener) ExitForLoop(ctx *ForLoopContext) {}

// EnterForInLoop is called when production ForInLoop is entered.
func (s *BaseManuscriptListener) EnterForInLoop(ctx *ForInLoopContext) {}

// ExitForInLoop is called when production ForInLoop is exited.
func (s *BaseManuscriptListener) ExitForInLoop(ctx *ForInLoopContext) {}

// EnterForTrinity is called when production forTrinity is entered.
func (s *BaseManuscriptListener) EnterForTrinity(ctx *ForTrinityContext) {}

// ExitForTrinity is called when production forTrinity is exited.
func (s *BaseManuscriptListener) ExitForTrinity(ctx *ForTrinityContext) {}

// EnterWhileStmt is called when production whileStmt is entered.
func (s *BaseManuscriptListener) EnterWhileStmt(ctx *WhileStmtContext) {}

// ExitWhileStmt is called when production whileStmt is exited.
func (s *BaseManuscriptListener) ExitWhileStmt(ctx *WhileStmtContext) {}

// EnterLoopBody is called when production loopBody is entered.
func (s *BaseManuscriptListener) EnterLoopBody(ctx *LoopBodyContext) {}

// ExitLoopBody is called when production loopBody is exited.
func (s *BaseManuscriptListener) ExitLoopBody(ctx *LoopBodyContext) {}

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

// EnterBitwiseOrExpr is called when production bitwiseOrExpr is entered.
func (s *BaseManuscriptListener) EnterBitwiseOrExpr(ctx *BitwiseOrExprContext) {}

// ExitBitwiseOrExpr is called when production bitwiseOrExpr is exited.
func (s *BaseManuscriptListener) ExitBitwiseOrExpr(ctx *BitwiseOrExprContext) {}

// EnterBitwiseXorExpr is called when production bitwiseXorExpr is entered.
func (s *BaseManuscriptListener) EnterBitwiseXorExpr(ctx *BitwiseXorExprContext) {}

// ExitBitwiseXorExpr is called when production bitwiseXorExpr is exited.
func (s *BaseManuscriptListener) ExitBitwiseXorExpr(ctx *BitwiseXorExprContext) {}

// EnterBitwiseAndExpr is called when production bitwiseAndExpr is entered.
func (s *BaseManuscriptListener) EnterBitwiseAndExpr(ctx *BitwiseAndExprContext) {}

// ExitBitwiseAndExpr is called when production bitwiseAndExpr is exited.
func (s *BaseManuscriptListener) ExitBitwiseAndExpr(ctx *BitwiseAndExprContext) {}

// EnterEqualityExpr is called when production equalityExpr is entered.
func (s *BaseManuscriptListener) EnterEqualityExpr(ctx *EqualityExprContext) {}

// ExitEqualityExpr is called when production equalityExpr is exited.
func (s *BaseManuscriptListener) ExitEqualityExpr(ctx *EqualityExprContext) {}

// EnterComparisonExpr is called when production comparisonExpr is entered.
func (s *BaseManuscriptListener) EnterComparisonExpr(ctx *ComparisonExprContext) {}

// ExitComparisonExpr is called when production comparisonExpr is exited.
func (s *BaseManuscriptListener) ExitComparisonExpr(ctx *ComparisonExprContext) {}

// EnterShiftExpr is called when production shiftExpr is entered.
func (s *BaseManuscriptListener) EnterShiftExpr(ctx *ShiftExprContext) {}

// ExitShiftExpr is called when production shiftExpr is exited.
func (s *BaseManuscriptListener) ExitShiftExpr(ctx *ShiftExprContext) {}

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

// EnterMatchExpr is called when production matchExpr is entered.
func (s *BaseManuscriptListener) EnterMatchExpr(ctx *MatchExprContext) {}

// ExitMatchExpr is called when production matchExpr is exited.
func (s *BaseManuscriptListener) ExitMatchExpr(ctx *MatchExprContext) {}

// EnterCaseClause is called when production caseClause is entered.
func (s *BaseManuscriptListener) EnterCaseClause(ctx *CaseClauseContext) {}

// ExitCaseClause is called when production caseClause is exited.
func (s *BaseManuscriptListener) ExitCaseClause(ctx *CaseClauseContext) {}

// EnterDefaultClause is called when production defaultClause is entered.
func (s *BaseManuscriptListener) EnterDefaultClause(ctx *DefaultClauseContext) {}

// ExitDefaultClause is called when production defaultClause is exited.
func (s *BaseManuscriptListener) ExitDefaultClause(ctx *DefaultClauseContext) {}

// EnterSingleQuotedString is called when production singleQuotedString is entered.
func (s *BaseManuscriptListener) EnterSingleQuotedString(ctx *SingleQuotedStringContext) {}

// ExitSingleQuotedString is called when production singleQuotedString is exited.
func (s *BaseManuscriptListener) ExitSingleQuotedString(ctx *SingleQuotedStringContext) {}

// EnterMultiQuotedString is called when production multiQuotedString is entered.
func (s *BaseManuscriptListener) EnterMultiQuotedString(ctx *MultiQuotedStringContext) {}

// ExitMultiQuotedString is called when production multiQuotedString is exited.
func (s *BaseManuscriptListener) ExitMultiQuotedString(ctx *MultiQuotedStringContext) {}

// EnterDoubleQuotedString is called when production doubleQuotedString is entered.
func (s *BaseManuscriptListener) EnterDoubleQuotedString(ctx *DoubleQuotedStringContext) {}

// ExitDoubleQuotedString is called when production doubleQuotedString is exited.
func (s *BaseManuscriptListener) ExitDoubleQuotedString(ctx *DoubleQuotedStringContext) {}

// EnterMultiDoubleQuotedString is called when production multiDoubleQuotedString is entered.
func (s *BaseManuscriptListener) EnterMultiDoubleQuotedString(ctx *MultiDoubleQuotedStringContext) {}

// ExitMultiDoubleQuotedString is called when production multiDoubleQuotedString is exited.
func (s *BaseManuscriptListener) ExitMultiDoubleQuotedString(ctx *MultiDoubleQuotedStringContext) {}

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

// EnterObjectFieldName is called when production objectFieldName is entered.
func (s *BaseManuscriptListener) EnterObjectFieldName(ctx *ObjectFieldNameContext) {}

// ExitObjectFieldName is called when production objectFieldName is exited.
func (s *BaseManuscriptListener) ExitObjectFieldName(ctx *ObjectFieldNameContext) {}

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

// EnterBreakStmt is called when production breakStmt is entered.
func (s *BaseManuscriptListener) EnterBreakStmt(ctx *BreakStmtContext) {}

// ExitBreakStmt is called when production breakStmt is exited.
func (s *BaseManuscriptListener) ExitBreakStmt(ctx *BreakStmtContext) {}

// EnterContinueStmt is called when production continueStmt is entered.
func (s *BaseManuscriptListener) EnterContinueStmt(ctx *ContinueStmtContext) {}

// ExitContinueStmt is called when production continueStmt is exited.
func (s *BaseManuscriptListener) ExitContinueStmt(ctx *ContinueStmtContext) {}

// EnterCheckStmt is called when production checkStmt is entered.
func (s *BaseManuscriptListener) EnterCheckStmt(ctx *CheckStmtContext) {}

// ExitCheckStmt is called when production checkStmt is exited.
func (s *BaseManuscriptListener) ExitCheckStmt(ctx *CheckStmtContext) {}

// EnterTaggedBlockString is called when production taggedBlockString is entered.
func (s *BaseManuscriptListener) EnterTaggedBlockString(ctx *TaggedBlockStringContext) {}

// ExitTaggedBlockString is called when production taggedBlockString is exited.
func (s *BaseManuscriptListener) ExitTaggedBlockString(ctx *TaggedBlockStringContext) {}
