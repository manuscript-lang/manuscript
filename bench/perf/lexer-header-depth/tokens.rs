//! Exact lexer-output oracle; capacity is intentionally excluded.
use ms_syntax::lexer::lex;
use std::sync::Arc;

fn main() {
    for path in std::env::args().skip(1) {
        let source = std::fs::read_to_string(&path).unwrap();
        let file: Arc<str> = path.into();
        let lexed = lex(&file, &source).unwrap();
        println!("{:?}\n{:?}", lexed.source, lexed.tokens);
    }
}
