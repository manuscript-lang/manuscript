//! Links the actual release ms-check library; setup and assertions are untimed.
use ms_check::api::Names;
use ms_check::api::types::{Kind, Param, Subst, Ty, function, n, primitive, same, sub};
use std::{hint::black_box, rc::Rc, time::Instant};

fn node(children: Vec<Ty>) -> Ty {
    let mut t = (*primitive("Int")).clone();
    t.kind = Kind::Record;
    t.id = n("bench/Node");
    t.name = n("Node");
    t.args = children;
    Rc::new(t)
}

fn variable() -> Ty {
    let mut t = (*primitive("Int")).clone();
    t.kind = Kind::Variable;
    t.id = n("bench/T");
    t.name = n("T");
    Rc::new(t)
}

fn graph(depth: usize, shared: bool) -> Ty {
    let mut t = primitive("Int");
    for _ in 0..depth {
        t = if shared {
            node(vec![t.clone(), t])
        } else {
            node(vec![t])
        };
    }
    t
}

fn signature(width: usize, child: &Ty) -> Ty {
    function(
        Names::global(),
        (0..width)
            .map(|i| Param::new(n(&format!("p{i}")), child.clone()))
            .collect(),
        primitive("Int"),
    )
}

fn main() {
    let case = std::env::args().nth(1).expect("case");
    let parts: Vec<_> = case.split('-').collect();
    let size: usize = parts[1].parse().expect("size");
    let int = primitive("Int");
    let string = primitive("String");
    let var = variable();
    let (input, bindings, expected, unchanged, iterations) = match parts[0] {
        "shared" => {
            let t = graph(size, true);
            (t.clone(), Subst::new(), t, true, 10)
        }
        "unique" => {
            let t = graph(size, false);
            (t.clone(), Subst::new(), t, true, 20_000)
        }
        "concrete" => {
            let t = signature(size, &int);
            (t.clone(), Subst::new(), t, true, 100_000)
        }
        "distinct" => {
            let children = [primitive("Int"), primitive("String"), primitive("Bool")];
            let t = function(
                Names::global(),
                (0..size)
                    .map(|i| Param::new(n(&format!("p{i}")), children[i % 3].clone()))
                    .collect(),
                primitive("Int"),
            );
            (t.clone(), Subst::new(), t, true, 100_000)
        }
        "fibonacci" => {
            let mut previous = primitive("Int");
            let mut current = primitive("String");
            for _ in 0..size {
                let next = node(vec![current.clone(), previous]);
                previous = current;
                current = next;
            }
            (current.clone(), Subst::new(), current, true, 100)
        }
        "changed" => (
            signature(size, &var),
            Subst::from([(var.id, string.clone())]),
            signature(size, &string),
            false,
            100_000,
        ),
        "unbound" => {
            let t = signature(size, &var);
            (t.clone(), Subst::new(), t, false, 100_000)
        }
        _ => panic!("unknown case"),
    };
    let got = sub(&input, &bindings);
    assert!(same(&got, &expected));
    assert_eq!(Rc::ptr_eq(&got, &input), unchanged);
    if parts[0] == "unbound" {
        assert!(!Rc::ptr_eq(&got.params[0].ty, &var));
    }
    for _ in 0..10 {
        black_box(sub(black_box(&input), black_box(&bindings)));
    }
    let start = Instant::now();
    for _ in 0..iterations {
        black_box(sub(black_box(&input), black_box(&bindings)));
    }
    println!(
        "{{\"case\":\"{case}\",\"iterations\":{iterations},\"elapsed_ns\":{}}}",
        start.elapsed().as_nanos()
    );
}
