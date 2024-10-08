#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <erl_nif.h>
#include <sqlite3.h>

static ERL_NIF_TERM am_ok;
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
    am_nil = enif_make_atom(env, "nil");
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

static ERL_NIF_TERM
make_binary(ErlNifEnv *env, const unsigned char *bytes, size_t size)
{
    ERL_NIF_TERM bin;
    uint8_t *data = enif_make_new_binary(env, size, &bin);
    memcpy(data, bytes, size);
    return bin;
}

static ERL_NIF_TERM
xqlite_open(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 2);

    ErlNifBinary path;
    if (!enif_inspect_binary(env, argv[0], &path))
        return enif_make_badarg(env);

    int flags;
    if (!enif_get_int(env, argv[1], &flags))
        return enif_make_badarg(env);

    db_t *db = enif_alloc_resource(db_type, sizeof(db_t));
    if (!db)
        return enif_raise_exception(env, am_out_of_memory);

    int rc = sqlite3_open_v2((char *)path.data, &db->db, flags, NULL);
    if (rc != SQLITE_OK)
    {
        enif_release_resource(db);
        return enif_make_int(env, rc);
    }

    ERL_NIF_TERM result = enif_make_resource(env, db);
    enif_release_resource(db);
    return result;
}

static ERL_NIF_TERM
xqlite_close(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    if (db->db == NULL)
        return enif_make_int(env, SQLITE_OK);

    int rc = sqlite3_close(db->db);
    if (rc == SQLITE_OK)
        db->db = NULL;

    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_close_v2(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    if (db->db == NULL)
        return enif_make_int(env, SQLITE_OK);

    int rc = sqlite3_close_v2(db->db);
    if (rc == SQLITE_OK)
        db->db = NULL;

    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_prepare(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 3);

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
        return enif_make_int(env, rc);
    }

    ERL_NIF_TERM result = enif_make_resource(env, stmt);
    enif_release_resource(stmt);
    return result;
}

static ERL_NIF_TERM
xqlite_bind_text(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 3);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int idx;
    if (!enif_get_uint(env, argv[1], &idx))
        return enif_make_badarg(env);

    ErlNifBinary text;
    if (!enif_inspect_binary(env, argv[2], &text))
        return enif_make_badarg(env);

    int rc = sqlite3_bind_text(stmt->stmt, idx, (char *)text.data, text.size, SQLITE_TRANSIENT);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_bind_blob(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 3);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int idx;
    if (!enif_get_uint(env, argv[1], &idx))
        return enif_make_badarg(env);

    ErlNifBinary blob;
    if (!enif_inspect_binary(env, argv[2], &blob))
        return enif_make_badarg(env);

    int rc = sqlite3_bind_blob(stmt->stmt, idx, (char *)blob.data, blob.size, SQLITE_TRANSIENT);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_bind_integer(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 3);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int idx;
    if (!enif_get_uint(env, argv[1], &idx))
        return enif_make_badarg(env);

    int rc;
    int i32;
    ErlNifSInt64 i64;
    ERL_NIF_TERM param = argv[2];

    if (enif_get_int(env, param, &i32))
    {
        rc = sqlite3_bind_int(stmt->stmt, idx, i32);
    }
    else if (enif_get_int64(env, param, &i64))
    {
        rc = sqlite3_bind_int64(stmt->stmt, idx, i64);
    }
    else
    {
        return enif_make_badarg(env);
    }

    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_bind_float(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 3);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int idx;
    if (!enif_get_uint(env, argv[1], &idx))
        return enif_make_badarg(env);

    double f64;
    if (!enif_get_double(env, argv[2], &f64))
        return enif_make_badarg(env);

    int rc = sqlite3_bind_double(stmt->stmt, idx, f64);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_bind_null(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 2);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int idx;
    if (!enif_get_uint(env, argv[1], &idx))
        return enif_make_badarg(env);

    int rc = sqlite3_bind_null(stmt->stmt, idx);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_reset(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    int rc = sqlite3_reset(stmt->stmt);
    return enif_make_int(env, rc);
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
        return enif_make_list(env, 2, make_cell(env, stmt, 0),
                              make_cell(env, stmt, 1));
    case 3:
        return enif_make_list(env, 3, make_cell(env, stmt, 0),
                              make_cell(env, stmt, 1), make_cell(env, stmt, 2));
    case 4:
        return enif_make_list(env, 4, make_cell(env, stmt, 0),
                              make_cell(env, stmt, 1), make_cell(env, stmt, 2),
                              make_cell(env, stmt, 3));
    case 5:
        return enif_make_list(env, 5, make_cell(env, stmt, 0),
                              make_cell(env, stmt, 1), make_cell(env, stmt, 2),
                              make_cell(env, stmt, 3), make_cell(env, stmt, 4));
    case 6:
        return enif_make_list(env, 6, make_cell(env, stmt, 0),
                              make_cell(env, stmt, 1), make_cell(env, stmt, 2),
                              make_cell(env, stmt, 3), make_cell(env, stmt, 4),
                              make_cell(env, stmt, 5));
    case 7:
        return enif_make_list(env, 7, make_cell(env, stmt, 0),
                              make_cell(env, stmt, 1), make_cell(env, stmt, 2),
                              make_cell(env, stmt, 3), make_cell(env, stmt, 4),
                              make_cell(env, stmt, 5), make_cell(env, stmt, 6));
    case 8:
        return enif_make_list(env, 8, make_cell(env, stmt, 0),
                              make_cell(env, stmt, 1), make_cell(env, stmt, 2),
                              make_cell(env, stmt, 3), make_cell(env, stmt, 4),
                              make_cell(env, stmt, 5), make_cell(env, stmt, 6),
                              make_cell(env, stmt, 7));
    case 9:
        return enif_make_list(env, 9, make_cell(env, stmt, 0),
                              make_cell(env, stmt, 1), make_cell(env, stmt, 2),
                              make_cell(env, stmt, 3), make_cell(env, stmt, 4),
                              make_cell(env, stmt, 5), make_cell(env, stmt, 6),
                              make_cell(env, stmt, 7), make_cell(env, stmt, 8));
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
    assert(argc == 1);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    int rc = sqlite3_step(stmt->stmt);

    switch (rc)
    {
    case SQLITE_ROW:
    {
        unsigned int column_count = sqlite3_column_count(stmt->stmt);
        ERL_NIF_TERM row = make_row(env, column_count, stmt->stmt);
        return enif_make_tuple2(env, am_row, row);
    }

    case SQLITE_DONE:
        return am_done;

    default:
        return enif_make_int(env, rc);
    }
}

