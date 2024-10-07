SRC = c_src/sqlite3.c c_src/xqlite_nif.c
CFLAGS = -Ic_src -I"$(ERTS_INCLUDE_DIR)"

KERNEL_NAME := $(shell uname -s)
PRIV = $(MIX_APP_PATH)/priv
BUILD  = $(MIX_APP_PATH)/obj
LIB = $(PRIV)/xqlite_nif.so
OBJ = $(SRC:c_src/%.c=$(BUILD)/%.o)

ifeq ($(MIX_ENV), dev)
    CFLAGS += -g
    CXXFLAGS += -g
else ifeq ($(MIX_ENV), test)
    CFLAGS += -g
    CXXFLAGS += -g
else
	CFLAGS += -O3 -DNDEBUG=1
	CXXFLAGS += -O3 -DNDEBUG=1
endif

ifeq ($(KERNEL_NAME), Linux)
	CFLAGS += -fPIC -fvisibility=hidden
	LDFLAGS += -fPIC -shared
endif
ifeq ($(KERNEL_NAME), Darwin)
	CFLAGS += -fPIC
	LDFLAGS += -dynamiclib -undefined dynamic_lookup
endif

CFLAGS += -DSQLITE_THREADSAFE=1
CFLAGS += -DSQLITE_USE_URI=1
CFLAGS += -DSQLITE_LIKE_DOESNT_MATCH_BLOBS=1
CFLAGS += -DSQLITE_DQS=0
CFLAGS += -DHAVE_USLEEP=1
CFLAGS += -DALLOW_COVERING_INDEX_SCAN=1
CFLAGS += -DENABLE_LOAD_EXTENSION=1
CFLAGS += -DENABLE_STAT4=1
CFLAGS += -DENABLE_UPDATE_DELETE_LIMIT=1
CFLAGS += -DSQLITE_ENABLE_MATH_FUNCTIONS=1
CFLAGS += -DSQLITE_OMIT_DEPRECATED=1
CFLAGS += -DSQLITE_ENABLE_DBSTAT_VTAB=1

all: $(PRIV) $(BUILD) $(LIB)

$(BUILD)/%.o: c_src/%.c
	@echo " CC $(notdir $@)"
	$(CC) -c $(ERL_CFLAGS) $(CFLAGS) -o $@ $<

$(LIB): $(OBJ)
	@echo " LD $(notdir $@)"
	$(CC) -o $@ $^ $(LDFLAGS)

$(PRIV) $(BUILD):
	mkdir -p $@

clean:
	$(RM) $(LIB) $(OBJ)

.PHONY: all clean

# Don't echo commands unless the caller exports "V=1"
${V}.SILENT:
