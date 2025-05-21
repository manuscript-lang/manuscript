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

// EnterLetDeclSingle is called when production LetDeclSingle is entered.
func (s *BaseManuscriptListener) EnterLetDeclSingle(ctx *LetDeclSingleContext) {}

// ExitLetDeclSingle is called when production LetDeclSingle is exited.
func (s *BaseManuscriptListener) ExitLetDeclSingle(ctx *LetDeclSingleContext) {}

// EnterLetDeclBlock is called when production LetDeclBlock is entered.
func (s *BaseManuscriptListener) EnterLetDeclBlock(ctx *LetDeclBlockContext) {}

// ExitLetDeclBlock is called when production LetDeclBlock is exited.
func (s *BaseManuscriptListener) ExitLetDeclBlock(ctx *LetDeclBlockContext) {}

// EnterLetDeclDestructuredObj is called when production LetDeclDestructuredObj is entered.
func (s *BaseManuscriptListener) EnterLetDeclDestructuredObj(ctx *LetDeclDestructuredObjContext) {}

// ExitLetDeclDestructuredObj is called when production LetDeclDestructuredObj is exited.
func (s *BaseManuscriptListener) ExitLetDeclDestructuredObj(ctx *LetDeclDestructuredObjContext) {}

// EnterLetDeclDestructuredArray is called when production LetDeclDestructuredArray is entered.
func (s *BaseManuscriptListener) EnterLetDeclDestructuredArray(ctx *LetDeclDestructuredArrayContext) {
}

// ExitLetDeclDestructuredArray is called when production LetDeclDestructuredArray is exited.
func (s *BaseManuscriptListener) ExitLetDeclDestructuredArray(ctx *LetDeclDestructuredArrayContext) {}

// EnterLetSingle is called when production letSingle is entered.
func (s *BaseManuscriptListener) EnterLetSingle(ctx *LetSingleContext) {}

// ExitLetSingle is called when production letSingle is exited.
func (s *BaseManuscriptListener) ExitLetSingle(ctx *LetSingleContext) {}

// EnterLetBlock is called when production letBlock is entered.
func (s *BaseManuscriptListener) EnterLetBlock(ctx *LetBlockContext) {}

// ExitLetBlock is called when production letBlock is exited.
func (s *BaseManuscriptListener) ExitLetBlock(ctx *LetBlockContext) {}

// EnterLetBlockItemList is called when production letBlockItemList is entered.
func (s *BaseManuscriptListener) EnterLetBlockItemList(ctx *LetBlockItemListContext) {}

// ExitLetBlockItemList is called when production letBlockItemList is exited.
func (s *BaseManuscriptListener) ExitLetBlockItemList(ctx *LetBlockItemListContext) {}

// EnterLetBlockItemSep is called when production letBlockItemSep is entered.
func (s *BaseManuscriptListener) EnterLetBlockItemSep(ctx *LetBlockItemSepContext) {}

// ExitLetBlockItemSep is called when production letBlockItemSep is exited.
func (s *BaseManuscriptListener) ExitLetBlockItemSep(ctx *LetBlockItemSepContext) {}

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

// EnterTypeDefBody is called when production typeDefBody is entered.
func (s *BaseManuscriptListener) EnterTypeDefBody(ctx *TypeDefBodyContext) {}

// ExitTypeDefBody is called when production typeDefBody is exited.
func (s *BaseManuscriptListener) ExitTypeDefBody(ctx *TypeDefBodyContext) {}

// EnterTypeAlias is called when production typeAlias is entered.
func (s *BaseManuscriptListener) EnterTypeAlias(ctx *TypeAliasContext) {}

// ExitTypeAlias is called when production typeAlias is exited.
func (s *BaseManuscriptListener) ExitTypeAlias(ctx *TypeAliasContext) {}

// EnterFieldList is called when production fieldList is entered.
func (s *BaseManuscriptListener) EnterFieldList(ctx *FieldListContext) {}

// ExitFieldList is called when production fieldList is exited.
func (s *BaseManuscriptListener) ExitFieldList(ctx *FieldListContext) {}

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

// EnterMethodImplList is called when production methodImplList is entered.
func (s *BaseManuscriptListener) EnterMethodImplList(ctx *MethodImplListContext) {}

// ExitMethodImplList is called when production methodImplList is exited.
func (s *BaseManuscriptListener) ExitMethodImplList(ctx *MethodImplListContext) {}

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

// EnterForInitLet is called when production ForInitLet is entered.
func (s *BaseManuscriptListener) EnterForInitLet(ctx *ForInitLetContext) {}

// ExitForInitLet is called when production ForInitLet is exited.
func (s *BaseManuscriptListener) ExitForInitLet(ctx *ForInitLetContext) {}

// EnterForInitEmpty is called when production ForInitEmpty is entered.
func (s *BaseManuscriptListener) EnterForInitEmpty(ctx *ForInitEmptyContext) {}

// ExitForInitEmpty is called when production ForInitEmpty is exited.
func (s *BaseManuscriptListener) ExitForInitEmpty(ctx *ForInitEmptyContext) {}

// EnterForCondExpr is called when production ForCondExpr is entered.
func (s *BaseManuscriptListener) EnterForCondExpr(ctx *ForCondExprContext) {}

// ExitForCondExpr is called when production ForCondExpr is exited.
func (s *BaseManuscriptListener) ExitForCondExpr(ctx *ForCondExprContext) {}

// EnterForCondEmpty is called when production ForCondEmpty is entered.
func (s *BaseManuscriptListener) EnterForCondEmpty(ctx *ForCondEmptyContext) {}

// ExitForCondEmpty is called when production ForCondEmpty is exited.
func (s *BaseManuscriptListener) ExitForCondEmpty(ctx *ForCondEmptyContext) {}

// EnterForPostExpr is called when production ForPostExpr is entered.
func (s *BaseManuscriptListener) EnterForPostExpr(ctx *ForPostExprContext) {}

// ExitForPostExpr is called when production ForPostExpr is exited.
func (s *BaseManuscriptListener) ExitForPostExpr(ctx *ForPostExprContext) {}

// EnterForPostEmpty is called when production ForPostEmpty is entered.
func (s *BaseManuscriptListener) EnterForPostEmpty(ctx *ForPostEmptyContext) {}

// ExitForPostEmpty is called when production ForPostEmpty is exited.
func (s *BaseManuscriptListener) ExitForPostEmpty(ctx *ForPostEmptyContext) {}

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

// EnterAssignEq is called when production AssignEq is entered.
func (s *BaseManuscriptListener) EnterAssignEq(ctx *AssignEqContext) {}

// ExitAssignEq is called when production AssignEq is exited.
func (s *BaseManuscriptListener) ExitAssignEq(ctx *AssignEqContext) {}

// EnterAssignPlusEq is called when production AssignPlusEq is entered.
func (s *BaseManuscriptListener) EnterAssignPlusEq(ctx *AssignPlusEqContext) {}

// ExitAssignPlusEq is called when production AssignPlusEq is exited.
func (s *BaseManuscriptListener) ExitAssignPlusEq(ctx *AssignPlusEqContext) {}

// EnterAssignMinusEq is called when production AssignMinusEq is entered.
func (s *BaseManuscriptListener) EnterAssignMinusEq(ctx *AssignMinusEqContext) {}

// ExitAssignMinusEq is called when production AssignMinusEq is exited.
func (s *BaseManuscriptListener) ExitAssignMinusEq(ctx *AssignMinusEqContext) {}

// EnterAssignStarEq is called when production AssignStarEq is entered.
func (s *BaseManuscriptListener) EnterAssignStarEq(ctx *AssignStarEqContext) {}

// ExitAssignStarEq is called when production AssignStarEq is exited.
func (s *BaseManuscriptListener) ExitAssignStarEq(ctx *AssignStarEqContext) {}

// EnterAssignSlashEq is called when production AssignSlashEq is entered.
func (s *BaseManuscriptListener) EnterAssignSlashEq(ctx *AssignSlashEqContext) {}

// ExitAssignSlashEq is called when production AssignSlashEq is exited.
func (s *BaseManuscriptListener) ExitAssignSlashEq(ctx *AssignSlashEqContext) {}

// EnterAssignModEq is called when production AssignModEq is entered.
func (s *BaseManuscriptListener) EnterAssignModEq(ctx *AssignModEqContext) {}

// ExitAssignModEq is called when production AssignModEq is exited.
func (s *BaseManuscriptListener) ExitAssignModEq(ctx *AssignModEqContext) {}

