lexer grammar ManuscriptLexer;

// Define whitespace first, so it has highest priority
WS: [ \t\r\n\f]+ -> channel(HIDDEN);
COMMENT: '//' ~[\r\n]* -> channel(HIDDEN);
MULTI_LINE_COMMENT: '/*' .*? '*/' -> channel(HIDDEN);

// Keywords (DEFAULT_MODE implicitly)
LET: 'let';
FN: 'fn';
RETURN: 'return';
YIELD: 'yield';
TYPE: 'type';
INTERFACE: 'interface';
IMPORT: 'import';
EXPORT: 'export';
EXTERN: 'extern';
VOID: 'void';
CHECK: 'check';
TRY: 'try';
CATCH: 'catch';
IN: 'in';
AS: 'as';
IS: 'is';
EXTENDS: 'extends';
FROM: 'from';
NULL: 'null';
IF: 'if';
ELSE: 'else';
FOR: 'for';
WHILE: 'while';
TRUE: 'true';
FALSE: 'false';
MATCH: 'match';
CASE: 'case';
ASYNC: 'async';
AWAIT: 'await';
METHODS: 'methods';
SELF: 'self';

// Punctuation (DEFAULT_MODE implicitly)
LBRACE: '{';
RBRACE: '}';
LSQBR: '[';
RSQBR: ']';
LPAREN: '(';
RPAREN: ')';
LT: '<';
GT: '>';
LT_EQUALS: '<=';
GT_EQUALS: '>=';
COLON: ':';
SEMICOLON: ';';
COMMA: ',';
EQUALS: '=';
EQUALS_EQUALS: '==';
PLUS: '+';
MINUS: '-';
PLUS_PLUS: '++';
MINUS_MINUS: '--';
PIPE_PIPE: '||';
AMP_AMP: '&&';
STAR: '*';
SLASH: '/';
EXCLAMATION: '!';
QUESTION: '?';
DOT: '.';
NEQ: '!=';

// bitwise operators 
PIPE: '|';
AMP: '&';
CARET: '^';

// Number literals (DEFAULT_MODE implicitly)
// Define numeric literals BEFORE the ID rule to ensure they take precedence

// Hexadecimal with 0x prefix
HEX_LITERAL: '0x' [0-9a-fA-F]+ ;

// Binary with 0b prefix
BINARY_LITERAL: '0b' [01][01_]* ;

// Floating point 
FLOAT:
    [0-9]+ '.' [0-9]* ([eE] [+-]? [0-9]+)? | // 1.23, 1.23e+10
    '.' [0-9]+ ([eE] [+-]? [0-9]+)? |        // .123, .123e-10
    [0-9]+ [eE] [+-]? [0-9]+                 // 123e+10
    ;

// Decimal integers - Must be before ID rule
INTEGER: [0-9]+ ;

// Identifiers (DEFAULT_MODE implicitly)
ID: [a-zA-Z_][a-zA-Z0-9_]*;

// --- String Literals ---

// Fragments used in strings
fragment ESC_SEQ: '\\' ('\\' | '"' | '\'' | '$' | 'n' | 'r' | 't' | 'b' | 'f');
fragment INTERP_START : '${';

// Single-quoted string start (switches to SINGLE_STRING_MODE)
SINGLE_QUOTE_START: '\'' -> pushMode(SINGLE_STRING_MODE);
// TODO: Add support for prefix (e.g., r'...') if needed

// Triple-quoted string start (switches to MULTI_STRING_MODE)
MULTI_QUOTE_START: '\'\'\'' -> pushMode(MULTI_STRING_MODE);
// TODO: Add support for prefix if needed

// Double-quoted string start (switches to DOUBLE_STRING_MODE)
DOUBLE_QUOTE_START: '"' -> pushMode(DOUBLE_STRING_MODE);

// --- Modes for String Processing ---

mode SINGLE_STRING_MODE;
    SINGLE_STR_INTERP_START: INTERP_START -> pushMode(INTERPOLATION_MODE);
    SINGLE_STR_CONTENT : ( ESC_SEQ | ~['\\${] )+ ;
    SINGLE_STR_END : '\'' -> popMode;

mode MULTI_STRING_MODE;
    MULTI_STR_INTERP_START: INTERP_START -> pushMode(INTERPOLATION_MODE);
    MULTI_STR_CONTENT : ( ESC_SEQ | ~['\\${] )+ ;
    MULTI_STR_END : '\'\'\'' -> popMode;

mode DOUBLE_STRING_MODE;
    DOUBLE_STR_INTERP_START: INTERP_START -> pushMode(INTERPOLATION_MODE);
    DOUBLE_STR_CONTENT : ( ESC_SEQ | ~["\\${] )+ ;
    DOUBLE_STR_END : '"' -> popMode;

mode INTERPOLATION_MODE;
    INTERP_LBRACE: '{' -> pushMode(INTERPOLATION_MODE);
    INTERP_RBRACE: '}' -> popMode;
    // Tokens from DEFAULT_MODE should be implicitly available here for the expression
    INTERP_WS: [ \t\r\n]+ -> skip; 