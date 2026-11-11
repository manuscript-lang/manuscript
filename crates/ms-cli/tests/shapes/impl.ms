type S{i}:
    a: Int

fn S{i}.area() Int: self.a + {i}