// EnterAssignCaretEq is called when production AssignCaretEq is entered.
func (s *BaseManuscriptListener) EnterAssignCaretEq(ctx *AssignCaretEqContext) {}

// ExitAssignCaretEq is called when production AssignCaretEq is exited.
func (s *BaseManuscriptListener) ExitAssignCaretEq(ctx *AssignCaretEqContext) {}

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

// EnterComparisonOp is called when production comparisonOp is entered.
func (s *BaseManuscriptListener) EnterComparisonOp(ctx *ComparisonOpContext) {}

// ExitComparisonOp is called when production comparisonOp is exited.
func (s *BaseManuscriptListener) ExitComparisonOp(ctx *ComparisonOpContext) {}

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

// EnterUnaryOpExpr is called when production UnaryOpExpr is entered.
func (s *BaseManuscriptListener) EnterUnaryOpExpr(ctx *UnaryOpExprContext) {}

// ExitUnaryOpExpr is called when production UnaryOpExpr is exited.
func (s *BaseManuscriptListener) ExitUnaryOpExpr(ctx *UnaryOpExprContext) {}

// EnterUnaryAwaitExpr is called when production UnaryAwaitExpr is entered.
func (s *BaseManuscriptListener) EnterUnaryAwaitExpr(ctx *UnaryAwaitExprContext) {}

// ExitUnaryAwaitExpr is called when production UnaryAwaitExpr is exited.
func (s *BaseManuscriptListener) ExitUnaryAwaitExpr(ctx *UnaryAwaitExprContext) {}

// EnterAwaitExpr is called when production awaitExpr is entered.
func (s *BaseManuscriptListener) EnterAwaitExpr(ctx *AwaitExprContext) {}

// ExitAwaitExpr is called when production awaitExpr is exited.
func (s *BaseManuscriptListener) ExitAwaitExpr(ctx *AwaitExprContext) {}

// EnterPostfixExpr is called when production postfixExpr is entered.
func (s *BaseManuscriptListener) EnterPostfixExpr(ctx *PostfixExprContext) {}

// ExitPostfixExpr is called when production postfixExpr is exited.
func (s *BaseManuscriptListener) ExitPostfixExpr(ctx *PostfixExprContext) {}

// EnterPostfixCall is called when production PostfixCall is entered.
func (s *BaseManuscriptListener) EnterPostfixCall(ctx *PostfixCallContext) {}

// ExitPostfixCall is called when production PostfixCall is exited.
func (s *BaseManuscriptListener) ExitPostfixCall(ctx *PostfixCallContext) {}

// EnterPostfixDot is called when production PostfixDot is entered.
func (s *BaseManuscriptListener) EnterPostfixDot(ctx *PostfixDotContext) {}

// ExitPostfixDot is called when production PostfixDot is exited.
func (s *BaseManuscriptListener) ExitPostfixDot(ctx *PostfixDotContext) {}

// EnterPostfixIndex is called when production PostfixIndex is entered.
func (s *BaseManuscriptListener) EnterPostfixIndex(ctx *PostfixIndexContext) {}

// ExitPostfixIndex is called when production PostfixIndex is exited.
func (s *BaseManuscriptListener) ExitPostfixIndex(ctx *PostfixIndexContext) {}

// EnterPrimaryLiteral is called when production PrimaryLiteral is entered.
func (s *BaseManuscriptListener) EnterPrimaryLiteral(ctx *PrimaryLiteralContext) {}

// ExitPrimaryLiteral is called when production PrimaryLiteral is exited.
func (s *BaseManuscriptListener) ExitPrimaryLiteral(ctx *PrimaryLiteralContext) {}

// EnterPrimaryID is called when production PrimaryID is entered.
func (s *BaseManuscriptListener) EnterPrimaryID(ctx *PrimaryIDContext) {}

// ExitPrimaryID is called when production PrimaryID is exited.
func (s *BaseManuscriptListener) ExitPrimaryID(ctx *PrimaryIDContext) {}

// EnterPrimaryParen is called when production PrimaryParen is entered.
func (s *BaseManuscriptListener) EnterPrimaryParen(ctx *PrimaryParenContext) {}

