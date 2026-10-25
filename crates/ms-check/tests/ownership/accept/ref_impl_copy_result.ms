interface Read[V]:
    def get() -> ref V

type Count:
    n: Int

# A scalar result is the same lent or owned, so an implementation may compute it.
impl Read[Int] for Count:
    def get() -> Int:
        return self.n + 1
