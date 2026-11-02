fn forward[A = B, B = Int](value: A) A: return value

fn recursive[A = A](value: A) A: return value

interface Reader[A]:
    fn forward[B = C, C = Int](value: B) Int
    fn recursive[B = B](value: B) Int
    fn first[B = Int](value: B) Int
    fn second[C = B](value: C) Int