// ExitPrimaryParen is called when production PrimaryParen is exited.
func (s *BaseManuscriptListener) ExitPrimaryParen(ctx *PrimaryParenContext) {}

// EnterPrimaryArray is called when production PrimaryArray is entered.
func (s *BaseManuscriptListener) EnterPrimaryArray(ctx *PrimaryArrayContext) {}

// ExitPrimaryArray is called when production PrimaryArray is exited.
func (s *BaseManuscriptListener) ExitPrimaryArray(ctx *PrimaryArrayContext) {}

// EnterPrimaryObject is called when production PrimaryObject is entered.
func (s *BaseManuscriptListener) EnterPrimaryObject(ctx *PrimaryObjectContext) {}

// ExitPrimaryObject is called when production PrimaryObject is exited.
func (s *BaseManuscriptListener) ExitPrimaryObject(ctx *PrimaryObjectContext) {}

// EnterPrimaryMap is called when production PrimaryMap is entered.
func (s *BaseManuscriptListener) EnterPrimaryMap(ctx *PrimaryMapContext) {}

// ExitPrimaryMap is called when production PrimaryMap is exited.
func (s *BaseManuscriptListener) ExitPrimaryMap(ctx *PrimaryMapContext) {}

// EnterPrimarySet is called when production PrimarySet is entered.
func (s *BaseManuscriptListener) EnterPrimarySet(ctx *PrimarySetContext) {}

// ExitPrimarySet is called when production PrimarySet is exited.
func (s *BaseManuscriptListener) ExitPrimarySet(ctx *PrimarySetContext) {}

// EnterPrimaryFn is called when production PrimaryFn is entered.
func (s *BaseManuscriptListener) EnterPrimaryFn(ctx *PrimaryFnContext) {}

// ExitPrimaryFn is called when production PrimaryFn is exited.
func (s *BaseManuscriptListener) ExitPrimaryFn(ctx *PrimaryFnContext) {}

// EnterPrimaryMatch is called when production PrimaryMatch is entered.
func (s *BaseManuscriptListener) EnterPrimaryMatch(ctx *PrimaryMatchContext) {}

// ExitPrimaryMatch is called when production PrimaryMatch is exited.
func (s *BaseManuscriptListener) ExitPrimaryMatch(ctx *PrimaryMatchContext) {}

// EnterPrimaryVoid is called when production PrimaryVoid is entered.
func (s *BaseManuscriptListener) EnterPrimaryVoid(ctx *PrimaryVoidContext) {}

// ExitPrimaryVoid is called when production PrimaryVoid is exited.
func (s *BaseManuscriptListener) ExitPrimaryVoid(ctx *PrimaryVoidContext) {}

// EnterPrimaryNull is called when production PrimaryNull is entered.
func (s *BaseManuscriptListener) EnterPrimaryNull(ctx *PrimaryNullContext) {}

// ExitPrimaryNull is called when production PrimaryNull is exited.
func (s *BaseManuscriptListener) ExitPrimaryNull(ctx *PrimaryNullContext) {}

// EnterPrimaryTaggedBlock is called when production PrimaryTaggedBlock is entered.
func (s *BaseManuscriptListener) EnterPrimaryTaggedBlock(ctx *PrimaryTaggedBlockContext) {}

// ExitPrimaryTaggedBlock is called when production PrimaryTaggedBlock is exited.
func (s *BaseManuscriptListener) ExitPrimaryTaggedBlock(ctx *PrimaryTaggedBlockContext) {}

// EnterPrimaryStructInit is called when production PrimaryStructInit is entered.
func (s *BaseManuscriptListener) EnterPrimaryStructInit(ctx *PrimaryStructInitContext) {}

// ExitPrimaryStructInit is called when production PrimaryStructInit is exited.
func (s *BaseManuscriptListener) ExitPrimaryStructInit(ctx *PrimaryStructInitContext) {}

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

// EnterStringPartSingle is called when production StringPartSingle is entered.
func (s *BaseManuscriptListener) EnterStringPartSingle(ctx *StringPartSingleContext) {}

// ExitStringPartSingle is called when production StringPartSingle is exited.
func (s *BaseManuscriptListener) ExitStringPartSingle(ctx *StringPartSingleContext) {}

// EnterStringPartMulti is called when production StringPartMulti is entered.
func (s *BaseManuscriptListener) EnterStringPartMulti(ctx *StringPartMultiContext) {}

// ExitStringPartMulti is called when production StringPartMulti is exited.
func (s *BaseManuscriptListener) ExitStringPartMulti(ctx *StringPartMultiContext) {}

// EnterStringPartDouble is called when production StringPartDouble is entered.
func (s *BaseManuscriptListener) EnterStringPartDouble(ctx *StringPartDoubleContext) {}

// ExitStringPartDouble is called when production StringPartDouble is exited.
func (s *BaseManuscriptListener) ExitStringPartDouble(ctx *StringPartDoubleContext) {}

// EnterStringPartMultiDouble is called when production StringPartMultiDouble is entered.
func (s *BaseManuscriptListener) EnterStringPartMultiDouble(ctx *StringPartMultiDoubleContext) {}

// ExitStringPartMultiDouble is called when production StringPartMultiDouble is exited.
func (s *BaseManuscriptListener) ExitStringPartMultiDouble(ctx *StringPartMultiDoubleContext) {}

// EnterStringPartInterp is called when production StringPartInterp is entered.
func (s *BaseManuscriptListener) EnterStringPartInterp(ctx *StringPartInterpContext) {}

// ExitStringPartInterp is called when production StringPartInterp is exited.
func (s *BaseManuscriptListener) ExitStringPartInterp(ctx *StringPartInterpContext) {}

// EnterInterpolation is called when production interpolation is entered.
func (s *BaseManuscriptListener) EnterInterpolation(ctx *InterpolationContext) {}

// ExitInterpolation is called when production interpolation is exited.
func (s *BaseManuscriptListener) ExitInterpolation(ctx *InterpolationContext) {}

// EnterLiteralString is called when production LiteralString is entered.
func (s *BaseManuscriptListener) EnterLiteralString(ctx *LiteralStringContext) {}

// ExitLiteralString is called when production LiteralString is exited.
func (s *BaseManuscriptListener) ExitLiteralString(ctx *LiteralStringContext) {}

// EnterLiteralNumber is called when production LiteralNumber is entered.
func (s *BaseManuscriptListener) EnterLiteralNumber(ctx *LiteralNumberContext) {}

// ExitLiteralNumber is called when production LiteralNumber is exited.
func (s *BaseManuscriptListener) ExitLiteralNumber(ctx *LiteralNumberContext) {}

// EnterLiteralBool is called when production LiteralBool is entered.
func (s *BaseManuscriptListener) EnterLiteralBool(ctx *LiteralBoolContext) {}

// ExitLiteralBool is called when production LiteralBool is exited.
func (s *BaseManuscriptListener) ExitLiteralBool(ctx *LiteralBoolContext) {}

// EnterLiteralNull is called when production LiteralNull is entered.
func (s *BaseManuscriptListener) EnterLiteralNull(ctx *LiteralNullContext) {}

// ExitLiteralNull is called when production LiteralNull is exited.
func (s *BaseManuscriptListener) ExitLiteralNull(ctx *LiteralNullContext) {}

// EnterLiteralVoid is called when production LiteralVoid is entered.
func (s *BaseManuscriptListener) EnterLiteralVoid(ctx *LiteralVoidContext) {}

// ExitLiteralVoid is called when production LiteralVoid is exited.
func (s *BaseManuscriptListener) ExitLiteralVoid(ctx *LiteralVoidContext) {}

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

// EnterObjectFieldList is called when production objectFieldList is entered.
func (s *BaseManuscriptListener) EnterObjectFieldList(ctx *ObjectFieldListContext) {}

// ExitObjectFieldList is called when production objectFieldList is exited.
func (s *BaseManuscriptListener) ExitObjectFieldList(ctx *ObjectFieldListContext) {}

// EnterObjectField is called when production objectField is entered.
func (s *BaseManuscriptListener) EnterObjectField(ctx *ObjectFieldContext) {}

// ExitObjectField is called when production objectField is exited.
func (s *BaseManuscriptListener) ExitObjectField(ctx *ObjectFieldContext) {}

// EnterObjectFieldNameID is called when production ObjectFieldNameID is entered.
func (s *BaseManuscriptListener) EnterObjectFieldNameID(ctx *ObjectFieldNameIDContext) {}

// ExitObjectFieldNameID is called when production ObjectFieldNameID is exited.
func (s *BaseManuscriptListener) ExitObjectFieldNameID(ctx *ObjectFieldNameIDContext) {}

// EnterObjectFieldNameStr is called when production ObjectFieldNameStr is entered.
func (s *BaseManuscriptListener) EnterObjectFieldNameStr(ctx *ObjectFieldNameStrContext) {}

// ExitObjectFieldNameStr is called when production ObjectFieldNameStr is exited.
func (s *BaseManuscriptListener) ExitObjectFieldNameStr(ctx *ObjectFieldNameStrContext) {}

// EnterMapLiteralEmpty is called when production MapLiteralEmpty is entered.
func (s *BaseManuscriptListener) EnterMapLiteralEmpty(ctx *MapLiteralEmptyContext) {}

// ExitMapLiteralEmpty is called when production MapLiteralEmpty is exited.
func (s *BaseManuscriptListener) ExitMapLiteralEmpty(ctx *MapLiteralEmptyContext) {}

// EnterMapLiteralNonEmpty is called when production MapLiteralNonEmpty is entered.
func (s *BaseManuscriptListener) EnterMapLiteralNonEmpty(ctx *MapLiteralNonEmptyContext) {}

// ExitMapLiteralNonEmpty is called when production MapLiteralNonEmpty is exited.
func (s *BaseManuscriptListener) ExitMapLiteralNonEmpty(ctx *MapLiteralNonEmptyContext) {}

// EnterMapFieldList is called when production mapFieldList is entered.
func (s *BaseManuscriptListener) EnterMapFieldList(ctx *MapFieldListContext) {}

// ExitMapFieldList is called when production mapFieldList is exited.
func (s *BaseManuscriptListener) ExitMapFieldList(ctx *MapFieldListContext) {}

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

// EnterStructFieldList is called when production structFieldList is entered.
func (s *BaseManuscriptListener) EnterStructFieldList(ctx *StructFieldListContext) {}

// ExitStructFieldList is called when production structFieldList is exited.
func (s *BaseManuscriptListener) ExitStructFieldList(ctx *StructFieldListContext) {}

// EnterStructField is called when production structField is entered.
func (s *BaseManuscriptListener) EnterStructField(ctx *StructFieldContext) {}

// ExitStructField is called when production structField is exited.
func (s *BaseManuscriptListener) ExitStructField(ctx *StructFieldContext) {}

// EnterTypeAnnID is called when production TypeAnnID is entered.
func (s *BaseManuscriptListener) EnterTypeAnnID(ctx *TypeAnnIDContext) {}

// ExitTypeAnnID is called when production TypeAnnID is exited.
func (s *BaseManuscriptListener) ExitTypeAnnID(ctx *TypeAnnIDContext) {}

// EnterTypeAnnArray is called when production TypeAnnArray is entered.
func (s *BaseManuscriptListener) EnterTypeAnnArray(ctx *TypeAnnArrayContext) {}

// ExitTypeAnnArray is called when production TypeAnnArray is exited.
func (s *BaseManuscriptListener) ExitTypeAnnArray(ctx *TypeAnnArrayContext) {}

// EnterTypeAnnTuple is called when production TypeAnnTuple is entered.
func (s *BaseManuscriptListener) EnterTypeAnnTuple(ctx *TypeAnnTupleContext) {}

// ExitTypeAnnTuple is called when production TypeAnnTuple is exited.
func (s *BaseManuscriptListener) ExitTypeAnnTuple(ctx *TypeAnnTupleContext) {}

// EnterTypeAnnFn is called when production TypeAnnFn is entered.
func (s *BaseManuscriptListener) EnterTypeAnnFn(ctx *TypeAnnFnContext) {}

// ExitTypeAnnFn is called when production TypeAnnFn is exited.
func (s *BaseManuscriptListener) ExitTypeAnnFn(ctx *TypeAnnFnContext) {}

// EnterTypeAnnVoid is called when production TypeAnnVoid is entered.
func (s *BaseManuscriptListener) EnterTypeAnnVoid(ctx *TypeAnnVoidContext) {}

// ExitTypeAnnVoid is called when production TypeAnnVoid is exited.
func (s *BaseManuscriptListener) ExitTypeAnnVoid(ctx *TypeAnnVoidContext) {}

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
