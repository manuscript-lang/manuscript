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

// EnterDeclImport is called when production DeclImport is entered.
func (s *BaseManuscriptListener) EnterDeclImport(ctx *DeclImportContext) {}

// ExitDeclImport is called when production DeclImport is exited.
func (s *BaseManuscriptListener) ExitDeclImport(ctx *DeclImportContext) {}

// EnterDeclExport is called when production DeclExport is entered.
func (s *BaseManuscriptListener) EnterDeclExport(ctx *DeclExportContext) {}

// ExitDeclExport is called when production DeclExport is exited.
func (s *BaseManuscriptListener) ExitDeclExport(ctx *DeclExportContext) {}

// EnterDeclExtern is called when production DeclExtern is entered.
func (s *BaseManuscriptListener) EnterDeclExtern(ctx *DeclExternContext) {}

// ExitDeclExtern is called when production DeclExtern is exited.
func (s *BaseManuscriptListener) ExitDeclExtern(ctx *DeclExternContext) {}

// EnterDeclLet is called when production DeclLet is entered.
func (s *BaseManuscriptListener) EnterDeclLet(ctx *DeclLetContext) {}

// ExitDeclLet is called when production DeclLet is exited.
func (s *BaseManuscriptListener) ExitDeclLet(ctx *DeclLetContext) {}

// EnterDeclType is called when production DeclType is entered.
func (s *BaseManuscriptListener) EnterDeclType(ctx *DeclTypeContext) {}

// ExitDeclType is called when production DeclType is exited.
func (s *BaseManuscriptListener) ExitDeclType(ctx *DeclTypeContext) {}

// EnterDeclInterface is called when production DeclInterface is entered.
func (s *BaseManuscriptListener) EnterDeclInterface(ctx *DeclInterfaceContext) {}

// ExitDeclInterface is called when production DeclInterface is exited.
func (s *BaseManuscriptListener) ExitDeclInterface(ctx *DeclInterfaceContext) {}

// EnterDeclFn is called when production DeclFn is entered.
func (s *BaseManuscriptListener) EnterDeclFn(ctx *DeclFnContext) {}

// ExitDeclFn is called when production DeclFn is exited.
func (s *BaseManuscriptListener) ExitDeclFn(ctx *DeclFnContext) {}

// EnterDeclMethods is called when production DeclMethods is entered.
func (s *BaseManuscriptListener) EnterDeclMethods(ctx *DeclMethodsContext) {}

// ExitDeclMethods is called when production DeclMethods is exited.
func (s *BaseManuscriptListener) ExitDeclMethods(ctx *DeclMethodsContext) {}

// EnterStmt_list is called when production stmt_list is entered.
func (s *BaseManuscriptListener) EnterStmt_list(ctx *Stmt_listContext) {}

// ExitStmt_list is called when production stmt_list is exited.
func (s *BaseManuscriptListener) ExitStmt_list(ctx *Stmt_listContext) {}

// EnterImportDecl is called when production importDecl is entered.
func (s *BaseManuscriptListener) EnterImportDecl(ctx *ImportDeclContext) {}

// ExitImportDecl is called when production importDecl is exited.
func (s *BaseManuscriptListener) ExitImportDecl(ctx *ImportDeclContext) {}

// EnterExportDecl is called when production exportDecl is entered.
func (s *BaseManuscriptListener) EnterExportDecl(ctx *ExportDeclContext) {}

// ExitExportDecl is called when production exportDecl is exited.
func (s *BaseManuscriptListener) ExitExportDecl(ctx *ExportDeclContext) {}

// EnterExternDecl is called when production externDecl is entered.
func (s *BaseManuscriptListener) EnterExternDecl(ctx *ExternDeclContext) {}

// ExitExternDecl is called when production externDecl is exited.
func (s *BaseManuscriptListener) ExitExternDecl(ctx *ExternDeclContext) {}

