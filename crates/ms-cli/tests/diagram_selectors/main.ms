import other from "./other.ms"

type Box:
    value: Int

impl Box:
    fn read() Int:
        return self.value

type Item:
    value: Int

type Named:
    value: Int

fn unique() Int:
    return 1

test "main.ms#record#Box":
    let _value = 1

test "other.ms::Named":
    let _value = 1
