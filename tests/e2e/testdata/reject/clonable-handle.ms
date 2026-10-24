from "@std/fs.ms" import FileHandle

def twice[T: Clonable](value: T) -> List[T]:
    return [value.clone(), value]

def keep(handle: FileHandle) -> Int:
    return twice(handle).length()

export def main() -> Int:
    return 0