// EnterExportedFn is called when production ExportedFn is entered.
func (s *BaseManuscriptListener) EnterExportedFn(ctx *ExportedFnContext) {}

// ExitExportedFn is called when production ExportedFn is exited.
func (s *BaseManuscriptListener) ExitExportedFn(ctx *ExportedFnContext) {}

// EnterExportedLet is called when production ExportedLet is entered.
func (s *BaseManuscriptListener) EnterExportedLet(ctx *ExportedLetContext) {}

// ExitExportedLet is called when production ExportedLet is exited.
func (s *BaseManuscriptListener) ExitExportedLet(ctx *ExportedLetContext) {}

// EnterExportedType is called when production ExportedType is entered.
func (s *BaseManuscriptListener) EnterExportedType(ctx *ExportedTypeContext) {}

// ExitExportedType is called when production ExportedType is exited.
func (s *BaseManuscriptListener) ExitExportedType(ctx *ExportedTypeContext) {}

// EnterExportedInterface is called when production ExportedInterface is entered.
func (s *BaseManuscriptListener) EnterExportedInterface(ctx *ExportedInterfaceContext) {}

// ExitExportedInterface is called when production ExportedInterface is exited.
func (s *BaseManuscriptListener) ExitExportedInterface(ctx *ExportedInterfaceContext) {}

// EnterModuleImportDestructured is called when production ModuleImportDestructured is entered.
func (s *BaseManuscriptListener) EnterModuleImportDestructured(ctx *ModuleImportDestructuredContext) {
}

// ExitModuleImportDestructured is called when production ModuleImportDestructured is exited.
func (s *BaseManuscriptListener) ExitModuleImportDestructured(ctx *ModuleImportDestructuredContext) {}

// EnterModuleImportTarget is called when production ModuleImportTarget is entered.
func (s *BaseManuscriptListener) EnterModuleImportTarget(ctx *ModuleImportTargetContext) {}

// ExitModuleImportTarget is called when production ModuleImportTarget is exited.
func (s *BaseManuscriptListener) ExitModuleImportTarget(ctx *ModuleImportTargetContext) {}

// EnterDestructuredImport is called when production destructuredImport is entered.
func (s *BaseManuscriptListener) EnterDestructuredImport(ctx *DestructuredImportContext) {}

// ExitDestructuredImport is called when production destructuredImport is exited.
func (s *BaseManuscriptListener) ExitDestructuredImport(ctx *DestructuredImportContext) {}

// EnterTargetImport is called when production targetImport is entered.
func (s *BaseManuscriptListener) EnterTargetImport(ctx *TargetImportContext) {}

// ExitTargetImport is called when production targetImport is exited.
func (s *BaseManuscriptListener) ExitTargetImport(ctx *TargetImportContext) {}

// EnterImportItemList is called when production importItemList is entered.
func (s *BaseManuscriptListener) EnterImportItemList(ctx *ImportItemListContext) {}

// ExitImportItemList is called when production importItemList is exited.
func (s *BaseManuscriptListener) ExitImportItemList(ctx *ImportItemListContext) {}

// EnterImportItem is called when production importItem is entered.
func (s *BaseManuscriptListener) EnterImportItem(ctx *ImportItemContext) {}

// ExitImportItem is called when production importItem is exited.
func (s *BaseManuscriptListener) ExitImportItem(ctx *ImportItemContext) {}

// EnterImportStr is called when production importStr is entered.
func (s *BaseManuscriptListener) EnterImportStr(ctx *ImportStrContext) {}

// ExitImportStr is called when production importStr is exited.
func (s *BaseManuscriptListener) ExitImportStr(ctx *ImportStrContext) {}

// EnterLetDecl is called when production letDecl is entered.
func (s *BaseManuscriptListener) EnterLetDecl(ctx *LetDeclContext) {}

// ExitLetDecl is called when production letDecl is exited.
func (s *BaseManuscriptListener) ExitLetDecl(ctx *LetDeclContext) {}

