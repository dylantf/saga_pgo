# Types and decoding

How Saga values become query parameters, and how result columns
become Saga values.

## Encoding parameters

Query parameters are `Value`s, an opaque type from `SagaPgo.Types`.
The library ships a constructor per primitive:

| Function | Postgres type |
|---|---|
| `pg_int` | `INT`, `BIGINT` |
| `pg_float` | `REAL`, `DOUBLE PRECISION` |
| `pg_text` | `TEXT`, `VARCHAR` |
| `pg_bool` | `BOOLEAN` |
| `pg_uuid` | `UUID` |
| `pg_date` | `DATE` |
| `pg_null ()` | `NULL` |

Import the module qualified for readability:

```saga
import SagaPgo.Types as T

[T.pg_text "Alice", T.pg_int 30, T.pg_bool True]
```

## Optional values

`maybe_null` lifts any encoder over `Maybe`, emitting `NULL` for
`Nothing`:

```saga
T.maybe_null T.pg_text maybe_username
T.maybe_null T.pg_int maybe_age
T.maybe_null T.pg_date maybe_birthday
```

## UUIDs

`Uuid` is opaque — you can't build one out of thin air. Two ways in:

- Parse a hyphenated canonical string with `parse_uuid`, which returns
  `Result Uuid String`.
- Decode one out of a Postgres `UUID` column with the `uuid` decoder
  (see below).

Once you have a `Uuid`, `pg_uuid` re-encodes it as a parameter, and
`show` renders it back to its canonical 36-character string.

## Decoding rows

A successful query returns `Returned { count, rows }`, where each row
is a `Dynamic`. Pull columns out by position with
`Std.Dynamic.decode_element`:

```saga
import Std.Dynamic (string, int, decode_element)
import SagaPgo.Types as T (uuid, naive_datetime)

case lookup {
  Ok returned -> case returned.rows {
    row :: _ -> case do {
      Ok id <- decode_element 0 uuid row
      Ok name <- decode_element 1 string row
      Ok age <- decode_element 2 int row
      Ok created_at <- decode_element 3 naive_datetime row
      Ok (User { id: id, name: name, age: age, created_at: created_at })
    } else {
      Err e -> Err e
    } {
      Ok user -> println $"got {user.name}"
      Err _ -> println "decode failed"
    }
    [] -> println "no rows"
  }
  Err _ -> println "query failed"
}
```

`decode_element i decoder row` reads column `i` from `row` using the
given decoder, returning `Result a DecodeError`. The `do` block
chains them so the first failure short-circuits.

## Built-in decoders

From `Std.Dynamic`:

- `string`, `int`, `float`, `bool` for the primitive types.
- `list`, `maybe`, ... for the usual combinators.

From `SagaPgo.Types`:

- `uuid` — decodes `UUID` columns into the opaque `Uuid` type.
- `naive_datetime` — decodes `TIMESTAMP` and `TIMESTAMPTZ` columns
  into `Std.DateTime.NaiveDateTime` in UTC.

## Putting it together

```saga
record User {
  id: T.Uuid,
  name: String,
  age: Int,
  created_at: NaiveDateTime,
}

let lookup =
  sql "SELECT id, name, age, created_at FROM users WHERE name = $1"
  |> bind_values [T.pg_text "Alice"]
  |> execute conn
```

The encoders pick the right Postgres type for the parameters, and the
decoders pick it back apart on the way out. If a column doesn't have
a dedicated decoder in `SagaPgo.Types`, fall back to the
`Std.Dynamic` primitives or write your own with `Decoder` and the
bridge.