static ERL_NIF_TERM
xqlite_multi_step(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 2);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    unsigned int steps;
    if (!enif_get_uint(env, argv[1], &steps))
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
            // TODO don't lose rc
            sqlite3_reset(stmt->stmt);
            return enif_make_int(env, rc);
        }
    }

    return enif_make_tuple2(env, am_rows, rows);
}

static ERL_NIF_TERM
xqlite_interrupt(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    sqlite3_interrupt(db->db);
    return am_ok;
}

static ERL_NIF_TERM
xqlite_finalize(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

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
    assert(argc == 3);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    int stmt_param_count = (unsigned int)sqlite3_bind_parameter_count(stmt->stmt);
    int types_array[stmt_param_count];

    ERL_NIF_TERM types = argv[1];
    ERL_NIF_TERM rows = argv[2];
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

    int rc = SQLITE_OK;

    // process rows
    while (enif_get_list_cell(env, rows, &head, &tail))
    {
        // TODO dont lose rc
        sqlite3_reset(stmt->stmt);

        // bind row
        for (unsigned int i = 1; i <= stmt_param_count; i++)
        {
            ERL_NIF_TERM param;

            if (!enif_get_list_cell(env, head, &param, &head))
                return enif_make_badarg(env);

            if (enif_is_identical(param, am_nil))
            {
                rc = sqlite3_bind_null(stmt->stmt, i);
            }
            else
            {
                switch (types_array[i - 1])
                {
                case SQLITE_INTEGER:
                {
                    int i32;
                    ErlNifSInt64 i64;

                    if (enif_get_int(env, param, &i32))
                    {
                        rc = sqlite3_bind_int(stmt->stmt, i, i32);
                        break;
                    }
                    else if (enif_get_int64(env, param, &i64))
                    {
                        rc = sqlite3_bind_int64(stmt->stmt, i, i64);
                        break;
                    }
                    else
                    {
                        return enif_make_badarg(env);
                    }
                }

                case SQLITE_FLOAT:
                {
                    double f64;
                    if (!enif_get_double(env, param, &f64))
                        return enif_make_badarg(env);

                    rc = sqlite3_bind_double(stmt->stmt, i, f64);
                    break;
                }

                case SQLITE_TEXT:
                {
                    ErlNifBinary text;
                    if (!enif_inspect_binary(env, param, &text))
                        return enif_make_badarg(env);

                    rc = sqlite3_bind_text(stmt->stmt, i, (char *)text.data, text.size, SQLITE_TRANSIENT);
                    break;
                }

                case SQLITE_BLOB:
                {
                    ErlNifBinary blob;
                    if (!enif_inspect_binary(env, param, &blob))
                        return enif_make_badarg(env);

                    rc = sqlite3_bind_blob(stmt->stmt, i, (char *)blob.data, blob.size, SQLITE_TRANSIENT);
                    break;
                }
                }
            }

            if (rc != SQLITE_OK)
                return enif_make_int(env, rc);
        }

        rc = sqlite3_step(stmt->stmt);
        if (rc != SQLITE_DONE)
            return enif_make_int(env, rc);

        rows = tail;
    }

    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_fetch_all(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
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
            sqlite3_reset(stmt->stmt);
            return rows;

        case SQLITE_ROW:
            row = make_row(env, column_count, stmt->stmt);
            rows = enif_make_list_cell(env, row, rows);
            break;

        default:
            sqlite3_reset(stmt->stmt);
            return enif_make_int(env, rc);
        }
    }
}

