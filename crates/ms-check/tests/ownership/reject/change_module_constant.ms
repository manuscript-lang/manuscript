let ITEMS = [1, 2]

fn add() Unit:
    ITEMS.append(3)  // error: cannot change constant `ITEMS`

fn set() Unit:
    ITEMS[0] = 9  // error: cannot change constant `ITEMS`