// EnterLetPatternSingle is called when production LetPatternSingle is entered.
func (s *BaseManuscriptListener) EnterLetPatternSingle(ctx *LetPatternSingleContext) {}

// ExitLetPatternSingle is called when production LetPatternSingle is exited.
func (s *BaseManuscriptListener) ExitLetPatternSingle(ctx *LetPatternSingleContext) {}

// EnterLetPatternBlock is called when production LetPatternBlock is entered.
func (s *BaseManuscriptListener) EnterLetPatternBlock(ctx *LetPatternBlockContext) {}

// ExitLetPatternBlock is called when production LetPatternBlock is exited.
func (s *BaseManuscriptListener) ExitLetPatternBlock(ctx *LetPatternBlockContext) {}

// EnterLetPatternDestructuredObj is called when production LetPatternDestructuredObj is entered.
func (s *BaseManuscriptListener) EnterLetPatternDestructuredObj(ctx *LetPatternDestructuredObjContext) {
}

// ExitLetPatternDestructuredObj is called when production LetPatternDestructuredObj is exited.
func (s *BaseManuscriptListener) ExitLetPatternDestructuredObj(ctx *LetPatternDestructuredObjContext) {
}

// EnterLetPatternDestructuredArray is called when production LetPatternDestructuredArray is entered.
func (s *BaseManuscriptListener) EnterLetPatternDestructuredArray(ctx *LetPatternDestructuredArrayContext) {
}

// ExitLetPatternDestructuredArray is called when production LetPatternDestructuredArray is exited.
func (s *BaseManuscriptListener) ExitLetPatternDestructuredArray(ctx *LetPatternDestructuredArrayContext) {
}

// EnterLetSingle is called when production letSingle is entered.
func (s *BaseManuscriptListener) EnterLetSingle(ctx *LetSingleContext) {}

// ExitLetSingle is called when production letSingle is exited.
func (s *BaseManuscriptListener) ExitLetSingle(ctx *LetSingleContext) {}

// EnterLetBlock is called when production letBlock is entered.
func (s *BaseManuscriptListener) EnterLetBlock(ctx *LetBlockContext) {}

// ExitLetBlock is called when production letBlock is exited.
func (s *BaseManuscriptListener) ExitLetBlock(ctx *LetBlockContext) {}

// EnterLetBlockItemSingle is called when production LetBlockItemSingle is entered.
func (s *BaseManuscriptListener) EnterLetBlockItemSingle(ctx *LetBlockItemSingleContext) {}

// ExitLetBlockItemSingle is called when production LetBlockItemSingle is exited.
func (s *BaseManuscriptListener) ExitLetBlockItemSingle(ctx *LetBlockItemSingleContext) {}

// EnterLetBlockItemDestructuredObj is called when production LetBlockItemDestructuredObj is entered.
func (s *BaseManuscriptListener) EnterLetBlockItemDestructuredObj(ctx *LetBlockItemDestructuredObjContext) {
}

// ExitLetBlockItemDestructuredObj is called when production LetBlockItemDestructuredObj is exited.
func (s *BaseManuscriptListener) ExitLetBlockItemDestructuredObj(ctx *LetBlockItemDestructuredObjContext) {
}

// EnterLetBlockItemDestructuredArray is called when production LetBlockItemDestructuredArray is entered.
func (s *BaseManuscriptListener) EnterLetBlockItemDestructuredArray(ctx *LetBlockItemDestructuredArrayContext) {
}

// ExitLetBlockItemDestructuredArray is called when production LetBlockItemDestructuredArray is exited.
func (s *BaseManuscriptListener) ExitLetBlockItemDestructuredArray(ctx *LetBlockItemDestructuredArrayContext) {
}

// EnterLetDestructuredObj is called when production letDestructuredObj is entered.
func (s *BaseManuscriptListener) EnterLetDestructuredObj(ctx *LetDestructuredObjContext) {}

// ExitLetDestructuredObj is called when production letDestructuredObj is exited.
func (s *BaseManuscriptListener) ExitLetDestructuredObj(ctx *LetDestructuredObjContext) {}

// EnterLetDestructuredArray is called when production letDestructuredArray is entered.
func (s *BaseManuscriptListener) EnterLetDestructuredArray(ctx *LetDestructuredArrayContext) {}

// ExitLetDestructuredArray is called when production letDestructuredArray is exited.
func (s *BaseManuscriptListener) ExitLetDestructuredArray(ctx *LetDestructuredArrayContext) {}

// EnterTypedIDList is called when production typedIDList is entered.
func (s *BaseManuscriptListener) EnterTypedIDList(ctx *TypedIDListContext) {}

// ExitTypedIDList is called when production typedIDList is exited.
func (s *BaseManuscriptListener) ExitTypedIDList(ctx *TypedIDListContext) {}

// EnterTypedID is called when production typedID is entered.
func (s *BaseManuscriptListener) EnterTypedID(ctx *TypedIDContext) {}

// ExitTypedID is called when production typedID is exited.
func (s *BaseManuscriptListener) ExitTypedID(ctx *TypedIDContext) {}

// EnterTypeDecl is called when production typeDecl is entered.
func (s *BaseManuscriptListener) EnterTypeDecl(ctx *TypeDeclContext) {}

// ExitTypeDecl is called when production typeDecl is exited.
func (s *BaseManuscriptListener) ExitTypeDecl(ctx *TypeDeclContext) {}

// EnterTypeVariants is called when production typeVariants is entered.
func (s *BaseManuscriptListener) EnterTypeVariants(ctx *TypeVariantsContext) {}

// ExitTypeVariants is called when production typeVariants is exited.
func (s *BaseManuscriptListener) ExitTypeVariants(ctx *TypeVariantsContext) {}

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

// EnterTypeList is called when production typeList is entered.
func (s *BaseManuscriptListener) EnterTypeList(ctx *TypeListContext) {}

// ExitTypeList is called when production typeList is exited.
func (s *BaseManuscriptListener) ExitTypeList(ctx *TypeListContext) {}

// EnterInterfaceDecl is called when production interfaceDecl is entered.
func (s *BaseManuscriptListener) EnterInterfaceDecl(ctx *InterfaceDeclContext) {}

// ExitInterfaceDecl is called when production interfaceDecl is exited.
func (s *BaseManuscriptListener) ExitInterfaceDecl(ctx *InterfaceDeclContext) {}

// EnterInterfaceMethod is called when production interfaceMethod is entered.
func (s *BaseManuscriptListener) EnterInterfaceMethod(ctx *InterfaceMethodContext) {}

// ExitInterfaceMethod is called when production interfaceMethod is exited.
func (s *BaseManuscriptListener) ExitInterfaceMethod(ctx *InterfaceMethodContext) {}

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

// EnterMethodsDecl is called when production methodsDecl is entered.
func (s *BaseManuscriptListener) EnterMethodsDecl(ctx *MethodsDeclContext) {}

// ExitMethodsDecl is called when production methodsDecl is exited.
func (s *BaseManuscriptListener) ExitMethodsDecl(ctx *MethodsDeclContext) {}

// EnterMethodImpl is called when production methodImpl is entered.
func (s *BaseManuscriptListener) EnterMethodImpl(ctx *MethodImplContext) {}

// ExitMethodImpl is called when production methodImpl is exited.
func (s *BaseManuscriptListener) ExitMethodImpl(ctx *MethodImplContext) {}

// EnterStmtLet is called when production StmtLet is entered.
func (s *BaseManuscriptListener) EnterStmtLet(ctx *StmtLetContext) {}

// ExitStmtLet is called when production StmtLet is exited.
func (s *BaseManuscriptListener) ExitStmtLet(ctx *StmtLetContext) {}

// EnterStmtExpr is called when production StmtExpr is entered.
func (s *BaseManuscriptListener) EnterStmtExpr(ctx *StmtExprContext) {}

// ExitStmtExpr is called when production StmtExpr is exited.
func (s *BaseManuscriptListener) ExitStmtExpr(ctx *StmtExprContext) {}

// EnterStmtReturn is called when production StmtReturn is entered.
func (s *BaseManuscriptListener) EnterStmtReturn(ctx *StmtReturnContext) {}

// ExitStmtReturn is called when production StmtReturn is exited.
func (s *BaseManuscriptListener) ExitStmtReturn(ctx *StmtReturnContext) {}

// EnterStmtYield is called when production StmtYield is entered.
func (s *BaseManuscriptListener) EnterStmtYield(ctx *StmtYieldContext) {}

// ExitStmtYield is called when production StmtYield is exited.
func (s *BaseManuscriptListener) ExitStmtYield(ctx *StmtYieldContext) {}

// EnterStmtIf is called when production StmtIf is entered.
func (s *BaseManuscriptListener) EnterStmtIf(ctx *StmtIfContext) {}

// ExitStmtIf is called when production StmtIf is exited.
func (s *BaseManuscriptListener) ExitStmtIf(ctx *StmtIfContext) {}

// EnterStmtFor is called when production StmtFor is entered.
func (s *BaseManuscriptListener) EnterStmtFor(ctx *StmtForContext) {}

// ExitStmtFor is called when production StmtFor is exited.
func (s *BaseManuscriptListener) ExitStmtFor(ctx *StmtForContext) {}

// EnterStmtWhile is called when production StmtWhile is entered.
func (s *BaseManuscriptListener) EnterStmtWhile(ctx *StmtWhileContext) {}

// ExitStmtWhile is called when production StmtWhile is exited.
func (s *BaseManuscriptListener) ExitStmtWhile(ctx *StmtWhileContext) {}

// EnterStmtBlock is called when production StmtBlock is entered.
func (s *BaseManuscriptListener) EnterStmtBlock(ctx *StmtBlockContext) {}

// ExitStmtBlock is called when production StmtBlock is exited.
func (s *BaseManuscriptListener) ExitStmtBlock(ctx *StmtBlockContext) {}

// EnterStmtBreak is called when production StmtBreak is entered.
func (s *BaseManuscriptListener) EnterStmtBreak(ctx *StmtBreakContext) {}

// ExitStmtBreak is called when production StmtBreak is exited.
func (s *BaseManuscriptListener) ExitStmtBreak(ctx *StmtBreakContext) {}

// EnterStmtContinue is called when production StmtContinue is entered.
func (s *BaseManuscriptListener) EnterStmtContinue(ctx *StmtContinueContext) {}

// ExitStmtContinue is called when production StmtContinue is exited.
func (s *BaseManuscriptListener) ExitStmtContinue(ctx *StmtContinueContext) {}

// EnterStmtCheck is called when production StmtCheck is entered.
func (s *BaseManuscriptListener) EnterStmtCheck(ctx *StmtCheckContext) {}

// ExitStmtCheck is called when production StmtCheck is exited.
func (s *BaseManuscriptListener) ExitStmtCheck(ctx *StmtCheckContext) {}

// EnterStmtDefer is called when production StmtDefer is entered.
func (s *BaseManuscriptListener) EnterStmtDefer(ctx *StmtDeferContext) {}

// ExitStmtDefer is called when production StmtDefer is exited.
func (s *BaseManuscriptListener) ExitStmtDefer(ctx *StmtDeferContext) {}

// EnterReturnStmt is called when production returnStmt is entered.
func (s *BaseManuscriptListener) EnterReturnStmt(ctx *ReturnStmtContext) {}

// ExitReturnStmt is called when production returnStmt is exited.
func (s *BaseManuscriptListener) ExitReturnStmt(ctx *ReturnStmtContext) {}

// EnterYieldStmt is called when production yieldStmt is entered.
func (s *BaseManuscriptListener) EnterYieldStmt(ctx *YieldStmtContext) {}

// ExitYieldStmt is called when production yieldStmt is exited.
func (s *BaseManuscriptListener) ExitYieldStmt(ctx *YieldStmtContext) {}

// EnterDeferStmt is called when production deferStmt is entered.
func (s *BaseManuscriptListener) EnterDeferStmt(ctx *DeferStmtContext) {}

// ExitDeferStmt is called when production deferStmt is exited.
func (s *BaseManuscriptListener) ExitDeferStmt(ctx *DeferStmtContext) {}

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

// EnterForLoopType is called when production forLoopType is entered.
func (s *BaseManuscriptListener) EnterForLoopType(ctx *ForLoopTypeContext) {}

// ExitForLoopType is called when production forLoopType is exited.
func (s *BaseManuscriptListener) ExitForLoopType(ctx *ForLoopTypeContext) {}

// EnterForTrinity is called when production forTrinity is entered.
func (s *BaseManuscriptListener) EnterForTrinity(ctx *ForTrinityContext) {}

// ExitForTrinity is called when production forTrinity is exited.
func (s *BaseManuscriptListener) ExitForTrinity(ctx *ForTrinityContext) {}

// EnterForInit is called when production forInit is entered.
func (s *BaseManuscriptListener) EnterForInit(ctx *ForInitContext) {}

// ExitForInit is called when production forInit is exited.
func (s *BaseManuscriptListener) ExitForInit(ctx *ForInitContext) {}

// EnterForCond is called when production forCond is entered.
func (s *BaseManuscriptListener) EnterForCond(ctx *ForCondContext) {}

// ExitForCond is called when production forCond is exited.
func (s *BaseManuscriptListener) ExitForCond(ctx *ForCondContext) {}

// EnterForPost is called when production forPost is entered.
func (s *BaseManuscriptListener) EnterForPost(ctx *ForPostContext) {}

// ExitForPost is called when production forPost is exited.
func (s *BaseManuscriptListener) ExitForPost(ctx *ForPostContext) {}

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

// EnterExpr is called when production expr is entered.
func (s *BaseManuscriptListener) EnterExpr(ctx *ExprContext) {}

// ExitExpr is called when production expr is exited.
func (s *BaseManuscriptListener) ExitExpr(ctx *ExprContext) {}

// EnterAssignmentExpr is called when production assignmentExpr is entered.
func (s *BaseManuscriptListener) EnterAssignmentExpr(ctx *AssignmentExprContext) {}

// ExitAssignmentExpr is called when production assignmentExpr is exited.
func (s *BaseManuscriptListener) ExitAssignmentExpr(ctx *AssignmentExprContext) {}

// EnterAssignmentOp is called when production assignmentOp is entered.
func (s *BaseManuscriptListener) EnterAssignmentOp(ctx *AssignmentOpContext) {}

// ExitAssignmentOp is called when production assignmentOp is exited.
func (s *BaseManuscriptListener) ExitAssignmentOp(ctx *AssignmentOpContext) {}

// EnterTernaryExpr is called when production ternaryExpr is entered.
func (s *BaseManuscriptListener) EnterTernaryExpr(ctx *TernaryExprContext) {}

// ExitTernaryExpr is called when production ternaryExpr is exited.
func (s *BaseManuscriptListener) ExitTernaryExpr(ctx *TernaryExprContext) {}

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

// EnterPostfixOp is called when production postfixOp is entered.
func (s *BaseManuscriptListener) EnterPostfixOp(ctx *PostfixOpContext) {}

// ExitPostfixOp is called when production postfixOp is exited.
func (s *BaseManuscriptListener) ExitPostfixOp(ctx *PostfixOpContext) {}

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

