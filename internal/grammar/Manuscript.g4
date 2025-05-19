parser grammar Manuscript;

options {
	tokenVocab = ManuscriptLexer;
}

program: items += programItem* EOF;
programItem:
	(
		importStatement = importStmt
		| exportStatement = exportStmt
		| externStatement = externStmt
		| letDeclaration = letDecl
		| typeDeclaration = typeDecl
		| interfaceDeclaration = interfaceDecl
		| functionDeclaration = fnDecl
		| methodsDeclaration = methodsDecl
	) SEMICOLON?;

importStmt:
	IMPORT (
		LBRACE (
			items += importItem (COMMA items += importItem)* (
				COMMA
			)?
		)? RBRACE FROM path = importStr
		| target = ID FROM path = importStr
	);
importItem: name = ID (AS alias = ID)?;

importStr:
	pathSingle = singleQuotedString
	| pathMulti = multiQuotedString;

externStmt:
	EXTERN (
		LBRACE (
			items += importItem (COMMA items += importItem)* (
				COMMA
			)?
		)? RBRACE FROM path = importStr
		| target = ID FROM path = importStr
	);

exportStmt:
	EXPORT (
		exportedFunction = fnDecl
		| exportedLet = letDecl
		| exportedType = typeDecl
		| exportedInterface = interfaceDecl
	);

letDecl:
	LET (
		singleLet = letSingle
		| blockLet = letBlock
		| destructuredObjectLet = letDestructuredObj
		| destructuredArrayLet = letDestructuredArray
	);

letSingle: typedID (EQUALS value = expr)?;

letBlockItem:
	  lhsTypedId = typedID EQUALS rhsExpr = expr             # letBlockItemSingle
	| LBRACE lhsDestructuredIdsObj = typedIDList RBRACE EQUALS rhsExprObj = expr  # letBlockItemDestructuredObj
	| LSQBR lhsDestructuredIdsArr = typedIDList RSQBR EQUALS rhsExprArr = expr # letBlockItemDestructuredArray
;

letBlock: LPAREN (items += letBlockItem (items += letBlockItem)*)? RPAREN;

letDestructuredObj:
	LBRACE destructuredIds = typedIDList RBRACE EQUALS value = expr;
letDestructuredArray:
	LSQBR destructuredIds = typedIDList RSQBR EQUALS value = expr;

namedID: name = ID;
typedID: namedID (type = typeAnnotation)?;
typedIDList:
	names += typedID (COMMA names += typedID)* (COMMA)?;
typeList:
	types += typeAnnotation (COMMA types += typeAnnotation)* (
		COMMA
	)?;

fnDecl: signature = fnSignature block = codeBlock;

fnSignature:
	FN functionName = namedID LPAREN params = parameters? RPAREN (
		returnType = typeAnnotation
	)? (returnsError = EXCLAMATION)?;

parameters: param (COMMA param)* (COMMA)?;
param:
	paramName = namedID type = typeAnnotation (
		EQUALS defaultValue = expr
	)?;

typeDecl: TYPE typeName = namedID (typeDefBody | typeAlias);

typeDefBody:
	(EXTENDS extendedTypes = typeList)? LBRACE (
		fields += fieldDecl (COMMA fields += fieldDecl)* (COMMA)?
	)? RBRACE;

typeAlias:
	EQUALS aliasTarget = typeAnnotation (
		EXTENDS constraintTypes = typeList
	)?;

fieldDecl:
	fieldName = namedID (isOptionalField = QUESTION)? type = typeAnnotation;

interfaceDecl:
	INTERFACE interfaceName = namedID (
		EXTENDS extendedInterfaces = typeList
	)? LBRACE (methods += interfaceMethod)+ RBRACE;

interfaceMethod:
	methodName = namedID LPAREN params = parameters? RPAREN (
		returnType = typeAnnotation
	)? (returnsError = EXCLAMATION)?;

methodsDecl:
	METHODS target = ID AS receiver = ID LBRACE (methodImpl)* RBRACE;

methodImpl: method = interfaceMethod block = codeBlock;

