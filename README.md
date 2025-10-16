# Sys-YAML

Limited [YAML](https://yaml.org/spec/1.2.2/) with [JSON](https://www.json.org/)-conformant values, parser written in Bash, and CLI for writing environment variables, JSON, and YAML

## Features

- **YAML: The Good Parts** – all values must be valid JSON and string values are always double-quoted, while keys can be unquoted or double-quoted.
- **Parser in 2^8 [lines of code](sys-yaml.sh) using pure Bash**, except for optional [jq](https://jqlang.org/) integration for JSON validation/compaction. The parser is intended to be either sourced or copied and pasted into where it's needed, or used via the function library/CLI. However, _flow_ mappings/sequences are kept as stringified JSON and are not parsed.
- **Support for block scalars, tags, anchors/aliases, and complex mappings**, essentially implementing all of YAML except for the above limitations.
- **Function [library](sys-yaml)** for using the parser more conveniently as well as writing YAML and other formats. Also pure Bash, except jq integration for JSON formatting and improved long string encoding performance, as well as file import/export.
- **Command-line interface** for parsing YAML files and writing values to files as environment variables, JSON, YAML, and other formats.

## Supported YAML syntax

Basic syntax, per line:

```
[  ]*[- ][(key|"key"):][ ]["string"|<number>|true|false|||>][ #comment]
```

For example:

```yaml
my_key: "my string value, must always be double-quoted"
my_integer: 1234 # My comment
my_float: 12.34
my_boolean: false

my_mapping:
  another_key: "value for another_key in my_mapping"
  value_on_next_line:
    "the value can be here too"
  no_value: # This key has no value
  my_sequence:
    - "first item"
    - "second item"
    - another_mapping: true
      name: "third item"
```

Because string values must be double-quoted, the space after the colon in `key: <value>` becomes optional (as the line still can't be interpreted as a string), but the space should always be included for compatibility with other parsers and for the line to not be a string value according to the YAML specification.

For long double-quoted strings, it's possible to use `\` at the very end of the line to escape a line-break, so that the string can run across multiple lines. An alternative is to use block scalars, e.g.:

```yaml
my_text: |
  First line.
  Second line.
```

Full supported syntax, with k=key, s=string, n=number (integer or float), d=digit 1-9, c=comment:

```
[  ]*[(?|:) ][- ][[! ](k|"k"):][ ][*|[& ][! ]("s"|<n>|true|false|(||>)[d][+|-]|[]|{})][ #c]
```

`?` and `:` (at the start) are for a complex mapping's key and value, respectively. `!` (e.g., `!!str`) is for a tag and can be used for a key and/or a value. `&` and `*` are for an anchor and alias, e.g., `&reuse` and `*reuse`, where the former is the source to be re-used and the latter its destination. `|` and `>` are for block scalars (indented text contents below the line, with `>` for folding single line-breaks into spaces), with the optional digit indicating how much further contents are indented (by default it's detected) and the optional `+` or `-` for including or trimming extra trailing newlines, respectively. `{}` and `[]` are for _flow_ mappings and sequences, respectively, and can be any valid JSON object or array. They are also necessary in order to indicate an empty mapping or sequence, as a mapping or sequence without keys or items otherwise becomes no value (i.e., _null_).

Finally, directives (`%YAML` and `%TAG`) and directives/document end markers (`---`/`...`) are supported when parsing using the CLI. When writing environment variables, JSON, or YAML, aliases are transparently resolved to their anchors. When writing YAML, tag handles are resolved to their prefixes, if available.


## Examples

### Convert YAML to environment variables

Provide your own YAML file called _test.yml_, e.g., the example above. Alternatively, change the filename to `-` below to use standard input (which is also the default).

This assumes that keys in the YAML are lower-case a-z, 0-9, _ with double-underscore being reserved. Also, recall that all string values in the YAML must be double-quoted.

```bash
sys-yaml --in=test.yml --parse --name=my_config --write-conf
```
or
```bash
sys-yaml -i test.yml -pn my_config -f
```

### Convert YAML to JSON

```bash
sys-yaml --in=test.yml --parse --write-json
```
or
```bash
sys-yaml -i test.yml -pj
```

### Print subset of YAML

This assumes that there's a key called _my_mapping_.

```bash
sys-yaml --in=test.yml --parse --subkeys-add=my_mapping --write-yaml
```
or
```bash
sys-yaml -i test.yml -pa my_mapping -y
```

## Requirements

Bash 5, due to use of associative arrays and namerefs.

### macOS

Install `bash` from MacPorts or Homebrew, as the pre-installed Bash version is too old.

It is recommended to also install `jq`.

### Debian/Ubuntu

Bash 5 is in Debian since version 10 (Buster) and in Ubuntu since 20.04 LTS (Focal Fossa).

Recommended: `apt install jq`

## Usage

```
Usage: sys-yaml [option...]
Parse YAML files and write values to files as env. variables, JSON, YAML, and other formats.

All options can be used multiple times and are processed in the order in which they are given,
except for --help, --verbose, and --jq.

Options:
  --help, -h                    show this help message and exit
  --verbose, -v                 enable verbose parser output of values being added
  --jq=, -q <jq>                command to use for jq, false to disable, default detects jq
  --root=, -r <key>             set implicit key to the root, space-separated, default 'yaml'
  --name=, -n <key>             set initial key for writing, or : for full or ' ' for none
  --in=, -i <file>              set input file, by filename, or - for stdin, default -
  --out=, -o <file>             set output file, by filename, or - for stdout, default -
  --plain=, -l <file>           import plain-text data to the root from file, by filename
  --binary=, -x <file>          import binary data to the root from file, by filename
  --compress=, -g <gzip>        command for compressing binary data, or - for none, default -
  --decompress=, -m <gunzip>    command for decompress. binary data, or - for none, default -
  --clear, -c                   remove all current values, restoring initial state
  --parse, -p                   parse one YAML document from input file
  --read, -b                    read values from input file, previously written using --write
  --write, -d                   write values to output file, using one key-value per line
  --write-keys, -k              write keys to output file, using one key per line
  --write-value, -w             write a raw value to output file, if the value exists
  --write-line=, -z <line>      write a raw line to output file
  --write-conf, -f              write environment variables (Bash-compatible) to output file
  --write-json, -j              write JSON to output file
  --write-yaml, -y              write YAML to output file
  --subkeys, -s                 clear subkeys for where to base root, default same as --root
  --subkeys-add=, -a <key>      add raw, space-separated (possibly double-quoted) subkey(s)
  --subkeys-encode=, -e <key>   encode (i.e., double-quote if needed) and add subkey(s)
```

## Limited YAML

This section goes into more detail about the subset of YAML that is implemented. It may be worthwhile reading in case of interest in this concept of "limited" YAML, e.g., for constraining one's use of the YAML syntax and why (with inspiration from the book "JavaScript: The Good Parts") or for creating other implementations.

Sys-YAML implements [YAML 1.2](https://yaml.org/spec/1.2.2/) with the following restrictions/clarifications:

1. String values must always be double-quoted (\"...\"), like in [JSON](https://www.json.org/). Mapping keys must be either unquoted (plain) or double-quoted. However, even when keys are unquoted, they are always parsed as strings.
    * **Rationale:** YAML's syntax for keys, mappings, and sequences is convenient and powerful, but the different ways of quoting and not quoting string values might be confusing. Learning the intricacies of each method could take a long time. There is a risk of string values, and keys, being interpreted as unintended types, e.g., booleans. JSON is the opposite: writing keys and structuring objects and arrays is cumbersome to do by hand, but writing string values is arguably quite simple, except if multi-line or long.
    * **Workarounds:** Double-quote all string values. For multi-line string values, use block scalars (`|` or `>`). Mapping keys can remain unquoted (plain) and should be unquoted, unless they contain `"`, `\`, control characters (< 0x20, 0x7F), or `:`, in which case they must be double-quoted, or if they contain spaces or are empty strings, in which case they should be double-quoted (c.f., command line arguments).
    * **Exceptions:** It's still possible to write a long, double-quoted string across multiple lines, by using `\` at the end of the line to escape the line-break, as logically, it's on a single YAML line.
3. Values and double-quoted keys must conform to JSON. Flow mappings and sequences (`{...}` and `[...]` syntax) embed valid JSON objects/arrays as values for mappings and sequences and their contents, if any, are not parsed directly as YAML. If there are no contents, they are regarded as empty mappings/sequences (`{}`/`[]`).
    * **Rationale:** JSON is familiar to many and its syntax for values is mostly easy to understand and sufficient. YAML has a strength in being a superset of JSON, as it's therefore possible to embed JSON values, and a JSON document is also a valid YAML document. But YAML also allows non-JSON syntax within those values and, e.g., additional escape sequences, so that those parts of a YAML document are no longer valid JSON. Another way of looking at YAML is as a format for the structuring and embedding of JSON, or perhaps a superstructure. As such, JSON syntax can exist as embedded values within YAML. When a YAML document is then converted to JSON, the structure is converted but the embeddings (i.e., all values of all types) are included as they are, because they're already valid JSON.
    * **Workarounds:** In double-quoted strings, only use JSON-compatible escape sequences. However, Sys-YAML can parse all YAML escape sequences in string values even though they should not be used, but will itself only write JSON-compatible ones (and never `\/`). In double-quoted strings, use `\n` to include a newline or, for long strings, use `\` at the end of the line to escape a line-break. Inside flow mappings and sequences (`{}` and `[]` syntax), use valid JSON, including only JSON-compatible escape sequences and no comments. If flow mappings/sequences need to be parsed directly as YAML instead of kept as stringified JSON, rewrite them as regular YAML block mappings/sequences (`:` and `-` syntax). For floats, if `.inf`, `-.inf`, and `.nan` are needed, double-quote the values and possibly tag them with `!!float`.
    * **Exceptions:** It's still possible to use block scalars for multi-line string values (`|` or `>`). A missing value is still regarded as equivalent to `null`. Tags, anchors, and aliases are also still possible, but tags are stripped and aliases resolved before being written in JSON format.
5. Complex mappings must use `?`/`:` at the start of the line.
    * **Rationale:** Aside from flow mappings and sequences (`{}` and `[]` syntax), this might be the only syntax of YAML that makes it impossible to parse a single key and value pair from one line, as potentially a sequence can contain a complex mapping containing yet another sequence (or mapping) on the same line. However, from the specification, it's unclear whether this is actually allowed and no example places `?` after `-`, only before.
    * **Workarounds:** For complex mappings within a sequence, use a new line after the hyphen and indent two spaces in order to achieve the same semantics, or don't use a sequence (i.e., delete the `-` preceding the `?`) for similar semantics.
    * **Exceptions:** Tagged keys are interpreted as an alternative syntax for certain complex mappings, with the tagged string key as the key (following a `?`) and its value as the value (following a `:`).
7. Directives/document end markers `---` and `...` must not have any data after the marker on the same line.
    * **Rationale:** Allowing the marker to co-exist on the same line with data causes ambiguity, as the same characters can be part of a key (or a value, if unquoted strings are allowed), but if other data and unquoted string values are both not allowed, then a marker is clearly not a key/value. It also causes problems with line-based parsing, as when a document ends there might already be data from the next document on the same line, which would need to be stored for the parsing of the next document.
   * **Workarounds:** Add a newline immediately after the marker.
   * **Exceptions:** Spaces/tabs and/or a comment are still possible on the same line after the marker.

## License

Copyright © 2025 Erik Isaksson. Licensed under an [MIT License](LICENSE).
