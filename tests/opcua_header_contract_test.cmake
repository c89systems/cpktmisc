include("${CMAKE_CURRENT_LIST_DIR}/test-context.cmake")
set(work "${CPKT_SCRATCH}/header-contract")
file(MAKE_DIRECTORY "${work}")
file(READ "${CPKT_SCRATCH}/CMakeCache.txt" cache)
string(REGEX MATCH "CMAKE_CROSSCOMPILING_EMULATOR:STRING=([^\n]*)" match "${cache}")
set(runner "${CMAKE_MATCH_1}")
set(check ${runner} "${CPKT_SCRATCH}/cpkt_header_contract")
set(valid [=[/** Native UA_Server_run takes long long internally. */
// inline uint64_t and <open62541/types.h> are documentation.
typedef struct { long longValue; unsigned long ulongValue; } cpkt_pair;
#define CPKT_LABEL "UA_Server inline long long /* a literal */ // text"
#define CPKT_QUOTE "\" UA_NodeId"
#define CPKT_CHARACTER '\''
#include <stddef.h>
]=])
file(WRITE "${work}/api.h" "${valid}")
cpkt_test_command(${check} "${work}/api.h")
foreach(invalid "#include <open62541/types.h>" "#include \"stdint.h\"" "#include <stdbool.h>"
    "UA_Server *root\;" "#define CPKT_ALIAS UA_Client" "static inline int f(void)\;"
    "uint64_t value\;" "int64_t value\;" "_Bool enabled\;" "unsigned long\tlong value\;"
    "long/**/long value\;" "UA_\\\nNodeId value\;")
  file(WRITE "${work}/api.h" "${valid}\n${invalid}\n")
  cpkt_test_failure("forbidden C89 facade token|upstream/non-C89 include" ${check} "${work}/api.h")
endforeach()
file(GLOB headers "${CPKT_ROOT}/include/cpkt/opcua*.h" "${CPKT_SCRATCH}/generated/opcua/cpkt/*.h")
cpkt_test_command(${check} ${headers})
