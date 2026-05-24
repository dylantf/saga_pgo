# saga_pgo

A Saga library for talking to PostgreSQL, built on top of the Erlang
[`pgo`](https://hex.pm/packages/pgo) connection pool.

It exposes a small, effect-based API:

- A pooled `Connection` you get from `connect`.
- A `Postgres` effect for running SQL, with a real handler (`pg`) that
  delegates to `pgo`.
- A `Transaction` effect with a handler (`pg_transaction`) that drives
  commit / rollback from Saga while letting nested queries join the
  same transaction.
- A composable query builder (`sql`, `push`, `bind_values`,
  `push_bind`, `push_values`, `execute`).
- Typed parameter encoders and result decoders in `SagaPgo.Types`
  (`pg_int`, `pg_text`, `pg_uuid`, `pg_date`, `naive_datetime`,
  `uuid`, ...).

## Quick example

```saga
import SagaPgo (default_config, connect, pg, sql, bind_values, execute)
import SagaPgo.Types as T

main () = {
  let conn = connect (default_config "mydb")
  sql "INSERT INTO users (name, age) VALUES ($1, $2)"
  |> bind_values [T.pg_text "Alice", T.pg_int 30]
  |> execute conn
} with {pg, console}
```

See [`src/Main.saga`](src/Main.saga) for a fuller walkthrough.

## Docs

- [Guide](docs/guide/) — task-oriented introduction.
- [Reference](docs/reference/) — generated API docs for every public
  module.
