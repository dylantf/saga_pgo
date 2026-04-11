-module(saga_pgo_bridge).

-export([start_pool/1, query/3, begin_tx/1, commit_tx/1, rollback_tx/1, coerce/1, decode_naive_datetime/1, encode_date/1, decode_uuid/1, parse_uuid/1]).

coerce(Value) ->
    Value.

start_pool({sagapgo_Config, Host, Port, Database, User, Password, PoolSize, Ssl}) ->
    application:set_env(pg_types, timestamp_config, integer_system_time_microseconds),
    application:set_env(pg_types, uuid_format, string),
    application:ensure_all_started(pgo),
    PoolName = binary_to_atom(Database, utf8),
    Options = #{
        host => binary_to_list(Host),
        port => Port,
        database => Database,
        user => User,
        password => Password,
        pool_size => PoolSize,
        ssl => Ssl =:= true
    },
    case pgo_pool:start_link(PoolName, Options) of
        {ok, _Pid} ->
            {sagapgo_Connection, PoolName};
        {error, Reason} ->
            erlang:error({pgo_start_failed, Reason})
    end.

query({sagapgo_Connection, Pool}, Sql, Params) ->
    try
        Options = #{pool => Pool},
        case pgo:query(Sql, Params, Options) of
            #{rows := Rows, num_rows := NumRows} ->
                {ok, {sagapgo_Returned, NumRows, Rows}};
            {error, Error} ->
                {error, convert_error(Error)}
        end
    catch
        Type:Reason ->
            {error, {sagapgo_PostgresqlError,
                     atom_to_binary(Type, utf8),
                     <<"caught">>,
                     format_term(Reason)}}
    end.

