mod app;
mod extra;
mod model;
mod query;
mod util;

use app::App;
use std::io::{self, Read, Write};
use util::{split_n, trim_ws};

fn main() {
    let mut raw = Vec::new();
    io::stdin().read_to_end(&mut raw).unwrap_or(0);
    let input = String::from_utf8_lossy(&raw).into_owned();

    let mut app = App::new();
    let mut out = String::new();
    let mut lines = input.lines();

    while let Some(line) = lines.next() {
        let line = line.trim_end_matches('\r');
        let trimmed = trim_ws(line);
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let echo = line.trim_end_matches(|c| c == ' ' || c == '\t');
        out.push_str("> ");
        out.push_str(echo);
        out.push('\n');

        let (words, args) = split_n(trimmed, 1);
        let cmd = words[0];
        let res = match cmd {
            "actor" => app.cmd_actor(args),
            "today" => app.cmd_today(args),
            "workflow" => app.cmd_workflow(&mut lines),
            "create" => app.cmd_create(args),
            "edit" => app.cmd_edit(args),
            "label" => app.cmd_label(args),
            "assign" => app.cmd_assign(args),
            "move" => app.cmd_move(args),
            "comment" => app.cmd_comment(args),
            "delete" => app.cmd_delete(args),
            "show" => app.cmd_show(args),
            "list" => app.cmd_list(args),
            "view" => app.cmd_view(args),
            "bulk" => app.cmd_bulk(args),
            "log" => app.cmd_log(args),
            "report" => app.cmd_report(args),
            _ => Err(format!("unknown command '{}'", cmd)),
        };
        match res {
            Ok(ls) => {
                for l in ls {
                    out.push_str(&l);
                    out.push('\n');
                }
            }
            Err(e) => {
                out.push_str("error: ");
                out.push_str(&e);
                out.push('\n');
            }
        }
    }

    let stdout = io::stdout();
    let mut h = stdout.lock();
    let _ = h.write_all(out.as_bytes());
    let _ = h.flush();
}
