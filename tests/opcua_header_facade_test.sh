#!/usr/bin/env bash
set -euo pipefail
repo=${1:?repository required}
work=$(mktemp -d "${TMPDIR:?}/opcua-header.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
printf '#include <cpkt/opcua.h>\nint main(void) { cpkt_opcua_value value; cpkt_opcua_value_clear(&value); return value.type; }\n' > "$work/header.c"
printf '#include <cpkt/opcua.h>\nint main() { cpkt_opcua_node_id id=cpkt_opcua_node_id_null(); return id.identifier_type; }\n' > "$work/header.cpp"
"${CC:?selected C compiler required}" -std=c89 -Wall -Wextra -Wpedantic -Werror -I "$repo/include" -c "$work/header.c" -o "$work/header.o"
"${CXX:?selected C++ compiler required}" -std=c++98 -Wall -Wextra -Wpedantic -Werror -I "$repo/include" -c "$work/header.cpp" -o "$work/header-cpp.o"
