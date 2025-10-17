# Sys-YAML implements a limited and lenient YAML parser that reads lines from yaml_lines, an
# array filled using, e.g., readarray. Mapping keys must be unquoted or double-quoted. String
# values must be double-quoted. Values and double-quoted keys must conform to JSON. For JSON
# compat., explicit null is equivalant to no value and {}/[] "flow" syntax embeds valid JSON.
# | (or >) embeds (folded) text below, with indent d and/or +/- to keep/cut trailing newlines.
# Complex mappings must use initial ?/:, i.e., if in a sequence, use newline, indent 2 spaces.
# Supported syntax, with k=key, s=string, n=number (integer or float), d=digit 1-9, c=comment:
# [  ]*[(?|:) ][- ][[! ](k|"k"):][ ][*|[& ][! ]("s"|<n>|true|false|(||>)[d][+|-]|[]|{})][ #c]
# Output: Every value is put in an associative array, yaml_values, using a merged key of all
# nested subkeys, separated by spaces, and yaml_root as the implicit key to the root. Mapping
# keys containing ", \, control characters, :, or space or which are empty are double-quoted.
# Every key has a single-quoted subkey 'type'. Sequences have '<index>' and also 'length'. For
# complex mappings, similarly to sequences there are '_<index>' and '_length', with subkeys
# 'key' and 'val'. Tags are in 'tag'. Aliases are in 'alias', to be looked-up in yaml_anchors.
# The function yaml_encode escapes values for JSON/YAML. For Bash strings, add 2nd arg. for $,
# e.g.: value="${yaml_values["yaml key"]}"; echo -n 'key="'; yaml_encode 'value' '$'; echo '"'
# Source: https://github.com/erikis/sys-yaml (MIT License); Copyright 2025 Erik Isaksson
yaml_root="${yaml_root:-"yaml"}" # Implicit key to the root (space-separated, default 'yaml')
yaml_v="${yaml_v:-false}"       # Enable verbose output of values being added (default false)
yaml_jq="${yaml_jq:-""}"   # Use jq for piping JSON (default 'jq' if found, false to disable)
yaml_invalid=false     # This flag will be set true if there is invalid or unsupported syntax
declare -ga yaml_lines yaml_keys yaml_subkeys yaml_indents   # In: yaml_lines; Out: yaml_keys
declare -gA yaml_values yaml_anchors # Out: yaml_values w/ keys in yaml_keys and yaml_anchors
yaml_block=false; yaml_json=false; yaml_line=''; declare -i yaml_json_open yaml_json_close
yaml_encode() { # $1: name of variable to escape for double-quoted string, print to stdout
  local -n s="$1"; local i j k l; for ((i = 0; i < "${#s}"; i+=500)); do k="${s:$i:500}"
    for ((j = 0; j < "${#k}"; j++)); do l="${k:$j:1}" # Long strings are slow unless chunked
      case "$l" in $'"') l=$'\\"';; $'\\') l=$'\\\\';; $'\x7F') l=$'\\u007f';; *) # ", \, DEL
      if [[ "$l" < ' ' ]]; then case "$l" in $'\b') l='\b';; $'\f') l='\f';; $'\n') l='\n';;
        $'\r') l='\r';; $'\t') l='\t';; *) printf '\\u%04x' "'$l"; continue; esac; # < x20
      fi;; esac; if [[ -n "$2" && "$l" == @($2) ]] # 'x for codepoint of x, see bash man page
        then echo -n "\\$l"; else echo -n "$l"; fi; done; done # Escape |-sep. chars in $2
}
yaml_decode() { # $1: name of variable to unescape in place
  local -n s="$1"; local t="${s//\\\\}"; t="${t//\\[abtnvfre\"\\xuU]}" # E transform compat.
  if [[ -n "${t//[^\\]}" ]]; then t="${t//\\[\/0N_LP]}" # JSON's \/ and YAML's \0 \N \_ \L \P
    if [[ -n "${t//[^\\]}" ]]; then return; else s="${s//\\\\/\\E}" # Replace \\ temporarily
    s="${s//\\\//\/}"; s="${s//\\0/\\x00}"; s="${s//\\N/\\x85}"; s="${s//\\_/\\xA0}"
    s="${s//\\L/\\u2028}"; s="${s//\\P/\\u2029}"; s="${s//\\E/\\\\}"; fi; fi; s="${s@E}"
}
yaml_read_json() { # YAML parser helper function: reads one line of JSON/flow syntax
  local symbol_open="${yaml_json:0:1}" symbol_close="${yaml_json:1:1}" i; local -i count
  yaml_string="${1//\\.}"; yaml_string="${yaml_string//\"[^\"]*\"}" # Remove strings
  count=0; for ((i = 0; i < "${#yaml_string}"; i++)); do case "${yaml_string:$i:1}" in
    "$symbol_open") yaml_json_open+=1;;                                     # Count all {/[
    "$symbol_close") yaml_json_close+=1; count+=1;; esac                    # Count all }/]
    if [[ "$yaml_json_open" -eq "$yaml_json_close" ]]; then break; fi; done # Stop if match
  if [[ "$yaml_json_open" -eq "$yaml_json_close" ]] # If {/[ are as many as }|]
  then
    yaml_string='"([^\\"]*|\\.)*"'; yaml_string="^(([^$symbol_close\"]*|$yaml_string"
    yaml_string="$yaml_string)*\\$symbol_close){$count}(.*)$" # Match what's JSON and after
    [[ "$1" =~ $yaml_string ]] && yaml_string="${BASH_REMATCH[-1]}" || yaml_string=""
    if [[ ! "$yaml_string" =~ ^[[:blank:]]*(#.*)?$ ]] # If non-comment text after the JSON
    then echo "Warning: Ignoring YAML (invalid data after JSON)." >&2; fi
    IFS=''; yaml_value="${yaml_var[*]} ${1%%"$yaml_string"}"; unset 'IFS' 'yaml_var' # Merge
    if [[ "$yaml_value" =~ ^${symbol_open}[[:space:]]*${symbol_close}$ ]]
    then yaml_value="$yaml_json" # Only whitespace between outermost {}/[] -- empty map/seq
    elif [[ "$yaml_jq" != false ]]; then if [[ -z "$yaml_jq" && -z "$(which 'jq' >/dev/null \
      || echo '_')" ]]; then yaml_jq='jq'; else yaml_jq=false; fi # Detect 'jq', keep result
      if [[ "$yaml_jq" != false ]]; then yaml_value="$(echo "$yaml_value" | "$yaml_jq" \
        -cj . || echo '')"; fi; fi # Use jq if enabled (and is set explicitly or 'jq' found)
    if [[ -n "$yaml_value" ]] # Non-empty string if jq wasn't used or was used and succeeded
    then
      case "$yaml_json" in '{}') yaml_string='map';; '[]') yaml_string='seq';; esac
      if [[ "$yaml_value" == "$yaml_json" ]]; then # If empty map/seq, set type but not value
        yaml_set_value "$yaml_prefix_key" "$yaml_string" '_'     # tag:yaml.org,2002:map/
      else yaml_set_value "$yaml_prefix_key" "$yaml_string"; fi  # tag:yaml.org,2002:seq
      if [[ "$yaml_v" == true ]]; then echo -n "YAML: $yaml_prefix_key=" >&2
        yaml_encode 'yaml_value' >&2; echo '"' >&2; fi
    else # shellcheck disable=SC2034
      yaml_invalid=true; echo "Warning: Ignoring YAML (invalid JSON)." >&2; fi
    yaml_json=false # Finished reading JSON
  else yaml_var+=("$1"); fi # Append current line
}
yaml_set_key() { # YAML parser helper function: sets the value of yaml_key
  if [[ "$1" == '"'*'"' ]]; then yaml_key="${1:1:-1}"; yaml_decode 'yaml_key'
  else yaml_key="$1"; fi;                              yaml_key="$(yaml_encode 'yaml_key')"
  if [[ "$yaml_key" =~ ^$|[\\\'@\`\ ] ]]; then yaml_key="\"$yaml_key\""; fi # Double-quote
}
yaml_set_value() { # YAML parser helper function: sets a value and its type in yaml_values
  local k="$1"; if [[ -z "$3" ]]; then if [[ -z "${yaml_values["$k"]+_}" ]]; then # If unset
    yaml_keys+=("$k"); fi; yaml_values["$k"]="$yaml_value"; fi; k="$1 'type'" # Value if $3 == ''
  if [[ -z "${yaml_values["$k"]+_}" ]]; then yaml_keys+=("$k"); fi; yaml_values["$k"]="$2" # Type
}
yaml_set_complex() { # YAML parser helper function: sets a complex mapping
  yaml_prefix="$yaml_prefix $1"
  yaml_subkeys+=("$1"); yaml_indents+=("$yaml_indent")
  yaml_set_value "$yaml_prefix" 'map' '_'                             # tag:yaml.org,2002:map
  if [[ -n "$2" ]]; then yaml_prefix="$yaml_prefix $2"
    yaml_subkeys+=("$2"); yaml_indents+=("$yaml_indent"); fi
  yaml_set_value "$yaml_prefix" 'null' '_'                            # tag:yaml.org,2002:null
  yaml_indent="$(("$yaml_indent"+"${#yaml_cx}"+"${#yaml_hyphen}"))"
}
yaml_set() { # YAML parser helper function: sets a value in yaml_values
  if [[ -z "${yaml_values["$1"]+_}" ]]; then yaml_keys+=("$1"); fi; yaml_values["$1"]="$2"
}
# Parse YAML in yaml_lines, placing values incl. metadata in yaml_values
if [[ -n "$yaml_root" ]]; then yaml_subkeys+=("$yaml_root"); fi; yaml_indents+=('-1') # Add root
if [[ -z "${yaml_values["$yaml_root 'type'"]+_}" ]] # If not already set, set default root type
then yaml_set_value "$yaml_root" 'null' '_'; fi                       # tag:yaml.org,2002:null
yaml_lines+=($'#\n'); unset 'IFS'; for yaml_l in "${yaml_lines[@]}" # Loop over all YAML lines
do # Inserted ignored and impossible final line $'#\n' to ensure block/JSON end will be detected
  if [[ "$yaml_block" != false ]] # If inside a block scalar, read its value line by line
  then
    if [[ "$yaml_block" == true && -z "$yaml_style" ]]
    then
      case "${yaml_value:0:1}" in '|') yaml_style=$'\n';; '>') yaml_style=' ';; esac
      yaml_chomp=''; yaml_block='' # Look for chomp and indentation indicators
      if [[ "$yaml_value" =~  [+-]{1} ]]; then yaml_chomp="${BASH_REMATCH[0]}"; fi
      if [[ "$yaml_value" =~ [1-9]{1} ]]; then yaml_block="${BASH_REMATCH[0]}"; fi
      if [[ -z "$yaml_block" ]]; then yaml_block=true # If no indicator, detect indent
      else yaml_block="$(("$yaml_indent"+"$yaml_block"))"; fi; fi # If indicator, add to indent
    if [[ "$yaml_block" == true && "$yaml_l" =~ ^(\ {$(("$yaml_indent"+1)),})([^ ].*) && \
      "$yaml_l" != $'#\n' ]]; then yaml_block="${#BASH_REMATCH[1]}"
      if [[ "${#yaml_var[@]}" -gt 0 ]]; then yaml_var+=("$yaml_style"); fi
      yaml_string="${BASH_REMATCH[2]}"; yaml_var+=("$yaml_string"); continue # Detected indent
    elif [[ (("$yaml_block" != true && "$yaml_l" =~ ^(\ {$yaml_block})(.*)) || \
      ("$yaml_block" == true && "$yaml_l" =~ ^(\ *)(.*))) && "$yaml_l" != $'#\n' ]]
    then # If still inside a block scalar
      yaml_string="${BASH_REMATCH[2]}"; if [[ "$yaml_block" == true ]]; then yaml_string=''; fi
      if [[ "$yaml_style" == ' ' && -z "$yaml_string" ]] # If folded and empty line,
      then yaml_var+=($'\n'); yaml_style="x"; continue; fi # temp. use newlines
      if [[ "$yaml_style" == 'x' ]] # If using separation by newlines temporarily
      then yaml_var+=("$yaml_string"); yaml_var+=($'\n')
        if [[ -n "$yaml_string" ]]; then yaml_style=' '; fi # Separate by spaces again
      else # Append current line
        if [[ "${#yaml_var[@]}" -gt 0 ]]; then yaml_var+=("$yaml_style"); fi
        yaml_var+=("$yaml_string"); fi; continue
    else # If no longer inside a block scalar
      if [[ "$yaml_chomp" == '+' ]]; then yaml_var+=($'\n') # Whether to keep all \n
      else while [[ "${#yaml_var[@]}" -gt 0 && -z "${yaml_var[-1]%%$'\n'}" ]]
        do unset "yaml_var[-1]"; done; fi # Remove all \n
      if [[ -z "$yaml_chomp" ]]; then yaml_string=$'\n'; else yaml_string=''; fi
      IFS=''; yaml_value="${yaml_var[*]}$yaml_string"; unset 'IFS' 'yaml_var' # Merge
      yaml_set_value "$yaml_prefix_key" 'str'                    # tag:yaml.org,2002:str
      if [[ "$yaml_v" == true ]]; then echo -n "YAML: $yaml_prefix_key=\"" >&2
        yaml_encode 'yaml_value' >&2; echo '"' >&2; fi
      yaml_block=false; fi; fi
  if [[ "$yaml_json" != false ]] # If inside JSON/flow syntax, read lines until completed
  then if [[ "$yaml_l" != $'#\n' ]] # I.e., not the inserted $'#\n' at the end
    then # Append to existing JSON, space instead of newline; trim existing leading spaces/tabs
      yaml_read_json " ${yaml_l#"${yaml_l%%[![:blank:]]*}"}"; continue
    else yaml_json=false; yaml_invalid=true
      echo "Warning: Ignoring YAML (incomplete JSON)." >&2; fi; fi
  # If this is a continued line, trim leading spaces/tabs and append to existing line
  if [[ -n "$yaml_line" ]]; then yaml_line="$yaml_line${yaml_l#"${yaml_l%%[![:blank:]]*}"}"
  else yaml_line="$yaml_l"; fi # If this is not a continued line, start from scratch
  # Handle lines which are to be continued (line break escape in double-quoted string) or blank
  if [[ "$yaml_line" == *\\ && "$yaml_line" =~ ^([^\"{[]*|\"([^\\]*|\\.)*\")*\"([^\\]*|\\.)*\\$ ]]
  then yaml_line="${yaml_line:0:-1}"; continue; fi # Esc. linebreak within double-quotes; trim \
  if [[ "$yaml_line" =~ ^[[:blank:]]*(#.*)?$ ]]; then : # Ignoring blank line/comment
  # Match the line against a regex for the full supported YAML syntax
  elif [[ "$yaml_line" =~ \
    ^( *)([\?:] *)?(- *)?((\![^[:blank:]]+[[:blank:]]+)?[^\"]+:|\"([^\\]*|\\.)*\":)?[[:blank:]]*(\
    $ ignore )?((\*[^[:blank:]]+)|(([\!\&][^[:blank:]]+[[:blank:]]*)*)(\"(.*)\"|true|false|null|\
    $ |-?[0-9]+(\.[0-9]+)?([Ee][+-]?[0-9]+)?|(\||\>)[0-9+-]*|\{.*|\[.*)?)?[[:blank:]]*(#.*)?$ ]]
  then
    yaml_cx="${BASH_REMATCH[2]}"; yaml_hyphen="${BASH_REMATCH[3]}"
    yaml_key="${BASH_REMATCH[4]}"; yaml_ktag="${BASH_REMATCH[5]}"
    if [[ (-n "$yaml_hyphen" || -n "$yaml_key") && "${#yaml_cx}" -eq 1 ]] # If false '?'/':'
    then yaml_key="$yaml_cx$yaml_hyphen$yaml_key"; yaml_cx=''; yaml_hyphen=''; yaml_ktag=''
    elif [[ -n "$yaml_key" && "${#yaml_hyphen}" -eq 1 ]] # If false '-' (actually part of key)
    then yaml_key="$yaml_hyphen$yaml_key"; yaml_hyphen=''; yaml_ktag=''; fi
    if [[ -n "$yaml_hyphen" ]]; then yaml_hyphen='- '; else yaml_hyphen=''; fi # Normalize
    yaml_alias="${BASH_REMATCH[9]}"; yaml_vtag="${BASH_REMATCH[10]}"
    yaml_value="${BASH_REMATCH[12]}"; yaml_string="${BASH_REMATCH[13]}"
    if [[ -n "$yaml_hyphen" && -z "$yaml_key" && -z "$yaml_value" ]]; then yaml_hyphen='-'; fi
    if [[ -n "$yaml_cx" ]]; then yaml_indent="${#BASH_REMATCH[1]}" # Temp. excl. ?/: from indent
    else yaml_indent="$(("${#BASH_REMATCH[1]}"+"${#yaml_hyphen}"))"; fi # Incl. hyphen in indent
    if [[ -n "$yaml_ktag" ]]; then yaml_key="${yaml_key#"$yaml_ktag"}"
      yaml_ktag="${yaml_ktag%%[[:space:]]*}"; else yaml_ktag=''; fi
    if [[ -n "$yaml_vtag" ]]; then if [[ "$yaml_vtag" =~ \&([^[:blank:]]*) ]]
      then yaml_anchor="${BASH_REMATCH[1]}"; else yaml_anchor=''; fi
      if [[ "$yaml_vtag" =~ (\![^[:blank:]]*) ]]; then yaml_vtag="${BASH_REMATCH[1]}"
      else yaml_vtag=''; fi; else yaml_anchor=''; yaml_vtag=''; fi
    while [[ "$yaml_indent" -le "${yaml_indents[-1]}" ]]; do # Go up the stack until indent match
      yaml_previous="${yaml_subkeys[-1]}"; unset 'yaml_subkeys[-1]' 'yaml_indents[-1]'; done
    yaml_prefix="${yaml_subkeys[*]}" # Merge all keys in the stack, assumes IFS is unset
    if [[ -n "$yaml_key" ]]; then yaml_key="${yaml_key%':'}" # If key, trim colon
      if [[ -z "$yaml_ktag" ]]; then yaml_set_key "$yaml_key" # If key without tag
      else                     # If key with tag, convert to a complex mapping
        yaml_length="${yaml_values["$yaml_prefix '_length'"]:-0}"; if [[ "$yaml_length" -eq 0 ]]
        then yaml_set_value "$yaml_prefix" 'map' '_'                  # tag:yaml.org,2002:map
          yaml_keys+=("$yaml_prefix '_length'"); fi
        yaml_values["$yaml_prefix '_length'"]="$(("$yaml_length"+1))" # Set the new length
        yaml_set_complex "'_$yaml_length'" ''; yaml_set "$yaml_prefix 'key'" "$yaml_key"
        yaml_set "$yaml_prefix 'key' 'tag'" "$yaml_ktag"; yaml_set "$yaml_prefix 'key' 'type'" 'str'
        yaml_key="'val'"; fi; fi
    if [[ -n "$yaml_cx" ]]; then if [[ "$yaml_cx" == '?'* ]]
      then                     # If '?'/':' complex mapping          # If complex mapping key
        yaml_length="${yaml_values["$yaml_prefix '_length'"]:-0}"; if [[ "$yaml_length" -eq 0 ]]
        then yaml_set_value "$yaml_prefix" 'map' '_'                  # tag:yaml.org,2002:map
          yaml_keys+=("$yaml_prefix '_length'"); fi
        yaml_values["$yaml_prefix '_length'"]="$(("$yaml_length"+1))" # Set the new length
        yaml_set_complex "'_$yaml_length'" "'key'"
      elif [[ "$yaml_previous" == "'_"* &&
        -z "${yaml_values["$yaml_prefix $yaml_previous 'val'"]+_}" ]] # If complex mapping value
      then yaml_set_complex "$yaml_previous" "'val'"
      else # If the colon seems to actually be for an unquoted empty-string key
        yaml_key='""'; yaml_indent="$(("${#BASH_REMATCH[1]}"+"${#yaml_hyphen}"))"; fi; fi
    if [[ -n "$yaml_hyphen" ]]
    then                       # If there is a hyphen, then it means that this is a sequence
      yaml_length="${yaml_values["$yaml_prefix 'length'"]:-0}"; if [[ "$yaml_length" -eq 0 ]]
      then yaml_set_value "$yaml_prefix" 'seq' '_'                    # tag:yaml.org,2002:seq
        yaml_keys+=("$yaml_prefix 'length'"); fi
      yaml_values["$yaml_prefix 'length'"]="$(("$yaml_length"+1))" # Set the new length
      yaml_prefix="$yaml_prefix '$yaml_length'"
      yaml_subkeys+=("'$yaml_length'"); yaml_indents+=("$yaml_indent")
    elif [[ -n "${yaml_values["$yaml_prefix 'length'"]+_}" ]]
    then                       # If still on a sequence node
      yaml_length="${yaml_values["$yaml_prefix 'length'"]}"; yaml_length="$(("$yaml_length"-1))"
      yaml_prefix="$yaml_prefix '$yaml_length'" # Use the current index (not next one)
      yaml_subkeys+=("'$yaml_length'"); yaml_indents+=("$yaml_indent"); fi
    if [[ -n "$yaml_key" ]]    # If there is a key, then it might mean that this is a map
    then yaml_set_value "$yaml_prefix" 'map' '_'                      # tag:yaml.org,2002:map
      yaml_prefix_key="$yaml_prefix $yaml_key"; else yaml_prefix_key="$yaml_prefix"; fi
    if [[ -n "$yaml_vtag" ]]; then yaml_set "$yaml_prefix_key 'tag'" "$yaml_vtag"; fi
    if [[ -n "$yaml_anchor" ]]; then # shellcheck disable=SC2034
      yaml_anchors["$yaml_anchor"]="$yaml_prefix_key"; fi
    if [[ -n "$yaml_alias" ]]; then yaml_set "$yaml_prefix_key 'alias'" "${yaml_alias#'*'}"; fi
    if [[ -n "$yaml_key" && -z "$yaml_value" ]]
    then                                    # If key but no value
      yaml_subkeys+=("$yaml_key"); yaml_indents+=("$yaml_indent") # Push key and indent to stack
      yaml_set_value "$yaml_prefix $yaml_key" 'null' '_'              # tag:yaml.org,2002:null
      yaml_previous="$yaml_key"
    elif [[ "$yaml_value" =~ ^((\")|(-?[tf0-9]+(\.|[Ee])?)|(\||\>)|(\{|\[)|n) ]]
    then                                    # If value
      if [[ -n "$yaml_key" ]]; then yaml_previous="$yaml_key"; else yaml_previous=''; fi
      if [[ -n "${BASH_REMATCH[2]}" ]]      # If string value
      then yaml_value="$yaml_string"; yaml_decode 'yaml_value' # Unescape
        yaml_set_value "$yaml_prefix_key" 'str'                  # tag:yaml.org,2002:str
        if [[ "$yaml_v" == true ]]; then echo -n "YAML: $yaml_prefix_key=\"" >&2
          yaml_encode 'yaml_string' >&2; echo '"' >&2; fi
      elif [[ -n "${BASH_REMATCH[3]}" ]]    # If boolean or number value
      then case "${BASH_REMATCH[4]:-"${BASH_REMATCH[3]:0:1}"}" in
          .|E|e) yaml_set_value "$yaml_prefix_key" 'float';;     # tag:yaml.org,2002:float
          t|f) yaml_set_value "$yaml_prefix_key" 'bool';;        # tag:yaml.org,2002:bool
          *) yaml_set_value "$yaml_prefix_key" 'int';; esac      # tag:yaml.org,2002:int
        if [[ "$yaml_v" == true ]]; then echo "YAML: $yaml_prefix_key=$yaml_value" >&2; fi
      elif [[ -n "${BASH_REMATCH[5]}" ]]    # If block value
      then yaml_block=true; yaml_style=''; yaml_var=() # Trigger block init on next loop
        if [[ -z "$yaml_key" ]]; then yaml_indent="$(("$yaml_indent"-1))"; fi
      elif [[ -n "${BASH_REMATCH[6]}" ]]    # If JSON object/array / YAML flow mapping/sequence
      then case "${BASH_REMATCH[6]}" in \{) yaml_json='{}';; \[) yaml_json='[]';; esac
        if [[ "$yaml_value" =~ ^(\{\}|\[\])[[:blank:]]*(#.*)?$ ]] # Check whether empty
        then case "$yaml_json" in # For empty mapping/sequence {}/[], set type but not value
            '{}') yaml_set_value "$yaml_prefix_key" 'map' '_';;  # tag:yaml.org,2002:map
            '[]') yaml_set_value "$yaml_prefix_key" 'seq' '_';;  # tag:yaml.org,2002:seq
          esac; yaml_json=false # Optimization: don't read JSON for empty mapping/sequence
        else yaml_json_open=0; yaml_json_close=0; yaml_var=(); yaml_read_json "$yaml_value"; fi
      else                                  # If explicit/implicit null
        yaml_set_value "$yaml_prefix_key" 'null' '_'; fi         # tag:yaml.org,2002:null
    else yaml_set_value "$yaml_prefix" 'null' '_'; fi            # tag:yaml.org,2002:null
  else # shellcheck disable=SC2034
    yaml_invalid=true; echo "Warning: Ignoring YAML (unsupported syntax)." >&2; fi
  yaml_line=''; done # Reset line continuation before next line
