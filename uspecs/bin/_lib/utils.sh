#!/usr/bin/env bash

# Well, we do not neeed it, since it is sourced, just for consistency with other scripts
set -Eeuo pipefail

# Source guard - utils.sh must only be sourced once per shell.
if [[ -n "${_UTILS_SH_LOADED:-}" ]]; then
    return 0
fi
_UTILS_SH_LOADED=1

# atexit API - safe accumulating EXIT handlers
_ATEXIT_CMDS=()
_ATEXIT_STACK=()
_ATEXIT_CHAINED=""

_atexit_run() {
    local rc=$?
    trap - EXIT  # prevent re-entrancy if a chained handler calls exit
    local cmd
    for cmd in "${_ATEXIT_CMDS[@]+"${_ATEXIT_CMDS[@]}"}"; do
        eval "$cmd" || true
    done
    local i
    for (( i=${#_ATEXIT_STACK[@]}-1; i>=0; i-- )); do
        eval "${_ATEXIT_STACK[$i]}" || true
    done
    # Run chained pre-existing trap last so our cleanup completes even if it calls exit
    if [[ -n "$_ATEXIT_CHAINED" ]]; then
        eval "$_ATEXIT_CHAINED" || true
    fi
    exit "$rc"
}

# Capture any pre-existing EXIT trap and chain it last.
# The source guard above guarantees this runs at most once per shell, preventing
# the self-chaining recursion that would occur on double-sourcing.
{ _prev_trap=$(trap -p EXIT | sed "s/^trap -- '\\(.*\\)' EXIT$/\\1/")
  _ATEXIT_CHAINED="${_prev_trap:-}"
  unset _prev_trap; }
trap _atexit_run EXIT

# atexit_add <cmd>
# Appends cmd to the FIFO queue of EXIT handlers.
# cmd must be a single quoted string, e.g. atexit_add 'rm -f /tmp/foo'
atexit_add() {
    [[ $# -eq 1 ]] || { echo "atexit_add: expected 1 argument, got $#" >&2; return 1; }
    _ATEXIT_CMDS+=("$1")
}

# atexit_push <cmd>
# Pushes cmd onto the LIFO stack; dispatcher runs stack entries after _ATEXIT_CMDS.
# cmd must be a single quoted string, e.g. atexit_push 'rm -f /tmp/foo'
atexit_push() {
    [[ $# -eq 1 ]] || { echo "atexit_push: expected 1 argument, got $#" >&2; return 1; }
    _ATEXIT_STACK+=("$1")
}

# atexit_pop
# Removes the last-pushed entry from the stack.
atexit_pop() {
    if [[ ${#_ATEXIT_STACK[@]} -gt 0 ]]; then
        unset '_ATEXIT_STACK[-1]'
    fi
}

# git_path
# Ensures Git's usr/bin is in PATH on Windows (Git Bash / MSYS2 / Cygwin).
# Call this at the start of main() in every top-level script.
git_path() {
    if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
        PATH="/usr/bin:${PATH}"
    fi
}

# quiet <command> [args...]
# Runs the command with both stdout and stderr suppressed.
# On failure, dumps captured stdout to stdout and stderr to stderr,
# then returns the original exit code.
quiet() {
    local _q_out _q_err _q_rc=0
    _q_err=$(mktemp)
    _q_out=$("$@" 2>"$_q_err") || _q_rc=$?
    if [[ $_q_rc -ne 0 ]]; then
        [[ -n "$_q_out" ]] && printf '%s\n' "$_q_out"
        [[ -s "$_q_err" ]] && cat "$_q_err" >&2
    fi
    rm -f "$_q_err"
    return $_q_rc
}

# error <message>
# Prints an error message to stderr and exits with status 1.
error() {
    echo "Error: $1" >&2
    exit 1
}

# is_tty
# Returns 0 if stdin is connected to a terminal, 1 if piped or redirected.
is_tty() {
    [ -t 0 ]
}

# is_git_repo <dir>
# Returns 0 if <dir> is inside a git repository, 1 otherwise.
# //TODO replace with git.sh#git_validate_working_tree

is_git_repo() {
    local dir="$1"
    (cd "$dir" && git rev-parse --git-dir > /dev/null 2>&1)
}

# ---------------------------------------------------------------------------
# emit_prompt: file-per-section prompt emission with dependency resolution
# ---------------------------------------------------------------------------

# Global state for emit_prompt
declare -gA _EMIT_SEEN=()    # dedup: id -> 1
declare -ga _EMIT_QUEUE=()   # ordered list of entries: "tag\x1fid\x1fdescr\x1fbody"

# emit_prompt_reset
# Clears dedup and queue state. Call before starting a new emission sequence.
emit_prompt_reset() {
    _EMIT_SEEN=()
    _EMIT_QUEUE=()
}

# _emit_process_body <raw_body> <section_id> <file> [vars_map_name]
# Shared processing: conditional lines, variable substitution.
# Prints the processed body to stdout.
_emit_process_body() {
    local raw_body="$1"
    local section_id="$2"
    local file="$3"
    local vars_name="${4:-}"

    # Filter conditional lines: (?var) / (?!var)
    local filtered=""
    local _ep_cline _ep_negate _ep_cvar _ep_cval _ep_skip
    while IFS= read -r _ep_cline || [[ -n "$_ep_cline" ]]; do
        _ep_skip=0
        while [[ "$_ep_cline" =~ \(\?(\!?)([a-zA-Z_][a-zA-Z0-9_]*)\)[[:space:]]*$ ]]; do
            _ep_negate="${BASH_REMATCH[1]}"
            _ep_cvar="${BASH_REMATCH[2]}"
            _ep_cval=""
            if [[ -n "$vars_name" ]]; then
                local -n _ep_cond_map="$vars_name"
                if [[ -v "_ep_cond_map[$_ep_cvar]" ]]; then
                    _ep_cval="${_ep_cond_map[$_ep_cvar]}"
                else
                    error "unknown condition variable '${_ep_cvar}' in $section_id of $file (not in vars map '$vars_name')"
                fi
            else
                error "conditional (?${_ep_negate}${_ep_cvar}) in $section_id of $file but no vars map provided"
            fi
            if [[ -n "$_ep_negate" ]]; then
                [[ -z "$_ep_cval" ]] || _ep_skip=1
            else
                [[ -n "$_ep_cval" ]] || _ep_skip=1
            fi
            _ep_cline="${_ep_cline%"${BASH_REMATCH[0]}"}"
            _ep_cline="${_ep_cline%"${_ep_cline##*[! ]}"}"
        done
        (( _ep_skip )) && continue
        filtered+="${_ep_cline}"$'\n'
    done <<< "$raw_body"

    # Substitute ${KEY} patterns using pure bash (no subshells, no awk)
    local body="$filtered"
    if [[ -n "$vars_name" ]]; then
        local -n _ep_vars="$vars_name"
        local _ep_key _ep_pat
        for _ep_key in "${!_ep_vars[@]}"; do
            _ep_pat="\${${_ep_key}}"
            body="${body//"$_ep_pat"/"${_ep_vars[$_ep_key]}"}"
        done
    fi

    # Check for remaining unsubstituted ${...} placeholders
    if [[ "$body" =~ \$\{[a-zA-Z_][a-zA-Z0-9_]*\} ]]; then
        error "unbound variable in $section_id of $file: ${BASH_REMATCH[0]}"
    fi

    printf '%s' "$body"
}

# _emit_collect <prompts_dir> <section_id> [vars_map_name]
# Recursively collects a prompt file and its @artdef_ dependencies.
# Dependencies are collected first (depth-first), then self is appended.
# Dedup via _EMIT_SEEN prevents double-emission.
_emit_collect() {
    local dir="$1"
    local id="$2"
    local vars_name="${3:-}"

    # Dedup guard
    [[ ! -v "_EMIT_SEEN[$id]" ]] || return 0
    _EMIT_SEEN[$id]=1

    local file="$dir/$id.md"
    [[ -f "$file" ]] || error "prompt file not found: $file"

    # Read file content
    local content
    content=$(< "$file")

    # Extract description from first # heading
    local descr=""
    local _ep_hline
    while IFS= read -r _ep_hline; do
        if [[ "$_ep_hline" =~ ^#[[:space:]]+(.*) ]]; then
            descr="${BASH_REMATCH[1]}"
            break
        fi
    done <<< "$content"

    # Extract body: everything after "## data" line
    local body="" found_data=0
    while IFS= read -r _ep_hline; do
        if (( found_data )); then
            body+="${_ep_hline}"$'\n'
        elif [[ "$_ep_hline" =~ ^##[[:space:]]+data[[:space:]]*$ ]]; then
            found_data=1
        fi
    done <<< "$content"

    (( found_data )) || error "missing '## data' marker in $file"

    # Process body (conditionals, vars, comments)
    local processed
    processed=$(_emit_process_body "$body" "$id" "$file" "$vars_name") || exit 1

    # Scan for @artdef_ dependencies and collect them first
    local _ep_scan="$processed"
    while [[ "$_ep_scan" =~ \`@(artdef_[a-zA-Z0-9_-]+)\` ]]; do
        local dep="${BASH_REMATCH[1]}"
        _ep_scan="${_ep_scan#*"${BASH_REMATCH[0]}"}"
        _emit_collect "$dir" "$dep" "$vars_name"
    done

    # Determine XML tag
    local tag="instruction"
    if [[ "$id" == artdef_* ]]; then
        tag="artdef"
    fi

    # Append self to queue (after dependencies)
    local sep=$'\x1f'
    _EMIT_QUEUE+=("${tag}${sep}${id}${sep}${descr}${sep}${processed}")
}

# emit_prompt <prompts_dir> <section_id> [vars_map_name]
# Entry point: resets state, collects the section and its dependencies,
# then emits all collected entries (dependencies first, root last).
emit_prompt() {
    emit_prompt_reset
    _emit_collect "$@"

    # Flush queue
    local entry tag id descr body sep=$'\x1f'
    for entry in "${_EMIT_QUEUE[@]}"; do
        tag="${entry%%"$sep"*}"; entry="${entry#*"$sep"}"
        id="${entry%%"$sep"*}"; entry="${entry#*"$sep"}"
        descr="${entry%%"$sep"*}"; body="${entry#*"$sep"}"

        printf '%s\n' "<${tag} id=\"${id}\" descr=\"${descr}\">"
        printf '%s\n' "$body"
        printf '%s\n' "</${tag}>"
    done
}

# md_read_frontmatter_field <file> <field_name>
# Extracts the value of a named field from YAML frontmatter (between --- delimiters).
# Returns the trimmed value. Fails if the file is missing or the field is not found.
md_read_frontmatter_field() {
    local file="$1"
    local field_name="$2"

    [[ -f "$file" ]] || error "file not found: $file"

    local value
    value=$(awk -v field="$field_name" '
        /^---$/ { block++; next }
        block == 1 {
            # Match "field_name: value"
            if ($0 ~ "^" field ":") {
                sub("^" field ":[[:space:]]*", "")
                print
                exit
            }
        }
        block >= 2 { exit }
    ' "$file")

    [[ -n "$value" ]] || error "frontmatter field not found: $field_name in $file"
    printf '%s\n' "$value"
}

# md_read_title <file>
# Extracts the text of the first top-level heading (# ...) from a markdown file.
# Skips YAML frontmatter if present. Fails if the file is missing or has no heading.
md_read_title() {
    local file="$1"

    [[ -f "$file" ]] || error "file not found: $file"

    local title
    title=$(awk '
        /^---$/ && !past_fm { in_fm = !in_fm; next }
        in_fm { next }
        !in_fm { past_fm = 1 }
        /^# / { sub(/^# /, ""); print; exit }
    ' "$file")

    [[ -n "$title" ]] || error "no title heading found in $file"
    printf '%s\n' "$title"
}

# ---------------------------------------------------------------------------
# Temp file/dir management with automatic cleanup
# ---------------------------------------------------------------------------

case "$OSTYPE" in
    msys*|cygwin*) _TMP_BASE=$(cygpath -w "$TEMP") ;;
    *)             _TMP_BASE="/tmp" ;;
esac

# temp_create_dir <varname>
# Creates a temporary directory, stores its path in the caller's variable
# <varname>, and registers it for cleanup on exit.
temp_create_dir() {
    local -n _out=$1
    _out=$(mktemp -d "$_TMP_BASE/uspecs.XXXXXX")
    atexit_add "rm -rf '$_out'"
}

# temp_create_file <varname>
# Creates a temporary file, stores its path in the caller's variable
# <varname>, and registers it for cleanup on exit.
temp_create_file() {
    local -n _out=$1
    _out=$(mktemp "$_TMP_BASE/uspecs.XXXXXX")
    atexit_add "rm -f '$_out'"
}

# sed_inplace file sed-args...
# Portable in-place sed. Uses -i.bak for BSD compatibility.
# Restores the original file on failure.
sed_inplace() {
    local file="$1"
    shift
    if ! sed -i.bak "$@" "$file"; then
        mv "${file}.bak" "$file" 2>/dev/null || true
        return 1
    fi
    rm -f "${file}.bak"
}


# ---------------------------------------------------------------------------
# Structured prompt output (LOG / AGENT_INSTRUCTIONS)
# ---------------------------------------------------------------------------

_PROMPT_LOG_OPEN=0

# _prompt_close_tags_on_exit
# EXIT handler: auto-closes open LOG and AGENT_INSTRUCTIONS tags.
# If LOG is still open (script failed before prompt_start_instructions),
# emits error-handling instructions.
# If AGENT_INSTRUCTIONS is open, emits the closing tag.
_prompt_close_tags_on_exit() {
    if [[ "${_PROMPT_LOG_OPEN:-0}" -eq 1 ]]; then
        echo "</LOG>"
        echo "<AGENT_INSTRUCTIONS>"
        echo "The script exited with an error."
        echo "Describe what happened based on the log above."
        echo "Suggest recovery options as a numbered list, include Cancel as a last item."
        echo "Do not take any further action until user explicitly chooses an option."
        echo "</AGENT_INSTRUCTIONS>"
    elif [[ "${_PROMPT_INSTR_OPEN:-0}" -eq 1 ]]; then
        echo "</AGENT_INSTRUCTIONS>"
    fi
}
atexit_add '_prompt_close_tags_on_exit'

# prompt_start_log
# Emits the opening <LOG> tag.
prompt_start_log() {
    _PROMPT_LOG_OPEN=1
    echo "<LOG>"
}

# prompt_start_instructions <mode>
# Closes the LOG block and opens an AGENT_INSTRUCTIONS block with a meta-instruction.
# mode: "results" - inform user about results
#        "action"  - artifact definitions followed by instructions
# The closing tag is emitted automatically on exit.
prompt_start_instructions() {
    if [[ $# -eq 0 ]]; then
        error "prompt_start_instructions requires a mode: results or action"
    fi
    local mode="$1"
    _PROMPT_LOG_OPEN=0
    _PROMPT_INSTR_OPEN=1
    echo "</LOG>"
    echo "<AGENT_INSTRUCTIONS>"
    case "$mode" in
        results)
            echo "Inform user about the results, see below. Ignore the <LOG> content above."
            ;;
        action)
            echo "See artifact definitions below, followed by instructions."
            ;;
        *)
            error "prompt_start_instructions: unknown mode '$mode' (expected: results or action)"
            ;;
    esac
}
