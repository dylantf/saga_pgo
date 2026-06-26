---
title: SagaPgo
---

## Types

### Config

```saga
record Config {
  host: String,
  port: Int,
  database: String,
  user: String,
  password: String,
  pool_size: Int,
  ssl: Bool
}
```

### Connection

```saga
opaque type Connection
```

### QueryError

```saga
type QueryError =
  | ConstraintViolated (message: String) (constraint: String) (detail: String)
  | PostgresqlError (code: String) (severity: String) (message: String)
  | UnexpectedArgumentCount (expected: Int) (got: Int)
  | UnexpectedArgumentType (expected: String) (got: String)
  | UnexpectedResultType (expected: String)
  | QueryTimeout
  | ConnectionUnavailable
  deriving (Debug)
```

### Returned

```saga
record Returned a {
  count: Int,
  rows: List a
}
```

### TransactionError

```saga
type TransactionError e =
  | TransactionFailed QueryError
  | RolledBack e
  deriving (Debug)
```

`TransactionFailed` means the transaction could not begin. `RolledBack` wraps
the body error that caused an explicit or implicit rollback.

### QueryBuilder

```saga
opaque type QueryBuilder
```

A composable query builder. Build up a SQL string and its parameters with
`push`, `push_bind`, and `push_values`, then finalize by passing it to
`build` together with an executor function (typically `execute`).

## Effects

### Postgres

```saga
effect Postgres {
  fun raw_execute : Connection -> String -> List Value -> Result (Returned Dynamic) QueryError
}
```

### Transaction

```saga
effect Transaction {
  fun transaction : Connection -> Unit -> Result a e needs {Postgres, Rollback e} -> Result a (TransactionError e)
}
```

Transactions. Handlers for `Transaction` declare `needs {Postgres}` because
the user's callback uses Postgres operations. The real handler delegates to
`pgo:transaction`, so all queries inside the callback automatically join the
same transaction connection via pgo's process dictionary.

Multi-shot continuations whose captured slice escapes the callback boundary
are not supported and will run their re-invocations outside any transaction.

### Rollback

```saga
effect Rollback e {
  fun rollback : e -> a
}
```

Scoped early-exit effect for transactions. `rollback! err` aborts the current
transaction body, rolls back immediately, and returns `Err (RolledBack err)`
from the surrounding `transaction` call.

## Handlers

### pg

```saga
handler pg for Postgres
```

The real Postgres handler. Stateless — describes *how* to execute SQL by
delegating to the bridge. The connection is passed in by the caller.

### pg_transaction

```saga
handler pg_transaction for Transaction needs {Postgres}
```

The real Transaction handler. Drives the lifecycle from saga (we can't
pass an effectful saga lambda to `pgo:transaction` because the lambda
compiles to a CPS closure Erlang can't invoke). The bridge primitives
acquire / release a connection and stash it in pgo's process dictionary,
so `raw_execute!` calls inside `f ()` automatically join the transaction.

## Functions

### default_config

```saga
fun default_config : String -> Config
```

### query

```saga
fun query : Connection -> String -> List Value -> Result (Returned Dynamic) QueryError needs {Postgres}
```

Run a SQL statement directly with a flat parameter list. This is the
low-level primitive — use it when you don't need the builder, or when
building a higher-level query API on top of this library. For application
code that wants ergonomics, prefer the builder: `sql "..." |> ... |> execute conn`.

### transaction

```saga
fun transaction : Connection -> Unit -> Result a e needs {Postgres, Rollback e} -> Result a (TransactionError e) needs {Transaction}
```

Run a callback inside a database transaction. All `Postgres` effects
performed inside the callback against the same connection are routed to the
transaction, and the transaction commits if the callback returns `Ok`, rolls
back if it returns `Err`. Body errors return as `RolledBack e`; failures that
happen before the body starts return as `TransactionFailed QueryError`.
`rollback! err` rolls back immediately and returns `Err (RolledBack err)`.
Uses pgo's process-dictionary
mechanism under the hood, so don't let captured continuations from inside the
callback escape the boundary — re-invoking them later will run outside any
transaction.

### sql

```saga
fun sql : String -> QueryBuilder
```

Start a new query builder from a SQL prefix. The prefix is treated as raw
text — if it contains pre-written `$N` placeholders, attach their values
with `bind_values`. Otherwise, use `push_bind` / `push_values` to add
auto-numbered placeholders. Don't mix the two modes for the same query.

### bind_values

```saga
fun bind_values : List Value -> QueryBuilder -> QueryBuilder
```

Bind a flat list of values to the pre-written `$N` placeholders in the SQL.
Records the values and advances the placeholder counter, but does not emit
any SQL. Use this when the prefix already contains `$1, $2, ...`.

### push

```saga
fun push : String -> QueryBuilder -> QueryBuilder
```

Append a SQL fragment, automatically prepending a space so callers don't
have to manage spacing manually. Empty strings are a no-op.

### push_bind

```saga
fun push_bind : Value -> QueryBuilder -> QueryBuilder
```

Bind one parameter, emitting a ` $N` placeholder (with leading space) at the
current position so it reads cleanly after a SQL operator like `name =`.

### push_values

```saga
fun push_values : (rows: List a) -> (bind_row: a -> List Value) -> QueryBuilder -> QueryBuilder
```

Append `(p1, p2, ...)` row groups for each row, auto-numbering placeholders
and flattening parameters. The first call emits ` values `; subsequent calls
append more rows separated by commas, so multiple `push_values` calls merge
into one contiguous values clause. An empty `rows` list is a no-op.

Note: don't interleave non-values pushes between consecutive `push_values`
calls — the comma joining will produce broken SQL.

### execute

```saga
fun execute : Connection -> QueryBuilder -> Result (Returned Dynamic) QueryError needs {Postgres}
```

Finalize the builder and execute the query against the given connection.
This is the primary way to run queries — use `query` only if you don't
need the builder. Conn comes first for partial application:
sql "..." |> push_values ... |> execute conn

### connect

```saga
fun connect : Config -> Connection
```

Start a connection pool and return a `Connection` handle. Pass this to
`query`, `execute`, and `transaction`. Multiple calls to `connect` give
you multiple independent pools.
