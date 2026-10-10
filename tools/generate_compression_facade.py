#!/usr/bin/env python3
"""Generate a full public C89 facade and coverage data from pinned Clang ASTs.

This is a source/data generator. CMake owns invocation, build, install and
verification; CTest owns completeness and behavioral assertions.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from generated_output_paths import validate_output_paths, write_generated_text

ARCHIVE_MANUAL = {
    'archive_read_set_skip_callback', 'archive_read_set_seek_callback', 'archive_read_open2',
    'archive_free', 'archive_read_free', 'archive_write_free', 'archive_read_finish', 'archive_write_finish',
    'archive_write_disk_set_group_lookup', 'archive_write_disk_set_user_lookup',
    'archive_read_disk_set_gname_lookup', 'archive_read_disk_set_uname_lookup', 'archive_set_error',
}

def children(node):
    return [item for item in node.get('inner', []) if not item['kind'].endswith('Comment')]


def find_decl(node, kinds):
    if node.get('kind') in kinds and 'decl' in node:
        return node['decl']['id']
    for item in children(node):
        result = find_decl(item, kinds)
        if result:
            return result
    return None


def integer_value(node):
    if node.get('kind') in ('ConstantExpr', 'IntegerLiteral') and 'value' in node:
        return int(node['value'])
    for item in children(node):
        result = integer_value(item)
        if result is not None:
            return result
    return None


def alignment_decoration(node):
    values = [integer_value(item) for item in children(node) if item['kind'] == 'AlignedAttr']
    if any(value is None for value in values):
        raise ValueError('Unresolved public alignment attribute on ' + node.get('name', node['kind']))
    return ' __attribute__((aligned(' + str(max(values)) + ')))' if values else ''


def declaration(type_name, name):
    if '(*)' in type_name:
        return type_name.replace('(*)', '(*' + name + ')', 1)
    match = re.search(r'(\[[^]]*\].*)$', type_name)
    if match:
        return type_name[:match.start()].rstrip() + ' ' + name + match[1]
    if '(' in type_name:
        index = type_name.index('(')
        return type_name[:index].rstrip() + ' ' + name + type_name[index:]
    return type_name + ' ' + name


class Generator:
    def __init__(self, args):
        self.args = args
        self.prefix = 'cpkt_' + args.library + '_'
        self.guard = 'CPKT_' + args.library.upper()
        self.headers = {
            'zstd': ['zstd.h', 'zdict.h', 'zstd_errors.h'],
            'ffi': ['ffi.h'],
            'lz4': ['lz4.h', 'lz4hc.h', 'lz4frame.h', 'lz4file.h'],
            'archive': ['archive.h', 'archive_entry.h'],
            'lzma': ['lzma.h'],
            'lzo': ['lzo/' + name + '.h' for name in ('lzo1', 'lzo1a', 'lzo1b', 'lzo1c', 'lzo1f',
                     'lzo1x', 'lzo1y', 'lzo1z', 'lzo2a', 'lzo_asm', 'lzoutil')],
        }[args.library]
        self.family = {'zstd': r'^(ZSTD|ZDICT)_', 'ffi': r'^ffi_',
                       'lz4': r'^(LZ4|blockSizeID_t$|blockMode_t$|frameType_t$|contentChecksum_t$)',
                       'archive': r'^(archive_|la_)', 'lzma': r'^lzma_',
                       'lzo': r'^(lzo_|lzo[12]|_+lzo_)'}[args.library]
        self.macro_family = {'zstd': r'(?:ZSTD|ZDICT)_', 'ffi': r'(?:FFI_|ffi_type_)',
                             'lz4': r'LZ4\w*', 'archive': r'(?:ARCHIVE_|AE_)',
                             'lzma': r'(?:LZMA_|lzma_)', 'lzo': r'(?:LZO\w*|lzo_)'}[args.library]
        self.defines = {'zstd': '#define ZSTD_STATIC_LINKING_ONLY\n#define ZDICT_STATIC_LINKING_ONLY\n',
                        'ffi': '',
                        'lz4': '#define LZ4_STATIC_LINKING_ONLY\n#define LZ4_HC_STATIC_LINKING_ONLY\n'
                               '#define LZ4F_STATIC_LINKING_ONLY\n#define LZ4F_ENABLE_OBSOLETE_ENUMS\n',
                        'archive': '', 'lzma': '', 'lzo': ''}[args.library]
        self.input = self.defines + ''.join('#include <' + h + '>\n' for h in self.headers)
        command = [args.clang, '-x', 'c', '-std=c99', '-Wno-deprecated-declarations',
                   '-I', str(args.include)] + args.clang_argument
        ast = subprocess.run(command + ['-fsyntax-only', '-Xclang', '-ast-dump=json', '-'],
                             input=self.input, text=True, capture_output=True)
        if ast.returncode:
            raise ValueError('Public AST generation failed:\n' + ast.stderr)
        self.ast = json.loads(ast.stdout)
        self.nodes = self.ast['inner']
        self.by_id = {n['id']: n for n in self.nodes}
        self.system_typedefs = {n['name']: n['type'].get('desugaredQualType', n['type']['qualType'])
                                for n in self.nodes if n['kind'] == 'TypedefDecl'}
        self.unsigned_words = {'unsigned long long', 'uint64_t'}
        self.signed_words = {'long long', 'int64_t'}
        if args.library == 'lzma':
            self.unsigned_words.add('lzma_vli')
        if args.library == 'lzo':
            self.unsigned_words |= {'lzo_uint64_t', 'lzo_uint64', 'lzo_ullong_t__'}
            self.signed_words |= {'lzo_int64_t', 'lzo_int64', 'lzo_llong_t__'}
        if args.library == 'archive':
            self.unsigned_words |= {'la_uint64_t', 'dev_t'}
            self.signed_words |= {'la_int64_t', 'time_t'}
            self.system_typedefs['__LA_MODE_T'] = 'mode_t'
        self.stat_definitions = []
        self.stat_native_types = {}
        self.stat_private_aliases = {}
        if args.library == 'archive':
            def stat_definition(tag, node=None, native_type=None):
                if any(d[0] == tag for d in self.stat_definitions):
                    return
                if node is None:
                    node = next((n for n in self.nodes if n['kind'] == 'RecordDecl'
                                 and n.get('name') == tag and n.get('completeDefinition')), None)
                    if node is None:
                        raise ValueError('Missing native stat record definition: ' + tag)
                self.stat_native_types[tag] = native_type or 'struct ' + tag
                fields = []
                anonymous = None
                anonymous_tag = None
                for field in children(node):
                    if field['kind'] == 'RecordDecl' and not field.get('name'):
                        anonymous = field
                        anonymous_tag = None
                    if field['kind'] != 'FieldDecl':
                        continue
                    if field.get('isBitfield') and not field.get('name'):
                        # musl timespec uses unnamed padding bitfields. These
                        # have no public value; field-wise conversion already
                        # lets each native record retain its own padding.
                        continue
                    if not field.get('name'):
                        raise ValueError('Unsupported anonymous stat field in ' + tag)
                    native = field['type']['qualType']
                    public = native
                    if 'unnamed' in native or 'anonymous' in native:
                        if anonymous is None:
                            raise ValueError('Missing anonymous stat record: ' + tag + '.' + field['name'])
                        if anonymous_tag is None:
                            anonymous_tag = tag + '_' + field['name']
                            alias = 'cpkt_archive_native_' + anonymous_tag
                            self.stat_private_aliases[alias] = ('__typeof__(((' + self.stat_native_types[tag]
                                                               + ' *)0)->' + field['name'] + ')')
                            stat_definition(anonymous_tag, anonymous, alias)
                        native = public = 'struct ' + anonymous_tag
                    elif native.startswith('struct '):
                        stat_definition(native.split()[1])
                    elif field['name'] in ('st_dev', 'st_rdev', 'st_ino', 'st_nlink'):
                        public = 'uint64_t'
                    elif field['name'] in ('st_size', 'st_blocks', 'st_atime', 'st_mtime', 'st_ctime', 'tv_sec'):
                        public = 'int64_t'
                    fields.append((field['name'], native, public))
                self.stat_definitions.append((tag, fields))
            stat_definition('stat')
        self.typedefs = {n['name']: n for n in self.nodes if n['kind'] == 'TypedefDecl'
                         and re.match(self.family, n['name'])}
        if args.library == 'lzo':
            self.typedefs = {name: node for name, node in self.typedefs.items() if not name.endswith('__')}
        self.functions = {n['name']: n for n in self.nodes if n['kind'] == 'FunctionDecl'
                          and re.match(self.family, n['name'])}
        self.variables = {n['name']: n for n in self.nodes if n['kind'] == 'VarDecl'
                          and re.match(self.family, n['name'])}
        if args.library == 'lzo':
            self.variables = {name: node for name, node in self.variables.items() if not name.startswith('lzo_cta__')}
        self.records = {}
        self.enums = {}
        for name, node in self.typedefs.items():
            if '*' in node['type']['qualType'] or '(' in node['type']['qualType']:
                continue
            record_id = find_decl(node, ('RecordType', 'EnumType'))
            record = self.by_id.get(record_id)
            if record and record['kind'] == 'RecordDecl' and record.get('name'):
                record = next((n for n in self.nodes if n['kind'] == 'RecordDecl'
                               and n.get('name') == record['name'] and n.get('completeDefinition')), record)
            if record and record['kind'] == 'RecordDecl' and record.get('completeDefinition'):
                self.records[name] = record
            elif record and record['kind'] == 'EnumDecl':
                self.enums[name] = record
        self.converted = set()
        if args.library == 'lzma':
            self.converted.add('lzma_index_iter')
        elif args.library == 'lzo':
            self.converted.add('lzo_align_t')
        self.used_converters = set()
        if args.library == 'lzma':
            self.used_converters |= {(name, direction) for name in ('lzma_filter', 'lzma_stream', 'lzma_block')
                                     for direction in (True, False)}
        self.type_aliases = {}
        definitions = {}
        for name in self.typedefs:
            record = self.records.get(name) or self.enums.get(name)
            if record:
                if record['id'] in definitions:
                    self.type_aliases[name] = definitions[record['id']]
                else:
                    definitions[record['id']] = name
        while True:
            added = {name for name, node in self.records.items()
                     if any(self.needs_conversion(f['type']['qualType'])
                            for f in children(node) if f['kind'] == 'FieldDecl')}
            if added <= self.converted:
                break
            self.converted |= added
        self.mapping = {name: self.prefix + name for name in self.typedefs}
        self.mapping.update({name: self.prefix + name for name in self.functions})
        self.mapping.update({name: self.prefix + name for name in self.variables})
        self.constants = {}
        for record in self.enums.values():
            for member in children(record):
                if member['kind'] == 'EnumConstantDecl':
                    self.mapping[member['name']] = self.guard + '_' + member['name']
        pp = subprocess.run(command + ['-E', '-dM', '-'], input=self.input,
                            text=True, capture_output=True)
        if pp.returncode:
            raise ValueError('Public macro generation failed:\n' + pp.stderr)
        for line in pp.stdout.splitlines():
            match = re.match(r'#define (' + self.macro_family + r'\w+)(\([^\n]*?\))?\s*(.*)', line)
            if match:
                name, parameters, value = match.groups()
                if re.search(r'(?:_H(?:_|$)|STATIC_LINKING_ONLY$)', name):
                    continue
                if args.library == 'ffi' and name in ('FFI_64_BIT_MAX', 'FFI_LONG_LONG_MAX'):
                    # Compiler probes/alias selection already chose target ABI
                    # types. These internal preprocessor helpers are not API.
                    continue
                self.constants[name] = (parameters or '', value)
                self.mapping[name] = self.guard + '_' + name
        if args.library == 'lzo':
            internal = dict(re.findall(r'^#define (__LZO_\w+)[ \t]+([^\n]*)$', pp.stdout, re.M))
            for name, (parameters, value) in self.constants.items():
                for _ in range(len(internal)):
                    replaced = re.sub(r'\b__LZO_\w+\b', lambda m: internal.get(m[0], m[0]), value)
                    if replaced == value:
                        break
                    value = replaced
                value = value.replace('__lzo_cdecl', '').replace('__lzo_cte(0)', '(0)')
                self.constants[name] = (parameters, value)

    def needs_conversion(self, value):
        return bool(any(re.search(r'\b' + re.escape(word) + r'\b', value)
                        for word in self.unsigned_words | self.signed_words) or
                    any(re.search(r'\b' + re.escape(name) + r'\b', value)
                        for name in self.converted))

    def public_type(self, value):
        if self.args.library == 'archive':
            for tag, _ in self.stat_definitions:
                value = re.sub(r'\bstruct ' + re.escape(tag) + r'\b', 'cpkt_archive_' + tag, value)
        for native in sorted(self.unsigned_words, key=len, reverse=True):
            value = re.sub(r'\b' + re.escape(native) + r'\b', 'cpkt_compression_u64', value)
        for native in sorted(self.signed_words, key=len, reverse=True):
            value = re.sub(r'\b' + re.escape(native) + r'\b', 'cpkt_compression_i64', value)
        for native, public in {'int8_t': 'signed char', 'uint8_t': 'unsigned char',
                               'int16_t': 'short', 'uint16_t': 'unsigned short',
                               'int32_t': 'int', 'uint32_t': 'unsigned int'}.items():
            value = re.sub(r'\b' + native + r'\b', public, value)
        def replace(match):
            if match[1]:
                return match[0]
            token = match[0]
            if token in self.mapping:
                return self.mapping[token]
            if token in self.system_typedefs and token not in ('size_t', 'wchar_t', 'va_list'):
                expanded = self.system_typedefs[token]
                if expanded != token and '(' not in expanded:
                    return self.public_type(expanded)
            return token
        return re.sub(r'\b(struct|union|enum)\s+\w+|\b[A-Za-z_]\w*\b', replace, value)

    def word(self, expression):
        return self.prefix + 'word_from_native(' + expression + ')'

    def native_word(self, expression):
        return self.prefix + 'word_to_native(' + expression + ')'

    def convert(self, value, expression, to_native):
        clean = re.sub(r'\bconst\b|\bvolatile\b', '', value).strip()
        if clean in self.unsigned_words:
            return self.native_word(expression) if to_native else self.word(expression)
        if clean in self.signed_words:
            return self.prefix + ('signed_to_native(' if to_native else 'signed_from_native(') + expression + ')'
        if clean in self.converted:
            self.used_converters.add((clean, to_native))
            return self.prefix + ('to_' if to_native else 'from_') + clean + '(' + expression + ')'
        return expression

    def emit_types(self):
        output = []
        forward = set()
        for name, record in self.records.items():
            if not record.get('name') or name in self.type_aliases:
                continue
            tag = record['name']
            if name in self.converted:
                tag = self.prefix + tag
            else:
                output.append('#ifndef ' + self.guard + '_NATIVE_TYPES')
            output.append('typedef ' + record['tagUsed'] + ' ' + tag + ' ' + self.mapping[name]
                          + alignment_decoration(self.typedefs[name]) + ';')
            if name not in self.converted:
                output.append('#endif')
            forward.add(name)
        ordered = []
        pending = list(self.typedefs)
        while pending:
            for name in pending:
                node = self.typedefs[name]
                text = ' '.join(f['type']['qualType'] for f in children(self.records[name])
                                if f['kind'] == 'FieldDecl') if name in self.records else node['type']['qualType']
                dependencies = set(re.findall(r'\b\w+\b', text)) & set(self.typedefs)
                dependencies.discard(name)
                for dependency in forward:
                    if re.search(r'\b' + re.escape(dependency) + r'\s*\*', text):
                        dependencies.discard(dependency)
                if not (dependencies & set(pending)):
                    ordered.append(name)
                    pending.remove(name)
                    break
            else:
                raise ValueError('Unresolved public type dependency cycle: ' + ', '.join(pending))
        for name in ordered:
            node = self.typedefs[name]
            public = self.mapping[name]
            alias_alignment = alignment_decoration(node)
            converted = name in self.converted
            if not converted:
                if not self.needs_conversion(node['type']['qualType']):
                    output.append('#ifndef ' + self.guard + '_NATIVE_TYPES')
            if name in self.type_aliases:
                output.append('typedef ' + self.mapping[self.type_aliases[name]] + ' ' + public + alias_alignment + ';')
            elif name in self.records:
                record = self.records[name]
                tag = record.get('name', '')
                if tag and converted:
                    tag = self.prefix + tag
                if tag:
                    output += [record['tagUsed'] + ' ' + tag + ' {']
                else:
                    output.append('typedef ' + record['tagUsed'] + ' {')
                output += self.emit_fields(record)
                if self.args.library == 'lzma' and name == 'lzma_stream':
                    output.append('  void *cpkt_state; /* Private persistent native stream/block storage. */')
                if self.args.library == 'lzo' and name == 'lzo_align_t':
                    output.append('  double cpkt_alignment; /* Retains native 64-bit alignment on ARMv7. */')
                output.append('}' + alignment_decoration(record)
                              + (';' if tag else ' ' + public + alias_alignment + ';'))
            elif name in self.enums:
                output.append('enum {')
                value = -1
                members = [n for n in children(self.enums[name]) if n['kind'] == 'EnumConstantDecl']
                for index, member in enumerate(members):
                    explicit = integer_value(member)
                    value = value + 1 if explicit is None else explicit
                    output.append('  ' + self.mapping[member['name']] + ' = ' + str(value)
                                  + (',' if index + 1 < len(members) else ''))
                output.append('};')
                output.append('typedef ' + self.enum_integer(name) + ' ' + public + alias_alignment + ';')
            else:
                # Clang retains the complete callback signature and opaque tag.
                if '(' in node['type']['qualType']:
                    contracts = {
                        'archive_read_callback': 'Return a borrowed buffer and bytes read; the buffer stays valid until the next read callback.',
                        'archive_write_callback': 'Consume the borrowed chunk synchronously; return bytes accepted or a negative error.',
                        'archive_skip_callback': 'Return actual bytes skipped as a full-width signed value; partial skips are permitted.',
                        'archive_seek_callback': 'Seek using native whence; return the full-width new position or a negative error.',
                        'archive_passphrase_callback': 'Return a borrowed passphrase using the native client-data and retry contract.',
                    }
                    contract = contracts.get(name, 'Native callback ordering, status and client-data lifetime contracts apply.')
                    output.append('/** ' + contract + ' */')
                output.append('typedef ' + declaration(self.public_type(node['type']['qualType']), public) + alias_alignment + ';')
            if not converted and not self.needs_conversion(node['type']['qualType']):
                output.append('#endif')
                if name in self.enums and name not in self.type_aliases:
                    value = -1
                    output.append('#ifdef ' + self.guard + '_NATIVE_TYPES')
                    for member in children(self.enums[name]):
                        if member['kind'] != 'EnumConstantDecl':
                            continue
                        explicit = integer_value(member)
                        value = value + 1 if explicit is None else explicit
                        output.append('#define ' + self.mapping[member['name']] + ' ' + str(value))
                    output.append('#endif')
        return output

    def enum_integer(self, name):
        value = -1
        negative = False
        for member in children(self.enums[name]):
            if member['kind'] != 'EnumConstantDecl':
                continue
            explicit = integer_value(member)
            value = value + 1 if explicit is None else explicit
            negative |= value < 0
        return 'int' if negative else 'unsigned int'

    def emit_fields(self, record, indent='  '):
        output = []
        anonymous = None
        for field in children(record):
            if field['kind'] == 'RecordDecl' and not field.get('name'):
                anonymous = field
            elif field['kind'] == 'FieldDecl':
                if anonymous and ('anonymous' in field['type']['qualType'] or 'unnamed' in field['type']['qualType']):
                    # C89 names anonymous storage while retaining every native
                    # member and its layout, including libffi tramp/ftramp.
                    output.append(indent + anonymous['tagUsed'] + ' {')
                    output += self.emit_fields(anonymous, indent + '  ')
                    array = re.search(r'\[[^]]+\]$', field['type']['qualType'])
                    output.append(indent + '} ' + field.get('name', 'trampoline') + (array[0] if array else '') + ';')
                    anonymous = None
                else:
                    if self.args.library == 'lzo' and field['name'] == 'a10':
                        output.append(indent + 'cpkt_compression_u64 a10;')
                    elif self.args.library == 'lzma' and field['name'] == 'flags' and field['type']['qualType'] == 'const lzma_stream_flags *':
                        output += [indent + 'cpkt_lzma_lzma_stream_flags flags;', indent + 'int flags_present;']
                    else:
                        output.append(indent + declaration(self.public_type(field['type']['qualType']), field['name']) + ';')
        return output

    def emit_converters(self):
        output = []
        for name in self.records:
            if name not in self.converted:
                continue
            for to_native in (True, False):
                if (name, to_native) not in self.used_converters:
                    continue
                dest = name if to_native else self.mapping[name]
                source = self.mapping[name] if to_native else name
                function = self.prefix + ('to_' if to_native else 'from_') + name
                output += ['static ' + dest + ' ' + function + '(' + source + ' value) {',
                           '  ' + dest + ' result = {0};']
                output += self.convert_fields(self.records[name], 'result', 'value', to_native)
                output += ['  return result;', '}']
        return output

    def convert_fields(self, record, destination, source, to_native):
        output = []
        anonymous = None
        for field in children(record):
            if field['kind'] == 'RecordDecl' and not field.get('name'):
                anonymous = field
            if field['kind'] != 'FieldDecl':
                continue
            member = field['name']
            value = field['type']['qualType']
            dst, src = destination + '.' + member, source + '.' + member
            if anonymous and ('anonymous' in value or 'unnamed' in value):
                if anonymous['tagUsed'] == 'union':
                    output += ['  memcpy(&' + dst + ', &' + src + ', sizeof(' + dst + '));']
                else:
                    output += self.convert_fields(anonymous, dst, src, to_native)
                anonymous = None
            elif self.args.library == 'lzma' and value == 'const lzma_stream_flags *':
                if to_native:
                    output += ['  ' + dst + ' = NULL; /* Iterator flags are an output view. */']
                else:
                    converted = self.convert('lzma_stream_flags', '*' + src, False)
                    output += ['  if (' + src + ') ' + dst + ' = ' + converted + ';',
                               '  ' + destination + '.flags_present = ' + src + ' != NULL;']
            elif self.args.library == 'lzma' and re.fullmatch(r'(const )?lzma_filter \*', value):
                output += ['  ' + dst + ' = NULL; /* Call-boundary filter-array conversion supplies this pointer. */']
            elif '[' in value:
                if self.needs_conversion(value):
                    raise ValueError('Array conversion needs an explicit contract: ' + member)
                output += ['  memcpy(' + dst + ', ' + src + ', sizeof(' + dst + '));']
            else:
                output += ['  ' + dst + ' = ' + self.convert(value, src, to_native) + ';']
        return output

    def emit_function(self, name, node):
        result = node['type']['qualType'].split('(', 1)[0].strip()
        params = [n for n in children(node) if n['kind'] == 'ParmVarDecl']
        for index, param in enumerate(params):
            param['argument'] = param.get('name') or 'argument_' + str(index)
        if self.args.library == 'archive' and name == 'archive_entry_stat':
            signature = 'int cpkt_archive_archive_entry_stat(struct archive_entry *entry, cpkt_archive_stat *output)'
            return signature, [signature + ' {', '  const struct stat *value = archive_entry_stat(entry);',
                               '  if (!value || !output) return ARCHIVE_FATAL;',
                               '  *output = cpkt_archive_stat_from_native(*value);', '  return ARCHIVE_OK;', '}']
        arguments = []
        before, after = [], []
        for param in params:
            value, argument = param['type']['qualType'], param['argument']
            base = value.replace('const ', '').rstrip(' *')
            if self.args.library == 'lzma' and base == 'lzma_filter':
                local = 'native_' + argument
                array = not name.startswith(('lzma_properties_', 'lzma_filter_flags_'))
                count = 'LZMA_FILTERS_MAX + 1' if array else '1'
                output_only = (name == 'lzma_str_to_filters' or
                               name == 'lzma_filter_flags_decode' or
                               name == 'lzma_filters_copy' and not value.startswith('const '))
                before += ['  lzma_filter ' + local + '[' + count + '];',
                           '  cpkt_lzma_filters_to_native(' + local + ', ' + ('NULL' if output_only else argument) + ', ' + count + ');']
                arguments.append(argument + ' ? ' + local + ' : NULL')
                if not value.startswith('const '):
                    after += ['  cpkt_lzma_filters_from_native(' + argument + ', ' + local + ', ' + count + ');']
            elif self.args.library == 'lzma' and base == 'lzma_stream' and not value.startswith('const ') and name not in ('lzma_get_progress', 'lzma_end'):
                local = 'native_' + argument
                before += ['  struct cpkt_lzma_state *' + local + ' = cpkt_lzma_state_get(' + argument + ');',
                           '  if (!' + local + ') ' + ('return;' if result == 'void' else 'return LZMA_MEM_ERROR;')]
                arguments.append('&' + local + '->stream')
                after += ['  cpkt_lzma_state_commit(' + argument + ', ' + local + ');']
            elif self.args.library == 'archive' and base == 'struct stat':
                local = 'native_' + argument
                before += ['  struct stat ' + local + ' = {0};',
                           '  if (' + argument + ') ' + local + ' = cpkt_archive_stat_to_native(*' + argument + ');']
                arguments.append(argument + ' ? &' + local + ' : NULL')
            elif value.endswith('*') and base in self.unsigned_words | self.signed_words:
                local = 'native_' + argument
                before.append('  ' + base + ' ' + local + ' = 0;')
                if value.startswith('const ') or (self.args.library == 'lzma' and name in ('lzma_vli_decode', 'lzma_stream_buffer_decode', 'lzma_index_buffer_decode')):
                    before.append('  if (' + argument + ') ' + local + ' = ' + self.convert(base, '*' + argument, True) + ';')
                else:
                    after.append('  if (' + argument + ') *' + argument + ' = ' + self.convert(base, local, False) + ';')
                arguments.append(argument + ' ? &' + local + ' : NULL')
            elif value.endswith('*') and base in self.converted:
                local = 'native_' + argument
                before.append('  ' + base + ' ' + local + ' = {0};')
                if self.args.library == 'lzma' and base == 'lzma_stream' and not value.startswith('const '):
                    before.append('  void *saved_' + argument + '_state = ' + argument + ' ? ' + argument + '->cpkt_state : NULL;')
                inout = self.args.library == 'lzma' and not (name == 'lzma_index_iter_init' or name == 'lzma_stream_footer_decode' or name == 'lzma_stream_header_decode')
                if value.startswith('const ') or inout:
                    before.append('  if (' + argument + ') ' + local + ' = '
                                  + self.convert(base, '*' + argument, True) + ';')
                if not value.startswith('const '):
                    after.append('  if (' + argument + ') *' + argument + ' = '
                                 + self.convert(base, local, False) + ';')
                    if self.args.library == 'lzma' and base == 'lzma_stream':
                        after.append('  if (' + argument + ') ' + argument + '->cpkt_state = saved_' + argument + '_state;')
                if self.args.library == 'lzma' and base in ('lzma_block', 'lzma_mt'):
                    before += ['  lzma_filter ' + local + '_filters[LZMA_FILTERS_MAX + 1];',
                               '  if (' + argument + ') {',
                               '    cpkt_lzma_filters_to_native(' + local + '_filters, ' + argument + '->filters, LZMA_FILTERS_MAX + 1);',
                               '    ' + local + '.filters = ' + argument + '->filters ? ' + local + '_filters : NULL;', '  }']
                    if not value.startswith('const '):
                        # The facade-owned array always remains caller-owned.
                        after = ['  if (' + argument + ') {',
                                 '    cpkt_lzma_lzma_filter *filters = ' + argument + '->filters;',
                                 '    *' + argument + ' = ' + self.convert(base, local, False) + ';',
                                 '    ' + argument + '->filters = filters;',
                                 '    cpkt_lzma_filters_from_native(filters, ' + local + '_filters, LZMA_FILTERS_MAX + 1);', '  }'] + [a for a in after if '*' + argument + ' =' not in a]
                if self.args.library == 'lzma' and base == 'lzma_block' and name in ('lzma_block_encoder', 'lzma_block_decoder'):
                    state = next(p['argument'] for p in params if p['type']['qualType'] == 'lzma_stream *')
                    before += ['  if (' + argument + ') cpkt_lzma_state_block(native_' + state + ', ' + argument + ', ' + local + ');']
                    arguments.append(argument + ' ? &native_' + state + '->block : NULL')
                else:
                    arguments.append(argument + ' ? &' + local + ' : NULL')
            else:
                arguments.append(self.convert(value, argument, True))
        parameter_text = ', '.join(declaration(self.public_type(p['type']['qualType']), p['argument']) for p in params)
        if node.get('variadic'):
            parameter_text += ', ...'
        signature = self.public_type(result) + ' ' + self.prefix + name + '(' + (parameter_text or 'void') + ')'
        if self.args.library == 'archive' and name in ARCHIVE_MANUAL:
            return signature, []
        if self.args.library == 'lzma' and name == 'lzma_end':
            return signature, []
        body = [signature + ' {'] + before
        backend = name
        if self.args.library == 'lzo' and '_decompress_asm' in name:
            # These declarations are architecture-independent, but upstream
            # only implements the assembly symbols for 32-bit x86 (not a
            # shipped target). The equivalent upstream portable decoder keeps
            # every declared operation usable on all shipped architectures.
            backend = name.split('_decompress_asm')[0] + '_decompress' + ('_safe' if name.endswith('_safe') else '')
        call = backend + '(' + ', '.join(arguments) + ')'
        if result == 'void':
            body += ['  ' + call + ';'] + after
        else:
            body.append('  ' + result + ' cpkt_result = ' + call + ';')
            body += after + ['  return ' + self.convert(result, 'cpkt_result', False) + ';']
        body.append('}')
        return signature, body

    def generate(self):
        output = self.args.output
        header = output / 'include/cpkt' / (self.args.library + '.h')
        source = output / 'src' / (self.args.library + '.c')
        catalog = output / 'exports.txt'
        report = output / 'coverage.json'
        native_layout = output / 'native_layout.c'
        public_layout = output / 'public_layout.c'
        validate_output_paths(header, source, catalog, report, native_layout, public_layout)
        header.parent.mkdir(parents=True, exist_ok=True)
        source.parent.mkdir(parents=True, exist_ok=True)
        h = ['/* Generated from the complete pinned public compression API. */',
             '#ifndef ' + self.guard + '_H', '#define ' + self.guard + '_H',
             '#include <stddef.h>', '#include <stdio.h>', '#include <stdarg.h>',
             '#include <stdlib.h>', '#include <string.h>', '#include <cpkt/compression_types.h>',
             '#ifdef __cplusplus', 'extern "C" {', '#endif']
        if self.args.library == 'archive':
            h += ['struct archive;', 'struct archive_entry;', 'struct archive_entry_linkresolver;']
            for tag, fields in self.stat_definitions:
                h += ['/** Full target stat record; timestamps and file identities retain all 64 bits. */',
                      'typedef struct {']
                h += ['  ' + declaration(self.public_type(public), name) + ';' for name, _, public in fields]
                h += ['} cpkt_archive_' + tag + ';']
        h += self.emit_types()
        for name, (parameters, value) in self.constants.items():
            if name in ('ZSTD_CONTENTSIZE_UNKNOWN', 'ZSTD_CONTENTSIZE_ERROR'):
                low = '4294967295U' if name.endswith('UNKNOWN') else '4294967294U'
                value = self.prefix + 'u64_make(' + low + ', 4294967295U)'
            elif name == 'ZSTD_MAX_INPUT_SIZE':
                value = self.prefix + 'max_input_size()'
            elif name == 'LZ4F_INIT_FRAMEINFO':
                value = self.public_type(value.replace('0ULL', '{0U, 0U}'))
            elif self.args.library == 'lzma':
                if name == 'LZMA_STREAM_INIT':
                    value = '{0}'
                elif name == 'LZMA_VLI_C':
                    value = 'cpkt_lzma_u64_literal(#n)'
                elif name == 'LZMA_BACKWARD_SIZE_MAX':
                    value = 'cpkt_lzma_u64_make(0U, 4U)'
                elif name in ('LZMA_VLI_UNKNOWN', 'LZMA_VLI_MAX'):
                    value = 'cpkt_lzma_u64_make(4294967295U, ' + ('4294967295U' if name.endswith('UNKNOWN') else '2147483647U') + ')'
                elif name == 'lzma_vli_is_valid':
                    value = 'cpkt_lzma_vli_is_valid(vli)'
                elif name == 'lzma_set_ext_size':
                    value = 'do { (opt_lzma2).ext_size_low = (u64size).lo; (opt_lzma2).ext_size_high = (u64size).hi; } while (0)'
                else:
                    def wide_literal(match):
                        number = int(match[1], 0)
                        return 'cpkt_lzma_u64_make(' + str(number & 0xffffffff) + 'U, ' + str(number >> 32) + 'U)'
                    value = re.sub(r'UINT64_C\((0x[0-9A-Fa-f]+|[0-9]+)\)', wide_literal, value)
                    value = re.sub(r'UINT32_C\(([^)]+)\)', r'\1U', value)
                    value = self.public_type(value)
            elif self.args.library == 'lzo':
                if re.fullmatch(r'lzo_uint(?:64[elf]?|_(?:least|fast)64)_t', name):
                    value = 'cpkt_compression_u64'
                elif re.fullmatch(r'lzo_int(?:64[elf]?|_(?:least|fast)64)_t', name):
                    value = 'cpkt_compression_i64'
                elif name == 'LZO_UINT64_C':
                    value = 'cpkt_lzo_u64_literal(#c)'
                elif name == 'LZO_INT64_C':
                    value = 'cpkt_lzo_i64_literal(#c)'
                elif name == 'LZO_UNUSED_LABEL':
                    value = 'do { if (0) goto l; } while (0)'
                elif name in ('LZO_COMPILE_TIME_ASSERT', 'LZO_COMPILE_TIME_ASSERT_HEADER'):
                    value = 'extern int cpkt_lzo_compile_assert[(e) ? 1 : -1]'
                else:
                    value = self.public_type(value)
            else:
                value = self.public_type(value)
            h.append('#define ' + self.mapping[name] + parameters + ' ' + value)
        if self.args.library in ('zstd', 'lz4', 'lzma', 'lzo'):
            h += ['/** Construct a full-width unsigned C89 word without narrowing. */',
                  'cpkt_compression_u64 ' + self.prefix + 'u64_make(unsigned int lo, unsigned int hi);',
                  ]
        if self.args.library == 'zstd':
            h += ['/** Native maximum accepted input size for this target. */',
                  'size_t ' + self.prefix + 'max_input_size(void);']
        if self.args.library == 'archive':
            h += ['/** Construct a signed native-range value from its complete two-word representation. */',
                  'cpkt_compression_i64 cpkt_archive_i64_make(unsigned int lo, int hi);']
        if self.args.library == 'lzma':
            h += ['/** Accept a 63-bit VLI or the upstream unknown-value sentinel. */',
                  'int cpkt_lzma_vli_is_valid(cpkt_compression_u64 value);',
                  '/** Parse an integer literal for VLI macros using native strtoull/errno semantics. */',
                  'cpkt_compression_u64 cpkt_lzma_u64_literal(const char *literal);']
        if self.args.library == 'lzo':
            h += ['/** Parse an unsigned integer literal for constant macros using strtoull/errno semantics. */',
                  'cpkt_compression_u64 cpkt_lzo_u64_literal(const char *literal);',
                  '/** Parse a signed integer literal for constant macros using strtoll/errno semantics. */',
                  'cpkt_compression_i64 cpkt_lzo_i64_literal(const char *literal);']
        c = [self.defines, '#include <string.h>'] + ['#include <' + name + '>' for name in self.headers]
        for name, expression in self.stat_private_aliases.items():
            c.append('typedef ' + expression + ' ' + name + ';')
        for name in self.typedefs:
            if name not in self.converted and not self.needs_conversion(self.typedefs[name]['type']['qualType']):
                c.append('typedef ' + name + ' ' + self.mapping[name] + ';')
        c += ['#define ' + self.guard + '_NATIVE_TYPES 1',
              '#include <cpkt/' + self.args.library + '.h>']
        for name in self.enums:
            c += ['typedef char ' + self.prefix + name + '_enum_abi['
                  '__builtin_types_compatible_p(' + name + ', ' + self.enum_integer(name) + ') ? 1 : -1];']
        if self.args.library in ('zstd', 'lz4', 'lzma', 'lzo'):
            c += [
              'cpkt_compression_u64 ' + self.prefix + 'u64_make(unsigned int lo, unsigned int hi) {',
              '  cpkt_compression_u64 result; result.lo = lo; result.hi = hi; return result;', '}']
            if self.args.library != 'lzo':
                native_word = 'uint64_t' if self.args.library == 'lzma' else 'unsigned long long'
                c += ['static ' + native_word + ' ' + self.prefix + 'word_to_native(cpkt_compression_u64 word) {',
                      '  return ((unsigned long long)word.hi << 32) | word.lo;', '}']
            c += [
              'static cpkt_compression_u64 ' + self.prefix + 'word_from_native(unsigned long long word) {',
              '  return ' + self.prefix + 'u64_make((unsigned int)word, (unsigned int)(word >> 32));', '}']
        if self.args.library == 'zstd':
            c += ['size_t ' + self.prefix + 'max_input_size(void) { return ZSTD_MAX_INPUT_SIZE; }']
        if self.args.library == 'lzo':
            c += ['#include <stdlib.h>',
                  'cpkt_compression_u64 cpkt_lzo_u64_literal(const char *literal) {',
                  '  return cpkt_lzo_word_from_native(strtoull(literal, NULL, 0));', '}',
                  'cpkt_compression_i64 cpkt_lzo_i64_literal(const char *literal) {',
                  '  unsigned long long value = (unsigned long long)strtoll(literal, NULL, 0);',
                  '  cpkt_compression_i64 result; result.lo = (unsigned int)value; result.hi = (int)(value >> 32); return result;', '}']
        if self.args.library == 'archive':
            c += ['#include <stdint.h>', '#include <stdlib.h>', '#include <errno.h>', '#include <pthread.h>',
                  'cpkt_compression_i64 cpkt_archive_i64_make(unsigned int lo, int hi) {',
                  '  cpkt_compression_i64 result; result.lo = lo; result.hi = hi; return result;', '}',
                  'static int64_t cpkt_archive_signed_to_native(cpkt_compression_i64 value) {',
                  '  return (int64_t)(((uint64_t)(unsigned int)value.hi << 32) | value.lo);', '}',
                  'static cpkt_compression_i64 cpkt_archive_signed_from_native(int64_t value) {',
                  '  return cpkt_archive_i64_make((unsigned int)value, (int)((uint64_t)value >> 32));', '}',
                  'static uint64_t cpkt_archive_word_to_native(cpkt_compression_u64 value) {',
                  '  return ((uint64_t)value.hi << 32) | value.lo;', '}',
                  'static cpkt_compression_u64 cpkt_archive_word_from_native(uint64_t value) {',
                  '  cpkt_compression_u64 result; result.lo = (unsigned int)value; result.hi = (unsigned int)(value >> 32); return result;', '}']
            for tag, fields in self.stat_definitions:
                for to_native in (True, False):
                    native = self.stat_native_types[tag]
                    public = 'cpkt_archive_' + tag
                    dest, source_type = (native, public) if to_native else (public, native)
                    suffix = '_to_native' if to_native else '_from_native'
                    c += ['static ' + dest + ' cpkt_archive_' + tag + suffix + '(' + source_type + ' value) {',
                          '  ' + dest + ' result = {0};']
                    for name, original, converted in fields:
                        expression = self.convert(converted, 'value.' + name, to_native)
                        if original.startswith('struct '):
                            expression = 'cpkt_archive_' + original.split()[1] + suffix + '(value.' + name + ')'
                        if '[' in original:
                            c += ['  memcpy(result.' + name + ', value.' + name + ', sizeof(result.' + name + '));']
                        else:
                            c += ['  result.' + name + ' = ' + expression + ';']
                    c += ['  return result;', '}']
        coverage = {'functions': {}, 'types': sorted(self.typedefs), 'variables': {},
                    'constants': sorted(self.constants)}
        symbols = [self.prefix + 'u64_make'] if self.args.library in ('zstd', 'lz4', 'lzma', 'lzo') else []
        if self.args.library == 'lzo':
            symbols += ['cpkt_lzo_u64_literal', 'cpkt_lzo_i64_literal']
        if self.args.library == 'lzma':
            symbols.append('cpkt_lzma_vli_is_valid')
            symbols.append('cpkt_lzma_u64_literal')
        if self.args.library == 'zstd':
            symbols.append(self.prefix + 'max_input_size')
        if self.args.library == 'archive':
            symbols.append('cpkt_archive_i64_make')
        for name, node in self.variables.items():
            binding = self.prefix + name + '_ref'
            value = node['type']['qualType']
            h += ['/** Borrow the actual native public variable; lifetime is process-wide. */',
                  self.public_type(value) + ' *' + binding + '(void);',
                  '#define ' + self.mapping[name] + ' (*' + binding + '())']
            c += [self.public_type(value) + ' *' + binding + '(void) { return &' + name + '; }']
            symbols.append(binding)
            coverage['variables'][name] = {'binding': binding, 'native': value}
        function_bodies = []
        for name, node in self.functions.items():
            signature, body = self.emit_function(name, node)
            h += ['/** Native ' + name + '; preserves upstream ownership, callback and error contracts. */',
                  signature + ';']
            function_bodies += body
            symbols.append(self.prefix + name)
            coverage['functions'][name] = {'binding': self.prefix + name,
                                            'native': node['type']['qualType']}
        # Converter bodies can introduce dependencies on nested record converters.
        # Discover them before emitting the final, dependency-ordered definitions.
        previous = set()
        while previous != self.used_converters:
            previous = set(self.used_converters)
            self.emit_converters()
        converters = self.emit_converters()
        prototypes = [self.prefix + ('to_' if to_native else 'from_') + name
                      for name, to_native in sorted(self.used_converters)]
        for prototype in prototypes:
            line = next(line for line in converters if prototype + '(' in line and line.startswith('static '))
            c.append(line.removesuffix(' {') + ';')
        c += converters
        if self.args.library == 'lzma':
            c += [(Path(__file__).resolve().parents[1] / 'src/lzma_adapter.inc').read_text()]
        c += function_bodies
        if self.args.library == 'archive':
            c += [(Path(__file__).resolve().parents[1] / 'src/archive_adapter.inc').read_text()]
        h += ['#ifdef __cplusplus', '}', '#endif', '#endif']
        write_generated_text(header, '\n'.join(h) + '\n')
        write_generated_text(source, '\n'.join(c) + '\n')
        write_generated_text(catalog, '\n'.join(sorted(symbols)) + '\n')
        write_generated_text(report, json.dumps(coverage, sort_keys=True, indent=2) + '\n')
        native = [self.defines] + ['#include <' + name + '>' for name in self.headers]
        public = ['#include <cpkt/' + self.args.library + '.h>']
        native_values, public_values = [], []
        for index, (name, record) in enumerate(self.records.items()):
            if name in self.type_aliases or name in self.converted and name != 'lzo_align_t':
                continue
            for lines, type_name, values, side in ((native, name, native_values, 'native'),
                                                   (public, self.mapping[name], public_values, 'public')):
                probe = 'alignment_' + str(index)
                lines.append('struct ' + probe + ' { char padding; ' + type_name + ' object; };')
                values += ['sizeof(' + type_name + ')', 'offsetof(struct ' + probe + ', object)']
                for field in children(record):
                    if field['kind'] != 'FieldDecl':
                        continue
                    member = field.get('name')
                    if member:
                        values.append('offsetof(' + type_name + ', ' + member + ')')
                    elif 'anonymous' in field['type']['qualType'] or 'unnamed' in field['type']['qualType']:
                        for member in ('tramp', 'ftramp'):
                            values.append('offsetof(' + type_name + ', '
                                          + ('trampoline.' if side == 'public' else '') + member + ')')
        native += ['const size_t cpkt_native_layout[] = {' + ', '.join(native_values or ['0']) + '};',
                   'const size_t cpkt_native_layout_count = ' + str(len(native_values)) + ';']
        public += ['const size_t cpkt_public_layout[] = {' + ', '.join(public_values or ['0']) + '};',
                   'const size_t cpkt_public_layout_count = ' + str(len(public_values)) + ';']
        write_generated_text(native_layout, '\n'.join(native) + '\n')
        write_generated_text(public_layout, '\n'.join(public) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', required=True, choices=('zstd', 'ffi', 'lz4', 'archive', 'lzma', 'lzo'))
    parser.add_argument('--include', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--clang', required=True)
    parser.add_argument('--clang-argument', action='append', default=[])
    Generator(parser.parse_args()).generate()


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        raise SystemExit(str(error))
