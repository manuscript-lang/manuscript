import Entropy, RandomError from "@std/os/random.ms"

export extern fn msstd_random_draw_int(
    entropy: Entropy,
    min: Int,
    max_exclusive: Int?
) Int!RandomError

export extern fn msstd_random_draw_uuid(entropy: Entropy) String!RandomError

export extern fn msstd_random_draw_float(entropy: Entropy) Float!RandomError

export extern fn msstd_random_draw_shuffle[T](
    entropy: Entropy,
    values: List[T]
) List[T]!RandomError

export extern fn msstd_random_draw_choice[T](
    entropy: Entropy,
    values: List[T]
) T?!RandomError

export extern fn msstd_random_entropy() Entropy
