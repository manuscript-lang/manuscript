parser grammar Manuscript;

options {
	tokenVocab = ManuscriptLexer;
}

// --- Program Structure ---
program:
	stmt_sep* (declaration (stmt_sep+ declaration)*)? stmt_sep* EOF;

declaration:
	importDecl		
	| exportDecl	
	| externDecl	
	| letDecl		
	| typeDecl		
	| interfaceDecl	
	| fnDecl		
	| methodsDecl	
	;

// --- Imports/Exports/Extern ---
importDecl: IMPORT moduleImport SEMICOLON?;
exportDecl: EXPORT exportedItem SEMICOLON?;
externDecl: EXTERN moduleImport SEMICOLON?;

exportedItem:
	fnDecl			
	| letDecl		
	| typeDecl		
	| interfaceDecl;
moduleImport:
	destructuredImport	
	| targetImport;
destructuredImport:
	LBRACE importItemList? RBRACE FROM singleQuotedString;
targetImport: ID FROM singleQuotedString;
importItemList: importItem (COMMA importItem)* (COMMA)?;
importItem: ID (AS ID)?;

// --- Let Declarations ---
letDecl:
	LET letSingle SEMICOLON?				
	| LET letBlock SEMICOLON?			
	| LET letDestructuredObj SEMICOLON?	
	| LET letDestructuredArray SEMICOLON?;

letSingle: typedID (EQUALS expr)?;
letBlock: LPAREN letBlockItemList? RPAREN;
letBlockItemList:
	letBlockItemSep* letBlockItem (letBlockItemSep+ letBlockItem)* letBlockItemSep*;
letBlockItemSep: COMMA | stmt_sep;
letBlockItem:
	typedID EQUALS expr						# LabelLetBlockItemSingle
	| LBRACE typedIDList RBRACE EQUALS expr	# LabelLetBlockItemDestructuredObj
	| LSQBR typedIDList RSQBR EQUALS expr	# LabelLetBlockItemDestructuredArray;
letDestructuredObj: LBRACE typedIDList RBRACE EQUALS expr;
letDestructuredArray: LSQBR typedIDList RSQBR EQUALS expr;

typedIDList: typedID (COMMA typedID)* (COMMA)?;
typedID: ID (typeAnnotation)?;

// --- Type & Interface Declarations ---
typeDecl: TYPE ID (typeDefBody | typeAlias);
typeDefBody: (EXTENDS typeList)? LBRACE (
		stmt_sep* fieldDecl (stmt_sep* COMMA stmt_sep* fieldDecl)* (
			stmt_sep* COMMA
		)? stmt_sep*
	)? RBRACE;
typeAlias: EQUALS typeAnnotation (EXTENDS typeList)?;
fieldList: fieldDecl (COMMA fieldDecl)* (COMMA)?;
fieldDecl: ID (QUESTION)? typeAnnotation;

typeList: typeAnnotation (COMMA typeAnnotation)* (COMMA)?;

interfaceDecl:
	INTERFACE ID (EXTENDS typeList)? LBRACE (
		stmt_sep* interfaceMethod stmt_sep*
	)+ RBRACE;
interfaceMethod:
	ID LPAREN parameters? RPAREN (typeAnnotation)? (EXCLAMATION)?;

// --- Function & Methods ---
fnDecl: fnSignature codeBlock;
fnSignature:
	FN ID LPAREN parameters? RPAREN (typeAnnotation)? (
		EXCLAMATION
	)?;
parameters: param (COMMA param)* (COMMA)?;
param: ID typeAnnotation (EQUALS expr)?;

methodsDecl: METHODS ID AS ID LBRACE methodImplList? RBRACE;
methodImplList:
	stmt_sep* methodImpl (stmt_sep+ methodImpl)* stmt_sep*;
methodImpl: interfaceMethod codeBlock;

// --- Statements ---
stmt:
	letDecl				# LabelStmtLet
	| expr SEMICOLON?	# LabelStmtExpr
	| returnStmt		# LabelStmtReturn
	| yieldStmt			# LabelStmtYield
	| ifStmt			# LabelStmtIf
	| forStmt			# LabelStmtFor
	| whileStmt			# LabelStmtWhile
	| codeBlock			# LabelStmtBlock
	| breakStmt			# LabelStmtBreak
	| continueStmt		# LabelStmtContinue
	| checkStmt			# LabelStmtCheck
	| deferStmt			# LabelStmtDefer;

