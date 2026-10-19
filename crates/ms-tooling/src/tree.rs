//! The tree every diagram view is built from, and its two renderings.

use std::fmt::Write;

/// One line of a view: a label and what hangs under it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Node {
    pub label: String,
    pub children: Vec<Node>,
    /// Flow step kind: call, native, try, with, branch, match, arm, or exit.
    pub kind: String,
    /// The callee's entity key for project calls.
    pub reference: String,
    /// Where a flow step is in the source, for marking a diff.
    pub file: String,
    pub line: usize,
}

impl Node {
    pub fn new(label: impl Into<String>) -> Node {
        Node {
            label: label.into(),
            ..Node::default()
        }
    }

    pub fn with_children(label: impl Into<String>, children: Vec<Node>) -> Node {
        Node {
            label: label.into(),
            children,
            ..Node::default()
        }
    }

    /// Prints the tree with fixed connectors.
    pub fn ascii(&self) -> String {
        let mut out = String::new();
        out.push_str(&self.label);
        out.push('\n');
        write_children(&mut out, &self.children, "");
        out
    }

    /// Prints the same tree as a flowchart; node names are pre-order numbers.
    pub fn mermaid(&self) -> String {
        let mut out = String::from("flowchart TD\n");
        let mut count = 0;
        self.mermaid_into(&mut out, &mut count);
        out
    }

    fn mermaid_into(&self, out: &mut String, count: &mut usize) -> String {
        let id = format!("n{count}");
        *count += 1;
        let label = self
            .label
            .replace('&', "&amp;")
            .replace('"', "&quot;")
            .replace('<', "&lt;")
            .replace('>', "&gt;");
        let _ = writeln!(out, "    {id}[\"{label}\"]");
        for child in &self.children {
            let child_id = child.mermaid_into(out, count);
            let _ = writeln!(out, "    {id} --> {child_id}");
        }
        id
    }
}

fn write_children(out: &mut String, children: &[Node], prefix: &str) {
    for (i, child) in children.iter().enumerate() {
        let last = i + 1 == children.len();
        let (connector, next) = if last { ("`- ", "   ") } else { ("|- ", "|  ") };
        out.push_str(prefix);
        out.push_str(connector);
        out.push_str(&child.label);
        out.push('\n');
        write_children(out, &child.children, &format!("{prefix}{next}"));
    }
}
