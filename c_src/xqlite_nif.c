#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>

// Elixir workaround for . in module names
#ifdef STATIC_ERLANG_NIF
#define STATIC_ERLANG_NIF_LIBNAME xqlite_nif
#endif

#include <erl_nif.h>
#include <sqlite3.h>

#define MAX_ATOM_LENGTH 255

static ERL_NIF_TERM am_ok;
static ERL_NIF_TERM am_error;
static ERL_NIF_TERM am_nil;
static ERL_NIF_TERM am_out_of_memory;
static ERL_NIF_TERM am_done;
static ERL_NIF_TERM am_row;
static ERL_NIF_TERM am_rows;

static ErlNifResourceType *db_type = NULL;
static ErlNifResourceType *stmt_type = NULL;
static sqlite3_mem_methods default_mem_methods = {0};

typedef struct db
{
    sqlite3 *db;
} db_t;

typedef struct stmt
{
    sqlite3_stmt *stmt;
} stmt_t;

static ERL_NIF_TERM
make_binary(ErlNifEnv *env, const unsigned char *bytes, size_t size)
{
    ERL_NIF_TERM bin;
    uint8_t *data = enif_make_new_binary(env, size, &bin);
    memcpy(data, bytes, size);
    return bin;
}

// TODO just return rc, and let caller handle error, export the necessary nifs
static ERL_NIF_TERM
raise_sqlite3_error(ErlNifEnv *env, int rc, sqlite3 *db)
{
    const char *msg = sqlite3_errmsg(db);

    if (!msg)
        msg = sqlite3_errstr(rc);

    ERL_NIF_TERM code = enif_make_int64(env, rc);
    ERL_NIF_TERM reason = enif_make_string(env, msg, ERL_NIF_UTF8);
    ERL_NIF_TERM error = enif_make_tuple3(env, am_error, code, reason);
    return enif_raise_exception(env, error);
}

static ERL_NIF_TERM
xqlite_open(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 2)
        return enif_make_badarg(env);

    char path[256];
    if (enif_get_string(env, argv[0], path, sizeof(path), ERL_NIF_UTF8) < 0)
        return enif_make_badarg(env);

    int flags;
    if (!enif_get_int(env, argv[1], &flags))
        return enif_make_badarg(env);

    sqlite3 *db;
    int rc = sqlite3_open_v2(path, &db, flags, NULL);

    if (rc != SQLITE_OK)
    {
        const char *msg = sqlite3_errstr(rc);
        ERL_NIF_TERM code = enif_make_int64(env, rc);
        ERL_NIF_TERM reason = enif_make_string(env, msg, ERL_NIF_UTF8);
        ERL_NIF_TERM error = enif_make_tuple3(env, am_error, code, reason);
        return enif_raise_exception(env, error);
    }

    db_t *db_resource;
    db_resource = enif_alloc_resource(db_type, sizeof(db_t));

    if (!db_resource)
    {
        sqlite3_close_v2(db);
        return enif_raise_exception(env, am_out_of_memory);
    }

    db_resource->db = db;

    ERL_NIF_TERM result = enif_make_resource(env, db_resource);
    enif_release_resource(db_resource);
    return result;
}

static ERL_NIF_TERM
xqlite_close(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 1)
        return enif_make_badarg(env);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    // DB is already closed, nothing to do here
    if (db->db == NULL)
        return am_ok;

    int autocommit = sqlite3_get_autocommit(db->db);
    if (autocommit == 0)
    {
        int rc = sqlite3_exec(db->db, "ROLLBACK;", NULL, NULL, NULL);
        if (rc != SQLITE_OK)
            return raise_sqlite3_error(env, rc, db->db);
    }

    // note: _v2 may not fully close the connection, hence why we check if
    // any transaction is open above, to make sure other connections aren't blocked.
    // v1 is guaranteed to close or error, but will return error if any
    // unfinalized statements, which we likely have, as we rely on the destructors
    // to later run to clean those up
    int rc = sqlite3_close_v2(db->db);
    if (rc != SQLITE_OK)
        return raise_sqlite3_error(env, rc, db->db);

    db->db = NULL;
    return am_ok;
}