returnStmt: RETURN exprList? SEMICOLON?;
yieldStmt: YIELD exprList? SEMICOLON?;
deferStmt: DEFER expr SEMICOLON?;
exprList: expr (COMMA expr)* (COMMA)?;

ifStmt: IF expr codeBlock (ELSE codeBlock)?;
forStmt: FOR forLoopType;
forLoopType:
	forTrinity							# LabelForLoop
	| (ID (COMMA ID)?) IN expr loopBody	# LabelForInLoop;
forTrinity:
	forInit SEMICOLON forCond SEMICOLON forPost loopBody;
forInit: letSingle # LabelForInitLet | /* empty */ # LabelForInitEmpty;
forCond: expr # LabelForCondExpr | /* empty */ # LabelForCondEmpty;
forPost: expr # LabelForPostExpr | /* empty */ # LabelForPostEmpty;
whileStmt: WHILE expr loopBody;
loopBody:
	LBRACE stmt_sep* (stmt (stmt_sep+ stmt)*)? stmt_sep* RBRACE;
codeBlock:
	LBRACE stmt_sep* (stmt (stmt_sep+ stmt)*)? stmt_sep* RBRACE;
breakStmt: BREAK SEMICOLON?;
continueStmt: CONTINUE SEMICOLON?;
checkStmt: CHECK expr COMMA stringLiteral SEMICOLON?;

// --- Expressions --- Entry point for all expressions
expr: assignmentExpr;

// Assignment expressions (right-associative)
assignmentExpr:
	ternaryExpr
	| left = ternaryExpr op = assignmentOp right = assignmentExpr;
assignmentOp:
	EQUALS		
	| PLUS_EQUALS
	| MINUS_EQUALS
	| STAR_EQUALS
	| SLASH_EQUALS
	| MOD_EQUALS
	| CARET_EQUALS;

// Ternary conditional expression
ternaryExpr:
	logicalOrExpr
	| cond = logicalOrExpr QUESTION thenBranch = expr COLON elseExpr = ternaryExpr;

// Logical expressions
logicalOrExpr:
	logicalAndExpr
	| left = logicalOrExpr op = PIPE_PIPE right = logicalAndExpr;
logicalAndExpr:
	bitwiseOrExpr
	| left = logicalAndExpr op = AMP_AMP right = bitwiseOrExpr;

// Bitwise expressions
bitwiseOrExpr:
	bitwiseXorExpr
	| left = bitwiseOrExpr op = PIPE right = bitwiseXorExpr;
bitwiseXorExpr:
	bitwiseAndExpr
	| left = bitwiseXorExpr op = CARET right = bitwiseAndExpr;
bitwiseAndExpr:
	equalityExpr
	| left = bitwiseAndExpr op = AMP right = equalityExpr;

// Equality and comparison
equalityExpr:
	comparisonExpr
	| left = equalityExpr op = (EQUALS_EQUALS | NEQ) right = comparisonExpr;
comparisonOp: LT | LT_EQUALS | GT | GT_EQUALS;

comparisonExpr:
	shiftExpr
	| left = comparisonExpr op = comparisonOp right = shiftExpr;

// Arithmetic expressions
shiftExpr:
	additiveExpr
	| left = shiftExpr op = (PLUS | MINUS) right = additiveExpr;
additiveExpr:
	multiplicativeExpr
	| left = additiveExpr op = (PLUS | MINUS) right = multiplicativeExpr;
multiplicativeExpr:
	unaryExpr
	| left = multiplicativeExpr op = (STAR | SLASH | MOD) right = unaryExpr;

// Unary and postfix expressions
unaryExpr:
	op = (PLUS | MINUS | EXCLAMATION | TRY) unary = unaryExpr	# LabelUnaryOpExpr
	| awaitExpr													# LabelUnaryAwaitExpr;
awaitExpr: (TRY? AWAIT? ASYNC?) postfixExpr;
postfixExpr: primaryExpr | postfixExpr postfixOp;
postfixOp:
	LPAREN exprList? RPAREN	# LabelPostfixCall
	| DOT ID				# LabelPostfixDot
	| LSQBR expr RSQBR		# LabelPostfixIndex;