static ERL_NIF_TERM
xqlite_changes64(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    sqlite_int64 changes = sqlite3_changes64(db->db);
    return enif_make_int64(env, changes);
}

static ERL_NIF_TERM
xqlite_total_changes64(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    sqlite_int64 total_changes = sqlite3_total_changes64(db->db);
    return enif_make_int64(env, total_changes);
}

static ERL_NIF_TERM
xqlite_clear_bindings(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    int rc = sqlite3_clear_bindings(stmt->stmt);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_enable_load_extension(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 2);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    int onoff;
    if (!enif_get_int(env, argv[1], &onoff))
        return enif_make_badarg(env);

    int rc = sqlite3_enable_load_extension(db->db, onoff);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_sql(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    const char *sql = sqlite3_sql(stmt->stmt);
    return make_binary(env, (unsigned char *)sql, strlen(sql));
}

static ERL_NIF_TERM
xqlite_expanded_sql(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    const char *sql = sqlite3_expanded_sql(stmt->stmt);
    ERL_NIF_TERM bin = make_binary(env, (unsigned char *)sql, strlen(sql));
    sqlite3_free((void *)sql);
    return bin;
}

static ERL_NIF_TERM
xqlite_get_autocommit(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    int autocommit = sqlite3_get_autocommit(db->db);
    return enif_make_int(env, autocommit);
}

static ERL_NIF_TERM
xqlite_last_insert_rowid(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    sqlite3_int64 last_insert_rowid = sqlite3_last_insert_rowid(db->db);
    return enif_make_int64(env, last_insert_rowid);
}

static ERL_NIF_TERM
xqlite_memory_used(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 0);
    sqlite3_int64 memory_used = sqlite3_memory_used();
    return enif_make_int64(env, memory_used);
}

static ERL_NIF_TERM
xqlite_column_count(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    int column_count = sqlite3_column_count(stmt->stmt);
    return enif_make_int(env, column_count);
}

static ERL_NIF_TERM
xqlite_column_name(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 2);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    int idx;
    if (!enif_get_int(env, argv[1], &idx))
        return enif_make_badarg(env);

    const char *name = sqlite3_column_name(stmt->stmt, idx);
    if (!name)
        return am_nil;

    return make_binary(env, (unsigned char *)name, strlen(name));
}

static ERL_NIF_TERM
xqlite_column_names(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    int column_count = sqlite3_column_count(stmt->stmt);
    ERL_NIF_TERM columns[column_count];

    for (unsigned int i = 0; i < column_count; i++)
    {
        const char *name = sqlite3_column_name(stmt->stmt, i);
        if (!name)
        {
            columns[i] = am_nil;
        }
        else
        {
            columns[i] = make_binary(env, (unsigned char *)name, strlen(name));
        }
    }

    return enif_make_list_from_array(env, columns, column_count);
}

static ERL_NIF_TERM
xqlite_bind_parameter_count(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    int bind_parameter_count = sqlite3_bind_parameter_count(stmt->stmt);
    return enif_make_int(env, bind_parameter_count);
}

static ERL_NIF_TERM
xqlite_bind_parameter_index(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 2);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    ErlNifBinary name;
    if (!enif_inspect_binary(env, argv[1], &name))
        return enif_make_badarg(env);

    int idx = sqlite3_bind_parameter_index(stmt->stmt, (char *)name.data);
    return enif_make_int(env, idx);
}

