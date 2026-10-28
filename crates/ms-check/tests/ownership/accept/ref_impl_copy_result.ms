interface Read[V]:
    fn get() ref V

type Count:
    n: Int

# A scalar result is the same lent or owned, so an implementation may compute it.
impl Read[Int] for Count:
    fn get() Int:
        return self.n + 1