// Primary expressions (literals, identifiers, grouping, etc.)
primaryExpr:
	literal					# LabelPrimaryLiteral
	| ID					# LabelPrimaryID
	| LPAREN expr RPAREN	# LabelPrimaryParen
	| arrayLiteral			# LabelPrimaryArray
	| objectLiteral			# LabelPrimaryObject
	| mapLiteral			# LabelPrimaryMap
	| setLiteral			# LabelPrimarySet
	| fnExpr				# LabelPrimaryFn
	| matchExpr				# LabelPrimaryMatch
	| VOID					# LabelPrimaryVoid
	| NULL					# LabelPrimaryNull
	| taggedBlockString		# LabelPrimaryTaggedBlock
	| structInitExpr		# LabelPrimaryStructInit;

// --- Function Expressions ---
fnExpr:
	FN LPAREN parameters? RPAREN (typeAnnotation)? codeBlock;

// --- Match Expressions ---
matchExpr:
	MATCH expr LBRACE stmt_sep* caseClause (stmt_sep+ caseClause)* stmt_sep* defaultClause? RBRACE;
caseClause: expr (COLON expr | codeBlock) SEMICOLON?;
defaultClause: DEFAULT (COLON expr | codeBlock) SEMICOLON?;

// --- String Literals ---
singleQuotedString:
	SINGLE_QUOTE_START stringPart* SINGLE_STR_END;
multiQuotedString: MULTI_QUOTE_START stringPart* MULTI_STR_END;
doubleQuotedString:
	DOUBLE_QUOTE_START stringPart* DOUBLE_STR_END;
multiDoubleQuotedString:
	MULTI_DOUBLE_QUOTE_START stringPart* MULTI_DOUBLE_STR_END;
stringPart:
	SINGLE_STR_CONTENT		
	| MULTI_STR_CONTENT		
	| DOUBLE_STR_CONTENT	
	| MULTI_DOUBLE_STR_CONTENT	
	| interpolation;
interpolation: (
		SINGLE_STR_INTERP_START
		| MULTI_STR_INTERP_START
		| DOUBLE_STR_INTERP_START
		| MULTI_DOUBLE_STR_INTERP_START
	) expr INTERP_RBRACE;

// --- Literals ---
literal:
	stringLiteral		# LabelLiteralString
	| numberLiteral		# LabelLiteralNumber
	| booleanLiteral	# LabelLiteralBool
	| NULL				# LabelLiteralNull
	| VOID				# LabelLiteralVoid;
stringLiteral:
	singleQuotedString		
	| multiQuotedString		
	| doubleQuotedString	
	| multiDoubleQuotedString;
numberLiteral:
	INTEGER				# LabelNumberLiteralInt
	| FLOAT				# LabelNumberLiteralFloat
	| HEX_LITERAL		# LabelNumberLiteralHex
	| BINARY_LITERAL	# LabelNumberLiteralBin
	| OCTAL_LITERAL		# LabelNumberLiteralOct;
booleanLiteral:
	TRUE	# LabelBoolLiteralTrue
	| FALSE	# LabelBoolLiteralFalse;

// --- Collections ---
arrayLiteral: LSQBR exprList? RSQBR;
objectLiteral: LBRACE objectFieldList? RBRACE;
objectFieldList: objectField (COMMA objectField)* (COMMA)?;
objectField: objectFieldName (COLON expr)?;
objectFieldName:
	ID				# LabelObjectFieldNameID
	| stringLiteral	# LabelObjectFieldNameStr;
mapLiteral:
	LSQBR COLON RSQBR			# LabelMapLiteralEmpty
	| LSQBR mapFieldList? RSQBR	# LabelMapLiteralNonEmpty;
mapFieldList: mapField (COMMA mapField)* (COMMA)?;
mapField: expr COLON expr;
setLiteral: LT (expr (COMMA expr)* (COMMA)?)? GT;

taggedBlockString:
	ID (multiQuotedString | multiDoubleQuotedString);

structInitExpr: ID LPAREN structFieldList? RPAREN;
structFieldList: structField (COMMA structField)* (COMMA)?;
structField: ID COLON expr;

// --- Type Annotations ---
typeAnnotation:
	ID			# LabelTypeAnnID
	| arrayType	# LabelTypeAnnArray
	| tupleType	# LabelTypeAnnTuple
	| fnType	# LabelTypeAnnFn
	| VOID		# LabelTypeAnnVoid;
tupleType: LPAREN typeList? RPAREN;
arrayType: ID LSQBR RSQBR;
fnType: FN LPAREN parameters? RPAREN typeAnnotation?;

// --- Helper Rules ---
stmt_sep: SEMICOLON | NEWLINE;