static ERL_NIF_TERM
xqlite_bind_parameter_name(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 2);

    stmt_t *stmt;
    if (!enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
        return enif_make_badarg(env);

    int idx;
    if (!enif_get_int(env, argv[1], &idx))
        return enif_make_badarg(env);

    const char *name = sqlite3_bind_parameter_name(stmt->stmt, idx);
    if (!name)
        return am_nil;

    return make_binary(env, (unsigned char *)name, strlen(name));
}

static ERL_NIF_TERM
xqlite_exec(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 2);

    db_t *db;
    if (!enif_get_resource(env, argv[0], db_type, (void **)&db))
        return enif_make_badarg(env);

    ErlNifBinary sql;
    if (!enif_inspect_binary(env, argv[1], &sql))
        return enif_make_badarg(env);

    int rc = sqlite3_exec(db->db, (char *)sql.data, NULL, NULL, NULL);
    return enif_make_int(env, rc);
}

static ERL_NIF_TERM
xqlite_errstr(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    int rc;
    if (!enif_get_int(env, argv[0], &rc))
        return enif_make_badarg(env);

    const char *msg = sqlite3_errstr(rc);
    return make_binary(env, (unsigned char *)msg, strlen(msg));
}

static ERL_NIF_TERM
xqlite_errmsg(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    assert(argc == 1);

    db_t *db;
    stmt_t *stmt;
    const char *msg;

    if (enif_get_resource(env, argv[0], db_type, (void **)&db))
    {
        msg = sqlite3_errmsg(db->db);
    }
    else if (enif_get_resource(env, argv[0], stmt_type, (void **)&stmt))
    {
        msg = sqlite3_errmsg(sqlite3_db_handle(stmt->stmt));
    }
    else
    {
        return enif_make_badarg(env);
    }

    if (!msg)
        return am_nil;

    return make_binary(env, (unsigned char *)msg, strlen(msg));
}

static ErlNifFunc nif_funcs[] = {
    {"dirty_io_open_nif", 2, xqlite_open, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"dirty_io_close_nif", 1, xqlite_close, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"dirty_io_close_v2_nif", 1, xqlite_close_v2, ERL_NIF_DIRTY_JOB_IO_BOUND},

    {"prepare_nif", 3, xqlite_prepare, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"finalize", 1, xqlite_finalize, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"reset", 1, xqlite_reset, ERL_NIF_DIRTY_JOB_CPU_BOUND},

    {"bind_parameter_count", 1, xqlite_bind_parameter_count},
    {"bind_parameter_index_nif", 2, xqlite_bind_parameter_index},
    {"bind_parameter_name", 2, xqlite_bind_parameter_name},
    {"bind_text", 3, xqlite_bind_text},
    {"bind_blob", 3, xqlite_bind_blob},
    {"bind_integer", 3, xqlite_bind_integer},
    {"bind_float", 3, xqlite_bind_float},
    {"bind_null", 2, xqlite_bind_null},
    {"clear_bindings_nif", 1, xqlite_clear_bindings},

    {"step", 1, xqlite_step, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"unsafe_step", 1, xqlite_step},
    {"dirty_io_step_nif", 2, xqlite_multi_step, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"step_nif", 2, xqlite_multi_step},
    {"exec_nif", 2, xqlite_exec, ERL_NIF_DIRTY_JOB_IO_BOUND},

    {"get_autocommit", 1, xqlite_get_autocommit},

    {"interrupt", 1, xqlite_interrupt},

    {"dirty_io_fetch_all_nif", 1, xqlite_fetch_all, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"dirty_io_insert_all_nif", 3, xqlite_insert_all, ERL_NIF_DIRTY_JOB_IO_BOUND},

    {"column_count", 1, xqlite_column_count},
    {"column_name", 2, xqlite_column_name},
    {"column_names", 1, xqlite_column_names},

    {"changes", 1, xqlite_changes64},
    {"total_changes", 1, xqlite_total_changes64},
    {"last_insert_rowid", 1, xqlite_last_insert_rowid},

    {"enable_load_extension_nif", 2, xqlite_enable_load_extension},

    {"sql", 1, xqlite_sql},
    {"expanded_sql", 1, xqlite_expanded_sql},

    {"memory_used", 0, xqlite_memory_used},
    {"errstr", 1, xqlite_errstr},
    {"errmsg", 1, xqlite_errmsg},
};

ERL_NIF_INIT(Elixir.XQLite, nif_funcs, on_load, NULL, NULL, on_unload)
