import List from "@std/collections.ms"
import Result from "@std/result.ms"
import map_error from "@std/result.ms"
import ExecutionError from "@std/tasks.ms"
import parallel from "@std/tasks.ms"

type User:
    id: Int

type Order:
    id: Int

type UserError:
    case Missing

type OrderError:
    case Unavailable

interface Users:
    fn get(id: Int) -> Result[User, UserError]

interface Orders:
    fn for_user(user_id: Int) -> Result[List[Order], OrderError]

type Summary:
    user: User
    orders: List[Order]

type LoadError:
    case Execution(cause: ExecutionError)
    case UserFailure(cause: UserError)
    case OrderFailure(cause: OrderError)

fn load(user_id: Int, users: Users, orders: Orders) -> Result[Summary, LoadError]:
    let first = fn() -> Result[User, UserError]:
        return users.get(id: user_id)
    let second = fn() -> Result[List[Order], OrderError]:
        return orders.for_user(user_id: user_id)

    let [resA, resB] = try map_error(
        result: parallel(tasks: [first, second]),
        transform: fn(cause: ExecutionError) -> LoadError:
            return LoadError.Execution(cause: cause)
    )
    let user = try map_error(
        result: resA,
        transform: fn(cause: UserError) -> LoadError:
            return LoadError.UserFailure(cause: cause)
    )
    let user_orders = try map_error(
        result: resB,
        transform: fn(cause: OrderError) -> LoadError:
            return LoadError.OrderFailure(cause: cause)
    )
    return ok(value: Summary(user: user, orders: user_orders))
