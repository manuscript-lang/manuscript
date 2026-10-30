import Closeable from "@std/core.ms"
import {new_lock, Lock} from "@std/lock.ms"
import expect_equal from "@std/test.ms"

type Door:
    id: Int
    log: Lock[List[Int]]

impl Closeable for Door:
    var fn close() Unit:
        var seen = self.log.lock()
        seen.value.append(self.id)

test "a list moved on one path closes on the path that keeps it":
    let log: Lock[List[Int]] = new_lock([])
    block(log, 1)
    log.get().clone() | try expect_equal([1])

fn block(log: Lock[List[Int]], id: Int) Unit:
    let doors = [Door(id, log)]
    var moved: Optional[List[Door]] = none
    if doors.length() == 0:
        moved = some(doors)
    if moved.is_some():
        return

test "an optional resource reassigned after a conditional move closes the new value":
    let log: Lock[List[Int]] = new_lock([])
    reassign(log)
    log.get().clone() | try expect_equal([1, 2])

fn reassign(log: Lock[List[Int]]) Unit:
    var held: Optional[Door] = some(Door(1, log))
    if var door = held:
        door.id = 1
    held = some(Door(2, log))
    if held.is_none():
        return

fn walk(log: Lock[List[Int]], stop: Int) Unit:
    let doors = [Door(1, log), Door(2, log), Door(3, log)]
    var kept = List[Door]()

    for door in doors:
        if door.id == stop:
            break

        if door.id == 1:
            kept.append(door)

test "a loop over owned resources closes each element it does not move":
    let log: Lock[List[Int]] = new_lock([])
    walk(log, 99)
    log.get().clone() | try expect_equal([2, 3, 1])

test "a break closes the elements the loop never reached":
    let log: Lock[List[Int]] = new_lock([])
    walk(log, 1)
    log.get().clone() | try expect_equal([1, 2, 3])

fn wrap(door: Door, log: Lock[List[Int]]) List[Door]:
    var doors = [Door(9, log)]
    doors.append(door)
    return doors

test "a binding built from a call that consumes a resource closes it":
    let log: Lock[List[Int]] = new_lock([])
    block_wrap(log)
    log.get().clone() | try expect_equal([1, 9])

fn block_wrap(log: Lock[List[Int]]) Unit:
    let made = wrap(Door(1, log), log)
    if made.length() == 0:
        return

type Shape:
    case Circle(door: Door)
    case Empty

fn shape(log: Lock[List[Int]]) Shape:
    return Shape.Circle(Door(5, log))

test "a match on a temporary resource closes it when the match ends":
    let log: Lock[List[Int]] = new_lock([])
    var seen = 0

    match shape(log):
        Circle(door):
            seen = door.id
        _:
            seen = 0

    expect_equal(seen, 5) | try
    log.get().clone() | try expect_equal([5])
