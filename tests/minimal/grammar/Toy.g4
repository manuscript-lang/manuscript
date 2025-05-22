parser grammar Toy;

options {
    tokenVocab = ToyLexer;
}

program: (programItem)* EOF;

programItem:
    let  # LetLabel
    | fn  # FnLabel
    ;

let: LET ID EQUALS expr;
fn: FN ID LPAREN RPAREN LBRACE expr RBRACE;

expr: ID;