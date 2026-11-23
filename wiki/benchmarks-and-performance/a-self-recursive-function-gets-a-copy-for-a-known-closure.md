# A self-recursive function gets a copy for a known closure

Closure specialization skipped every callee on a cycle, so `quick(..., cmp)` in a Manuscript sort ran `call.ind` per comparison. A callee whose only cycle is itself now gets the copy: the parameter becomes a `closure.new`, and the copy's own recursive call resolves to the same copy in the next round. Mutual recursion is still skipped. A Manuscript stable quicksort over swaps went from 156M to 111M instructions at 200k records (builtin 102M); what remains is a data-dependent partition branch the builtin avoids.
