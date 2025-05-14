// Code generated from Manuscript.g4 by ANTLR 4.13.1. DO NOT EDIT.

package parser // Manuscript

import "github.com/antlr4-go/antlr/v4"

// ManuscriptListener is a complete listener for a parse tree produced by Manuscript.
type ManuscriptListener interface {
	antlr.ParseTreeListener

	// EnterProgram is called when entering the program production.
	EnterProgram(c *ProgramContext)

	// EnterProgramItem is called when entering the programItem production.
	EnterProgramItem(c *ProgramItemContext)

	// EnterImportStmt is called when entering the importStmt production.
	EnterImportStmt(c *ImportStmtContext)

	// EnterImportItem is called when entering the importItem production.
	EnterImportItem(c *ImportItemContext)

	// EnterExternStmt is called when entering the externStmt production.
	EnterExternStmt(c *ExternStmtContext)

	// EnterExternItem is called when entering the externItem production.
	EnterExternItem(c *ExternItemContext)

	// EnterExportStmt is called when entering the exportStmt production.
	EnterExportStmt(c *ExportStmtContext)

	// EnterLetDecl is called when entering the letDecl production.
	EnterLetDecl(c *LetDeclContext)

	// EnterLetAssignment is called when entering the letAssignment production.
	EnterLetAssignment(c *LetAssignmentContext)

	// EnterLetPattern is called when entering the letPattern production.
	EnterLetPattern(c *LetPatternContext)

	// EnterArrayPattn is called when entering the arrayPattn production.
	EnterArrayPattn(c *ArrayPattnContext)

	// EnterObjectPattn is called when entering the objectPattn production.
	EnterObjectPattn(c *ObjectPattnContext)

	// EnterFnDecl is called when entering the fnDecl production.
	EnterFnDecl(c *FnDeclContext)

	// EnterParameters is called when entering the parameters production.
	EnterParameters(c *ParametersContext)

	// EnterParam is called when entering the param production.
	EnterParam(c *ParamContext)

	// EnterTypeDecl is called when entering the typeDecl production.
	EnterTypeDecl(c *TypeDeclContext)

	// EnterFieldDecl is called when entering the fieldDecl production.
	EnterFieldDecl(c *FieldDeclContext)

	// EnterIfaceDecl is called when entering the ifaceDecl production.
	EnterIfaceDecl(c *IfaceDeclContext)

	// EnterMethodDecl is called when entering the methodDecl production.
	EnterMethodDecl(c *MethodDeclContext)

	// EnterMethodBlockDecl is called when entering the methodBlockDecl production.
	EnterMethodBlockDecl(c *MethodBlockDeclContext)

	// EnterMethodImpl is called when entering the methodImpl production.
	EnterMethodImpl(c *MethodImplContext)

	// EnterTypeAnnotation is called when entering the typeAnnotation production.
	EnterTypeAnnotation(c *TypeAnnotationContext)

	// EnterBaseTypeAnnotation is called when entering the baseTypeAnnotation production.
	EnterBaseTypeAnnotation(c *BaseTypeAnnotationContext)

	// EnterFunctionType is called when entering the functionType production.
	EnterFunctionType(c *FunctionTypeContext)

	// EnterStmt is called when entering the stmt production.
	EnterStmt(c *StmtContext)

	// EnterExprStmt is called when entering the exprStmt production.
	EnterExprStmt(c *ExprStmtContext)

	// EnterReturnStmt is called when entering the returnStmt production.
	EnterReturnStmt(c *ReturnStmtContext)

	// EnterYieldStmt is called when entering the yieldStmt production.
	EnterYieldStmt(c *YieldStmtContext)

	// EnterIfStmt is called when entering the ifStmt production.
	EnterIfStmt(c *IfStmtContext)

	// EnterForStmt is called when entering the forStmt production.
	EnterForStmt(c *ForStmtContext)

	// EnterForInitPattn is called when entering the forInitPattn production.
	EnterForInitPattn(c *ForInitPattnContext)

	// EnterLoopPattern is called when entering the loopPattern production.
	EnterLoopPattern(c *LoopPatternContext)

	// EnterWhileStmt is called when entering the whileStmt production.
	EnterWhileStmt(c *WhileStmtContext)

	// EnterCodeBlock is called when entering the codeBlock production.
	EnterCodeBlock(c *CodeBlockContext)

	// EnterExpr is called when entering the expr production.
	EnterExpr(c *ExprContext)

	// EnterAssignmentExpr is called when entering the assignmentExpr production.
	EnterAssignmentExpr(c *AssignmentExprContext)

	// EnterLogicalOrExpr is called when entering the logicalOrExpr production.
	EnterLogicalOrExpr(c *LogicalOrExprContext)

	// EnterLogicalAndExpr is called when entering the logicalAndExpr production.
	EnterLogicalAndExpr(c *LogicalAndExprContext)

	// EnterEqualityExpr is called when entering the equalityExpr production.
	EnterEqualityExpr(c *EqualityExprContext)

	// EnterComparisonExpr is called when entering the comparisonExpr production.
	EnterComparisonExpr(c *ComparisonExprContext)

	// EnterAdditiveExpr is called when entering the additiveExpr production.
	EnterAdditiveExpr(c *AdditiveExprContext)

	// EnterMultiplicativeExpr is called when entering the multiplicativeExpr production.
	EnterMultiplicativeExpr(c *MultiplicativeExprContext)

	// EnterUnaryExpr is called when entering the unaryExpr production.
	EnterUnaryExpr(c *UnaryExprContext)

	// EnterAwaitExpr is called when entering the awaitExpr production.
	EnterAwaitExpr(c *AwaitExprContext)

	// EnterPostfixExpr is called when entering the postfixExpr production.
	EnterPostfixExpr(c *PostfixExprContext)

	// EnterPrimaryExpr is called when entering the primaryExpr production.
	EnterPrimaryExpr(c *PrimaryExprContext)

	// EnterFnExpr is called when entering the fnExpr production.
	EnterFnExpr(c *FnExprContext)

	// EnterLambdaExpr is called when entering the lambdaExpr production.
	EnterLambdaExpr(c *LambdaExprContext)

	// EnterTryBlockExpr is called when entering the tryBlockExpr production.
	EnterTryBlockExpr(c *TryBlockExprContext)

	// EnterMatchExpr is called when entering the matchExpr production.
	EnterMatchExpr(c *MatchExprContext)

	// EnterCaseClause is called when entering the caseClause production.
	EnterCaseClause(c *CaseClauseContext)

	// EnterSingleQuotedString is called when entering the singleQuotedString production.
	EnterSingleQuotedString(c *SingleQuotedStringContext)

	// EnterMultiQuotedString is called when entering the multiQuotedString production.
	EnterMultiQuotedString(c *MultiQuotedStringContext)

	// EnterDoubleQuotedString is called when entering the doubleQuotedString production.
	EnterDoubleQuotedString(c *DoubleQuotedStringContext)

	// EnterStringPart is called when entering the stringPart production.
	EnterStringPart(c *StringPartContext)

	// EnterInterpolation is called when entering the interpolation production.
	EnterInterpolation(c *InterpolationContext)

	// EnterLiteral is called when entering the literal production.
	EnterLiteral(c *LiteralContext)

	// EnterStringLiteral is called when entering the stringLiteral production.
	EnterStringLiteral(c *StringLiteralContext)

	// EnterNumberLiteral is called when entering the numberLiteral production.
	EnterNumberLiteral(c *NumberLiteralContext)

	// EnterBooleanLiteral is called when entering the booleanLiteral production.
	EnterBooleanLiteral(c *BooleanLiteralContext)

	// EnterArrayLiteral is called when entering the arrayLiteral production.
	EnterArrayLiteral(c *ArrayLiteralContext)

	// EnterObjectLiteral is called when entering the objectLiteral production.
	EnterObjectLiteral(c *ObjectLiteralContext)

	// EnterObjectField is called when entering the objectField production.
	EnterObjectField(c *ObjectFieldContext)

	// EnterMapLiteral is called when entering the mapLiteral production.
	EnterMapLiteral(c *MapLiteralContext)

	// EnterMapField is called when entering the mapField production.
	EnterMapField(c *MapFieldContext)

	// EnterSetLiteral is called when entering the setLiteral production.
	EnterSetLiteral(c *SetLiteralContext)

	// EnterTupleLiteral is called when entering the tupleLiteral production.
	EnterTupleLiteral(c *TupleLiteralContext)

	// EnterImportStr is called when entering the importStr production.
	EnterImportStr(c *ImportStrContext)

	// EnterTupleType is called when entering the tupleType production.
	EnterTupleType(c *TupleTypeContext)

	// ExitProgram is called when exiting the program production.
	ExitProgram(c *ProgramContext)

	// ExitProgramItem is called when exiting the programItem production.
	ExitProgramItem(c *ProgramItemContext)

	// ExitImportStmt is called when exiting the importStmt production.
	ExitImportStmt(c *ImportStmtContext)

	// ExitImportItem is called when exiting the importItem production.
	ExitImportItem(c *ImportItemContext)

	// ExitExternStmt is called when exiting the externStmt production.
	ExitExternStmt(c *ExternStmtContext)

	// ExitExternItem is called when exiting the externItem production.
	ExitExternItem(c *ExternItemContext)

	// ExitExportStmt is called when exiting the exportStmt production.
	ExitExportStmt(c *ExportStmtContext)

	// ExitLetDecl is called when exiting the letDecl production.
	ExitLetDecl(c *LetDeclContext)

	// ExitLetAssignment is called when exiting the letAssignment production.
	ExitLetAssignment(c *LetAssignmentContext)

	// ExitLetPattern is called when exiting the letPattern production.
	ExitLetPattern(c *LetPatternContext)

	// ExitArrayPattn is called when exiting the arrayPattn production.
	ExitArrayPattn(c *ArrayPattnContext)

	// ExitObjectPattn is called when exiting the objectPattn production.
	ExitObjectPattn(c *ObjectPattnContext)

	// ExitFnDecl is called when exiting the fnDecl production.
	ExitFnDecl(c *FnDeclContext)

	// ExitParameters is called when exiting the parameters production.
	ExitParameters(c *ParametersContext)

	// ExitParam is called when exiting the param production.
	ExitParam(c *ParamContext)

	// ExitTypeDecl is called when exiting the typeDecl production.
	ExitTypeDecl(c *TypeDeclContext)

	// ExitFieldDecl is called when exiting the fieldDecl production.
	ExitFieldDecl(c *FieldDeclContext)

	// ExitIfaceDecl is called when exiting the ifaceDecl production.
	ExitIfaceDecl(c *IfaceDeclContext)

	// ExitMethodDecl is called when exiting the methodDecl production.
	ExitMethodDecl(c *MethodDeclContext)

	// ExitMethodBlockDecl is called when exiting the methodBlockDecl production.
	ExitMethodBlockDecl(c *MethodBlockDeclContext)

	// ExitMethodImpl is called when exiting the methodImpl production.
	ExitMethodImpl(c *MethodImplContext)

	// ExitTypeAnnotation is called when exiting the typeAnnotation production.
	ExitTypeAnnotation(c *TypeAnnotationContext)

	// ExitBaseTypeAnnotation is called when exiting the baseTypeAnnotation production.
	ExitBaseTypeAnnotation(c *BaseTypeAnnotationContext)

	// ExitFunctionType is called when exiting the functionType production.
	ExitFunctionType(c *FunctionTypeContext)

	// ExitStmt is called when exiting the stmt production.
	ExitStmt(c *StmtContext)

	// ExitExprStmt is called when exiting the exprStmt production.
	ExitExprStmt(c *ExprStmtContext)

	// ExitReturnStmt is called when exiting the returnStmt production.
	ExitReturnStmt(c *ReturnStmtContext)

	// ExitYieldStmt is called when exiting the yieldStmt production.
	ExitYieldStmt(c *YieldStmtContext)

	// ExitIfStmt is called when exiting the ifStmt production.
	ExitIfStmt(c *IfStmtContext)

	// ExitForStmt is called when exiting the forStmt production.
	ExitForStmt(c *ForStmtContext)

	// ExitForInitPattn is called when exiting the forInitPattn production.
	ExitForInitPattn(c *ForInitPattnContext)

	// ExitLoopPattern is called when exiting the loopPattern production.
	ExitLoopPattern(c *LoopPatternContext)

	// ExitWhileStmt is called when exiting the whileStmt production.
	ExitWhileStmt(c *WhileStmtContext)

	// ExitCodeBlock is called when exiting the codeBlock production.
	ExitCodeBlock(c *CodeBlockContext)

	// ExitExpr is called when exiting the expr production.
	ExitExpr(c *ExprContext)

	// ExitAssignmentExpr is called when exiting the assignmentExpr production.
	ExitAssignmentExpr(c *AssignmentExprContext)

	// ExitLogicalOrExpr is called when exiting the logicalOrExpr production.
	ExitLogicalOrExpr(c *LogicalOrExprContext)

	// ExitLogicalAndExpr is called when exiting the logicalAndExpr production.
	ExitLogicalAndExpr(c *LogicalAndExprContext)

	// ExitEqualityExpr is called when exiting the equalityExpr production.
	ExitEqualityExpr(c *EqualityExprContext)

	// ExitComparisonExpr is called when exiting the comparisonExpr production.
	ExitComparisonExpr(c *ComparisonExprContext)

	// ExitAdditiveExpr is called when exiting the additiveExpr production.
	ExitAdditiveExpr(c *AdditiveExprContext)

	// ExitMultiplicativeExpr is called when exiting the multiplicativeExpr production.
	ExitMultiplicativeExpr(c *MultiplicativeExprContext)

	// ExitUnaryExpr is called when exiting the unaryExpr production.
	ExitUnaryExpr(c *UnaryExprContext)

	// ExitAwaitExpr is called when exiting the awaitExpr production.
	ExitAwaitExpr(c *AwaitExprContext)

	// ExitPostfixExpr is called when exiting the postfixExpr production.
	ExitPostfixExpr(c *PostfixExprContext)

	// ExitPrimaryExpr is called when exiting the primaryExpr production.
	ExitPrimaryExpr(c *PrimaryExprContext)

	// ExitFnExpr is called when exiting the fnExpr production.
	ExitFnExpr(c *FnExprContext)

	// ExitLambdaExpr is called when exiting the lambdaExpr production.
	ExitLambdaExpr(c *LambdaExprContext)

	// ExitTryBlockExpr is called when exiting the tryBlockExpr production.
	ExitTryBlockExpr(c *TryBlockExprContext)

	// ExitMatchExpr is called when exiting the matchExpr production.
	ExitMatchExpr(c *MatchExprContext)

	// ExitCaseClause is called when exiting the caseClause production.
	ExitCaseClause(c *CaseClauseContext)

	// ExitSingleQuotedString is called when exiting the singleQuotedString production.
	ExitSingleQuotedString(c *SingleQuotedStringContext)

	// ExitMultiQuotedString is called when exiting the multiQuotedString production.
	ExitMultiQuotedString(c *MultiQuotedStringContext)

	// ExitDoubleQuotedString is called when exiting the doubleQuotedString production.
	ExitDoubleQuotedString(c *DoubleQuotedStringContext)

	// ExitStringPart is called when exiting the stringPart production.
	ExitStringPart(c *StringPartContext)

	// ExitInterpolation is called when exiting the interpolation production.
	ExitInterpolation(c *InterpolationContext)

	// ExitLiteral is called when exiting the literal production.
	ExitLiteral(c *LiteralContext)

	// ExitStringLiteral is called when exiting the stringLiteral production.
	ExitStringLiteral(c *StringLiteralContext)

	// ExitNumberLiteral is called when exiting the numberLiteral production.
	ExitNumberLiteral(c *NumberLiteralContext)

	// ExitBooleanLiteral is called when exiting the booleanLiteral production.
	ExitBooleanLiteral(c *BooleanLiteralContext)

	// ExitArrayLiteral is called when exiting the arrayLiteral production.
	ExitArrayLiteral(c *ArrayLiteralContext)

	// ExitObjectLiteral is called when exiting the objectLiteral production.
	ExitObjectLiteral(c *ObjectLiteralContext)

	// ExitObjectField is called when exiting the objectField production.
	ExitObjectField(c *ObjectFieldContext)

	// ExitMapLiteral is called when exiting the mapLiteral production.
	ExitMapLiteral(c *MapLiteralContext)

	// ExitMapField is called when exiting the mapField production.
	ExitMapField(c *MapFieldContext)

	// ExitSetLiteral is called when exiting the setLiteral production.
	ExitSetLiteral(c *SetLiteralContext)

	// ExitTupleLiteral is called when exiting the tupleLiteral production.
	ExitTupleLiteral(c *TupleLiteralContext)

	// ExitImportStr is called when exiting the importStr production.
	ExitImportStr(c *ImportStrContext)

	// ExitTupleType is called when exiting the tupleType production.
	ExitTupleType(c *TupleTypeContext)
}
