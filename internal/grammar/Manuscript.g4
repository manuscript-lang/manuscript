grammar Manuscript;

// Parser Rules
program : statement+ EOF ;

statement : expr ';' ;

expr : expr ('*'|'/') expr   # MulDiv
     | expr ('+'|'-') expr   # AddSub
     | INT                   # Int
     | '(' expr ')'          # Parens
     ;

// Lexer Rules
INT      : [0-9]+ ;
MUL      : '*' ;
DIV      : '/' ;
ADD      : '+' ;
SUB      : '-' ;
LPAREN   : '(' ;
RPAREN   : ')' ;
SEMI     : ';' ;
WS       : [ \t\r\n]+ -> skip ; 