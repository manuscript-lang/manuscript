import Pair from "@std/collections.ms"
import Deque from "@std/deque.ms"

fn pair_value(pair: Pair[Int, String]) String:
    return pair.second

fn deque_size(deque: Deque[Int]) Int:
    return deque.size
