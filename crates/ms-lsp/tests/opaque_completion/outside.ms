import Vault, Open, Choice, vault from "./vault.ms"

fn inspect(value: Vault[Int]) Int:
    return 1

fn use() Int:
    hidden := vault()
    public := Open[Int](7)
    return inspect(hidden) + public.value + hidden.size()