// EnterStringLiteralSingle is called when production StringLiteralSingle is entered.
func (s *BaseManuscriptListener) EnterStringLiteralSingle(ctx *StringLiteralSingleContext) {}

// ExitStringLiteralSingle is called when production StringLiteralSingle is exited.
func (s *BaseManuscriptListener) ExitStringLiteralSingle(ctx *StringLiteralSingleContext) {}

// EnterStringLiteralMulti is called when production StringLiteralMulti is entered.
func (s *BaseManuscriptListener) EnterStringLiteralMulti(ctx *StringLiteralMultiContext) {}

// ExitStringLiteralMulti is called when production StringLiteralMulti is exited.
func (s *BaseManuscriptListener) ExitStringLiteralMulti(ctx *StringLiteralMultiContext) {}

// EnterStringLiteralDouble is called when production StringLiteralDouble is entered.
func (s *BaseManuscriptListener) EnterStringLiteralDouble(ctx *StringLiteralDoubleContext) {}

// ExitStringLiteralDouble is called when production StringLiteralDouble is exited.
func (s *BaseManuscriptListener) ExitStringLiteralDouble(ctx *StringLiteralDoubleContext) {}

// EnterStringLiteralMultiDouble is called when production StringLiteralMultiDouble is entered.
func (s *BaseManuscriptListener) EnterStringLiteralMultiDouble(ctx *StringLiteralMultiDoubleContext) {
}

// ExitStringLiteralMultiDouble is called when production StringLiteralMultiDouble is exited.
func (s *BaseManuscriptListener) ExitStringLiteralMultiDouble(ctx *StringLiteralMultiDoubleContext) {}

// EnterNumberLiteralInt is called when production NumberLiteralInt is entered.
func (s *BaseManuscriptListener) EnterNumberLiteralInt(ctx *NumberLiteralIntContext) {}

// ExitNumberLiteralInt is called when production NumberLiteralInt is exited.
func (s *BaseManuscriptListener) ExitNumberLiteralInt(ctx *NumberLiteralIntContext) {}

// EnterNumberLiteralFloat is called when production NumberLiteralFloat is entered.
func (s *BaseManuscriptListener) EnterNumberLiteralFloat(ctx *NumberLiteralFloatContext) {}

// ExitNumberLiteralFloat is called when production NumberLiteralFloat is exited.
func (s *BaseManuscriptListener) ExitNumberLiteralFloat(ctx *NumberLiteralFloatContext) {}

// EnterNumberLiteralHex is called when production NumberLiteralHex is entered.
func (s *BaseManuscriptListener) EnterNumberLiteralHex(ctx *NumberLiteralHexContext) {}

// ExitNumberLiteralHex is called when production NumberLiteralHex is exited.
func (s *BaseManuscriptListener) ExitNumberLiteralHex(ctx *NumberLiteralHexContext) {}

// EnterNumberLiteralBin is called when production NumberLiteralBin is entered.
func (s *BaseManuscriptListener) EnterNumberLiteralBin(ctx *NumberLiteralBinContext) {}

// ExitNumberLiteralBin is called when production NumberLiteralBin is exited.
func (s *BaseManuscriptListener) ExitNumberLiteralBin(ctx *NumberLiteralBinContext) {}

// EnterNumberLiteralOct is called when production NumberLiteralOct is entered.
func (s *BaseManuscriptListener) EnterNumberLiteralOct(ctx *NumberLiteralOctContext) {}

// ExitNumberLiteralOct is called when production NumberLiteralOct is exited.
func (s *BaseManuscriptListener) ExitNumberLiteralOct(ctx *NumberLiteralOctContext) {}

// EnterBoolLiteralTrue is called when production BoolLiteralTrue is entered.
func (s *BaseManuscriptListener) EnterBoolLiteralTrue(ctx *BoolLiteralTrueContext) {}

