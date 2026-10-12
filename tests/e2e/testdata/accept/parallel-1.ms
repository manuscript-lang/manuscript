import List from "@std/collections.ms"
import Result from "@std/result.ms"
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

    match parallel(tasks: [first, second]):
        error(cause):
            return error(cause: LoadError.Execution(cause: cause))
        ok(results):
            let [user_result, orders_result] = results
            match user_result:
                error(cause):
                    return error(cause: LoadError.UserFailure(cause: cause))
                ok(user):
                    match orders_result:
                        error(cause):
                            return error(cause: LoadError.OrderFailure(cause: cause))
                        ok(user_orders):
                            return ok(value: Summary(user: user, orders: user_orders))