typeAnnotation:
	(
		idAsType = ID
		| tupleAsType = tupleType
		| funcAsType = fnSignature
		| objAsType = objectTypeAnnotation
		| mapAsType = mapTypeAnnotation
		| setAsType = setTypeAnnotation
		| VOID
	) (isNullable = QUESTION)? (arrayMarker = LSQBR RSQBR)?;

tupleType: LPAREN elements = typeList? RPAREN;

objectTypeAnnotation:
	LBRACE (
		fields += fieldDecl (COMMA fields += fieldDecl)* (COMMA)?
	)? RBRACE;

mapTypeAnnotation:
	LSQBR keyType = typeAnnotation COLON valueType = typeAnnotation RSQBR;

setTypeAnnotation: LT elementType = typeAnnotation GT;

stmt:
	(
		sLetDecl = letDecl
		| sExpr = expr
		| sReturn = returnStmt
		| sYield = yieldStmt
		| sIf = ifStmt
		| sFor = forStmt
		| sWhile = whileStmt
		| sCodeBlock = codeBlock
		| sBreak = breakStmt
		| sContinue = continueStmt
		| sCheck = checkStmt
		| sDefer = deferStmt
	) SEMICOLON?
	| SEMICOLON;

returnStmt: RETURN returnedValues = exprList?;
yieldStmt: YIELD yieldedValues = exprList?;
deferStmt: DEFER expr;
exprList: expr (COMMA expr)* (COMMA)?;

ifStmt:
	IF condition = expr thenBlock = codeBlock (
		ELSE elseBlock = codeBlock
	)?;

forStmt: FOR type = forLoopType;

forLoopType:
	forTrinity													# ForLoop
	| (key = ID (COMMA val = ID)?) IN iterable = expr loopBody	# ForInLoop;

forTrinity:
	(initializerDecl = letSingle | initializerExprs = exprList)? SEMICOLON condition = expr?
		SEMICOLON postUpdate = exprList? body = loopBody;

whileStmt: WHILE condition = expr loopBody;

loopBody: LBRACE (bodyStmts += stmt)* RBRACE;

codeBlock: LBRACE (stmts += stmt)* RBRACE;

expr: assignmentExpr;
assignmentExpr:
	left = ternaryExpr (
		op = (
			EQUALS
			| PLUS_EQUALS
			| MINUS_EQUALS
			| STAR_EQUALS
			| SLASH_EQUALS
			| MOD_EQUALS
			| CARET_EQUALS
		) right = assignmentExpr
	)?;

ternaryExpr:
	condition = logicalOrExpr (QUESTION trueExpr = expr COLON falseExpr = ternaryExpr)?;

logicalOrExpr:
	left = logicalAndExpr (op = PIPE_PIPE right = logicalAndExpr)*;
logicalAndExpr:
	left = bitwiseOrExpr (op = AMP_AMP right = bitwiseOrExpr)*;
bitwiseOrExpr:
	left = bitwiseXorExpr (op = PIPE right = bitwiseXorExpr)*;
bitwiseXorExpr:
	left = bitwiseAndExpr (op = CARET right = bitwiseAndExpr)*;
bitwiseAndExpr:
	left = equalityExpr (op = AMP right = equalityExpr)*;
equalityExpr:
	left = comparisonExpr (
		op = (EQUALS_EQUALS | NEQ) right = comparisonExpr
	)*;
comparisonExpr:
	left = shiftExpr (
		op = (LT | LT_EQUALS | GT | GT_EQUALS) right = shiftExpr
	)*;
shiftExpr:
	left = additiveExpr (
		op = (LSHIFT | RSHIFT) right = additiveExpr
	)*;
additiveExpr:
	left = multiplicativeExpr (
		op = (PLUS | MINUS) right = multiplicativeExpr
	)*;
multiplicativeExpr:
	left = unaryExpr (
		op = (STAR | SLASH | MOD) right = unaryExpr
	)*;
unaryExpr:
	op = (PLUS | MINUS | EXCLAMATION | TRY) unaryExpr
	| awaitExpr;
awaitExpr: (TRY? AWAIT? ASYNC?) postfixExpr;

postfixExpr:
	primaryExpr (
		LPAREN (args = exprList)? RPAREN
		| DOT member = ID
		| LSQBR indexExpr = expr RSQBR
	)*;

primaryExpr:
	literal
	| ID
	| LPAREN parenExpr = expr RPAREN
	| arrayLiteral
	| objectLiteral
	| mapLiteral
	| setLiteral
	| fnExpr
	| matchExpr
	| VOID
	| NULL
	| taggedBlockString
	| structInitExpr;

fnExpr:
	FN LPAREN fnParams = parameters? RPAREN (
		returnType = typeAnnotation
	)? block = codeBlock;

matchExpr:
	MATCH valueToMatch = expr LBRACE
		(cs += caseClause)*
		(def = defaultClause)?
	RBRACE;

caseClause:
	pattern = expr (
		COLON resultExpr = expr
		| resultBlock = codeBlock
	) SEMICOLON?;

defaultClause:
	DEFAULT (COLON resultExpr = expr | resultBlock = codeBlock) SEMICOLON?;

// --- String Parsing Rules --- 
singleQuotedString:
	SINGLE_QUOTE_START parts += stringPart* SINGLE_STR_END;
multiQuotedString:
	MULTI_QUOTE_START parts += stringPart* MULTI_STR_END;
doubleQuotedString:
	DOUBLE_QUOTE_START parts += stringPart* DOUBLE_STR_END;
multiDoubleQuotedString:
	MULTI_DOUBLE_QUOTE_START parts += stringPart* MULTI_DOUBLE_STR_END;

stringPart:
	SINGLE_STR_CONTENT
	| MULTI_STR_CONTENT
	| DOUBLE_STR_CONTENT
	| MULTI_DOUBLE_STR_CONTENT
	| interp = interpolation;

interpolation: (
		SINGLE_STR_INTERP_START
		| MULTI_STR_INTERP_START
		| DOUBLE_STR_INTERP_START
		| MULTI_DOUBLE_STR_INTERP_START
	) value = expr INTERP_RBRACE;

// --- Literals ---
literal:
	stringLit = stringLiteral
	| numLit = numberLiteral
	| boolLit = booleanLiteral
	| nullConstant = NULL
	| voidConstant = VOID;
stringLiteral:
	sglQuotedStr = singleQuotedString
	| mulQuotedStr = multiQuotedString
	| dblQuotedStr = doubleQuotedString
	| mulDblQuotedStr = multiDoubleQuotedString;
numberLiteral:
	intValue = INTEGER
	| floatValue = FLOAT
	| hexValue = HEX_LITERAL
	| binaryValue = BINARY_LITERAL
	| octalValue = OCTAL_LITERAL;
booleanLiteral: TRUE | FALSE;

arrayLiteral: LSQBR items = exprList? RSQBR;

objectLiteral:
	LBRACE (
		objFields += objectField (COMMA objFields += objectField)* (
			COMMA
		)?
	)? RBRACE;

objectFieldName: keyName = ID | keyString = stringLiteral;

objectField: key = objectFieldName (COLON val = expr)?;

mapLiteral:
	LSQBR COLON RSQBR
	| LSQBR (
		fields += mapField (COMMA fields += mapField)* (
			COMMA
		)?
	)? RSQBR;
mapField: key = expr COLON value = expr;

setLiteral:
	LT (
		elements += expr (COMMA elements += expr)* (COMMA)?
	)? GT;

breakStmt: BREAK;
continueStmt: CONTINUE;

checkStmt:
	CHECK condition = expr COMMA message = stringLiteral SEMICOLON?;

taggedBlockString:
	tag = ID (
		blockStrMultiSingle = multiQuotedString
		| blockStrMultiDouble = multiDoubleQuotedString
	);

structInitExpr: ID LPAREN (fields += structField (COMMA fields += structField)* (COMMA)?)? RPAREN;
structField: key = ID COLON val = expr;