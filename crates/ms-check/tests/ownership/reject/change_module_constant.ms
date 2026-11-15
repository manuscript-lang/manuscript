ITEMS := [1, 2]

fn add() Void:
    ITEMS.append(3)  // error: cannot change constant `ITEMS`

fn set() Void:
    ITEMS[0] = 9  // error: cannot change constant `ITEMS`
