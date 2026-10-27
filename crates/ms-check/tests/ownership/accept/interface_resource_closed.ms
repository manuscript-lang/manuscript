interface Handle:
    def close() -> Unit

def open_handle() -> Handle:
    return open_handle()

def closes() -> Int:
    let handle = open_handle()
    handle.close()
    return 1

def hands_on() -> Handle:
    let handle = open_handle()
    return handle

def scoped() -> Int:
    with let handle = open_handle():
        return 1
