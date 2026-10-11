# Native AST data -> C89 enum and member probes. CMake owns compilation and
# assertions; this is independent of the facade generator and its report.
def members($path):
  reduce .inner[]? as $item ({record: null, fields: []};
    if $item.kind == "RecordDecl" then .record = $item
    elif $item.kind == "FieldDecl" then
      .fields += [{field: $item, record:
        (if ($item.type.qualType | test("anonymous|unnamed")) then .record else null end)}]
    else . end) |
  .fields[] |
  ($path + (.field.name // "trampoline") +
    (if .record != null and (.field.type.qualType | test("\\[")) then "[0]" else "" end)) as $member |
  $member, (select(.record != null) | .record | members($member + "."));

.inner as $nodes |
[$nodes[] | select(.kind == "TypedefDecl" and (.name | test($family))) |
  .. | objects | select(.kind == "EnumType") | .decl.id] as $enum_ids |
(
  $nodes[] | select(.kind == "EnumDecl") |
  select((.id as $id | $enum_ids | index($id)) != null or
    any(.inner[]?; .kind == "EnumConstantDecl" and (.name | test($constants)))) |
  reduce (.inner[]? | select(.kind == "EnumConstantDecl")) as $member
    ({value: -1, probes: []};
      .value = ([$member | .. | objects | select(.kind == "ConstantExpr") | .value | tonumber][0] // (.value + 1)) |
      .probes += ["typedef char cpkt_enum_probe_\($member.name)[(\($prefix)\($member.name) == (\(.value))) ? 1 : -1];"]) |
  .probes[]
),
(
  $nodes[] | select(.kind == "TypedefDecl" and (.name | test($family))) as $type |
  select(($type.type.qualType | test("[*(]")) | not) |
  [$type | .. | objects | select(.kind == "RecordType") | .decl.id][0] as $id |
  $nodes[] | select(.kind == "RecordDecl" and .id == $id) as $record |
  (if $record.completeDefinition then $record
   else $nodes[] | select(.kind == "RecordDecl" and .name == $record.name and .completeDefinition) end) |
  members("") as $member |
  ($member | gsub("[^A-Za-z0-9_]"; "_")) as $identifier |
  "typedef char cpkt_field_probe_\($type.name)_\($identifier)[sizeof(((\($type_prefix)\($type.name) *)0)->\($member)) ? 1 : -1];"
)
