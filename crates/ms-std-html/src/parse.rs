//! The HTML5 tree builder, ported from `golang.org/x/net/html/parse.go` (document parsing only,
//! scripting enabled). Nodes live in an arena and refer to each other by index.
use crate::foreign::*;
use crate::token::{Attribute, Token, TokenType, Tokenizer, atom_of};
use alloc::string::String;
use alloc::vec;
use alloc::vec::Vec;

pub type Id = usize;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum NodeType {
    Document,
    Element,
    Text,
    Comment,
    Doctype,
    ScopeMarker,
}

#[derive(Clone, Debug)]
pub struct Node {
    pub ty: NodeType,
    pub atom: String,
    pub data: String,
    pub namespace: String,
    pub attr: Vec<Attribute>,
    pub parent: Option<Id>,
    pub first: Option<Id>,
    pub last: Option<Id>,
    pub prev: Option<Id>,
    pub next: Option<Id>,
}

impl Node {
    pub(crate) fn new(ty: NodeType) -> Self {
        Node {
            ty,
            atom: String::new(),
            data: String::new(),
            namespace: String::new(),
            attr: Vec::new(),
            parent: None,
            first: None,
            last: None,
            prev: None,
            next: None,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Scope {
    Default,
    ListItem,
    Button,
    Table,
    TableRow,
    TableBody,
    Select,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Im {
    Initial,
    BeforeHtml,
    BeforeHead,
    InHead,
    AfterHead,
    InBody,
    Text,
    InTable,
    InCaption,
    InColumnGroup,
    InTableBody,
    InRow,
    InCell,
    InSelect,
    InSelectInTable,
    InTemplate,
    AfterBody,
    InFrameset,
    AfterFrameset,
    AfterAfterBody,
    AfterAfterFrameset,
    IgnoreRemaining,
}

const WHITESPACE: &[char] = &[' ', '\t', '\r', '\n', '\x0c'];

fn trim_left(s: &str) -> &str {
    s.trim_start_matches(WHITESPACE)
}

const MARKER: Id = 0;

pub struct Parser {
    tokenizer: Tokenizer,
    tok: Token,
    has_self_closing: bool,
    pub nodes: Vec<Node>,
    pub doc: Id,
    oe: Vec<Id>,
    afe: Vec<Id>,
    head: Option<Id>,
    form: Option<Id>,
    frameset_ok: bool,
    template_stack: Vec<Im>,
    im: Im,
    original_im: Option<Im>,
    foster_parenting: bool,
    quirks: bool,
}

fn is_special_name(name: &str) -> bool {
    matches!(
        name,
        "address"
            | "applet"
            | "area"
            | "article"
            | "aside"
            | "base"
            | "basefont"
            | "bgsound"
            | "blockquote"
            | "body"
            | "br"
            | "button"
            | "caption"
            | "center"
            | "col"
            | "colgroup"
            | "dd"
            | "details"
            | "dir"
            | "div"
            | "dl"
            | "dt"
            | "embed"
            | "fieldset"
            | "figcaption"
            | "figure"
            | "footer"
            | "form"
            | "frame"
            | "frameset"
            | "h1"
            | "h2"
            | "h3"
            | "h4"
            | "h5"
            | "h6"
            | "head"
            | "header"
            | "hgroup"
            | "hr"
            | "html"
            | "iframe"
            | "img"
            | "input"
            | "keygen"
            | "li"
            | "link"
            | "listing"
            | "main"
            | "marquee"
            | "menu"
            | "meta"
            | "nav"
            | "noembed"
            | "noframes"
            | "noscript"
            | "object"
            | "ol"
            | "p"
            | "param"
            | "plaintext"
            | "pre"
            | "script"
            | "section"
            | "select"
            | "source"
            | "style"
            | "summary"
            | "table"
            | "tbody"
            | "td"
            | "template"
            | "textarea"
            | "tfoot"
            | "th"
            | "thead"
            | "title"
            | "tr"
            | "track"
            | "ul"
            | "wbr"
            | "xmp"
    )
}

fn default_scope_stop(ns: &str) -> &'static [&'static str] {
    match ns {
        "" => &[
            "applet", "caption", "html", "table", "td", "th", "marquee", "object", "template",
        ],
        "math" => &["annotation-xml", "mi", "mn", "mo", "ms", "mtext"],
        "svg" => &["desc", "foreignObject", "title"],
        _ => &[],
    }
}

impl Parser {
    pub fn new(input: &[u8]) -> Self {
        let mut nodes = vec![
            Node::new(NodeType::ScopeMarker),
            Node::new(NodeType::Document),
        ];
        nodes.reserve(input.len() / 8);
        Parser {
            tokenizer: Tokenizer::new(input),
            tok: Token {
                ty: TokenType::Error,
                atom: String::new(),
                data: String::new(),
                attr: Vec::new(),
            },
            has_self_closing: false,
            nodes,
            doc: 1,
            oe: Vec::new(),
            afe: Vec::new(),
            head: None,
            form: None,
            frameset_ok: true,
            template_stack: Vec::new(),
            im: Im::Initial,
            original_im: None,
            foster_parenting: false,
            quirks: false,
        }
    }

    // ---- node tree ----

    fn alloc(&mut self, n: Node) -> Id {
        self.nodes.push(n);
        self.nodes.len() - 1
    }

    fn new_node(&mut self, ty: NodeType, data: &str) -> Id {
        let mut n = Node::new(ty);
        n.data = String::from(data);
        self.alloc(n)
    }

    fn insert_before(&mut self, parent: Id, new: Id, old: Option<Id>) {
        let (prev, next) = match old {
            Some(o) => (self.nodes[o].prev, Some(o)),
            None => (self.nodes[parent].last, None),
        };
        match prev {
            Some(p) => self.nodes[p].next = Some(new),
            None => self.nodes[parent].first = Some(new),
        }
        match next {
            Some(n) => self.nodes[n].prev = Some(new),
            None => self.nodes[parent].last = Some(new),
        }
        let c = &mut self.nodes[new];
        c.parent = Some(parent);
        c.prev = prev;
        c.next = next;
    }

    fn append_child(&mut self, parent: Id, c: Id) {
        self.insert_before(parent, c, None);
    }

    fn remove_child(&mut self, parent: Id, c: Id) {
        let (prev, next) = (self.nodes[c].prev, self.nodes[c].next);
        if self.nodes[parent].first == Some(c) {
            self.nodes[parent].first = next;
        }
        if let Some(n) = next {
            self.nodes[n].prev = prev;
        }
        if self.nodes[parent].last == Some(c) {
            self.nodes[parent].last = prev;
        }
        if let Some(p) = prev {
            self.nodes[p].next = next;
        }
        let n = &mut self.nodes[c];
        n.parent = None;
        n.prev = None;
        n.next = None;
    }

    fn detach(&mut self, c: Id) {
        if let Some(p) = self.nodes[c].parent {
            self.remove_child(p, c);
        }
    }

    fn reparent_children(&mut self, dst: Id, src: Id) {
        while let Some(child) = self.nodes[src].first {
            self.remove_child(src, child);
            self.append_child(dst, child);
        }
    }

    /// `Node.clone`: type, atom, data and attributes (not the namespace).
    fn clone_node(&mut self, n: Id) -> Id {
        let o = &self.nodes[n];
        let mut m = Node::new(o.ty);
        m.atom = o.atom.clone();
        m.data = o.data.clone();
        m.attr = o.attr.clone();
        self.alloc(m)
    }

    // ---- stacks ----

    fn oe_top(&self) -> Option<Id> {
        self.oe.last().copied()
    }

    fn top(&self) -> Id {
        self.oe_top().unwrap_or(self.doc)
    }

    fn atom(&self, n: Id) -> &str {
        &self.nodes[n].atom
    }

    fn top_atom(&self) -> &str {
        self.atom(self.top())
    }

    fn oe_top_atom(&self) -> &str {
        match self.oe_top() {
            Some(n) => self.atom(n),
            None => "",
        }
    }

    fn index_in(stack: &[Id], n: Id) -> Option<usize> {
        stack.iter().rposition(|&x| x == n)
    }

    fn remove_from(stack: &mut Vec<Id>, n: Id) {
        if let Some(i) = Self::index_in(stack, n) {
            stack.remove(i);
        }
    }

    fn oe_contains(&self, atom: &str) -> bool {
        self.oe
            .iter()
            .any(|&n| self.nodes[n].atom == atom && self.nodes[n].namespace.is_empty())
    }

    fn is_special_element(&self, n: Id) -> bool {
        let node = &self.nodes[n];
        match node.namespace.as_str() {
            "" | "html" => is_special_name(&node.data),
            "math" => matches!(
                node.data.as_str(),
                "mi" | "mo" | "mn" | "ms" | "mtext" | "annotation-xml"
            ),
            "svg" => matches!(node.data.as_str(), "foreignObject" | "desc" | "title"),
            _ => false,
        }
    }

    // ---- scope ----

    fn index_of_element_in_scope(&self, s: Scope, match_tags: &[&str]) -> Option<usize> {
        for i in (0..self.oe.len()).rev() {
            let n = &self.nodes[self.oe[i]];
            let tag = n.atom.as_str();
            if n.namespace.is_empty() {
                if match_tags.contains(&tag) {
                    return Some(i);
                }
                match s {
                    Scope::Default => {}
                    Scope::ListItem => {
                        if tag == "ol" || tag == "ul" {
                            return None;
                        }
                    }
                    Scope::Button => {
                        if tag == "button" {
                            return None;
                        }
                    }
                    Scope::Table => {
                        if tag == "html" || tag == "table" || tag == "template" {
                            return None;
                        }
                    }
                    Scope::Select => {
                        if tag != "optgroup" && tag != "option" {
                            return None;
                        }
                    }
                    Scope::TableRow | Scope::TableBody => {}
                }
            }
            if matches!(s, Scope::Default | Scope::ListItem | Scope::Button)
                && default_scope_stop(&n.namespace).contains(&tag)
            {
                return None;
            }
        }
        None
    }

    fn pop_until(&mut self, s: Scope, match_tags: &[&str]) -> bool {
        match self.index_of_element_in_scope(s, match_tags) {
            Some(i) => {
                self.oe.truncate(i);
                true
            }
            None => false,
        }
    }

    fn element_in_scope(&self, s: Scope, match_tags: &[&str]) -> bool {
        self.index_of_element_in_scope(s, match_tags).is_some()
    }

    fn clear_stack_to_context(&mut self, s: Scope) {
        for i in (0..self.oe.len()).rev() {
            let tag = self.atom(self.oe[i]);
            let hit = match s {
                Scope::Table => matches!(tag, "html" | "table" | "template"),
                Scope::TableRow => matches!(tag, "html" | "tr" | "template"),
                Scope::TableBody => {
                    matches!(tag, "html" | "tbody" | "tfoot" | "thead" | "template")
                }
                _ => false,
            };
            if hit {
                self.oe.truncate(i + 1);
                return;
            }
        }
    }

    fn parse_generic_raw_text_element(&mut self) {
        self.add_element();
        self.original_im = Some(self.im);
        self.im = Im::Text;
    }

    fn generate_implied_end_tags(&mut self, exceptions: &[&str]) {
        let mut i = self.oe.len();
        'outer: while i > 0 {
            let n = &self.nodes[self.oe[i - 1]];
            if n.ty != NodeType::Element {
                break;
            }
            if matches!(
                n.atom.as_str(),
                "dd" | "dt" | "li" | "optgroup" | "option" | "p" | "rb" | "rp" | "rt" | "rtc"
            ) {
                if exceptions.contains(&n.data.as_str()) {
                    break 'outer;
                }
                i -= 1;
                continue;
            }
            break;
        }
        self.oe.truncate(i);
    }

    fn add_child(&mut self, n: Id) {
        if self.should_foster_parent() {
            self.foster_parent(n);
        } else {
            let t = self.top();
            self.append_child(t, n);
        }
        if self.nodes[n].ty == NodeType::Element {
            self.oe.push(n);
        }
    }

    fn should_foster_parent(&self) -> bool {
        self.foster_parenting
            && matches!(
                self.top_atom(),
                "table" | "tbody" | "tfoot" | "thead" | "tr"
            )
    }

    fn foster_parent(&mut self, n: Id) {
        let table_i = self.oe.iter().rposition(|&x| self.nodes[x].atom == "table");
        let template_j = self
            .oe
            .iter()
            .rposition(|&x| self.nodes[x].atom == "template");
        if let Some(j) = template_j
            && table_i.is_none_or(|i| j > i)
        {
            let t = self.oe[j];
            self.append_child(t, n);
            return;
        }
        let table = table_i.map(|i| self.oe[i]);
        let parent = match table {
            None => Some(self.oe[0]),
            Some(t) => self.nodes[t].parent,
        };
        let parent = parent.unwrap_or_else(|| self.oe[table_i.unwrap_or(1) - 1]);
        let prev = match table {
            Some(t) => self.nodes[t].prev,
            None => self.nodes[parent].last,
        };
        if let Some(p) = prev
            && self.nodes[p].ty == NodeType::Text
            && self.nodes[n].ty == NodeType::Text
        {
            let add = core::mem::take(&mut self.nodes[n].data);
            self.nodes[p].data.push_str(&add);
            return;
        }
        self.insert_before(parent, n, table);
    }

    fn add_text(&mut self, text: &str) {
        if text.is_empty() {
            return;
        }
        if self.should_foster_parent() {
            let n = self.new_node(NodeType::Text, text);
            self.foster_parent(n);
            return;
        }
        let t = self.top();
        if let Some(l) = self.nodes[t].last
            && self.nodes[l].ty == NodeType::Text
        {
            self.nodes[l].data.push_str(text);
            return;
        }
        let n = self.new_node(NodeType::Text, text);
        self.add_child(n);
    }

    fn add_comment(&mut self) {
        let data = self.tok.data.clone();
        let n = self.new_node(NodeType::Comment, &data);
        self.add_child(n);
    }

    fn append_doc_comment(&mut self) {
        let data = self.tok.data.clone();
        let n = self.new_node(NodeType::Comment, &data);
        let d = self.doc;
        self.append_child(d, n);
    }

    fn add_element(&mut self) {
        let mut n = Node::new(NodeType::Element);
        n.atom = self.tok.atom.clone();
        n.data = self.tok.data.clone();
        n.attr = self.tok.attr.clone();
        let id = self.alloc(n);
        self.add_child(id);
    }

    fn add_formatting_element(&mut self) {
        let tag_atom = self.tok.atom.clone();
        let attr = self.tok.attr.clone();
        self.add_element();
        let mut identical = 0;
        let mut i = self.afe.len();
        'find: while i > 0 {
            i -= 1;
            let id = self.afe[i];
            let n = &self.nodes[id];
            if n.ty == NodeType::ScopeMarker {
                break;
            }
            if n.ty != NodeType::Element
                || !n.namespace.is_empty()
                || n.atom != tag_atom
                || n.attr.len() != attr.len()
            {
                continue;
            }
            for t0 in &n.attr {
                if !attr
                    .iter()
                    .any(|t1| t0.key == t1.key && t0.namespace == t1.namespace && t0.val == t1.val)
                {
                    continue 'find;
                }
            }
            identical += 1;
            if identical >= 3 {
                Self::remove_from(&mut self.afe, id);
            }
        }
        let t = self.top();
        self.afe.push(t);
    }

    fn clear_active_formatting_elements(&mut self) {
        loop {
            let n = self.afe.pop();
            if self.afe.is_empty() || n.is_none_or(|n| self.nodes[n].ty == NodeType::ScopeMarker) {
                return;
            }
        }
    }

    fn reconstruct_active_formatting_elements(&mut self) {
        let Some(&top) = self.afe.last() else {
            return;
        };
        let mut n = top;
        if self.nodes[n].ty == NodeType::ScopeMarker || Self::index_in(&self.oe, n).is_some() {
            return;
        }
        let mut i = self.afe.len() as isize - 1;
        while self.nodes[n].ty != NodeType::ScopeMarker && Self::index_in(&self.oe, n).is_none() {
            if i == 0 {
                i = -1;
                break;
            }
            i -= 1;
            n = self.afe[i as usize];
        }
        loop {
            i += 1;
            let clone = self.clone_node(self.afe[i as usize]);
            self.add_child(clone);
            self.afe[i as usize] = clone;
            if i as usize == self.afe.len() - 1 {
                break;
            }
        }
    }

    fn reset_insertion_mode(&mut self) {
        for i in (0..self.oe.len()).rev() {
            let n = self.oe[i];
            let last = i == 0;
            match self.atom(n) {
                "select" => {
                    if !last {
                        let first = self.oe[0];
                        let mut ancestor = n;
                        while ancestor != first {
                            let idx = Self::index_in(&self.oe, ancestor).unwrap_or(0);
                            ancestor = self.oe[idx.saturating_sub(1)];
                            match self.atom(ancestor) {
                                "template" => {
                                    self.im = Im::InSelect;
                                    return;
                                }
                                "table" => {
                                    self.im = Im::InSelectInTable;
                                    return;
                                }
                                _ => {}
                            }
                        }
                    }
                    self.im = Im::InSelect;
                }
                "td" | "th" => self.im = Im::InCell,
                "tr" => self.im = Im::InRow,
                "tbody" | "thead" | "tfoot" => self.im = Im::InTableBody,
                "caption" => self.im = Im::InCaption,
                "colgroup" => self.im = Im::InColumnGroup,
                "table" => self.im = Im::InTable,
                "template" => {
                    if !self.nodes[n].namespace.is_empty() {
                        continue;
                    }
                    self.im = self.template_stack.last().copied().unwrap_or(Im::InBody);
                }
                "head" => self.im = Im::InHead,
                "body" => self.im = Im::InBody,
                "frameset" => self.im = Im::InFrameset,
                "html" => {
                    self.im = if self.head.is_none() {
                        Im::BeforeHead
                    } else {
                        Im::AfterHead
                    };
                }
                _ => {
                    if last {
                        self.im = Im::InBody;
                        return;
                    }
                    continue;
                }
            }
            return;
        }
    }

    fn copy_attributes(&mut self, dst: Id) {
        if self.tok.attr.is_empty() {
            return;
        }
        for t in self.tok.attr.clone() {
            if !self.nodes[dst].attr.iter().any(|a| a.key == t.key) {
                self.nodes[dst].attr.push(t);
            }
        }
    }

    fn tok_attr_is_hidden_input(&self) -> bool {
        self.tok
            .attr
            .iter()
            .any(|t| t.key == "type" && t.val.eq_ignore_ascii_case("hidden"))
    }

    // ---- insertion modes ----

    fn run_im(&mut self, im: Im) -> bool {
        match im {
            Im::Initial => self.initial_im(),
            Im::BeforeHtml => self.before_html_im(),
            Im::BeforeHead => self.before_head_im(),
            Im::InHead => self.in_head_im(),
            Im::AfterHead => self.after_head_im(),
            Im::InBody => self.in_body_im(),
            Im::Text => self.text_im(),
            Im::InTable => self.in_table_im(),
            Im::InCaption => self.in_caption_im(),
            Im::InColumnGroup => self.in_column_group_im(),
            Im::InTableBody => self.in_table_body_im(),
            Im::InRow => self.in_row_im(),
            Im::InCell => self.in_cell_im(),
            Im::InSelect => self.in_select_im(),
            Im::InSelectInTable => self.in_select_in_table_im(),
            Im::InTemplate => self.in_template_im(),
            Im::AfterBody => self.after_body_im(),
            Im::InFrameset => self.in_frameset_im(),
            Im::AfterFrameset => self.after_frameset_im(),
            Im::AfterAfterBody => self.after_after_body_im(),
            Im::AfterAfterFrameset => self.after_after_frameset_im(),
            Im::IgnoreRemaining => true,
        }
    }

    fn trim_tok_left(&mut self) -> bool {
        self.tok.data = String::from(trim_left(&self.tok.data));
        self.tok.data.is_empty()
    }

    /// Splits leading whitespace off a text token and adds it; returns true when nothing remains.
    fn add_leading_whitespace(&mut self) -> bool {
        let s_len = trim_left(&self.tok.data).len();
        if s_len < self.tok.data.len() {
            let ws = String::from(&self.tok.data[..self.tok.data.len() - s_len]);
            self.add_text(&ws);
            if s_len == 0 {
                return true;
            }
            self.tok.data = String::from(&self.tok.data[self.tok.data.len() - s_len..]);
        }
        false
    }

    fn initial_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Text => {
                if self.trim_tok_left() {
                    return true;
                }
            }
            TokenType::Comment => {
                self.append_doc_comment();
                return true;
            }
            TokenType::Doctype => {
                let (n, quirks) = crate::doctype::parse_doctype(&self.tok.data);
                let id = self.alloc(n);
                let d = self.doc;
                self.append_child(d, id);
                self.quirks = quirks;
                self.im = Im::BeforeHtml;
                return true;
            }
            _ => {}
        }
        self.quirks = true;
        self.im = Im::BeforeHtml;
        false
    }

    fn before_html_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Doctype => return true,
            TokenType::Text => {
                if self.trim_tok_left() {
                    return true;
                }
            }
            TokenType::StartTag => {
                if self.tok.atom == "html" {
                    self.add_element();
                    self.im = Im::BeforeHead;
                    return true;
                }
            }
            TokenType::EndTag => {
                return match self.tok.atom.as_str() {
                    "head" | "body" | "html" | "br" => {
                        self.parse_implied_token(TokenType::StartTag, "html");
                        false
                    }
                    _ => true,
                };
            }
            TokenType::Comment => {
                self.append_doc_comment();
                return true;
            }
            _ => {}
        }
        self.parse_implied_token(TokenType::StartTag, "html");
        false
    }

    fn before_head_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Text => {
                if self.trim_tok_left() {
                    return true;
                }
            }
            TokenType::StartTag => match self.tok.atom.as_str() {
                "head" => {
                    self.add_element();
                    self.head = Some(self.top());
                    self.im = Im::InHead;
                    return true;
                }
                "html" => return self.in_body_im(),
                _ => {}
            },
            TokenType::EndTag => {
                return match self.tok.atom.as_str() {
                    "head" | "body" | "html" | "br" => {
                        self.parse_implied_token(TokenType::StartTag, "head");
                        false
                    }
                    _ => true,
                };
            }
            TokenType::Comment => {
                self.add_comment();
                return true;
            }
            TokenType::Doctype => return true,
            _ => {}
        }
        self.parse_implied_token(TokenType::StartTag, "head");
        false
    }

    fn in_head_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Text => {
                if self.add_leading_whitespace() {
                    return true;
                }
            }
            TokenType::StartTag => match self.tok.atom.clone().as_str() {
                "html" => return self.in_body_im(),
                "base" | "basefont" | "bgsound" | "link" | "meta" => {
                    self.add_element();
                    self.oe.pop();
                    self.acknowledge_self_closing_tag();
                    return true;
                }
                "noscript" => {
                    self.parse_generic_raw_text_element();
                    return true;
                }
                "script" | "title" => {
                    self.add_element();
                    self.original_im = Some(self.im);
                    self.im = Im::Text;
                    return true;
                }
                "noframes" | "style" => {
                    self.parse_generic_raw_text_element();
                    return true;
                }
                "head" => return true,
                "template" => {
                    if self.oe.iter().any(|&e| !self.nodes[e].namespace.is_empty()) {
                        self.im = Im::IgnoreRemaining;
                        return true;
                    }
                    self.add_element();
                    self.afe.push(MARKER);
                    self.frameset_ok = false;
                    self.im = Im::InTemplate;
                    self.template_stack.push(Im::InTemplate);
                    return true;
                }
                _ => {}
            },
            TokenType::EndTag => match self.tok.atom.as_str() {
                "head" => {
                    self.oe.pop();
                    self.im = Im::AfterHead;
                    return true;
                }
                "body" | "html" | "br" => {
                    self.parse_implied_token(TokenType::EndTag, "head");
                    return false;
                }
                "template" => {
                    if !self.oe_contains("template") {
                        return true;
                    }
                    self.generate_implied_end_tags(&[]);
                    for i in (0..self.oe.len()).rev() {
                        let n = &self.nodes[self.oe[i]];
                        if n.namespace.is_empty() && n.atom == "template" {
                            self.oe.truncate(i);
                            break;
                        }
                    }
                    self.clear_active_formatting_elements();
                    self.template_stack.pop();
                    self.reset_insertion_mode();
                    return true;
                }
                _ => return true,
            },
            TokenType::Comment => {
                self.add_comment();
                return true;
            }
            TokenType::Doctype => return true,
            _ => {}
        }
        self.parse_implied_token(TokenType::EndTag, "head");
        false
    }

    fn after_head_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Text => {
                if self.add_leading_whitespace() {
                    return true;
                }
            }
            TokenType::StartTag => match self.tok.atom.as_str() {
                "html" => return self.in_body_im(),
                "body" => {
                    self.add_element();
                    self.frameset_ok = false;
                    self.im = Im::InBody;
                    return true;
                }
                "frameset" => {
                    self.add_element();
                    self.im = Im::InFrameset;
                    return true;
                }
                "base" | "basefont" | "bgsound" | "link" | "meta" | "noframes" | "script"
                | "style" | "template" | "title" => {
                    let head = self.head.unwrap_or(self.doc);
                    self.oe.push(head);
                    let r = self.in_head_im();
                    Self::remove_from(&mut self.oe, head);
                    return r;
                }
                "head" => return true,
                _ => {}
            },
            TokenType::EndTag => match self.tok.atom.as_str() {
                "body" | "html" | "br" => {}
                "template" => return self.in_head_im(),
                _ => return true,
            },
            TokenType::Comment => {
                self.add_comment();
                return true;
            }
            TokenType::Doctype => return true,
            _ => {}
        }
        self.parse_implied_token(TokenType::StartTag, "body");
        self.frameset_ok = true;
        self.tok.ty == TokenType::Error
    }

    fn in_body_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Text => {
                let mut d: &str = &self.tok.data;
                if let Some(n) = self.oe_top()
                    && matches!(self.atom(n), "pre" | "listing")
                    && self.nodes[n].first.is_none()
                {
                    if let Some(r) = d.strip_prefix('\r') {
                        d = r;
                    }
                    if let Some(r) = d.strip_prefix('\n') {
                        d = r;
                    }
                }
                let d: String = d.replace('\0', "");
                if d.is_empty() {
                    return true;
                }
                self.reconstruct_active_formatting_elements();
                self.add_text(&d);
                if self.frameset_ok && !trim_left(&d).is_empty() {
                    self.frameset_ok = false;
                }
            }
            TokenType::StartTag => return self.in_body_start_tag(),
            TokenType::EndTag => return self.in_body_end_tag(),
            TokenType::Comment => self.add_comment(),
            TokenType::Error => {
                if !self.template_stack.is_empty() {
                    self.im = Im::InTemplate;
                    return false;
                }
                for &e in &self.oe {
                    match self.atom(e) {
                        "dd" | "dt" | "li" | "optgroup" | "option" | "p" | "rb" | "rp" | "rt"
                        | "rtc" | "tbody" | "td" | "tfoot" | "th" | "thead" | "tr" | "body"
                        | "html" => {}
                        _ => return true,
                    }
                }
            }
            _ => {}
        }
        true
    }

    fn in_body_start_tag(&mut self) -> bool {
        let tag = self.tok.atom.clone();
        match tag.as_str() {
            "html" => {
                if self.oe_contains("template") {
                    return true;
                }
                let dst = self.oe[0];
                self.copy_attributes(dst);
            }
            "base" | "basefont" | "bgsound" | "link" | "meta" | "noframes" | "script" | "style"
            | "template" | "title" => {
                return self.in_head_im();
            }
            "body" => {
                if self.oe_contains("template") {
                    return true;
                }
                if self.oe.len() >= 2 {
                    let body = self.oe[1];
                    if self.nodes[body].ty == NodeType::Element && self.atom(body) == "body" {
                        self.frameset_ok = false;
                        self.copy_attributes(body);
                    }
                }
            }
            "frameset" => {
                if !self.frameset_ok || self.oe.len() < 2 || self.atom(self.oe[1]) != "body" {
                    return true;
                }
                let body = self.oe[1];
                self.detach(body);
                self.oe.truncate(1);
                self.add_element();
                self.im = Im::InFrameset;
                return true;
            }
            "address" | "article" | "aside" | "blockquote" | "center" | "details" | "dialog"
            | "dir" | "div" | "dl" | "fieldset" | "figcaption" | "figure" | "footer" | "header"
            | "hgroup" | "main" | "menu" | "nav" | "ol" | "p" | "search" | "section"
            | "summary" | "ul" => {
                self.pop_until(Scope::Button, &["p"]);
                self.add_element();
            }
            "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => {
                self.pop_until(Scope::Button, &["p"]);
                if matches!(self.top_atom(), "h1" | "h2" | "h3" | "h4" | "h5" | "h6") {
                    self.oe.pop();
                }
                self.add_element();
            }
            "pre" | "listing" => {
                self.pop_until(Scope::Button, &["p"]);
                self.add_element();
                self.frameset_ok = false;
            }
            "form" => {
                if self.form.is_some() && !self.oe_contains("template") {
                    return true;
                }
                self.pop_until(Scope::Button, &["p"]);
                self.add_element();
                if !self.oe_contains("template") {
                    self.form = Some(self.top());
                }
            }
            "li" => {
                self.frameset_ok = false;
                self.close_list_item(&["li"]);
                self.pop_until(Scope::Button, &["p"]);
                self.add_element();
            }
            "dd" | "dt" => {
                self.frameset_ok = false;
                self.close_list_item(&["dd", "dt"]);
                self.pop_until(Scope::Button, &["p"]);
                self.add_element();
            }
            "plaintext" => {
                self.pop_until(Scope::Button, &["p"]);
                self.add_element();
            }
            "button" => {
                self.pop_until(Scope::Default, &["button"]);
                self.reconstruct_active_formatting_elements();
                self.add_element();
                self.frameset_ok = false;
            }
            "a" => {
                let mut i = self.afe.len();
                while i > 0 && self.nodes[self.afe[i - 1]].ty != NodeType::ScopeMarker {
                    i -= 1;
                    let n = self.afe[i];
                    if self.nodes[n].ty == NodeType::Element && self.atom(n) == "a" {
                        self.in_body_end_tag_formatting("a", "a");
                        Self::remove_from(&mut self.oe, n);
                        Self::remove_from(&mut self.afe, n);
                        break;
                    }
                }
                self.reconstruct_active_formatting_elements();
                self.add_formatting_element();
            }
            "b" | "big" | "code" | "em" | "font" | "i" | "s" | "small" | "strike" | "strong"
            | "tt" | "u" => {
                self.reconstruct_active_formatting_elements();
                self.add_formatting_element();
            }
            "nobr" => {
                self.reconstruct_active_formatting_elements();
                if self.element_in_scope(Scope::Default, &["nobr"]) {
                    self.in_body_end_tag_formatting("nobr", "nobr");
                    self.reconstruct_active_formatting_elements();
                }
                self.add_formatting_element();
            }
            "applet" | "marquee" | "object" => {
                self.reconstruct_active_formatting_elements();
                self.add_element();
                self.afe.push(MARKER);
                self.frameset_ok = false;
            }
            "table" => {
                if !self.quirks {
                    self.pop_until(Scope::Button, &["p"]);
                }
                self.add_element();
                self.frameset_ok = false;
                self.im = Im::InTable;
                return true;
            }
            "area" | "br" | "embed" | "img" | "input" | "keygen" | "wbr" => {
                self.reconstruct_active_formatting_elements();
                self.add_element();
                self.oe.pop();
                self.acknowledge_self_closing_tag();
                if self.tok.atom == "input" && self.tok_attr_is_hidden_input() {
                    return true;
                }
                self.frameset_ok = false;
            }
            "param" | "source" | "track" => {
                self.add_element();
                self.oe.pop();
                self.acknowledge_self_closing_tag();
            }
            "hr" => {
                self.pop_until(Scope::Button, &["p"]);
                self.add_element();
                self.oe.pop();
                self.acknowledge_self_closing_tag();
                self.frameset_ok = false;
            }
            "image" => {
                self.tok.atom = String::from("img");
                self.tok.data = String::from("img");
                return false;
            }
            "textarea" => {
                self.add_element();
                self.original_im = Some(self.im);
                self.frameset_ok = false;
                self.im = Im::Text;
            }
            "xmp" => {
                self.pop_until(Scope::Button, &["p"]);
                self.reconstruct_active_formatting_elements();
                self.frameset_ok = false;
                self.parse_generic_raw_text_element();
            }
            "iframe" => {
                self.frameset_ok = false;
                self.parse_generic_raw_text_element();
            }
            "noembed" => self.parse_generic_raw_text_element(),
            "noscript" => {
                self.parse_generic_raw_text_element();
                return true;
            }
            "select" => {
                self.reconstruct_active_formatting_elements();
                self.add_element();
                self.frameset_ok = false;
                self.im = Im::InSelect;
                return true;
            }
            "optgroup" | "option" => {
                if self.top_atom() == "option" {
                    self.oe.pop();
                }
                self.reconstruct_active_formatting_elements();
                self.add_element();
            }
            "rb" | "rtc" => {
                if self.element_in_scope(Scope::Default, &["ruby"]) {
                    self.generate_implied_end_tags(&[]);
                }
                self.add_element();
            }
            "rp" | "rt" => {
                if self.element_in_scope(Scope::Default, &["ruby"]) {
                    self.generate_implied_end_tags(&["rtc"]);
                }
                self.add_element();
            }
            "math" | "svg" => {
                self.reconstruct_active_formatting_elements();
                if tag == "math" {
                    adjust_attribute_names(&mut self.tok.attr, math_attribute_adjustment);
                } else {
                    adjust_attribute_names(&mut self.tok.attr, svg_attribute_adjustment);
                }
                adjust_foreign_attributes(&mut self.tok.attr);
                self.add_element();
                let t = self.top();
                self.nodes[t].namespace = self.tok.data.clone();
                if self.has_self_closing {
                    self.oe.pop();
                    self.acknowledge_self_closing_tag();
                }
                return true;
            }
            "caption" | "col" | "colgroup" | "frame" | "head" | "tbody" | "td" | "tfoot" | "th"
            | "thead" | "tr" => {}
            _ => {
                self.reconstruct_active_formatting_elements();
                self.add_element();
            }
        }
        true
    }

    /// The `li` / `dd` / `dt` loop of the start-tag rules: closes an open item of the same kind.
    fn close_list_item(&mut self, items: &[&str]) {
        for i in (0..self.oe.len()).rev() {
            let node = self.oe[i];
            let a = self.atom(node);
            if items.contains(&a) {
                self.oe.truncate(i);
            } else if matches!(a, "address" | "div" | "p") || !self.is_special_element(node) {
                continue;
            }
            break;
        }
    }

    fn in_body_end_tag(&mut self) -> bool {
        let tag = self.tok.atom.clone();
        match tag.as_str() {
            "body" => {
                if self.element_in_scope(Scope::Default, &["body"]) {
                    self.im = Im::AfterBody;
                }
            }
            "html" => {
                if self.element_in_scope(Scope::Default, &["body"]) {
                    self.parse_implied_token(TokenType::EndTag, "body");
                    return false;
                }
                return true;
            }
            "address" | "article" | "aside" | "blockquote" | "button" | "center" | "details"
            | "dialog" | "dir" | "div" | "dl" | "fieldset" | "figcaption" | "figure" | "footer"
            | "header" | "hgroup" | "listing" | "main" | "menu" | "nav" | "ol" | "pre"
            | "search" | "section" | "summary" | "ul" => {
                self.pop_until(Scope::Default, &[&tag]);
            }
            "form" => {
                if self.oe_contains("template") {
                    let Some(i) = self.index_of_element_in_scope(Scope::Default, &["form"]) else {
                        return true;
                    };
                    self.generate_implied_end_tags(&[]);
                    if self.atom(self.oe[i]) != "form" {
                        return true;
                    }
                    self.pop_until(Scope::Default, &["form"]);
                } else {
                    let node = self.form.take();
                    let i = self.index_of_element_in_scope(Scope::Default, &["form"]);
                    match (node, i) {
                        (Some(node), Some(i)) if self.oe[i] == node => {}
                        _ => return true,
                    }
                    self.generate_implied_end_tags(&[]);
                    Self::remove_from(&mut self.oe, node.unwrap_or(0));
                }
            }
            "p" => {
                if !self.element_in_scope(Scope::Button, &["p"]) {
                    self.parse_implied_token(TokenType::StartTag, "p");
                }
                self.pop_until(Scope::Button, &["p"]);
            }
            "li" => {
                self.pop_until(Scope::ListItem, &["li"]);
            }
            "dd" | "dt" => {
                self.pop_until(Scope::Default, &[&tag]);
            }
            "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => {
                self.pop_until(Scope::Default, &["h1", "h2", "h3", "h4", "h5", "h6"]);
            }
            "a" | "b" | "big" | "code" | "em" | "font" | "i" | "nobr" | "s" | "small"
            | "strike" | "strong" | "tt" | "u" => {
                let data = self.tok.data.clone();
                self.in_body_end_tag_formatting(&tag, &data);
            }
            "applet" | "marquee" | "object" => {
                if self.pop_until(Scope::Default, &[&tag]) {
                    self.clear_active_formatting_elements();
                }
            }
            "br" => {
                self.tok.ty = TokenType::StartTag;
                return false;
            }
            "template" => return self.in_head_im(),
            _ => {
                let data = self.tok.data.clone();
                self.in_body_end_tag_other(&tag, &data);
            }
        }
        true
    }

    /// The adoption agency algorithm.
    fn in_body_end_tag_formatting(&mut self, tag_atom: &str, tag_name: &str) {
        if let Some(current) = self.oe_top()
            && self.nodes[current].data == tag_name
            && Self::index_in(&self.afe, current).is_none()
        {
            self.oe.pop();
            return;
        }
        for _ in 0..8 {
            let mut formatting: Option<Id> = None;
            for j in (0..self.afe.len()).rev() {
                let n = self.afe[j];
                if self.nodes[n].ty == NodeType::ScopeMarker {
                    break;
                }
                if self.atom(n) == tag_atom {
                    formatting = Some(n);
                    break;
                }
            }
            let Some(formatting) = formatting else {
                self.in_body_end_tag_other(tag_atom, tag_name);
                return;
            };
            let Some(fe_index) = Self::index_in(&self.oe, formatting) else {
                Self::remove_from(&mut self.afe, formatting);
                return;
            };
            if !self.element_in_scope(Scope::Default, &[tag_atom]) {
                return;
            }
            let furthest = self.oe[fe_index..]
                .iter()
                .copied()
                .find(|&e| self.is_special_element(e));
            let Some(furthest) = furthest else {
                loop {
                    let e = self.oe.pop();
                    if e == Some(formatting) || e.is_none() {
                        break;
                    }
                }
                Self::remove_from(&mut self.afe, formatting);
                return;
            };
            let common_ancestor = self.oe[fe_index - 1];
            let mut bookmark = Self::index_in(&self.afe, formatting).map_or(-1, |x| x as isize);
            let mut last_node = furthest;
            let mut node;
            let mut x = Self::index_in(&self.oe, furthest).map_or(-1, |x| x as isize);
            let mut j = 0;
            loop {
                j += 1;
                x -= 1;
                node = self.oe[x as usize];
                if node == formatting {
                    break;
                }
                let ni = Self::index_in(&self.afe, node);
                if j > 3
                    && let Some(ni) = ni
                {
                    Self::remove_from(&mut self.afe, node);
                    if ni as isize <= bookmark {
                        bookmark -= 1;
                    }
                    continue;
                }
                let Some(ni) = ni else {
                    Self::remove_from(&mut self.oe, node);
                    continue;
                };
                let clone = self.clone_node(node);
                self.afe[ni] = clone;
                if let Some(oi) = Self::index_in(&self.oe, node) {
                    self.oe[oi] = clone;
                }
                node = clone;
                if last_node == furthest {
                    bookmark = Self::index_in(&self.afe, node).map_or(-1, |x| x as isize) + 1;
                }
                self.detach(last_node);
                self.append_child(node, last_node);
                last_node = node;
            }
            self.detach(last_node);
            if matches!(
                self.atom(common_ancestor),
                "table" | "tbody" | "tfoot" | "thead" | "tr"
            ) {
                self.foster_parent(last_node);
            } else {
                self.append_child(common_ancestor, last_node);
            }
            let clone = self.clone_node(formatting);
            self.reparent_children(clone, furthest);
            self.append_child(furthest, clone);
            if let Some(old) = Self::index_in(&self.afe, formatting)
                && (old as isize) < bookmark
            {
                bookmark -= 1;
            }
            Self::remove_from(&mut self.afe, formatting);
            let at = (bookmark.max(0) as usize).min(self.afe.len());
            self.afe.insert(at, clone);
            Self::remove_from(&mut self.oe, formatting);
            let at = Self::index_in(&self.oe, furthest).map_or(0, |i| i + 1);
            self.oe.insert(at, clone);
        }
    }

    fn in_body_end_tag_other(&mut self, tag_atom: &str, tag_name: &str) {
        for i in (0..self.oe.len()).rev() {
            let n = self.oe[i];
            if self.atom(n) == tag_atom && (!tag_atom.is_empty() || self.nodes[n].data == tag_name)
            {
                self.oe.truncate(i);
                break;
            }
            if self.is_special_element(n) {
                break;
            }
        }
    }

    fn text_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Error => {
                self.oe.pop();
            }
            TokenType::Text => {
                let mut d: &str = &self.tok.data;
                if let Some(n) = self.oe_top()
                    && self.atom(n) == "textarea"
                    && self.nodes[n].first.is_none()
                {
                    if let Some(r) = d.strip_prefix('\r') {
                        d = r;
                    }
                    if let Some(r) = d.strip_prefix('\n') {
                        d = r;
                    }
                }
                if d.is_empty() {
                    return true;
                }
                let d = String::from(d);
                self.add_text(&d);
                return true;
            }
            TokenType::EndTag => {
                self.oe.pop();
            }
            _ => {}
        }
        self.im = self.original_im.take().unwrap_or(Im::InBody);
        self.tok.ty == TokenType::EndTag
    }

    fn in_table_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Text => {
                self.tok.data = self.tok.data.replace('\0', "");
                if matches!(
                    self.oe_top_atom(),
                    "table" | "tbody" | "tfoot" | "thead" | "tr"
                ) && self.tok.data.trim_matches(WHITESPACE).is_empty()
                {
                    let d = self.tok.data.clone();
                    self.add_text(&d);
                    return true;
                }
            }
            TokenType::StartTag => match self.tok.atom.clone().as_str() {
                "caption" => {
                    self.clear_stack_to_context(Scope::Table);
                    self.afe.push(MARKER);
                    self.add_element();
                    self.im = Im::InCaption;
                    return true;
                }
                "colgroup" => {
                    self.clear_stack_to_context(Scope::Table);
                    self.add_element();
                    self.im = Im::InColumnGroup;
                    return true;
                }
                "col" => {
                    self.parse_implied_token(TokenType::StartTag, "colgroup");
                    return false;
                }
                "tbody" | "tfoot" | "thead" => {
                    self.clear_stack_to_context(Scope::Table);
                    self.add_element();
                    self.im = Im::InTableBody;
                    return true;
                }
                "td" | "th" | "tr" => {
                    self.parse_implied_token(TokenType::StartTag, "tbody");
                    return false;
                }
                "table" => {
                    if self.pop_until(Scope::Table, &["table"]) {
                        self.reset_insertion_mode();
                        return false;
                    }
                    return true;
                }
                "style" | "script" | "template" => return self.in_head_im(),
                "input" => {
                    if self.tok_attr_is_hidden_input() {
                        self.add_element();
                        self.oe.pop();
                        return true;
                    }
                }
                "form" => {
                    if self.oe_contains("template") || self.form.is_some() {
                        return true;
                    }
                    self.add_element();
                    self.form = self.oe.pop();
                }
                "select" => {
                    self.reconstruct_active_formatting_elements();
                    if matches!(
                        self.top_atom(),
                        "table" | "tbody" | "tfoot" | "thead" | "tr"
                    ) {
                        self.foster_parenting = true;
                    }
                    self.add_element();
                    self.foster_parenting = false;
                    self.frameset_ok = false;
                    self.im = Im::InSelectInTable;
                    return true;
                }
                _ => {}
            },
            TokenType::EndTag => match self.tok.atom.as_str() {
                "table" => {
                    if self.pop_until(Scope::Table, &["table"]) {
                        self.reset_insertion_mode();
                    }
                    return true;
                }
                "body" | "caption" | "col" | "colgroup" | "html" | "tbody" | "td" | "tfoot"
                | "th" | "thead" | "tr" => {
                    return true;
                }
                "template" => return self.in_head_im(),
                _ => {}
            },
            TokenType::Comment => {
                self.add_comment();
                return true;
            }
            TokenType::Doctype => return true,
            TokenType::Error => return self.in_body_im(),
            _ => {}
        }
        self.foster_parenting = true;
        let r = self.in_body_im();
        self.foster_parenting = false;
        r
    }

    fn in_caption_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::StartTag => match self.tok.atom.as_str() {
                "caption" | "col" | "colgroup" | "tbody" | "td" | "tfoot" | "thead" | "tr" => {
                    if !self.pop_until(Scope::Table, &["caption"]) {
                        return true;
                    }
                    self.clear_active_formatting_elements();
                    self.im = Im::InTable;
                    return false;
                }
                "select" => {
                    self.reconstruct_active_formatting_elements();
                    self.add_element();
                    self.frameset_ok = false;
                    self.im = Im::InSelectInTable;
                    return true;
                }
                _ => {}
            },
            TokenType::EndTag => match self.tok.atom.as_str() {
                "caption" => {
                    if self.pop_until(Scope::Table, &["caption"]) {
                        self.clear_active_formatting_elements();
                        self.im = Im::InTable;
                    }
                    return true;
                }
                "table" => {
                    if !self.pop_until(Scope::Table, &["caption"]) {
                        return true;
                    }
                    self.clear_active_formatting_elements();
                    self.im = Im::InTable;
                    return false;
                }
                "body" | "col" | "colgroup" | "html" | "tbody" | "td" | "tfoot" | "th"
                | "thead" | "tr" => return true,
                _ => {}
            },
            _ => {}
        }
        self.in_body_im()
    }

    fn in_column_group_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Text => {
                if self.add_leading_whitespace() {
                    return true;
                }
            }
            TokenType::Comment => {
                self.add_comment();
                return true;
            }
            TokenType::Doctype => return true,
            TokenType::StartTag => match self.tok.atom.as_str() {
                "html" => return self.in_body_im(),
                "col" => {
                    self.add_element();
                    self.oe.pop();
                    self.acknowledge_self_closing_tag();
                    return true;
                }
                "template" => return self.in_head_im(),
                _ => {}
            },
            TokenType::EndTag => match self.tok.atom.as_str() {
                "colgroup" => {
                    if self.oe_top_atom() == "colgroup" {
                        self.oe.pop();
                        self.im = Im::InTable;
                    }
                    return true;
                }
                "col" => return true,
                "template" => return self.in_head_im(),
                _ => {}
            },
            TokenType::Error => return self.in_body_im(),
            _ => {}
        }
        if self.oe_top_atom() != "colgroup" {
            return true;
        }
        self.oe.pop();
        self.im = Im::InTable;
        false
    }

    fn in_table_body_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::StartTag => match self.tok.atom.as_str() {
                "tr" => {
                    self.clear_stack_to_context(Scope::TableBody);
                    self.add_element();
                    self.im = Im::InRow;
                    return true;
                }
                "td" | "th" => {
                    self.parse_implied_token(TokenType::StartTag, "tr");
                    return false;
                }
                "caption" | "col" | "colgroup" | "tbody" | "tfoot" | "thead" => {
                    if self.pop_until(Scope::Table, &["tbody", "thead", "tfoot"]) {
                        self.im = Im::InTable;
                        return false;
                    }
                    return true;
                }
                _ => {}
            },
            TokenType::EndTag => {
                let tag = self.tok.atom.clone();
                match tag.as_str() {
                    "tbody" | "tfoot" | "thead" => {
                        if self.element_in_scope(Scope::Table, &[&tag]) {
                            self.clear_stack_to_context(Scope::TableBody);
                            self.oe.pop();
                            self.im = Im::InTable;
                        }
                        return true;
                    }
                    "table" => {
                        if self.pop_until(Scope::Table, &["tbody", "thead", "tfoot"]) {
                            self.im = Im::InTable;
                            return false;
                        }
                        return true;
                    }
                    "body" | "caption" | "col" | "colgroup" | "html" | "td" | "th" | "tr" => {
                        return true;
                    }
                    _ => {}
                }
            }
            TokenType::Comment => {
                self.add_comment();
                return true;
            }
            _ => {}
        }
        self.in_table_im()
    }

    fn in_row_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::StartTag => match self.tok.atom.as_str() {
                "td" | "th" => {
                    self.clear_stack_to_context(Scope::TableRow);
                    self.add_element();
                    self.afe.push(MARKER);
                    self.im = Im::InCell;
                    return true;
                }
                "caption" | "col" | "colgroup" | "tbody" | "tfoot" | "thead" | "tr" => {
                    if self.pop_until(Scope::Table, &["tr"]) {
                        self.im = Im::InTableBody;
                        return false;
                    }
                    return true;
                }
                _ => {}
            },
            TokenType::EndTag => {
                let tag = self.tok.atom.clone();
                match tag.as_str() {
                    "tr" => {
                        if self.pop_until(Scope::Table, &["tr"]) {
                            self.im = Im::InTableBody;
                        }
                        return true;
                    }
                    "table" => {
                        if self.pop_until(Scope::Table, &["tr"]) {
                            self.im = Im::InTableBody;
                            return false;
                        }
                        return true;
                    }
                    "tbody" | "tfoot" | "thead" => {
                        if self.element_in_scope(Scope::Table, &[&tag]) {
                            self.parse_implied_token(TokenType::EndTag, "tr");
                            return false;
                        }
                        return true;
                    }
                    "body" | "caption" | "col" | "colgroup" | "html" | "td" | "th" => return true,
                    _ => {}
                }
            }
            _ => {}
        }
        self.in_table_im()
    }

    fn in_cell_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::StartTag => match self.tok.atom.as_str() {
                "caption" | "col" | "colgroup" | "tbody" | "td" | "tfoot" | "th" | "thead"
                | "tr" => {
                    if self.pop_until(Scope::Table, &["td", "th"]) {
                        self.clear_active_formatting_elements();
                        self.im = Im::InRow;
                        return false;
                    }
                    return true;
                }
                "select" => {
                    self.reconstruct_active_formatting_elements();
                    self.add_element();
                    self.frameset_ok = false;
                    self.im = Im::InSelectInTable;
                    return true;
                }
                _ => {}
            },
            TokenType::EndTag => {
                let tag = self.tok.atom.clone();
                match tag.as_str() {
                    "td" | "th" => {
                        if !self.pop_until(Scope::Table, &[&tag]) {
                            return true;
                        }
                        self.clear_active_formatting_elements();
                        self.im = Im::InRow;
                        return true;
                    }
                    "body" | "caption" | "col" | "colgroup" | "html" => return true,
                    "table" | "tbody" | "tfoot" | "thead" | "tr" => {
                        if !self.element_in_scope(Scope::Table, &[&tag]) {
                            return true;
                        }
                        if self.pop_until(Scope::Table, &["td", "th"]) {
                            self.clear_active_formatting_elements();
                        }
                        self.im = Im::InRow;
                        return false;
                    }
                    _ => {}
                }
            }
            _ => {}
        }
        self.in_body_im()
    }

    fn in_select_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Text => {
                let d = self.tok.data.replace('\0', "");
                self.add_text(&d);
            }
            TokenType::StartTag => match self.tok.atom.as_str() {
                "html" => return self.in_body_im(),
                "option" => {
                    if self.top_atom() == "option" {
                        self.oe.pop();
                    }
                    self.add_element();
                }
                "optgroup" => {
                    if self.top_atom() == "option" {
                        self.oe.pop();
                    }
                    if self.top_atom() == "optgroup" {
                        self.oe.pop();
                    }
                    self.add_element();
                }
                "select" => {
                    if !self.pop_until(Scope::Select, &["select"]) {
                        return true;
                    }
                    self.reset_insertion_mode();
                }
                "input" | "keygen" | "textarea" => {
                    if self.element_in_scope(Scope::Select, &["select"]) {
                        self.parse_implied_token(TokenType::EndTag, "select");
                        return false;
                    }
                    self.tokenizer.next_is_not_raw_text();
                    return true;
                }
                "script" | "template" => return self.in_head_im(),
                "iframe" | "noembed" | "noframes" | "noscript" | "plaintext" | "style"
                | "title" | "xmp" => {
                    self.tokenizer.next_is_not_raw_text();
                    return true;
                }
                _ => {}
            },
            TokenType::EndTag => match self.tok.atom.as_str() {
                "option" => {
                    if self.top_atom() == "option" {
                        self.oe.pop();
                    }
                }
                "optgroup" => {
                    let mut i = self.oe.len() - 1;
                    if self.atom(self.oe[i]) == "option" {
                        i -= 1;
                    }
                    if self.atom(self.oe[i]) == "optgroup" {
                        self.oe.truncate(i);
                    }
                }
                "select" => {
                    if !self.pop_until(Scope::Select, &["select"]) {
                        return true;
                    }
                    self.reset_insertion_mode();
                }
                "template" => return self.in_head_im(),
                _ => {}
            },
            TokenType::Comment => self.add_comment(),
            TokenType::Doctype => return true,
            TokenType::Error => return self.in_body_im(),
            _ => {}
        }
        true
    }

    fn in_select_in_table_im(&mut self) -> bool {
        if matches!(self.tok.ty, TokenType::StartTag | TokenType::EndTag) {
            let tag = self.tok.atom.clone();
            if matches!(
                tag.as_str(),
                "caption" | "table" | "tbody" | "tfoot" | "thead" | "tr" | "td" | "th"
            ) {
                if self.tok.ty == TokenType::EndTag && !self.element_in_scope(Scope::Table, &[&tag])
                {
                    return true;
                }
                for i in (0..self.oe.len()).rev() {
                    if self.atom(self.oe[i]) == "select" {
                        self.oe.truncate(i);
                        break;
                    }
                }
                self.reset_insertion_mode();
                return false;
            }
        }
        self.in_select_im()
    }

    fn set_template_top(&mut self, im: Im) {
        self.template_stack.pop();
        self.template_stack.push(im);
        self.im = im;
    }

    fn in_template_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Text | TokenType::Comment | TokenType::Doctype => self.in_body_im(),
            TokenType::StartTag => {
                match self.tok.atom.as_str() {
                    "base" | "basefont" | "bgsound" | "link" | "meta" | "noframes" | "script"
                    | "style" | "template" | "title" => return self.in_head_im(),
                    "caption" | "colgroup" | "tbody" | "tfoot" | "thead" => {
                        self.set_template_top(Im::InTable)
                    }
                    "col" => self.set_template_top(Im::InColumnGroup),
                    "tr" => self.set_template_top(Im::InTableBody),
                    "td" | "th" => self.set_template_top(Im::InRow),
                    _ => self.set_template_top(Im::InBody),
                }
                false
            }
            TokenType::EndTag => {
                if self.tok.atom == "template" {
                    self.in_head_im()
                } else {
                    true
                }
            }
            TokenType::Error => {
                if !self.oe_contains("template") {
                    return true;
                }
                self.generate_implied_end_tags(&[]);
                for i in (0..self.oe.len()).rev() {
                    let n = &self.nodes[self.oe[i]];
                    if n.namespace.is_empty() && n.atom == "template" {
                        self.oe.truncate(i);
                        break;
                    }
                }
                self.clear_active_formatting_elements();
                self.template_stack.pop();
                self.reset_insertion_mode();
                false
            }
            _ => false,
        }
    }

    fn after_body_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Error => return true,
            TokenType::Text => {
                if trim_left(&self.tok.data).is_empty() {
                    return self.in_body_im();
                }
            }
            TokenType::StartTag => {
                if self.tok.atom == "html" {
                    return self.in_body_im();
                }
            }
            TokenType::EndTag => {
                if self.tok.atom == "html" {
                    self.im = Im::AfterAfterBody;
                    return true;
                }
            }
            TokenType::Comment => {
                let data = self.tok.data.clone();
                let n = self.new_node(NodeType::Comment, &data);
                let html = self.oe[0];
                self.append_child(html, n);
                return true;
            }
            _ => {}
        }
        self.im = Im::InBody;
        false
    }

    /// The whitespace characters of the text token, as the framesets keep only those.
    fn tok_whitespace_only(&self) -> String {
        self.tok
            .data
            .chars()
            .filter(|c| matches!(c, ' ' | '\t' | '\n' | '\x0c' | '\r'))
            .collect()
    }

    fn in_frameset_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Comment => self.add_comment(),
            TokenType::Text => {
                let s = self.tok_whitespace_only();
                if !s.is_empty() {
                    self.add_text(&s);
                }
            }
            TokenType::StartTag => match self.tok.atom.as_str() {
                "html" => return self.in_body_im(),
                "frameset" => self.add_element(),
                "frame" => {
                    self.add_element();
                    self.oe.pop();
                    self.acknowledge_self_closing_tag();
                }
                "noframes" => return self.in_head_im(),
                _ => {}
            },
            TokenType::EndTag if self.tok.atom == "frameset" && self.oe_top_atom() != "html" => {
                self.oe.pop();
                if self.oe_top_atom() != "frameset" {
                    self.im = Im::AfterFrameset;
                    return true;
                }
            }
            _ => {}
        }
        true
    }

    fn after_frameset_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Comment => self.add_comment(),
            TokenType::Text => {
                let s = self.tok_whitespace_only();
                if !s.is_empty() {
                    self.add_text(&s);
                }
            }
            TokenType::StartTag => match self.tok.atom.as_str() {
                "html" => return self.in_body_im(),
                "noframes" => return self.in_head_im(),
                _ => {}
            },
            TokenType::EndTag if self.tok.atom == "html" => {
                self.im = Im::AfterAfterFrameset;
                return true;
            }
            _ => {}
        }
        true
    }

    fn after_after_body_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Error => return true,
            TokenType::Text => {
                if trim_left(&self.tok.data).is_empty() {
                    return self.in_body_im();
                }
            }
            TokenType::StartTag => {
                if self.tok.atom == "html" {
                    return self.in_body_im();
                }
            }
            TokenType::Comment => {
                self.append_doc_comment();
                return true;
            }
            TokenType::Doctype => return self.in_body_im(),
            _ => {}
        }
        self.im = Im::InBody;
        false
    }

    fn after_after_frameset_im(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Comment => self.append_doc_comment(),
            TokenType::Text => {
                let s = self.tok_whitespace_only();
                if !s.is_empty() {
                    self.tok.data = s;
                    return self.in_body_im();
                }
            }
            TokenType::StartTag => match self.tok.atom.as_str() {
                "html" => return self.in_body_im(),
                "noframes" => return self.in_head_im(),
                _ => {}
            },
            TokenType::Doctype => return self.in_body_im(),
            _ => {}
        }
        true
    }

    // ---- foreign content ----

    fn parse_foreign_content(&mut self) -> bool {
        match self.tok.ty {
            TokenType::Text => {
                if self.frameset_ok {
                    self.frameset_ok = self
                        .tok
                        .data
                        .trim_start_matches(|c| WHITESPACE.contains(&c) || c == '\0')
                        .is_empty();
                }
                self.tok.data = self.tok.data.replace('\0', "\u{FFFD}");
                let d = self.tok.data.clone();
                self.add_text(&d);
            }
            TokenType::Comment => self.add_comment(),
            TokenType::StartTag => {
                let mut b = is_breakout(&self.tok.data);
                if self.tok.atom == "font"
                    && self
                        .tok
                        .attr
                        .iter()
                        .any(|a| matches!(a.key.as_str(), "color" | "face" | "size"))
                {
                    b = true;
                }
                if b {
                    for i in (0..self.oe.len()).rev() {
                        let n = &self.nodes[self.oe[i]];
                        if n.namespace.is_empty()
                            || html_integration_point(n)
                            || math_ml_text_integration_point(n)
                        {
                            self.oe.truncate(i + 1);
                            break;
                        }
                    }
                    return false;
                }
                let current = self.adjusted_current_node();
                let ns = self.nodes[current].namespace.clone();
                match ns.as_str() {
                    "math" => adjust_attribute_names(&mut self.tok.attr, math_attribute_adjustment),
                    "svg" => {
                        if let Some(x) = svg_tag_name_adjustment(&self.tok.data) {
                            self.tok.atom = atom_of(x);
                            self.tok.data = String::from(x);
                        }
                        adjust_attribute_names(&mut self.tok.attr, svg_attribute_adjustment);
                    }
                    _ => {}
                }
                adjust_foreign_attributes(&mut self.tok.attr);
                self.add_element();
                let t = self.top();
                self.nodes[t].namespace = ns.clone();
                if !ns.is_empty() {
                    self.tokenizer.next_is_not_raw_text();
                }
                if self.has_self_closing {
                    self.oe.pop();
                    self.acknowledge_self_closing_tag();
                }
            }
            TokenType::EndTag => {
                for i in (0..self.oe.len()).rev() {
                    if self.nodes[self.oe[i]].namespace.is_empty() {
                        return self.run_im(self.im);
                    }
                    if self.nodes[self.oe[i]]
                        .data
                        .eq_ignore_ascii_case(&self.tok.data)
                    {
                        self.oe.truncate(i);
                        break;
                    }
                }
                return true;
            }
            _ => {}
        }
        true
    }

    fn adjusted_current_node(&self) -> Id {
        self.oe_top().unwrap_or(self.doc)
    }

    fn in_foreign_content(&self) -> bool {
        let Some(n) = self.oe_top() else {
            return false;
        };
        let node = &self.nodes[n];
        if node.namespace.is_empty() {
            return false;
        }
        if math_ml_text_integration_point(node) {
            if self.tok.ty == TokenType::StartTag
                && self.tok.atom != "mglyph"
                && self.tok.atom != "malignmark"
            {
                return false;
            }
            if self.tok.ty == TokenType::Text {
                return false;
            }
        }
        if node.namespace == "math"
            && node.atom == "annotation-xml"
            && self.tok.ty == TokenType::StartTag
            && self.tok.atom == "svg"
        {
            return false;
        }
        if html_integration_point(node)
            && matches!(self.tok.ty, TokenType::StartTag | TokenType::Text)
        {
            return false;
        }
        if self.tok.ty == TokenType::Error {
            return false;
        }
        true
    }

    fn acknowledge_self_closing_tag(&mut self) {
        self.has_self_closing = false;
    }

    fn parse_implied_token(&mut self, ty: TokenType, name: &str) {
        let real = core::mem::replace(
            &mut self.tok,
            Token {
                ty,
                atom: atom_of(name),
                data: String::from(name),
                attr: Vec::new(),
            },
        );
        let self_closing = self.has_self_closing;
        self.has_self_closing = false;
        self.parse_current_token();
        self.tok = real;
        self.has_self_closing = self_closing;
    }

    fn parse_current_token(&mut self) {
        if self.tok.ty == TokenType::SelfClosingTag {
            self.has_self_closing = true;
            self.tok.ty = TokenType::StartTag;
        }
        let mut consumed = false;
        while !consumed {
            consumed = if self.in_foreign_content() {
                self.parse_foreign_content()
            } else {
                self.run_im(self.im)
            };
        }
        if self.has_self_closing {
            self.has_self_closing = false;
        }
    }

    pub fn parse(&mut self) {
        loop {
            let n = self.oe_top();
            let foreign = n.is_some_and(|n| !self.nodes[n].namespace.is_empty());
            self.tokenizer.allow_cdata(foreign);
            self.tokenizer.next();
            self.tok = self.tokenizer.token();
            let eof = self.tok.ty == TokenType::Error;
            self.parse_current_token();
            if eof {
                break;
            }
        }
    }
}