%% Transaction lifecycle primitives. We can't pass a saga effectful callback to
%% pgo:transaction (it compiles to a CPS closure that Erlang can't invoke), so
%% we expose begin/commit/rollback separately and let saga drive the lifecycle.
%%
%% begin_tx checks out a connection, runs BEGIN, and stores the connection in
%% pgo_transaction_connection so subsequent pgo:query calls (from query/3 above)
%% automatically use it. The {Ref, Conn} pair is wrapped in a TxHandle so saga
%% can pass it back to commit_tx / rollback_tx.
begin_tx({sagapgo_Connection, Pool}) ->
    try
        case pgo:checkout(Pool, []) of
            {ok, Ref, Conn} ->
                case pgo_handler:extended_query(Conn, "BEGIN", [], #{queue_time => undefined}) of
                    #{command := 'begin'} ->
                        put(pgo_transaction_connection, Conn),
                        {ok, {sagapgo_TxHandle, {Ref, Conn}}};
                    Other ->
                        pgo:checkin(Ref, Conn),
                        {error, {sagapgo_PostgresqlError,
                                 <<"begin failed">>,
                                 <<"unknown">>,
                                 format_term(Other)}}
                end;
            {error, CheckoutErr} ->
                {error, convert_error(CheckoutErr)}
        end
    catch
        Type:Reason ->
            {error, {sagapgo_PostgresqlError,
                     atom_to_binary(Type, utf8),
                     <<"caught">>,
                     format_term(Reason)}}
    end.

%% commit_tx and rollback_tx are total — they swallow any cleanup-time errors
%% so the saga handler arm can rely on them returning Unit. The connection is
%% always returned to the pool and the process dict entry is always cleared,
%% even if the COMMIT/ROLLBACK statement itself fails.
commit_tx({sagapgo_TxHandle, {Ref, Conn}}) ->
    catch pgo_handler:extended_query(Conn, "COMMIT", [], #{queue_time => undefined}),
    catch pgo:checkin(Ref, Conn),
    erase(pgo_transaction_connection),
    unit.

rollback_tx({sagapgo_TxHandle, {Ref, Conn}}) ->
    catch pgo_handler:extended_query(Conn, "ROLLBACK", [], #{queue_time => undefined}),
    catch pgo:checkin(Ref, Conn),
    erase(pgo_transaction_connection),
    unit.

format_term(T) ->
    list_to_binary(io_lib:format("~p", [T])).

convert_error(none_available) ->
    {sagapgo_ConnectionUnavailable};
convert_error({pgo_protocol, {parameters, Expected, Got}}) ->
    {sagapgo_UnexpectedArgumentCount, Expected, Got};
convert_error({pgsql_error, #{
    message := Message,
    constraint := Constraint,
    detail := Detail
}}) ->
    {sagapgo_ConstraintViolated, Message, Constraint, Detail};
convert_error({pgsql_error, #{code := Code, message := Message}}) ->
    {sagapgo_PostgresqlError, Code, <<"unknown">>, Message};
convert_error(#{
    error := badarg_encoding,
    type_info := #{name := Expected},
    value := Value
}) ->
    Got = list_to_binary(io_lib:format("~p", [Value])),
    {sagapgo_UnexpectedArgumentType, Expected, Got};
convert_error(closed) ->
    {sagapgo_QueryTimeout};
convert_error(Other) ->
    {sagapgo_PostgresqlError, <<"unknown">>, <<"unknown">>, list_to_binary(io_lib:format("~p", [Other]))}.

%% Postgres TIMESTAMP / TIMESTAMPTZ decoder.
%%
%% Two shapes are accepted because the underlying pg_types library handles
%% the two postgres types differently:
%%
%%   - TIMESTAMP (oid 1114) honors `application:get_env(pg_types, timestamp_config)`,
%%     which we set to `integer_system_time_microseconds` in start_pool. With
%%     that config, values arrive as int64 microseconds since the Unix epoch.
%%
%%   - TIMESTAMPTZ (oid 1184) is hardcoded in pg_timestampz.erl to always
%%     decode with config `[]`, ignoring the env setting entirely. Values
%%     always arrive as `{{Y,M,D},{H,M,S}}` tuples where the seconds field
%%     is integer if microseconds == 0, otherwise float.
decode_naive_datetime(Microseconds) when is_integer(Microseconds) ->
    Seconds = Microseconds div 1000000,
    Us = Microseconds rem 1000000,
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(Seconds, second),
    {ok, {std_datetime_NaiveDateTime, Y, Mo, D, H, Mi, S, Us}};
decode_naive_datetime({{Y, Mo, D}, {H, Mi, S}}) when is_integer(S) ->
    {ok, {std_datetime_NaiveDateTime, Y, Mo, D, H, Mi, S, 0}};
decode_naive_datetime({{Y, Mo, D}, {H, Mi, S}}) when is_float(S) ->
    IntS = trunc(S),
    Us = trunc((S - IntS) * 1000000),
    {ok, {std_datetime_NaiveDateTime, Y, Mo, D, H, Mi, IntS, Us}};
decode_naive_datetime(Other) ->
    Found = classify(Other),
    {error, {std_dynamic_DecodeError, <<"NaiveDateTime">>, Found, []}}.

%% Postgres DATE encoder. pg_date expects a plain {Year, Month, Day} 3-tuple
%% (see deps/pg_types/src/pg_date.erl), but a saga `Std.DateTime.Date` lowers
%% to the tagged 4-tuple {std_datetime_Date, Y, M, D}. Strip the tag.
encode_date({std_datetime_Date, Y, M, D}) ->
    {Y, M, D}.

classify(V) when is_binary(V) -> <<"String">>;
classify(V) when is_integer(V) -> <<"Int">>;
classify(V) when is_float(V) -> <<"Float">>;
classify(V) when is_atom(V) -> <<"Atom">>;
classify(V) when is_list(V) -> <<"List">>;
classify(V) when is_tuple(V) -> <<"Tuple">>;
classify(V) when is_map(V) -> <<"Map">>;
classify(_) -> <<"Unknown">>.

%% Postgres UUID decoder. With uuid_format=string set, pgo gives us a 36-byte
%% binary in canonical form (lowercase hex with hyphens). We trust postgres'
%% stored value and just wrap it.
decode_uuid(V) when is_binary(V), byte_size(V) =:= 36 ->
    {ok, {sagapgo_Uuid, V}};
decode_uuid(V) when is_binary(V) ->
    {error, {std_dynamic_DecodeError, <<"Uuid">>, <<"String of wrong length">>, []}};
decode_uuid(Other) ->
    {error, {std_dynamic_DecodeError, <<"Uuid">>, classify(Other), []}}.

%% Validate a user-supplied UUID string. Accepts canonical hyphenated form.
parse_uuid(<<A:8/binary, "-", B:4/binary, "-", C:4/binary, "-", D:4/binary, "-", E:12/binary>>) ->
    case all_hex(A) andalso all_hex(B) andalso all_hex(C) andalso all_hex(D) andalso all_hex(E) of
        true -> {ok, <<A/binary, "-", B/binary, "-", C/binary, "-", D/binary, "-", E/binary>>};
        false -> {error, <<"invalid UUID: non-hex character">>}
    end;
parse_uuid(_) ->
    {error, <<"invalid UUID: expected 36-char hyphenated form">>}.

all_hex(<<>>) -> true;
all_hex(<<C, Rest/binary>>) when C >= $0, C =< $9 -> all_hex(Rest);
all_hex(<<C, Rest/binary>>) when C >= $a, C =< $f -> all_hex(Rest);
all_hex(<<C, Rest/binary>>) when C >= $A, C =< $F -> all_hex(Rest);
all_hex(_) -> false.
