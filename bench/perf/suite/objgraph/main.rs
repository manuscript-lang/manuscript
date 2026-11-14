struct Node { key: i64, left: Option<Box<Node>>, right: Option<Box<Node>> }

fn lcg(x: i64) -> i64 { (x * 1103515245 + 12345) % 2147483648 }

impl Node {
    fn insert(&mut self, key: i64) {
        if key == self.key { return; }
        let slot = if key < self.key { &mut self.left } else { &mut self.right };
        match slot {
            Some(n) => n.insert(key),
            None => *slot = Some(Box::new(Node { key, left: None, right: None }))
        }
    }
    fn count(&self) -> i64 {
        1 + self.left.as_ref().map_or(0, |n| n.count()) + self.right.as_ref().map_or(0, |n| n.count())
    }
    fn height(&self) -> i64 {
        let lh = self.left.as_ref().map_or(0, |n| n.height());
        let rh = self.right.as_ref().map_or(0, |n| n.height());
        1 + lh.max(rh)
    }
    fn sum(&self) -> i64 {
        self.key + self.left.as_ref().map_or(0, |n| n.sum()) + self.right.as_ref().map_or(0, |n| n.sum())
    }
}

enum Tree { Leaf, Branch(Box<Tree>, Box<Tree>) }

fn make(depth: i64) -> Tree {
    if depth == 0 { return Tree::Leaf; }
    Tree::Branch(Box::new(make(depth - 1)), Box::new(make(depth - 1)))
}

fn count(t: &Tree) -> i64 {
    match t { Tree::Leaf => 1, Tree::Branch(l, r) => 1 + count(l) + count(r) }
}

struct Link { value: i64, next: Option<Box<Link>> }

fn main() {
    let mut root = Node { key: 1000000000, left: None, right: None };
    let mut x = 11;
    for _ in 0..400000 {
        x = lcg(x);
        root.insert(x % 2000000000);
    }
    println!("bst {} {} {}", root.count(), root.height(), root.sum() % 1000003);

    let mut nodes = 0;
    for _ in 0..40 { nodes += count(&make(16)); }
    println!("trees {nodes}");

    let mut head: Option<Box<Link>> = None;
    for i in 0..1000000 { head = Some(Box::new(Link { value: i, next: head })); }
    let mut total = 0;
    let mut cur = &head;
    while let Some(l) = cur { total += l.value; cur = &l.next; }
    println!("list {total}");
    // drop iteratively: the default recursive drop overflows the stack on a long list
    let mut cur = head.take();
    while let Some(mut l) = cur { cur = l.next.take(); }
}
