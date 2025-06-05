KERNEL_NAME := $(shell uname -s)
PRIV = $(MIX_APP_PATH)/priv
BUILD  = $(MIX_APP_PATH)/obj
LIB = $(PRIV)/xqlite.so

XQLITE_CFLAGS ?=
XQLITE_LDFLAGS ?=

CFLAGS = -Ic_src -I"$(ERTS_INCLUDE_DIR)" -fPIC -pedantic -Wall -Wextra -Werror \
	-Wno-unused-parameter -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable \
	-Wno-unused-value -Wno-unused-label -Wno-unused-result -Wno-unused-local-typedefs

ifeq ($(MIX_ENV), dev)
	CFLAGS += -g
else ifeq ($(MIX_ENV), test)
	CFLAGS += -g
else
	CFLAGS += -O3 -DNDEBUG
endif

ifeq ($(KERNEL_NAME), Darwin)
	LDFLAGS += -dynamiclib -undefined dynamic_lookup
else ifeq ($(KERNEL_NAME), Linux)
	LDFLAGS += -shared
else
	$(error Unsupported operating system $(KERNEL_NAME))
endif

# TODO
# CFLAGS += -DSQLITE_THREADSAFE=1
# CFLAGS += -DSQLITE_USE_URI=1
# CFLAGS += -DSQLITE_LIKE_DOESNT_MATCH_BLOBS=1
# CFLAGS += -DSQLITE_DQS=0
# CFLAGS += -DHAVE_USLEEP=1
# CFLAGS += -DALLOW_COVERING_INDEX_SCAN=1
# CFLAGS += -DENABLE_LOAD_EXTENSION=1
# CFLAGS += -DENABLE_STAT4=1
# CFLAGS += -DENABLE_UPDATE_DELETE_LIMIT=1
# CFLAGS += -DSQLITE_ENABLE_MATH_FUNCTIONS=1
# CFLAGS += -DSQLITE_OMIT_DEPRECATED=1
# CFLAGS += -DSQLITE_ENABLE_DBSTAT_VTAB=1

all: $(PRIV) $(BUILD) $(LIB)

$(PRIV) $(BUILD):
	mkdir -p $@

$(BUILD)/sqlite3.o: c_src/sqlite3.c
	@echo " CC $(notdir $@)"
	$(CC) $(CFLAGS) $(XQLITE_CFLAGS) -c c_src/sqlite3.c -o $@

$(BUILD)/xqlite.o: c_src/xqlite.c
	@echo " CC $(notdir $@)"
	$(CC) $(CFLAGS) $(XQLITE_CFLAGS) -c c_src/xqlite.c -o $@

$(LIB): $(BUILD)/xqlite.o $(BUILD)/sqlite3.o
	@echo " LD $(notdir $@)"
	$(CC) $(BUILD)/sqlite3.o $(BUILD)/xqlite.o $(LDFLAGS) $(XQLITE_LDFLAGS) -o $@

clean:
	$(RM) $(LIB) $(OBJ)

.PHONY: all clean

# Don't echo commands unless the caller exports "V=1"
${V}.SILENT:
