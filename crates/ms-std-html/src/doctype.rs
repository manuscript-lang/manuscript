//! Doctype parsing and quirks-mode detection, ported from `doctype.go`.
use crate::parse::{Node, NodeType};
use crate::token::Attribute;
use alloc::string::String;

const WHITESPACE: &[char] = &[' ', '\t', '\r', '\n', '\x0c'];

const QUIRKY_IDS: &[&str] = &[
    "+//silmaril//dtd html pro v0r11 19970101//",
    "-//advasoft ltd//dtd html 3.0 aswedit + extensions//",
    "-//as//dtd html 3.0 aswedit + extensions//",
    "-//ietf//dtd html 2.0 level 1//",
    "-//ietf//dtd html 2.0 level 2//",
    "-//ietf//dtd html 2.0 strict level 1//",
    "-//ietf//dtd html 2.0 strict level 2//",
    "-//ietf//dtd html 2.0 strict//",
    "-//ietf//dtd html 2.0//",
    "-//ietf//dtd html 2.1e//",
    "-//ietf//dtd html 3.0//",
    "-//ietf//dtd html 3.2 final//",
    "-//ietf//dtd html 3.2//",
    "-//ietf//dtd html 3//",
    "-//ietf//dtd html level 0//",
    "-//ietf//dtd html level 1//",
    "-//ietf//dtd html level 2//",
    "-//ietf//dtd html level 3//",
    "-//ietf//dtd html strict level 0//",
    "-//ietf//dtd html strict level 1//",
    "-//ietf//dtd html strict level 2//",
    "-//ietf//dtd html strict level 3//",
    "-//ietf//dtd html strict//",
    "-//ietf//dtd html//",
    "-//metrius//dtd metrius presentational//",
    "-//microsoft//dtd internet explorer 2.0 html strict//",
    "-//microsoft//dtd internet explorer 2.0 html//",
    "-//microsoft//dtd internet explorer 2.0 tables//",
    "-//microsoft//dtd internet explorer 3.0 html strict//",
    "-//microsoft//dtd internet explorer 3.0 html//",
    "-//microsoft//dtd internet explorer 3.0 tables//",
    "-//netscape comm. corp.//dtd html//",
    "-//netscape comm. corp.//dtd strict html//",
    "-//o'reilly and associates//dtd html 2.0//",
    "-//o'reilly and associates//dtd html extended 1.0//",
    "-//o'reilly and associates//dtd html extended relaxed 1.0//",
    "-//softquad software//dtd hotmetal pro 6.0::19990601::extensions to html 4.0//",
    "-//softquad//dtd hotmetal pro 4.0::19971010::extensions to html 4.0//",
    "-//spyglass//dtd html 2.0 extended//",
    "-//sq//dtd html 2.0 hotmetal + extensions//",
    "-//sun microsystems corp.//dtd hotjava html//",
    "-//sun microsystems corp.//dtd hotjava strict html//",
    "-//w3c//dtd html 3 1995-03-24//",
    "-//w3c//dtd html 3.2 draft//",
    "-//w3c//dtd html 3.2 final//",
    "-//w3c//dtd html 3.2//",
    "-//w3c//dtd html 3.2s draft//",
    "-//w3c//dtd html 4.0 frameset//",
    "-//w3c//dtd html 4.0 transitional//",
    "-//w3c//dtd html experimental 19960712//",
    "-//w3c//dtd html experimental 970421//",
    "-//w3c//dtd w3 html//",
    "-//w3o//dtd w3 html 3.0//",
    "-//webtechs//dtd mozilla html 2.0//",
    "-//webtechs//dtd mozilla html//",
];

/// `strings.ToLower`: simple (one-to-one) case mapping with no context rules.
fn go_lower(s: &str) -> String {
    s.chars()
        .map(|c| {
            let mut l = c.to_lowercase();
            match (l.next(), l.next()) {
                (Some(x), None) => x,
                // U+0130 is the only character whose full lower-case form has two code points; its
                // simple mapping is `i`.
                _ if c == '\u{130}' => 'i',
                _ => c,
            }
        })
        .collect()
}

/// Parses the contents of a doctype token into a doctype node and whether it implies quirks mode.
pub fn parse_doctype(s: &str) -> (Node, bool) {
    let mut n = Node::new(NodeType::Doctype);
    let mut quirks = false;
    let space = s.find(WHITESPACE).unwrap_or(s.len());
    if &s[..space] != "html" {
        quirks = true;
    }
    n.data = go_lower(&s[..space]);
    let mut s = s[space..].trim_start_matches(WHITESPACE);

    if s.len() < 6 {
        return (n, quirks || !s.is_empty());
    }

    // The first six bytes may split a multi-byte character; fall back to a non-matching key.
    let mut key = go_lower(s.get(..6).unwrap_or(""));
    s = s.get(6..).unwrap_or("");
    if key.is_empty() {
        key = String::from("?");
    }
    while key == "public" || key == "system" {
        s = s.trim_start_matches(WHITESPACE);
        if s.is_empty() {
            break;
        }
        let quote = s.as_bytes()[0];
        if quote != b'"' && quote != b'\'' {
            break;
        }
        s = &s[1..];
        let id = match s.find(quote as char) {
            None => {
                let id = s;
                s = "";
                id
            }
            Some(q) => {
                let id = &s[..q];
                s = &s[q + 1..];
                id
            }
        };
        n.attr.push(Attribute {
            namespace: String::new(),
            key: key.clone(),
            val: String::from(id),
        });
        key = if key == "public" {
            String::from("system")
        } else {
            String::new()
        };
    }

    if !key.is_empty() || !s.is_empty() {
        quirks = true;
    } else if !n.attr.is_empty() {
        if n.attr[0].key == "public" {
            let public = go_lower(&n.attr[0].val);
            match public.as_str() {
                "-//w3o//dtd w3 html strict 3.0//en//"
                | "-/w3d/dtd html 4.0 transitional/en"
                | "html" => quirks = true,
                _ => {
                    if QUIRKY_IDS.iter().any(|q| public.starts_with(q)) {
                        quirks = true;
                    }
                }
            }
            if n.attr.len() == 1
                && (public.starts_with("-//w3c//dtd html 4.01 frameset//")
                    || public.starts_with("-//w3c//dtd html 4.01 transitional//"))
            {
                quirks = true;
            }
        }
        let last = &n.attr[n.attr.len() - 1];
        if last.key == "system"
            && last
                .val
                .eq_ignore_ascii_case("http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd")
        {
            quirks = true;
        }
    }
    (n, quirks)
}
