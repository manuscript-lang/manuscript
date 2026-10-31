use std::collections::VecDeque;
use std::io::{self, Read, Write};

fn fail(msg: &str) -> ! {
    println!("error: {}", msg);
    std::process::exit(0);
}

fn main() {
    let mut bytes = Vec::new();
    io::stdin().read_to_end(&mut bytes).expect("read stdin");
    let text = String::from_utf8_lossy(&bytes);

    // Split into lines; drop trailing empty lines (interior empty lines are kept as width-0 rows).
    let mut lines: Vec<&str> = text.split('\n').collect();
    while let Some(last) = lines.last() {
        if last.is_empty() {
            lines.pop();
        } else {
            break;
        }
    }

    // Grid as rows of chars.
    let grid: Vec<Vec<char>> = lines.iter().map(|l| l.chars().collect()).collect();

    // 1. Bad characters, in reading order.
    for (r, row) in grid.iter().enumerate() {
        for (c, &ch) in row.iter().enumerate() {
            if !matches!(ch, '#' | '.' | 'S' | 'E') {
                fail(&format!("bad character at {},{}", r + 1, c + 1));
            }
        }
    }

    // 2. Ragged grid.
    if let Some(first) = grid.first() {
        let w = first.len();
        if grid.iter().any(|row| row.len() != w) {
            fail("ragged grid");
        }
    } else {
        // No rows at all.
        fail("no start");
    }

    // 3. Start cells.
    let mut starts = Vec::new();
    let mut ends = Vec::new();
    for (r, row) in grid.iter().enumerate() {
        for (c, &ch) in row.iter().enumerate() {
            if ch == 'S' {
                starts.push((r, c));
            } else if ch == 'E' {
                ends.push((r, c));
            }
        }
    }
    if starts.is_empty() {
        fail("no start");
    }
    if starts.len() > 1 {
        fail("multiple starts");
    }
    // 4. End cells.
    if ends.is_empty() {
        fail("no end");
    }
    if ends.len() > 1 {
        fail("multiple ends");
    }

    let h = grid.len();
    let w = grid[0].len();
    let (sr, sc) = starts[0];
    let (er, ec) = ends[0];

    // BFS from S over non-wall cells.
    let mut dist = vec![vec![usize::MAX; w]; h];
    let mut q = VecDeque::new();
    dist[sr][sc] = 0;
    q.push_back((sr, sc));
    let mut answer: Option<usize> = None;
    while let Some((r, c)) = q.pop_front() {
        if (r, c) == (er, ec) {
            answer = Some(dist[r][c]);
            break;
        }
        let d = dist[r][c];
        let mut neighbors = Vec::with_capacity(4);
        if r > 0 {
            neighbors.push((r - 1, c));
        }
        if r + 1 < h {
            neighbors.push((r + 1, c));
        }
        if c > 0 {
            neighbors.push((r, c - 1));
        }
        if c + 1 < w {
            neighbors.push((r, c + 1));
        }
        for (nr, nc) in neighbors {
            if grid[nr][nc] != '#' && dist[nr][nc] == usize::MAX {
                dist[nr][nc] = d + 1;
                q.push_back((nr, nc));
            }
        }
    }

    let out = match answer {
        Some(d) => format!("{}\n", d),
        None => "no path\n".to_string(),
    };
    io::stdout().write_all(out.as_bytes()).expect("write stdout");
}
