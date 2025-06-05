#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <erl_nif.h>
#include <sqlite3.h>

static ERL_NIF_TERM am_ok;
static ERL_NIF_TERM am_nil;
static ERL_NIF_TERM am_true;
static ERL_NIF_TERM am_false;
static ERL_NIF_TERM am_system_error;
static ERL_NIF_TERM am_badarg;
static ERL_NIF_TERM am_done;
static ERL_NIF_TERM am_rows;

static ErlNifResourceType *db_t;
static ErlNifResourceType *stmt_t;

typedef struct _db
{
    sqlite3 *sqlite;
} xqlite;

typedef struct _stmt
{
    sqlite3_stmt *sqlite;
} xqlite_stmt;

static void
db_type_destructor(ErlNifEnv *env, void *arg)
{
    xqlite *db = (xqlite *)arg;
    if (db->sqlite)
    {
        sqlite3_close_v2(db->sqlite);
        db->sqlite = NULL;
    }
}

static void
stmt_type_destructor(ErlNifEnv *env, void *arg)
{
    xqlite_stmt *stmt = (xqlite_stmt *)arg;
    if (stmt->sqlite)
    {
        sqlite3_finalize(stmt->sqlite);
        stmt->sqlite = NULL;
    }
}

static int
on_load(ErlNifEnv *env, void **priv, ERL_NIF_TERM info)
{
    am_ok = enif_make_atom(env, "ok");
    am_nil = enif_make_atom(env, "nil");
    am_true = enif_make_atom(env, "true");
    am_false = enif_make_atom(env, "false");
    am_system_error = enif_make_atom(env, "system_error");
    am_badarg = enif_make_atom(env, "badarg");
    am_done = enif_make_atom(env, "done");
    am_rows = enif_make_atom(env, "rows");

    db_t = enif_open_resource_type(env, "xqlite", "db", db_type_destructor, ERL_NIF_RT_CREATE, NULL);
    if (!db_t)
        return -1;

    stmt_t = enif_open_resource_type(env, "xqlite", "stmt", stmt_type_destructor, ERL_NIF_RT_CREATE, NULL);
    if (!stmt_t)
        return -1;

    return 0;
}

static ERL_NIF_TERM
make_binary(ErlNifEnv *env, const unsigned char *bytes, size_t size)
{
    ERL_NIF_TERM bin;
    uint8_t *data = enif_make_new_binary(env, size, &bin);
    memcpy(data, bytes, size);
    return bin;
}

static ERL_NIF_TERM
make_badarg(ErlNifEnv *env, ERL_NIF_TERM arg)
{
    ERL_NIF_TERM badarg = enif_make_tuple2(env, am_badarg, arg);
    return enif_raise_exception(env, badarg);
}

static ERL_NIF_TERM
xqlite_open(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    ErlNifBinary path;
    if (!enif_inspect_iolist_as_binary(env, argv[0], &path))
        return make_badarg(env, argv[0]);

    int flags;
    if (!enif_get_int(env, argv[1], &flags))
        return make_badarg(env, argv[1]);

    xqlite *db = enif_alloc_resource(db_t, sizeof(xqlite));
    if (!db)
        return enif_raise_exception(env, am_system_error);

    int rc = sqlite3_open_v2((char *)path.data, &db->sqlite, flags, NULL);
    if (rc != SQLITE_OK)
    {
        enif_release_resource(db);
        assert(db->sqlite == NULL);
        return enif_make_int(env, rc);
    }

    ERL_NIF_TERM db_resource = enif_make_resource(env, db);
    enif_release_resource(db);
    return db_resource;
}

static ERL_NIF_TERM
xqlite_close(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite *db;
    if (!enif_get_resource(env, argv[0], db_t, (void **)&db))
        return make_badarg(env, argv[0]);

    if (db->sqlite != NULL)
    {
        // TODO
        int rc = sqlite3_close_v2(db->sqlite);
        if (rc != SQLITE_OK)
            return enif_make_int(env, rc);

        db->sqlite = NULL;
    }

    return am_ok;
}