static ERL_NIF_TERM
xqlite_prepare(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 3)
        return enif_make_badarg(env);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    ErlNifBinary sql;
    if (!enif_inspect_binary(env, argv[1], &sql))
        return enif_make_badarg(env);

    int flags;
    if (!enif_get_int(env, argv[2], &flags))
        return enif_make_badarg(env);

    stmt_t *stmt;
    stmt = enif_alloc_resource(stmt_type, sizeof(stmt_t));
    if (!stmt)
        return enif_raise_exception(env, am_out_of_memory);

    int rc = sqlite3_prepare_v3(db->db, (char *)sql.data, sql.size, flags, &stmt->stmt, NULL);
    if (rc != SQLITE_OK)
    {
        enif_release_resource(stmt);
        return raise_sqlite3_error(env, rc, db->db);
    }

    ERL_NIF_TERM result = enif_make_resource(env, stmt);
    enif_release_resource(stmt);
    return result;
}

static int
bind_text(ErlNifEnv *env, sqlite3_stmt *stmt, unsigned int idx, ERL_NIF_TERM param)
{
    if (enif_is_identical(param, am_nil) == 1)
        return sqlite3_bind_null(stmt, idx);

    ErlNifBinary text;
    if (enif_inspect_binary(env, param, &text))
        return sqlite3_bind_text(stmt, idx, (char *)text.data, text.size, SQLITE_TRANSIENT);

    return -1;
}

static ERL_NIF_TERM
xqlite_bind_text(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 4)
        return enif_make_badarg(env);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[1], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int idx;
    if (!enif_get_uint(env, argv[2], &idx))
        return enif_make_badarg(env);

    int rc = bind_text(env, stmt->stmt, idx, argv[3]);

    if (rc == -1)
        return enif_make_badarg(env);

    if (rc != SQLITE_OK)
        return raise_sqlite3_error(env, rc, db->db);

    return am_ok;
}

static int
bind_blob(ErlNifEnv *env, sqlite3_stmt *stmt, unsigned int idx, ERL_NIF_TERM param)
{
    if (enif_is_identical(param, am_nil) == 1)
        return sqlite3_bind_null(stmt, idx);

    ErlNifBinary blob;
    if (enif_inspect_binary(env, param, &blob))
        return sqlite3_bind_blob(stmt, idx, (char *)blob.data, blob.size, SQLITE_TRANSIENT);

    return -1;
}

static ERL_NIF_TERM
xqlite_bind_blob(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 4)
        return enif_make_badarg(env);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[1], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int idx;
    if (!enif_get_uint(env, argv[2], &idx))
        return enif_make_badarg(env);

    int rc = bind_blob(env, stmt->stmt, idx, argv[3]);

    if (rc == -1)
        return enif_make_badarg(env);

    if (rc != SQLITE_OK)
        return raise_sqlite3_error(env, rc, db->db);

    return am_ok;
}

static int
bind_integer(ErlNifEnv *env, sqlite3_stmt *stmt, unsigned int idx, ERL_NIF_TERM param)
{
    if (enif_is_identical(param, am_nil) == 1)
        return sqlite3_bind_null(stmt, idx);

    int i32;
    if (enif_get_int(env, param, &i32))
        return sqlite3_bind_int(stmt, idx, i32);

    ErlNifSInt64 i64;
    if (enif_get_int64(env, param, &i64))
        return sqlite3_bind_int64(stmt, idx, i64);

    return -1;
}

static int
bind_real(ErlNifEnv *env, sqlite3_stmt *stmt, unsigned int idx, ERL_NIF_TERM param)
{
    if (enif_is_identical(param, am_nil) == 1)
        return sqlite3_bind_null(stmt, idx);

    double f64;
    if (enif_get_double(env, param, &f64))
        return sqlite3_bind_double(stmt, idx, f64);

    return -1;
}

static ERL_NIF_TERM
xqlite_bind_number(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 4)
        return enif_make_badarg(env);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[1], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int idx;
    if (!enif_get_uint(env, argv[2], &idx))
        return enif_make_badarg(env);

    ERL_NIF_TERM param = argv[3];
    int rc = bind_integer(env, stmt->stmt, idx, param);

    if (rc == -1)
        rc = bind_real(env, stmt->stmt, idx, param);

    if (rc == -1)
        return enif_make_badarg(env);

    if (rc != SQLITE_OK)
        return raise_sqlite3_error(env, rc, db->db);

    return am_ok;
}

static ERL_NIF_TERM
xqlite_bind_null(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 3)
        return enif_make_badarg(env);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[1], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int idx;
    if (!enif_get_uint(env, argv[2], &idx))
        return enif_make_badarg(env);

    int rc = sqlite3_bind_null(stmt->stmt, idx);

    if (rc != SQLITE_OK)
        return raise_sqlite3_error(env, rc, db->db);

    return am_ok;
}

static ERL_NIF_TERM
make_cell(ErlNifEnv *env, sqlite3_stmt *stmt, unsigned int idx)
{
    switch (sqlite3_column_type(stmt, idx))
    {
    case SQLITE_INTEGER:
        // TODO maybe use enif_make_int if possible?
        return enif_make_int64(env, sqlite3_column_int64(stmt, idx));

    case SQLITE_FLOAT:
        return enif_make_double(env, sqlite3_column_double(stmt, idx));

    case SQLITE_TEXT:
        return make_binary(env, sqlite3_column_text(stmt, idx), sqlite3_column_bytes(stmt, idx));

    case SQLITE_BLOB:
        return make_binary(env, sqlite3_column_blob(stmt, idx), sqlite3_column_bytes(stmt, idx));

    case SQLITE_NULL:
        return am_nil;

    // TODO
    default:
        return am_nil;
    }
}

static ERL_NIF_TERM
make_row(ErlNifEnv *env, unsigned int column_count, sqlite3_stmt *stmt)
{
    assert(env);
    assert(stmt);

    // TODO lol this is a bit silly, but it's a start
    switch (column_count)
    {
    case 0:
        return enif_make_list(env, 0);
    case 1:
        return enif_make_list(env, 1, make_cell(env, stmt, 0));
    case 2:
        return enif_make_list(env, 2, make_cell(env, stmt, 0), make_cell(env, stmt, 1));
    case 3:
        return enif_make_list(env, 3, make_cell(env, stmt, 0), make_cell(env, stmt, 1), make_cell(env, stmt, 2));
    case 4:
        return enif_make_list(env, 4, make_cell(env, stmt, 0), make_cell(env, stmt, 1), make_cell(env, stmt, 2), make_cell(env, stmt, 3));
    case 5:
        return enif_make_list(env, 5, make_cell(env, stmt, 0), make_cell(env, stmt, 1), make_cell(env, stmt, 2), make_cell(env, stmt, 3), make_cell(env, stmt, 4));
    case 6:
        return enif_make_list(env, 6, make_cell(env, stmt, 0), make_cell(env, stmt, 1), make_cell(env, stmt, 2), make_cell(env, stmt, 3), make_cell(env, stmt, 4), make_cell(env, stmt, 5));
    case 7:
        return enif_make_list(env, 7, make_cell(env, stmt, 0), make_cell(env, stmt, 1), make_cell(env, stmt, 2), make_cell(env, stmt, 3), make_cell(env, stmt, 4), make_cell(env, stmt, 5), make_cell(env, stmt, 6));
    case 8:
        return enif_make_list(env, 8, make_cell(env, stmt, 0), make_cell(env, stmt, 1), make_cell(env, stmt, 2), make_cell(env, stmt, 3), make_cell(env, stmt, 4), make_cell(env, stmt, 5), make_cell(env, stmt, 6), make_cell(env, stmt, 7));
    case 9:
        return enif_make_list(env, 9, make_cell(env, stmt, 0), make_cell(env, stmt, 1), make_cell(env, stmt, 2), make_cell(env, stmt, 3), make_cell(env, stmt, 4), make_cell(env, stmt, 5), make_cell(env, stmt, 6), make_cell(env, stmt, 7), make_cell(env, stmt, 8));
    // TODO continue till 16
    default:
    {
        ERL_NIF_TERM *columns;
        columns = enif_alloc(sizeof(ERL_NIF_TERM) * column_count);
        if (!columns)
            return enif_raise_exception(env, am_out_of_memory);

        for (unsigned int i = 0; i < column_count; i++)
            columns[i] = make_cell(env, stmt, i);

        ERL_NIF_TERM row = enif_make_list_from_array(env, columns, column_count);
        enif_free(columns);
        return row;
    }
    }
}

static ERL_NIF_TERM
xqlite_step(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 2)
        return enif_make_badarg(env);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[1], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int column_count = sqlite3_column_count(stmt->stmt);
    int rc = sqlite3_step(stmt->stmt);

    switch (rc)
    {
    case SQLITE_ROW:
        return enif_make_tuple2(env, am_row, make_row(env, column_count, stmt->stmt));

    case SQLITE_DONE:
        return am_done;

    default:
        return raise_sqlite3_error(env, rc, db->db);
    }
}

static ERL_NIF_TERM
xqlite_multi_step(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 3)
        return enif_make_badarg(env);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[1], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int steps;
    if (!enif_get_uint(env, argv[2], &steps))
        return enif_make_badarg(env);

    unsigned int column_count = sqlite3_column_count(stmt->stmt);

    ERL_NIF_TERM row;
    ERL_NIF_TERM rows = enif_make_list_from_array(env, NULL, 0);
    for (unsigned int step = 0; step < steps; step++)
    {
        int rc = sqlite3_step(stmt->stmt);
        switch (rc)
        {
        case SQLITE_DONE:
            return enif_make_tuple2(env, am_done, rows);

        case SQLITE_ROW:
            row = make_row(env, column_count, stmt->stmt);
            rows = enif_make_list_cell(env, row, rows);
            break;

        default:
            sqlite3_reset(stmt->stmt);
            return raise_sqlite3_error(env, rc, db->db);
        }
    }

    return enif_make_tuple2(env, am_rows, rows);
}

static ERL_NIF_TERM
xqlite_interrupt(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 1)
        return enif_make_badarg(env);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    sqlite3_interrupt(db->db);
    return am_ok;
}

static ERL_NIF_TERM
xqlite_finalize(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 1)
        return enif_make_badarg(env);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    if (stmt->stmt)
    {
        sqlite3_finalize(stmt->stmt);
        stmt->stmt = NULL;
    }

    return am_ok;
}

static ERL_NIF_TERM
xqlite_insert_all(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 4)
        return enif_make_badarg(env);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[1], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    int stmt_param_count = (unsigned int)sqlite3_bind_parameter_count(stmt->stmt);
    int types_array[stmt_param_count];

    ERL_NIF_TERM types = argv[2];
    ERL_NIF_TERM rows = argv[3];
    ERL_NIF_TERM head, tail;

    // process types
    for (unsigned int i = 0; i < stmt_param_count; i++)
    {
        if (!enif_get_list_cell(env, types, &head, &tail))
            return enif_make_badarg(env);

        int type;
        if (!enif_get_int(env, head, &type))
            return enif_make_badarg(env);

        types_array[i] = type;
        types = tail;
    }

    int rc;

    // process rows
    while (enif_get_list_cell(env, rows, &head, &tail))
    {
        // TODO need it?
        sqlite3_reset(stmt->stmt);

        // bind row
        for (unsigned int i = 1; i <= stmt_param_count; i++)
        {
            ERL_NIF_TERM param;

            if (!enif_get_list_cell(env, head, &param, &head))
                return enif_make_badarg(env);

            switch (types_array[i - 1])
            {
            case SQLITE_INTEGER:
                rc = bind_integer(env, stmt->stmt, i, param);
                break;

            case SQLITE_FLOAT:
                rc = bind_real(env, stmt->stmt, i, param);
                break;

            case SQLITE_TEXT:
                rc = bind_text(env, stmt->stmt, i, param);
                break;

            case SQLITE_BLOB:
                rc = bind_blob(env, stmt->stmt, i, param);
                break;
            }

            if (rc != SQLITE_OK)
                return raise_sqlite3_error(env, rc, db->db);
        }

        rc = sqlite3_step(stmt->stmt);
        if (rc != SQLITE_DONE)
            return raise_sqlite3_error(env, rc, db->db);

        rows = tail;
    }

    return am_ok;
}

