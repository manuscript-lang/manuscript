//! Lexical tokens of module sources, shared by index construction and
//! document symbols. Bundled standard sources are lexed once per thread.

use ms_check::syntax::ModRef;
use ms_syntax::lexer;
use ms_syntax::token::{Tok, Token};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::Arc;

/// The tokens of one source.
pub struct Lexical {
    /// The CRLF-normalised source the token text indexes into.
    pub source: String,
    /// Tokens ending with `Eof`.
    pub tokens: Vec<Token>,
}

impl Lexical {
    /// The text of a token.
    pub fn text(&self, t: &Token) -> &str {
        &self.source[t.lo as usize..t.hi as usize]
    }

    /// The first `Name` token spelled `name` on the line that starts at
    /// `offset` (skipping a newline token exactly at `offset`); the position of
    /// a header's declared name, whatever precedes it.
    pub fn header(&self, offset: usize, name: &str) -> Option<usize> {
        let start = self
            .tokens
            .partition_point(|t| (t.pos.offset as usize) < offset);
        for token in &self.tokens[start..] {
            if token.kind == Tok::Newline {
                if token.pos.offset as usize == offset {
                    continue;
                }
                break;
            }
            if token.kind == Tok::Name && self.text(token) == name {
                return Some(token.pos.offset as usize);
            }
        }
        None
    }
}

type StandardLex = HashMap<(String, usize), Option<Rc<Lexical>>>;

thread_local! {
    static STANDARD: RefCell<StandardLex> = RefCell::new(HashMap::new());
}

/// Lexes a source; `None` when it does not lex.
pub fn lex(file: &str, source: &str) -> Option<Lexical> {
    let file: Arc<str> = Arc::from(file);
    let lexed = lexer::lex(&file, source).ok()?;
    Some(Lexical {
        source: lexed.source.into_owned(),
        tokens: lexed.tokens,
    })
}

/// The tokens of a module's source.
pub fn tokens(m: &ModRef) -> Option<Rc<Lexical>> {
    if m.file.as_str().starts_with("@std/") {
        let key = (m.file.as_str().to_string(), m.source.len());
        if let Some(found) = STANDARD.with(|s| s.borrow().get(&key).cloned()) {
            return found;
        }
        let lexed = lex(m.file.as_str(), &m.source).map(Rc::new);
        STANDARD.with(|s| s.borrow_mut().insert(key, lexed.clone()));
        return lexed;
    }
    lex(m.file.as_str(), &m.source).map(Rc::new)
}
