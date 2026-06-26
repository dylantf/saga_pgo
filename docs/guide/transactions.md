# Transactions

Wrap a sequence of queries in `transaction` and they commit together
or roll back together.

## The handler

Transactions are a separate effect from `Postgres`, so you install a
second handler — `pg_transaction` — alongside `pg`:

```saga
import SagaPgo (pg, pg_transaction, transaction, sql, push_values, execute)

main () = {
  let conn = connect config
  let result = transaction conn (fun () -> {
    sql "INSERT INTO users (name, age)"
    |> push_values new_users (fun u -> [T.pg_text u.name, T.pg_int u.age])
    |> push "RETURNING id"
    |> execute conn
  })

  case result {
    Ok r -> println $"Inserted {r.count} users"
    Err _ -> println "transaction failed"
  }
} with {pg_transaction, pg, console}
```

`pg_transaction` declares `needs {Postgres}` — it can only be
installed when a `Postgres` handler is already available.

## Commit and rollback

The callback can return any `Result a e`. The handler reads that result and:

- `Ok value` — commits, then returns `Ok value` from `transaction`.
- `Err e` — rolls back, then returns `Err (RolledBack e)`.

Failures that happen before the body starts, such as failing to begin the
transaction, return `Err (TransactionFailed query_error)`.

Use `rollback! e` for a scoped early exit from the transaction body:

```saga
type AppError =
  | Validation String

let result = transaction conn (fun () -> {
  if invalid then rollback! (Validation "bad data")
  else Ok ()
})
```

`rollback! e` rolls back immediately, skips the rest of the body, and returns
`Err (RolledBack e)`.

Every `Postgres` operation inside the callback that uses the same
`Connection` automatically joins this transaction. That's done via
`pgo`'s process dictionary, which the bridge primitives manage for
you.

## Mixing transactions with effect handlers

Because the callback's effects are routed through `Postgres`, you can
still use the builder, raw `query`, decoding helpers, and any of your
own effect-using code inside the transaction. The only thing the
transaction wraps is the database lifecycle — everything else
composes normally.

## A caveat: escaping continuations

Multi-shot continuations whose captured slice escapes the callback
boundary aren't supported. In practice that means: don't capture a
continuation inside the transaction and invoke it later, outside the
`transaction` call. Re-invocations run *outside* the transaction,
because by then commit or rollback has already happened.

If you're not using algebraic effects in fancy ways — just running
queries — none of this affects you.