static ERL_NIF_TERM
xqlite_fetch_all(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 2)
        return enif_make_badarg(env);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[1], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int column_count = sqlite3_column_count(stmt->stmt);

    ERL_NIF_TERM row;
    ERL_NIF_TERM rows = enif_make_list_from_array(env, NULL, 0);

    while (1)
    {
        int rc = sqlite3_step(stmt->stmt);
        switch (rc)
        {
        case SQLITE_DONE:
            return rows;

        case SQLITE_ROW:
            row = make_row(env, column_count, stmt->stmt);
            rows = enif_make_list_cell(env, row, rows);
            break;

        default:
            sqlite3_reset(stmt->stmt);
            return raise_sqlite3_error(env, rc, db->db);
        }
    }
}

static void
db_type_destructor(ErlNifEnv *env, void *arg)
{
    assert(env);
    assert(arg);

    db_t *db = (db_t *)arg;

    if (db->db)
    {
        sqlite3_close_v2(db->db);
        db->db = NULL;
    }
}

static void
stmt_type_destructor(ErlNifEnv *env, void *arg)
{
    assert(env);
    assert(arg);

    stmt_t *stmt = (stmt_t *)arg;

    if (stmt->stmt)
    {
        sqlite3_finalize(stmt->stmt);
        stmt->stmt = NULL;
    }
}

static int
on_load(ErlNifEnv *env, void **priv, ERL_NIF_TERM info)
{
    assert(env);

    am_ok = enif_make_atom(env, "ok");
    am_error = enif_make_atom(env, "error");
    am_nil = enif_make_atom(env, "nil");
    // TODO rename to alloc_error
    am_out_of_memory = enif_make_atom(env, "out_of_memory");
    am_done = enif_make_atom(env, "done");
    am_row = enif_make_atom(env, "row");
    am_rows = enif_make_atom(env, "rows");

    sqlite3_config(SQLITE_CONFIG_GETMALLOC, &default_mem_methods);

    db_type = enif_open_resource_type(env, "xqlite", "db_type", db_type_destructor, ERL_NIF_RT_CREATE, NULL);
    if (!db_type)
        return -1;

    stmt_type = enif_open_resource_type(env, "xqlite", "stmt_type", stmt_type_destructor, ERL_NIF_RT_CREATE, NULL);
    if (!stmt_type)
        return -1;

    return 0;
}

static void
on_unload(ErlNifEnv *caller_env, void *priv_data)
{
    assert(caller_env);
    sqlite3_config(SQLITE_CONFIG_MALLOC, &default_mem_methods);
}

static ErlNifFunc nif_funcs[] = {
    {"dirty_io_open_nif", 2, xqlite_open, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"dirty_io_close_nif", 1, xqlite_close, ERL_NIF_DIRTY_JOB_IO_BOUND},

    {"prepare_nif", 3, xqlite_prepare, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"finalize", 1, xqlite_finalize, ERL_NIF_DIRTY_JOB_CPU_BOUND},

    {"bind_text", 4, xqlite_bind_text},
    {"bind_blob", 4, xqlite_bind_blob},
    {"bind_number", 4, xqlite_bind_number},
    {"bind_null", 3, xqlite_bind_null},

    {"step", 2, xqlite_step, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"unsafe_step", 2, xqlite_step},
    {"dirty_io_step_nif", 3, xqlite_multi_step, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"step_nif", 3, xqlite_multi_step},

    {"interrupt", 1, xqlite_interrupt},

    {"dirty_io_fetch_all_nif", 2, xqlite_fetch_all, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"dirty_io_insert_all_nif", 4, xqlite_insert_all, ERL_NIF_DIRTY_JOB_IO_BOUND},
};

ERL_NIF_INIT(Elixir.XQLite, nif_funcs, on_load, NULL, NULL, on_unload)