static ERL_NIF_TERM
xqlite_prepare(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite *db;
    if (!enif_get_resource(env, argv[0], db_t, (void **)&db))
        return make_badarg(env, argv[0]);

    ErlNifBinary sql;
    if (!enif_inspect_binary(env, argv[1], &sql))
        return make_badarg(env, argv[1]);

    int flags;
    if (!enif_get_int(env, argv[2], &flags))
        return make_badarg(env, argv[2]);

    xqlite_stmt *stmt;
    stmt = enif_alloc_resource(stmt_t, sizeof(xqlite_stmt));
    if (!stmt)
        return enif_raise_exception(env, am_system_error);

    int rc = sqlite3_prepare_v3(db->sqlite, (char *)sql.data, sql.size, flags, &stmt->sqlite, NULL);
    if (rc != SQLITE_OK)
    {
        enif_release_resource(stmt);
        assert(stmt->sqlite == NULL);
        return enif_make_int(env, rc);
    }

    ERL_NIF_TERM stmt_resource = enif_make_resource(env, stmt);
    enif_release_resource(stmt);
    return stmt_resource;
}

static ERL_NIF_TERM
xqlite_bind_text(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int idx;
    if (!enif_get_int(env, argv[1], &idx))
        return make_badarg(env, argv[1]);

    ErlNifBinary text;
    if (!enif_inspect_binary(env, argv[2], &text))
        return make_badarg(env, argv[2]);

    // TODO can be something other than SQLITE_TRANSIENT?
    int rc = sqlite3_bind_text(stmt->sqlite, idx, (char *)text.data, text.size, SQLITE_TRANSIENT);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_bind_blob(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int idx;
    if (!enif_get_int(env, argv[1], &idx))
        return make_badarg(env, argv[1]);

    ErlNifBinary blob;
    if (!enif_inspect_binary(env, argv[2], &blob))
        return make_badarg(env, argv[2]);

    // TODO can be something other than SQLITE_TRANSIENT?
    int rc = sqlite3_bind_blob(stmt->sqlite, idx, (char *)blob.data, blob.size, SQLITE_TRANSIENT);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_bind_integer(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int idx;
    if (!enif_get_int(env, argv[1], &idx))
        return make_badarg(env, argv[1]);

    ErlNifSInt64 i;
    if (!enif_get_int64(env, argv[2], &i))
        return make_badarg(env, argv[2]);

    int rc = sqlite3_bind_int64(stmt->sqlite, idx, i);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_bind_float(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int idx;
    if (!enif_get_int(env, argv[1], &idx))
        return make_badarg(env, argv[1]);

    double f;
    if (!enif_get_double(env, argv[2], &f))
        return make_badarg(env, argv[2]);

    int rc = sqlite3_bind_double(stmt->sqlite, idx, f);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_bind_null(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int idx;
    if (!enif_get_int(env, argv[1], &idx))
        return make_badarg(env, argv[1]);

    int rc = sqlite3_bind_null(stmt->sqlite, idx);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_reset(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    // TODO check rc?
    sqlite3_reset(stmt->sqlite);
    return am_ok;
}

static ERL_NIF_TERM
make_cell(ErlNifEnv *env, sqlite3_stmt *stmt, int idx)
{
    switch (sqlite3_column_type(stmt, idx))
    {
    case SQLITE_INTEGER:
        return enif_make_int64(env, sqlite3_column_int64(stmt, idx));

    case SQLITE_FLOAT:
        return enif_make_double(env, sqlite3_column_double(stmt, idx));

    case SQLITE_TEXT:
        return make_binary(env, sqlite3_column_text(stmt, idx), sqlite3_column_bytes(stmt, idx));

    case SQLITE_BLOB:
        return make_binary(env, sqlite3_column_blob(stmt, idx), sqlite3_column_bytes(stmt, idx));

    default:
        return am_nil;
    }
}

static ERL_NIF_TERM
make_row(ErlNifEnv *env, sqlite3_stmt *stmt, ERL_NIF_TERM *columns, unsigned int column_count)
{
    for (unsigned int i = 0; i < column_count; i++)
        columns[i] = make_cell(env, stmt, i);

    return enif_make_list_from_array(env, columns, column_count);
}

static ERL_NIF_TERM
xqlite_step(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int rc = sqlite3_step(stmt->sqlite);

    if (rc == SQLITE_ROW)
    {
        unsigned int column_count = sqlite3_column_count(stmt->sqlite);
        ERL_NIF_TERM columns[column_count];
        return make_row(env, stmt->sqlite, columns, column_count);
    }

    // TODO don't lose rc
    sqlite3_reset(stmt->sqlite);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_multi_step(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    unsigned int steps;
    if (!enif_get_uint(env, argv[1], &steps))
        return make_badarg(env, argv[1]);

    unsigned int column_count = sqlite3_column_count(stmt->sqlite);
    ERL_NIF_TERM columns[column_count];

    ERL_NIF_TERM row;
    ERL_NIF_TERM rows = enif_make_list(env, 0);

    for (unsigned int step = 0; step < steps; step++)
    {
        int rc = sqlite3_step(stmt->sqlite);
        switch (rc)
        {
        case SQLITE_DONE:
            // TODO don't lose rc
            sqlite3_reset(stmt->sqlite);
            return enif_make_tuple2(env, am_done, rows);

        case SQLITE_ROW:
            row = make_row(env, stmt->sqlite, columns, column_count);
            rows = enif_make_list_cell(env, row, rows);
            break;

        default:
            // TODO don't lose rc
            sqlite3_reset(stmt->sqlite);
            return enif_make_int(env, rc);
        }
    }

    return enif_make_tuple2(env, am_rows, rows);
}

static ERL_NIF_TERM
xqlite_interrupt(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite *db;
    if (!enif_get_resource(env, argv[0], db_t, (void **)&db))
        return make_badarg(env, argv[0]);

    sqlite3_interrupt(db->sqlite);
    return am_ok;
}

static ERL_NIF_TERM
xqlite_finalize(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    if (stmt->sqlite)
    {
        // TODO dont lose rc
        sqlite3_finalize(stmt->sqlite);
        stmt->sqlite = NULL;
    }

    return am_ok;
}

// TODO refactor
static ERL_NIF_TERM
xqlite_insert_all(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int stmt_param_count = sqlite3_bind_parameter_count(stmt->sqlite);
    int types_array[stmt_param_count];

    ERL_NIF_TERM types = argv[1];
    ERL_NIF_TERM rows = argv[2];
    ERL_NIF_TERM head, tail;

    // process types
    for (int i = 0; i < stmt_param_count; i++)
    {
        int type;
        enif_get_list_cell(env, types, &head, &tail);
        enif_get_int(env, head, &type);
        types_array[i] = type;
        types = tail;
    }

    int rc;

    // process rows
    while (enif_get_list_cell(env, rows, &head, &tail))
    {
        // TODO dont lose rc
        // TODO move below
        sqlite3_reset(stmt->sqlite);

        // bind row
        for (int i = 1; i <= stmt_param_count; i++)
        {
            ERL_NIF_TERM param;

            if (!enif_get_list_cell(env, head, &param, &head))
                return make_badarg(env, head);

            if (enif_is_identical(param, am_nil))
            {
                rc = sqlite3_bind_null(stmt->sqlite, i);
            }
            else
            {
                switch (types_array[i - 1])
                {
                case SQLITE_INTEGER:
                {
                    ErlNifSInt64 i64;
                    if (!enif_get_int64(env, param, &i64))
                        return make_badarg(env, param);

                    rc = sqlite3_bind_int64(stmt->sqlite, i, i64);
                    break;
                }

                case SQLITE_FLOAT:
                {
                    double f64;
                    if (!enif_get_double(env, param, &f64))
                        return make_badarg(env, param);

                    rc = sqlite3_bind_double(stmt->sqlite, i, f64);
                    break;
                }

                case SQLITE_TEXT:
                {
                    ErlNifBinary text;
                    if (!enif_inspect_binary(env, param, &text))
                        return make_badarg(env, param);

                    rc = sqlite3_bind_text(stmt->sqlite, i, (char *)text.data, text.size, SQLITE_TRANSIENT);
                    break;
                }

                case SQLITE_BLOB:
                {
                    ErlNifBinary blob;
                    if (!enif_inspect_binary(env, param, &blob))
                        return make_badarg(env, param);

                    rc = sqlite3_bind_blob(stmt->sqlite, i, (char *)blob.data, blob.size, SQLITE_TRANSIENT);
                    break;
                }
                }
            }

            if (rc != SQLITE_OK)
                return enif_make_int(env, rc);
        }

        rc = sqlite3_step(stmt->sqlite);
        if (rc != SQLITE_DONE)
            return enif_make_int(env, rc);

        rows = tail;
    }

    return am_done;
}

static ERL_NIF_TERM
xqlite_fetch_all(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int column_count = sqlite3_column_count(stmt->sqlite);
    ERL_NIF_TERM columns[column_count];

    ERL_NIF_TERM row;
    ERL_NIF_TERM rows = enif_make_list(env, 0);

    while (1)
    {
        int rc = sqlite3_step(stmt->sqlite);
        switch (rc)
        {
        case SQLITE_DONE:
            // TODO don't lose rc
            sqlite3_reset(stmt->sqlite);
            return rows;

        case SQLITE_ROW:
            row = make_row(env, stmt->sqlite, columns, column_count);
            rows = enif_make_list_cell(env, row, rows);
            break;

        default:
            // TODO don't lose rc
            sqlite3_reset(stmt->sqlite);
            return enif_make_int(env, rc);
        }
    }
}

static ERL_NIF_TERM
xqlite_changes64(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite *db;
    if (!enif_get_resource(env, argv[0], db_t, (void **)&db))
        return make_badarg(env, argv[0]);

    sqlite_int64 changes = sqlite3_changes64(db->sqlite);
    return enif_make_int64(env, changes);
}

static ERL_NIF_TERM
xqlite_total_changes64(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite *db;
    if (!enif_get_resource(env, argv[0], db_t, (void **)&db))
        return make_badarg(env, argv[0]);

    sqlite_int64 total_changes = sqlite3_total_changes64(db->sqlite);
    return enif_make_int64(env, total_changes);
}

static ERL_NIF_TERM
xqlite_clear_bindings(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int rc = sqlite3_clear_bindings(stmt->sqlite);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_enable_load_extension(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite *db;
    if (!enif_get_resource(env, argv[0], db_t, (void **)&db))
        return make_badarg(env, argv[0]);

    int rc;
    if (enif_is_identical(argv[1], am_true))
    {
        rc = sqlite3_enable_load_extension(db->sqlite, 1);
    }
    else if (enif_is_identical(argv[1], am_false))
    {
        rc = sqlite3_enable_load_extension(db->sqlite, 0);
    }
    else
    {
        return make_badarg(env, argv[1]);
    }

    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_sql(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    const char *sql = sqlite3_sql(stmt->sqlite);
    return make_binary(env, (unsigned char *)sql, strlen(sql));
}

static ERL_NIF_TERM
xqlite_expanded_sql(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    char *sql = sqlite3_expanded_sql(stmt->sqlite);
    ERL_NIF_TERM bin = make_binary(env, (unsigned char *)sql, strlen(sql));
    sqlite3_free(sql);
    return bin;
}

static ERL_NIF_TERM
xqlite_get_autocommit(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite *db;
    if (!enif_get_resource(env, argv[0], db_t, (void **)&db))
        return make_badarg(env, argv[0]);

    int autocommit = sqlite3_get_autocommit(db->sqlite);
    return enif_make_int(env, autocommit);
}

static ERL_NIF_TERM
xqlite_last_insert_rowid(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite *db;
    if (!enif_get_resource(env, argv[0], db_t, (void **)&db))
        return make_badarg(env, argv[0]);

    sqlite3_int64 last_insert_rowid = sqlite3_last_insert_rowid(db->sqlite);
    return enif_make_int64(env, last_insert_rowid);
}

static ERL_NIF_TERM
xqlite_memory_used(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    sqlite3_int64 memory_used = sqlite3_memory_used();
    return enif_make_int64(env, memory_used);
}

static ERL_NIF_TERM
xqlite_column_count(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int column_count = sqlite3_column_count(stmt->sqlite);
    return enif_make_int(env, column_count);
}

static ERL_NIF_TERM
xqlite_column_name(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int idx;
    if (!enif_get_int(env, argv[1], &idx))
        return make_badarg(env, argv[1]);

    const char *name = sqlite3_column_name(stmt->sqlite, idx);
    if (!name)
        return enif_raise_exception(env, am_system_error);

    return make_binary(env, (unsigned char *)name, strlen(name));
}

static ERL_NIF_TERM
xqlite_column_names(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int column_count = sqlite3_column_count(stmt->sqlite);
    ERL_NIF_TERM columns[column_count];

    for (int i = 0; i < column_count; i++)
    {
        const char *name = sqlite3_column_name(stmt->sqlite, i);
        if (!name)
            return enif_raise_exception(env, am_system_error);

        columns[i] = make_binary(env, (unsigned char *)name, strlen(name));
    }

    return enif_make_list_from_array(env, columns, column_count);
}

static ERL_NIF_TERM
xqlite_bind_parameter_count(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int bind_parameter_count = sqlite3_bind_parameter_count(stmt->sqlite);
    return enif_make_int(env, bind_parameter_count);
}

static ERL_NIF_TERM
xqlite_bind_parameter_index(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    ErlNifBinary name;
    if (!enif_inspect_iolist_as_binary(env, argv[1], &name))
        return make_badarg(env, argv[1]);

    int idx = sqlite3_bind_parameter_index(stmt->sqlite, (const char *)name.data);
    return enif_make_int(env, idx);
}

static ERL_NIF_TERM
xqlite_bind_parameter_name(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite_stmt *stmt;
    if (!enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
        return make_badarg(env, argv[0]);

    int idx;
    if (!enif_get_int(env, argv[1], &idx))
        return make_badarg(env, argv[1]);

    const char *name = sqlite3_bind_parameter_name(stmt->sqlite, idx);
    if (!name)
        return am_nil;

    return make_binary(env, (unsigned char *)name, strlen(name));
}

static ERL_NIF_TERM
xqlite_exec(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    xqlite *db;
    if (!enif_get_resource(env, argv[0], db_t, (void **)&db))
        return make_badarg(env, argv[0]);

    ErlNifBinary sql;
    if (!enif_inspect_iolist_as_binary(env, argv[1], &sql))
        return make_badarg(env, argv[1]);

    int rc = sqlite3_exec(db->sqlite, (char *)sql.data, NULL, NULL, NULL);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_errstr(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    int rc;
    if (!enif_get_int(env, argv[0], &rc))
        return enif_make_badarg(env);

    const char *errstr = sqlite3_errstr(rc);
    return make_binary(env, (unsigned char *)errstr, strlen(errstr));
}

static ERL_NIF_TERM
xqlite_errmsg(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    sqlite3 *sqlite;

    xqlite *db;
    xqlite_stmt *stmt;

    if (enif_get_resource(env, argv[0], db_t, (void **)&db))
    {
        sqlite = db->sqlite;
    }
    else if (enif_get_resource(env, argv[0], stmt_t, (void **)&stmt))
    {
        sqlite = sqlite3_db_handle(stmt->sqlite);
    }
    else
    {
        return make_badarg(env, argv[0]);
    }

    const char *msg = sqlite3_errmsg(sqlite);
    if (!msg)
        return am_nil;

    return make_binary(env, (unsigned char *)msg, strlen(msg));
}

static ErlNifFunc nif_funcs[] = {
    {"dirty_io_open_nif", 2, xqlite_open, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"dirty_io_close_nif", 1, xqlite_close, ERL_NIF_DIRTY_JOB_IO_BOUND},

    {"prepare_nif", 3, xqlite_prepare, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"finalize", 1, xqlite_finalize, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"reset", 1, xqlite_reset, ERL_NIF_DIRTY_JOB_CPU_BOUND},

    {"bind_parameter_count", 1, xqlite_bind_parameter_count, 0},
    {"bind_parameter_index_nif", 2, xqlite_bind_parameter_index, 0},
    {"bind_parameter_name", 2, xqlite_bind_parameter_name, 0},
    {"bind_text_nif", 3, xqlite_bind_text, 0},
    {"bind_blob_nif", 3, xqlite_bind_blob, 0},
    {"bind_integer_nif", 3, xqlite_bind_integer, 0},
    {"bind_float_nif", 3, xqlite_bind_float, 0},
    {"bind_null_nif", 2, xqlite_bind_null, 0},
    {"clear_bindings_nif", 1, xqlite_clear_bindings, 0},

    {"step_nif", 1, xqlite_step, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"unsafe_step_nif", 1, xqlite_step, 0},
    {"dirty_io_step_nif", 2, xqlite_multi_step, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"step_nif", 2, xqlite_multi_step, 0},
    {"exec_nif", 2, xqlite_exec, ERL_NIF_DIRTY_JOB_IO_BOUND},

    {"get_autocommit", 1, xqlite_get_autocommit, 0},

    {"interrupt", 1, xqlite_interrupt, 0},

    {"dirty_io_fetch_all_nif", 1, xqlite_fetch_all, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"dirty_io_insert_all_nif", 3, xqlite_insert_all, ERL_NIF_DIRTY_JOB_IO_BOUND},

    {"column_count", 1, xqlite_column_count, 0},
    {"column_name", 2, xqlite_column_name, 0},
    {"column_names", 1, xqlite_column_names, 0},

    {"changes", 1, xqlite_changes64, 0},
    {"total_changes", 1, xqlite_total_changes64, 0},
    {"last_insert_rowid", 1, xqlite_last_insert_rowid, 0},

    {"enable_load_extension_nif", 2, xqlite_enable_load_extension, 0},

    {"sql", 1, xqlite_sql, 0},
    {"expanded_sql", 1, xqlite_expanded_sql, 0},

    {"memory_used", 0, xqlite_memory_used, 0},
    {"errstr", 1, xqlite_errstr, 0},
    {"errmsg", 1, xqlite_errmsg, 0},
};

ERL_NIF_INIT(Elixir.XQLite, nif_funcs, on_load, NULL, NULL, NULL)