// ExitBoolLiteralTrue is called when production BoolLiteralTrue is exited.
func (s *BaseManuscriptListener) ExitBoolLiteralTrue(ctx *BoolLiteralTrueContext) {}

// EnterBoolLiteralFalse is called when production BoolLiteralFalse is entered.
func (s *BaseManuscriptListener) EnterBoolLiteralFalse(ctx *BoolLiteralFalseContext) {}

// ExitBoolLiteralFalse is called when production BoolLiteralFalse is exited.
func (s *BaseManuscriptListener) ExitBoolLiteralFalse(ctx *BoolLiteralFalseContext) {}

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

// EnterObjectFieldName is called when production objectFieldName is entered.
func (s *BaseManuscriptListener) EnterObjectFieldName(ctx *ObjectFieldNameContext) {}

// ExitObjectFieldName is called when production objectFieldName is exited.
func (s *BaseManuscriptListener) ExitObjectFieldName(ctx *ObjectFieldNameContext) {}

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

// EnterTaggedBlockString is called when production taggedBlockString is entered.
func (s *BaseManuscriptListener) EnterTaggedBlockString(ctx *TaggedBlockStringContext) {}

// ExitTaggedBlockString is called when production taggedBlockString is exited.
func (s *BaseManuscriptListener) ExitTaggedBlockString(ctx *TaggedBlockStringContext) {}

// EnterStructInitExpr is called when production structInitExpr is entered.
func (s *BaseManuscriptListener) EnterStructInitExpr(ctx *StructInitExprContext) {}

// ExitStructInitExpr is called when production structInitExpr is exited.
func (s *BaseManuscriptListener) ExitStructInitExpr(ctx *StructInitExprContext) {}

// EnterStructField is called when production structField is entered.
func (s *BaseManuscriptListener) EnterStructField(ctx *StructFieldContext) {}

// ExitStructField is called when production structField is exited.
func (s *BaseManuscriptListener) ExitStructField(ctx *StructFieldContext) {}

// EnterTypeAnnotation is called when production typeAnnotation is entered.
func (s *BaseManuscriptListener) EnterTypeAnnotation(ctx *TypeAnnotationContext) {}

// ExitTypeAnnotation is called when production typeAnnotation is exited.
func (s *BaseManuscriptListener) ExitTypeAnnotation(ctx *TypeAnnotationContext) {}

// EnterTypeBase is called when production typeBase is entered.
func (s *BaseManuscriptListener) EnterTypeBase(ctx *TypeBaseContext) {}

// ExitTypeBase is called when production typeBase is exited.
func (s *BaseManuscriptListener) ExitTypeBase(ctx *TypeBaseContext) {}

// EnterTupleType is called when production tupleType is entered.
func (s *BaseManuscriptListener) EnterTupleType(ctx *TupleTypeContext) {}

// ExitTupleType is called when production tupleType is exited.
func (s *BaseManuscriptListener) ExitTupleType(ctx *TupleTypeContext) {}

// EnterArrayType is called when production arrayType is entered.
func (s *BaseManuscriptListener) EnterArrayType(ctx *ArrayTypeContext) {}

// ExitArrayType is called when production arrayType is exited.
func (s *BaseManuscriptListener) ExitArrayType(ctx *ArrayTypeContext) {}

// EnterFnType is called when production fnType is entered.
func (s *BaseManuscriptListener) EnterFnType(ctx *FnTypeContext) {}

// ExitFnType is called when production fnType is exited.
func (s *BaseManuscriptListener) ExitFnType(ctx *FnTypeContext) {}

// EnterStmt_sep is called when production stmt_sep is entered.
func (s *BaseManuscriptListener) EnterStmt_sep(ctx *Stmt_sepContext) {}

// ExitStmt_sep is called when production stmt_sep is exited.
func (s *BaseManuscriptListener) ExitStmt_sep(ctx *Stmt_sepContext) {}
