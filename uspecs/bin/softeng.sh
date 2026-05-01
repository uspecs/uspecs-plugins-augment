#!/usr/bin/env bash

# Re-exec under a modern Bash if the current interpreter is too old.
# This script uses Bash 4.2+ features (declare -g, -gA). macOS still ships
# /bin/bash 3.2, so an explicit `/bin/bash bin/softeng.sh` would otherwise fail.
# The check below uses only Bash 3.2-safe syntax.
if [ -z "${SOFTENG_BASH_REEXEC:-}" ] && \
   { [ -z "${BASH_VERSINFO+x}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ] || \
     { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; }; then
    for _candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash; do
        if [ -x "$_candidate" ]; then
            # shellcheck disable=SC2016
            _cand_major=$("$_candidate" -c 'echo ${BASH_VERSINFO[0]}')
            # shellcheck disable=SC2016
            _cand_minor=$("$_candidate" -c 'echo ${BASH_VERSINFO[1]}')
            if [ "$_cand_major" -gt 4 ] || \
               { [ "$_cand_major" -eq 4 ] && [ "$_cand_minor" -ge 2 ]; }; then
                export SOFTENG_BASH_REEXEC=1
                exec "$_candidate" "$0" "$@"
            fi
        fi
    done
    echo "Error: this script requires Bash 4.2+. Found Bash ${BASH_VERSION:-unknown}." >&2
    echo "Install a modern Bash (e.g. 'brew install bash') and retry." >&2
    exit 1
fi

set -Eeuo pipefail

# softeng automation
#
# Usage:
#   softeng action uchange --kebab-name <name> [--no-impl] [--branch] [--no-branch] [--issue-url <url>]
#   softeng action uimpl [--change-folder <path>]
#   softeng action uarchive [--change-folder <path>] [--all]
#   softeng action upr [--no-archive]
#   softeng action umergepr
#   softeng action usync [-y]
#   softeng change list-wcf
#   softeng diff specs
#   softeng diff file <path>
#
# diff specs:
#   Outputs git diff of the specs folder between HEAD and pr_remote/default_branch.
# diff file <path>:
#   Outputs git diff of a single file between merge-base and HEAD.

get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

get_baseline() {
    local _is_git
    context_is_git_repo _is_git
    if [[ "$_is_git" == "1" ]]; then
        git rev-parse HEAD 2>/dev/null || echo ""
    else
        echo ""
    fi
}

get_folder_name() {
    local path="$1"
    basename "$path"
}

count_uncompleted_items() {
    local folder="$1"
    local count
    count=$(grep -r "^[[:space:]]*-[[:space:]]*\[ \]" "$folder"/*.md 2>/dev/null | wc -l)
    echo "${count:-0}" | tr -d ' '
}

extract_change_name() {
    local folder_name="$1"
    # shellcheck disable=SC2001
    echo "$folder_name" | sed 's/^[0-9]\{10\}-//'
}

move_folder() {
    local source="$1"
    local destination="$2"
    local project_dir="${3:-}"
    local check_dir="${project_dir:-$PWD}"
    if is_git_repo "$check_dir"; then
        if [[ -n "$project_dir" ]]; then
            local rel_src="${source#"$project_dir/"}"
            local rel_dst="${destination#"$project_dir/"}"
            git mv "$rel_src" "$rel_dst" 2>/dev/null || mv "$source" "$destination"
        else
            git mv "$source" "$destination" 2>/dev/null || mv "$source" "$destination"
        fi
    else
        mv "$source" "$destination"
    fi
}

# Cache script dir at source time (one subshell, reused everywhere).
_CTX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$OSTYPE" in
    msys*|cygwin*) _CTX_SCRIPT_DIR=$(cygpath -w "$_CTX_SCRIPT_DIR") ;;
esac

# shellcheck source=_lib/utils.sh
source "$_CTX_SCRIPT_DIR/_lib/utils.sh"
# shellcheck source=_lib/git.sh
source "$_CTX_SCRIPT_DIR/_lib/git.sh"

# ---------------------------------------------------------------------------
# Context accessors (param-by-ref, no subshells)
# The script must be invoked from the project root directory.
# ---------------------------------------------------------------------------

# context_project_dir <varname>
# Project dir is the current working directory (script invoked from project root).
context_project_dir() {
    local -n _cpd_ref=$1
    _cpd_ref="."
}

# context_changes_folder <varname>
# Returns the changes folder path relative to project root.
context_changes_folder() {
    local -n _ccf_ref=$1
    _ccf_ref="uspecs/changes"
}

# context_specs_folder <varname>
# Returns the specs folder path relative to project root.
context_specs_folder() {
    local -n _csf_ref=$1
    _csf_ref="uspecs/specs"
}

# context_prompts_dir <varname>
# Returns the prompts directory path.
context_prompts_dir() {
    local -n _cprd_ref=$1
    _cprd_ref="$_CTX_SCRIPT_DIR/prompts"
}

_CTX_IS_GIT_REPO=""

# context_is_git_repo <varname>
# Sets caller's variable to "1" if inside a git repo, "0" otherwise. Cached.
context_is_git_repo() {
    if [[ -z "$_CTX_IS_GIT_REPO" ]]; then
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            _CTX_IS_GIT_REPO="1"
        else
            _CTX_IS_GIT_REPO="0"
        fi
    fi
    local -n _cigr_ref=$1
    _cigr_ref="$_CTX_IS_GIT_REPO"
}

extract_issue_id() {
    # Extract issue ID from the last segment of an issue URL
    # Takes the last /-separated segment, finds the first contiguous
    # run of valid characters (alphanumeric, hyphens, underscores)
    local url="$1"
    local segment="${url##*/}"
    if [[ "$segment" =~ ^[^a-zA-Z0-9_-]*([a-zA-Z0-9_-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# TODO: this is a part of obsoleted approach, refactor
cmd_change_new() {
    local change_name=""
    local issue_url=""
    local opt_branch=""
    local opt_no_branch=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue-url)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    error "--issue-url requires a URL argument"
                fi
                issue_url="$2"
                shift 2
                ;;
            --branch)
                opt_branch="1"
                shift
                ;;
            --no-branch)
                opt_no_branch="1"
                shift
                ;;
            *)
                if [ -z "$change_name" ]; then
                    change_name="$1"
                    shift
                else
                    error "Unknown argument: $1"
                fi
                ;;
        esac
    done

    if [ -n "$opt_branch" ] && [ -n "$opt_no_branch" ]; then
        error "--branch and --no-branch are mutually exclusive"
    fi

    local is_new_branch="1"
    if [ -n "$opt_no_branch" ]; then
        is_new_branch=""
    elif [ -z "$opt_branch" ]; then
        # Skip branch creation when not on the default branch (unless --branch forces it)
        local _is_git
        context_is_git_repo _is_git
        if [[ "$_is_git" == "1" ]]; then
            local current_branch_name
            current_branch_name=$(git symbolic-ref --short HEAD)
            local def_branch
            def_branch=$(git_default_branch_name || echo "")
            if [ "$current_branch_name" != "$def_branch" ]; then
                is_new_branch=""
            fi
        fi
    fi

    if [ -z "$change_name" ]; then
        error "change-name is required"
    fi

    if [[ ! "$change_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        error "change-name must be kebab-case (lowercase letters, numbers, hyphens): $change_name"
    fi

    local changes_folder_rel
    context_changes_folder changes_folder_rel

    local project_dir
    context_project_dir project_dir

    local changes_folder="$project_dir/$changes_folder_rel"


    local timestamp
    timestamp=$(date -u +"%y%m%d%H%M")

    local folder_name="${timestamp}-${change_name}"
    local change_folder="$changes_folder/$folder_name"

    if [ -d "$change_folder" ]; then
        error "Change folder already exists: $change_folder"
    fi

    mkdir -p "$change_folder"

    local registered_at baseline
    registered_at=$(get_timestamp)
    baseline=$(get_baseline "$project_dir")

    local frontmatter="---"$'\n'
    frontmatter+="registered_at: $registered_at"$'\n'
    frontmatter+="change_id: $folder_name"$'\n'

    if [ -n "$baseline" ]; then
        frontmatter+="baseline: $baseline"$'\n'
    fi

    if [ -n "$issue_url" ]; then
        frontmatter+="issue_url: $issue_url"$'\n'
    fi

    frontmatter+="---"

    printf '%s\n' "$frontmatter" > "$change_folder/change.md"

    if [ -n "$is_new_branch" ]; then
        local _is_git
        context_is_git_repo _is_git
        if [[ "$_is_git" == "1" ]]; then
            local branch_name="$change_name"
            if [ -n "$issue_url" ]; then
                local issue_id
                issue_id=$(extract_issue_id "$issue_url")
                if [ -n "$issue_id" ]; then
                    branch_name="${issue_id}-${change_name}"
                fi
            fi
            if ! git checkout -b "$branch_name"; then
                echo "Warning: Failed to create branch '$branch_name'" >&2
            fi
        else
            echo "Warning: Not a git repository, cannot create branch" >&2
        fi
    fi

    echo "$changes_folder_rel/$folder_name"
}

convert_links_to_relative() {
    local folder="$1"

    if [ -z "$folder" ]; then
        error "folder path is required for convert_links_to_relative"
    fi

    if [ ! -d "$folder" ]; then
        error "Folder not found: $folder"
    fi

    # Find all .md files in the folder
    local md_files
    md_files=$(find "$folder" -maxdepth 1 -name "*.md" -type f)

    if [ -z "$md_files" ]; then
        # No markdown files to process, return success
        return 0
    fi

    # Process each markdown file
    while IFS= read -r file; do
        # Archive moves folder 2 levels deeper (changes/ -> changes/archive/yymm/)
        # Only paths starting with ../ need adjustment - add ../../ prefix
        #
        # Example: ](../foo) -> ](../../../foo)
        #
        # Skip (do not modify):
        # - http://, https:// (absolute URLs)
        # - # (anchors)
        # - / (absolute paths)
        # - ./ (current directory - stays in same folder)
        # - filename.ext (same folder files like impl.md, issue.md)

        # Add ../../ prefix to paths starting with ../
        # ](../ -> ](../../../
        if ! sed_inplace "$file" -E 's#\]\(\.\./#](../../../#g'; then
            error "Failed to convert links in file: $file"
        fi
    done <<< "$md_files"

    return 0
}

# changes_archive <project_dir> <changes_folder> <change_folder> <is_git> <result_var>
# Archives an active change folder: updates YAML metadata, converts links,
# moves to archive/YYMM/YYMMDDHHMM-<change_name>.
# project_dir: absolute path to project root
# changes_folder: relative to project_dir (e.g. uspecs/changes)
# change_folder: relative to project_dir (e.g. uspecs/changes/2601010000-my-change)
# is_git: "1" if project is a git repo, "0" otherwise
# Sets result_var (nameref) to the archived folder path, relative to project_dir.
changes_archive() {
    local project_dir="$1"
    local changes_folder="$2"
    local change_folder="$3"
    local is_git="$4"
    local -n result_ref="$5"

    local abs_change="$project_dir/$change_folder"
    local abs_changes="$project_dir/$changes_folder"

    local folder_basename
    folder_basename=$(basename "$change_folder")

    local change_name
    change_name=$(extract_change_name "$folder_basename")

    local change_file="$abs_change/change.md"

    local timestamp
    timestamp=$(get_timestamp)

    # Insert archived_at into YAML front matter (before closing ---)
    local temp_file
    temp_create_file temp_file
    # // TODO archived_at may already exists...
    awk -v ts="$timestamp" '
        /^---$/ {
            if (count == 0) {
                print
                count++
            } else {
                print "archived_at: " ts
                print
            }
            next
        }
        /^archived_at:/ { next }
        { print }
    ' "$change_file" > "$temp_file"
    if cat "$temp_file" > "$change_file"; then
        :  # Success, continue
    else
        error "failed to update $change_file"
    fi

    # Add ../ prefix to relative links for archive folder depth
    if ! convert_links_to_relative "$abs_change"; then
        error "failed to convert links to relative paths"
    fi

    local archive_dir="$abs_changes/archive"

    local date_prefix
    date_prefix=$(date -u +"%y%m%d%H%M")

    local yymm="${date_prefix:0:4}"

    local archive_sub="$archive_dir/$yymm"
    mkdir -p "$archive_sub"

    local dest="$archive_sub/${date_prefix}-${change_name}"

    if [ -d "$dest" ]; then
        error "Archive folder already exists: $dest"
    fi

    if [[ "$is_git" == "1" ]]; then
        quiet git add "$change_folder"
    fi

    move_folder "$abs_change" "$dest" "$project_dir"

    local rel_dest="${dest#"$project_dir/"}"

    if [[ "$is_git" == "1" ]]; then
        quiet git add "$rel_dest"
    fi

    # shellcheck disable=SC2034
    result_ref="$rel_dest"
}

# wcf_list <project_dir> <changes_folder_rel> [<pr_remote> <default_branch>]
# Lists Working Change Folders -- change folders whose files have been modified
# since merge-base with pr_remote/default_branch (committed or uncommitted).
# If there is no git repository, returns all Change Folders (non-archive subdirs).
# Outputs one relative path per line (from changes_folder), sorted.
# Does not error on 0 or multiple results.
wcf_list() {
    local project_dir="$1"
    local changes_folder_rel="$2"
    local pr_remote="${3:-}"
    local default_branch="${4:-}"

    local changes_folder="$project_dir/$changes_folder_rel"

    local _is_git
    context_is_git_repo _is_git
    if [[ "$_is_git" != "1" ]]; then
        # No git -- return all non-archive subdirs that contain change.md
        local dir
        for dir in "$changes_folder"/*/; do
            [[ -d "$dir" ]] || continue
            local fname
            fname=$(basename "$dir")
            [[ "$fname" == "archive" ]] && continue
            printf '%s\n' "$fname"
        done | sort
        return 0
    fi

    # Determine merge-base (need pr_remote and default_branch)
    local merge_base=""
    if [[ -n "$pr_remote" && -n "$default_branch" ]]; then
        merge_base=$(git merge-base HEAD "${pr_remote}/${default_branch}" 2>/dev/null) || true
    fi

    # Collect changed files: committed diff + uncommitted (staged + unstaged)
    local all_changed=""
    if [[ -n "$merge_base" ]]; then
        all_changed=$(git diff --name-only "$merge_base" HEAD -- "$changes_folder_rel" 2>/dev/null) || true
    fi
    # Uncommitted changes (staged + unstaged working tree)
    local uncommitted
    uncommitted=$(git diff --name-only HEAD -- "$changes_folder_rel" 2>/dev/null) || true
    # Untracked files
    local untracked
    untracked=$(git ls-files --others --exclude-standard -- "$changes_folder_rel" 2>/dev/null) || true

    # Merge all sources
    all_changed=$(printf '%s\n%s\n%s\n' "$all_changed" "$uncommitted" "$untracked")

    # Collect unique change folder paths.
    # Active folders: first path component (e.g. "my-change")
    # Archived folders: archive/yymm/<name> (3 components)
    local -A folders=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Strip changes_folder_rel/ prefix
        local rel="${line#"${changes_folder_rel}/"}"
        local top="${rel%%/*}"
        [[ -z "$top" ]] && continue
        if [[ "$top" == "archive" ]]; then
            # Extract archive/yymm/<name> (3 path components)
            local rest="${rel#archive/}"
            local yymm="${rest%%/*}"
            rest="${rest#"$yymm"/}"
            local name="${rest%%/*}"
            if [[ -n "$yymm" && -n "$name" ]]; then
                folders["archive/$yymm/$name"]=1
            fi
        else
            folders["$top"]=1
        fi
    done <<< "$all_changed"

    printf '%s\n' "${!folders[@]}" | sort
}

# cmd_change_list_wcf
# Lists Working Change Folders. Resolves pr_remote/default_branch automatically.
cmd_change_list_wcf() {
    local project_dir
    context_project_dir project_dir

    local changes_folder_rel
    context_changes_folder changes_folder_rel

    local pr_remote="" default_branch=""
    local _is_git
    context_is_git_repo _is_git
    if [[ "$_is_git" == "1" ]]; then
        local -A pr_info
        if git_pr_info pr_info "$project_dir"; then
            pr_remote="${pr_info[pr_remote]:-}"
            default_branch="${pr_info[default_branch]:-}"
        fi
    fi

    wcf_list "$project_dir" "$changes_folder_rel" "$pr_remote" "$default_branch"
}

# wcf_resolve_active
# Resolves active (non-archive) Working Change Folders.
# Resolves project_dir, changes_folder_rel, pr_remote/default_branch internally.
# Outputs newline-separated active WCF names to stdout (consistent with wcf_list).
wcf_resolve_active() {
    local project_dir
    context_project_dir project_dir

    local changes_folder_rel
    context_changes_folder changes_folder_rel

    local pr_remote="" default_branch=""
    local _is_git
    context_is_git_repo _is_git
    if [[ "$_is_git" == "1" ]]; then
        local -A pr_info
        if git_pr_info pr_info "$project_dir"; then
            pr_remote="${pr_info[pr_remote]:-}"
            default_branch="${pr_info[default_branch]:-}"
        fi
    fi

    local wcf_output
    wcf_output=$(wcf_list "$project_dir" "$changes_folder_rel" "$pr_remote" "$default_branch")

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == archive/* ]] && continue
        printf '%s\n' "$line"
    done <<< "$wcf_output"
}

# changes_validate_single_wcf <project_dir> <changes_folder_rel> <pr_remote> <default_branch>
# Reflects scenario: "Exactly one Working Change Folder"
# Detects the Working Change Folder (WCF) -- a change folder whose files have been
# modified since merge-base with pr_remote/default_branch.
# Outputs the relative path from changes_folder (e.g. "my-change" for active,
# "archive/yymm/timestamp-name" for archived). Fails if not exactly one WCF is found.
changes_validate_single_wcf() {
    local project_dir="$1"
    local changes_folder_rel="$2"
    local pr_remote="$3"
    local default_branch="$4"

    local wcf_output
    wcf_output=$(wcf_list "$project_dir" "$changes_folder_rel" "$pr_remote" "$default_branch")

    local -a wcf_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && wcf_array+=("$line")
    done <<< "$wcf_output"

    local count=${#wcf_array[@]}
    if [[ "$count" -eq 0 ]]; then
        error "No Working Change Folder found (no changes in $changes_folder_rel since merge-base)"
    elif [[ "$count" -gt 1 ]]; then
        local names
        names=$(printf '%s\n' "${wcf_array[@]}")
        error "Multiple Working Change Folders found (expected exactly one):\n$names"
    fi

    printf '%s\n' "${wcf_array[0]}"
}

# changes_validate_todos_completed <wcf_path> <project_dir>
# Reflects scenario: "All todo items are completed"
# Checks that there are no uncompleted todo items in the WCF.
# On failure, outputs error to stderr and exits.
changes_validate_todos_completed() {
    local wcf_path="$1"
    local project_dir="$2"

    local uncompleted_count
    uncompleted_count=$(count_uncompleted_items "$wcf_path")
    if [[ "$uncompleted_count" -gt 0 ]]; then
        local uncompleted_files
        uncompleted_files=$(grep -rl "^[[:space:]]*-[[:space:]]*\[ \]" "$wcf_path"/*.md 2>/dev/null | sed "s|^$project_dir/||")

        {
            echo "Error: $uncompleted_count uncompleted todo item(s) found in files:"
            echo ""
            echo "$uncompleted_files"
            echo ""
            echo "Complete todo items before creating a PR."
        } >&2
        exit 1
    fi
}


# cmd_action_uchange --kebab-name <name> [--no-impl] [--branch] [--no-branch] [--issue-url <url>] [--specs]
# Creates Change Folder via cmd_change_new, then emits AGENT_INSTRUCTIONS
# telling the agent to append sections to the created change.md.
cmd_action_uchange() {
    local opt_no_impl=""
    local opt_specs=""
    local opt_branch=""
    local opt_no_branch=""
    local issue_url=""
    local change_name=""
    local change_new_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-impl)
                # shellcheck disable=SC2034
                opt_no_impl="1"
                shift
                ;;
            --kebab-name)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    error "--kebab-name requires a name argument"
                fi
                change_name="$2"
                shift 2
                ;;
            --specs)
                opt_specs="1"
                shift
                ;;
            --branch)
                opt_branch="1"
                change_new_args+=("--branch")
                shift
                ;;
            --no-branch)
                opt_no_branch="1"
                change_new_args+=("--no-branch")
                shift
                ;;
            --issue-url)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    error "--issue-url requires a URL argument"
                fi
                issue_url="$2"
                change_new_args+=("--issue-url" "$2")
                shift 2
                ;;
            *)
                error "Unknown argument: $1"
                ;;
        esac
    done

    if [[ -z "$change_name" ]]; then
        error "--kebab-name is required"
    fi

    if [[ -n "$opt_branch" && -n "$opt_no_branch" ]]; then
        error "--branch and --no-branch are mutually exclusive"
    fi

    # Create Change Folder and change.md via cmd_change_new
    local change_folder_rel
    change_folder_rel=$(cmd_change_new "$change_name" "${change_new_args[@]+"${change_new_args[@]}"}")

    local project_dir
    context_project_dir project_dir

    local change_file="$change_folder_rel/change.md"

    local prompts_dir
    context_prompts_dir prompts_dir

    prompt_start_log
    echo "Action: uchange"
    echo "Change folder: $change_folder_rel"

    # Detect specs folder
    local specs_folder_rel
    context_specs_folder specs_folder_rel
    local specs_maybe=""
    if [[ -n "$opt_specs" ]]; then
        mkdir -p "$project_dir/$specs_folder_rel"
        specs_maybe="1"
    elif [[ -d "$project_dir/$specs_folder_rel" ]]; then
        specs_maybe="1"
    fi

    # Cascade `_maybe` flags collapse here because `cmd_uchange` has no impl
    # file: spec-tier flags follow `specs_maybe`; prov/constr are always on.
    # shellcheck disable=SC2034  # used via nameref in emit_prompt
    declare -A context_vars=(
        [change_file]="$change_file"
        [specs_folder]="$specs_folder_rel"
        [no_impl]="$opt_no_impl"
        [domains_maybe]="$specs_maybe"
        [fd_maybe]="$specs_maybe"
        [prov_maybe]="1"
        [td_maybe]="$specs_maybe"
        [constr_maybe]="1"
        [change_file_rel_path]="$change_file"
    )

    prompt_start_instructions "action"
    emit_prompt "$prompts_dir" "instr_uchange" context_vars
}


# cmd_action_uimpl [--change-folder <path>]
# Determines the Implementation Folder and emits AGENT_INSTRUCTIONS
# for the next implementation step.
cmd_action_uimpl() {
    local opt_change_folder=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --change-folder)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    error "--change-folder requires a path argument"
                fi
                opt_change_folder="$2"
                shift 2
                ;;
            *)
                error "Unknown argument: $1"
                ;;
        esac
    done

    local project_dir
    context_project_dir project_dir

    local changes_folder_rel
    context_changes_folder changes_folder_rel

    local prompts_dir
    context_prompts_dir prompts_dir

    prompt_start_log
    echo "Action: uimpl"

    local change_folder_rel=""

    if [[ -n "$opt_change_folder" ]]; then
        change_folder_rel="$opt_change_folder"
    else
        local -a active_wcfs=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && active_wcfs+=("$line")
        done <<< "$(wcf_resolve_active)"

        local count=${#active_wcfs[@]}
        if [[ "$count" -eq 0 ]]; then
            prompt_start_instructions "results"
            emit_prompt "$prompts_dir" "instr_uimpl_no_change_folder"
            return 0
        elif [[ "$count" -eq 1 ]]; then
            change_folder_rel="$changes_folder_rel/${active_wcfs[0]}"
        else
            # Multiple active WCFs -- let agent select
            local folder_list=""
            local i=1
            for f in "${active_wcfs[@]}"; do
                folder_list+="$i. $changes_folder_rel/$f"$'\n'
                ((i++))
            done
            # shellcheck disable=SC2034
            declare -A select_vars=(
                [next_command]="bash bin/softeng.sh action uimpl"
                [folder_list]="$folder_list"
            )
            prompt_start_instructions "results"
            emit_prompt "$prompts_dir" "instr_shared_select_change_folder" select_vars
            return 0
        fi
    fi

    echo "Change folder: $change_folder_rel"

    # Determine impl_file: if impl.md exists use it, else change.md
    local impl_file="change.md"
    if [[ -f "$project_dir/$change_folder_rel/impl.md" ]]; then
        impl_file="impl.md"
    fi
    echo "Implementation Plan File: $impl_file"

    local impl_file_path="$project_dir/$change_folder_rel/$impl_file"

    # Single pass: detect sections, unchecked items, and review item (no grep subprocesses)
    local domains_exists="" fd_exists="" prov_exists="" td_exists="" constr_exists=""
    local has_unchecked="" has_review_unchecked="" review_item="" review_is_checkbox=""
    local total_unchecked=0
    local _line_num=0
    local _first_review_line=""
    local unchecked_items=""
    local _in_item=0
    local _current_buf=""
    local _current_is_review=0
    local _seen_item=0
    local _area_closed=0

    _uimpl_flush_item() {
        if (( ! _current_is_review )) && [[ -n "$_current_buf" ]]; then
            unchecked_items+="$_current_buf"
        fi
        _current_buf=""
        _current_is_review=0
        _in_item=0
    }

    # Close the first contiguous run of unchecked items on section boundaries and
    # on non-indented non-empty lines. After the area is closed no further
    # unchecked items are collected (section-existence and review-item scans
    # continue across the whole file).
    _flush_and_close_area() {
        _uimpl_flush_item
        if (( _seen_item )) && (( ! _area_closed )); then
            _area_closed=1
        fi
    }

    while IFS= read -r _line; do
        ((_line_num++)) || true
        case "$_line" in
            "##"*"Domain specifications"*) domains_exists="1"; _flush_and_close_area ;;
            "##"*"Functional design"*)     fd_exists="1";      _flush_and_close_area ;;
            "##"*"Provisioning"*)          prov_exists="1";    _flush_and_close_area ;;
            "##"*"Technical design"*)      td_exists="1";      _flush_and_close_area ;;
            "##"*"Construction"*)          constr_exists="1";  _flush_and_close_area ;;
            "- [ ] "*)
                if (( _area_closed )); then
                    :
                else
                    _uimpl_flush_item
                    has_unchecked="1"
                    ((total_unchecked++)) || true
                    _current_buf="${_line}"$'\n'
                    _in_item=1
                    _seen_item=1
                    local _lower_item="${_line,,}"
                    if [[ "$_lower_item" =~ ^-[[:space:]]+\[[[:space:]]+\][[:space:]]+review($|[[:space:]]) ]]; then
                        _current_is_review=1
                    fi
                fi
                ;;
            *)
                if (( _in_item )); then
                    if [[ -z "$_line" ]]; then
                        _current_buf+=$'\n'
                    elif [[ "$_line" =~ ^[[:space:]] ]]; then
                        _current_buf+="${_line}"$'\n'
                    else
                        _flush_and_close_area
                    fi
                fi
                ;;
        esac
        # Detect review item (case-insensitive): "- [ ] Review...", "- Review..."
        if [[ -z "$_first_review_line" ]]; then
            local _lower="${_line,,}"
            if [[ "$_lower" =~ ^-[[:space:]]+(\[[[:space:]]+\][[:space:]]+)?review($|[[:space:]]) ]]; then
                _first_review_line="$_line_num:$_line"
            fi
        fi
    done < "$impl_file_path" 2>/dev/null || true
    _uimpl_flush_item

    if [[ -n "$_first_review_line" ]]; then
        has_review_unchecked="1"
        review_item="${_first_review_line#*:}"
        if [[ "$review_item" =~ ^-[[:space:]]+\[ ]]; then
            review_is_checkbox="1"
        fi
    fi

    # Count non-review unchecked items
    local non_review_unchecked_count=0
    if [[ -n "$has_unchecked" ]]; then
        if [[ -n "$review_is_checkbox" ]]; then
            non_review_unchecked_count=$((total_unchecked - 1))
        else
            non_review_unchecked_count=$total_unchecked
        fi
    fi

    # Detect specs_maybe
    local specs_folder_rel
    context_specs_folder specs_folder_rel
    local specs_maybe=""
    if [[ -d "$project_dir/$specs_folder_rel" ]]; then
        specs_maybe="1"
    fi

    # Cascade `_maybe` flags: each section is offered only when its own
    # heading is absent and no later-stage section exists. Spec-tier flags
    # additionally require `specs_maybe`. See uimpl.feature priority order.
    local domains_maybe="" fd_maybe="" prov_maybe="" td_maybe="" constr_maybe=""
    if [[ -n "$specs_maybe" && -z "$domains_exists" && -z "$fd_exists" && -z "$prov_exists" && -z "$td_exists" && -z "$constr_exists" ]]; then
        domains_maybe="1"
    fi
    if [[ -n "$specs_maybe" && -z "$fd_exists" && -z "$prov_exists" && -z "$td_exists" && -z "$constr_exists" ]]; then
        fd_maybe="1"
    fi
    if [[ -z "$prov_exists" && -z "$td_exists" && -z "$constr_exists" ]]; then
        prov_maybe="1"
    fi
    if [[ -n "$specs_maybe" && -z "$td_exists" && -z "$constr_exists" ]]; then
        td_maybe="1"
    fi
    if [[ -z "$constr_exists" ]]; then
        constr_maybe="1"
    fi

    # Branching
    if [[ "$non_review_unchecked_count" -eq 0 && -n "$has_review_unchecked" ]]; then
        # Only review item unchecked
        prompt_start_instructions "results"
        emit_prompt "$prompts_dir" "instr_uimpl_review_pending"
    elif [[ "$non_review_unchecked_count" -gt 0 ]]; then
        # Has unchecked to-do items (not just review)
        # shellcheck disable=SC2034
        declare -A todos_vars=(
            [change_folder]="$change_folder_rel"
            [impl_file]="$impl_file"
            [has_review]="$has_review_unchecked"
            [review_item]="${review_item:-}"
            [unchecked_items]="$unchecked_items"
        )
        prompt_start_instructions "action"
        emit_prompt "$prompts_dir" "instr_uimpl_todos" todos_vars
    else
        # No unchecked todos -- add next section
        # shellcheck disable=SC2034
        declare -A impl_vars=(
            [change_folder]="$change_folder_rel"
            [impl_file]="$impl_file"
            [specs_folder]="$specs_folder_rel"
            [domains_maybe]="$domains_maybe"
            [fd_maybe]="$fd_maybe"
            [prov_maybe]="$prov_maybe"
            [td_maybe]="$td_maybe"
            [constr_maybe]="$constr_maybe"
            [change_file_rel_path]="$change_folder_rel/$impl_file"
        )
        prompt_start_instructions "action"
        emit_prompt "$prompts_dir" "instr_uimpl" impl_vars
    fi
}


# cmd_action_uarchive [--change-folder <path>] [--all]
# Archives a change folder or all modified change folders.
cmd_action_uarchive() {
    local opt_change_folder=""
    local opt_all=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --change-folder)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    error "--change-folder requires a path argument"
                fi
                opt_change_folder="$2"
                shift 2
                ;;
            --all)
                opt_all="1"
                shift
                ;;
            *)
                error "Unknown argument: $1"
                ;;
        esac
    done

    if [[ -n "$opt_all" && -n "$opt_change_folder" ]]; then
        error "--all and --change-folder are mutually exclusive"
    fi

    local project_dir
    context_project_dir project_dir

    local changes_folder_rel
    context_changes_folder changes_folder_rel

    local prompts_dir
    context_prompts_dir prompts_dir

    prompt_start_log
    echo "Action: uarchive"

    local is_git=""
    context_is_git_repo is_git

    if [[ -n "$opt_all" ]]; then
        if [[ "$is_git" != "1" ]]; then
            error "--all requires a git repository"
        fi

        local -A pr_info
        if ! git_pr_info pr_info "$project_dir"; then
            error "--all requires remote info to be available (remote reachable?)"
        fi
        local pr_remote="${pr_info[pr_remote]:-}"
        local default_branch="${pr_info[default_branch]:-}"

        local changes_folder="$project_dir/$changes_folder_rel"

        echo "Fetching ${pr_remote}/${default_branch}..."
        git fetch "$pr_remote" "$default_branch" 2>&1

        if [ ! -d "$changes_folder" ]; then
            error "Changes folder not found: $changes_folder"
        fi

        local archived=0 unchanged=0 failed=0
        local archiveall_output=""

        for folder_path in "$changes_folder"/*/; do
            [ -d "$folder_path" ] || continue
            local fname
            fname=$(basename "$folder_path")
            [ "$fname" = "archive" ] && continue

            local rel_folder="$changes_folder_rel/$fname"
            local diff_output
            diff_output=$(git diff --name-only "${pr_remote}/${default_branch}" HEAD -- "$rel_folder")
            if [ -z "$diff_output" ]; then
                unchanged=$((unchanged + 1))
                continue
            fi

            local uncompleted_count
            uncompleted_count=$(count_uncompleted_items "$folder_path")
            if [ "$uncompleted_count" -gt 0 ]; then
                archiveall_output+="failed: $rel_folder (uncompleted items)"$'\n'
                failed=$((failed + 1))
                continue
            fi

            local archive_path=""
            if changes_archive "$project_dir" "$changes_folder_rel" "$rel_folder" "$is_git" archive_path; then
                archiveall_output+="ok: $rel_folder -> $archive_path"$'\n'
                archived=$((archived + 1))
            else
                archiveall_output+="failed: $rel_folder (archive error)"$'\n'
                failed=$((failed + 1))
            fi
        done

        archiveall_output+="Done: $archived archived, $unchanged unchanged, $failed failed"
        echo "$archiveall_output"

        # shellcheck disable=SC2034
        declare -A all_vars=(
            [archiveall_output]="$archiveall_output"
        )
        prompt_start_instructions "results"
        emit_prompt "$prompts_dir" "instr_uarchive_all" all_vars

        if [ "$failed" -gt 0 ]; then
            return 1
        fi
        return 0
    fi

    local change_folder_name=""

    if [[ -n "$opt_change_folder" ]]; then
        # Extract folder name from relative path (e.g. uspecs/changes/foo -> foo)
        change_folder_name=$(basename "$opt_change_folder")
    else
        local -a active_wcfs=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && active_wcfs+=("$line")
        done <<< "$(wcf_resolve_active)"

        local count=${#active_wcfs[@]}
        if [[ "$count" -eq 0 ]]; then
            prompt_start_instructions "results"
            emit_prompt "$prompts_dir" "instr_uarchive_no_change_folder"
            return 0
        elif [[ "$count" -eq 1 ]]; then
            change_folder_name="${active_wcfs[0]}"
        else
            # Multiple active WCFs -- let agent select
            local folder_list=""
            local i=1
            for f in "${active_wcfs[@]}"; do
                folder_list+="$i. $changes_folder_rel/$f"$'\n'
                ((i++))
            done
            # shellcheck disable=SC2034
            declare -A select_vars=(
                [next_command]="bash bin/softeng.sh action uarchive"
                [folder_list]="$folder_list"
            )
            prompt_start_instructions "results"
            emit_prompt "$prompts_dir" "instr_shared_select_change_folder" select_vars
            return 0
        fi
    fi

    # Validate folder
    local path_to_change_folder="$project_dir/$changes_folder_rel/$change_folder_name"

    if [ ! -d "$path_to_change_folder" ]; then
        error "Folder not found: $path_to_change_folder"
    fi

    if [ ! -f "$path_to_change_folder/change.md" ]; then
        error "change.md not found in folder: $path_to_change_folder"
    fi

    local uncompleted_count
    uncompleted_count=$(count_uncompleted_items "$path_to_change_folder")
    if [ "$uncompleted_count" -gt 0 ]; then
        echo "Cannot archive: $uncompleted_count uncompleted todo item(s) found"
        echo ""
        echo "Uncompleted items:"
        grep -rn "^[[:space:]]*-[[:space:]]*\[ \]" "$path_to_change_folder"/*.md 2>/dev/null | sed 's/^/  /'
        echo ""
        echo "Complete or cancel todo items before archiving"
        exit 1
    fi

    echo "Archiving: $changes_folder_rel/$change_folder_name"

    local archive_path=""
    changes_archive "$project_dir" "$changes_folder_rel" "$changes_folder_rel/$change_folder_name" "$is_git" archive_path

    # shellcheck disable=SC2034
    declare -A success_vars=(
        [archive_path]="$archive_path"
    )
    prompt_start_instructions "results"
    emit_prompt "$prompts_dir" "instr_uarchive_success" success_vars
}


# cmd_action_usync [-y]
# Aligns Working Change Folder plan and specs with source changes.
# Emits prompt with diff or file list depending on diff size.
cmd_action_usync() {
    local opt_yes=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y) opt_yes="1"; shift ;;
            *) error "Unknown argument: $1" ;;
        esac
    done

    local project_dir
    context_project_dir project_dir

    prompt_start_log
    echo "Action: usync"

    # Validate preconditions
    git_validate_working_tree

    local current_branch
    current_branch=$(git symbolic-ref --short HEAD)

    local pr_remote default_branch
    pr_remote=$(determine_pr_remote)
    default_branch=$(git_default_branch_name)

    git_validate_clean_repo "$current_branch" "$default_branch"

    echo "Branch: $current_branch -> $pr_remote/$default_branch"

    # Fetch remote default branch
    echo "Fetching $pr_remote/$default_branch..."
    quiet git fetch "$pr_remote" "$default_branch"

    # Detect Working Change Folder
    local changes_folder_rel
    context_changes_folder changes_folder_rel
    local wcf_name
    wcf_name=$(changes_validate_single_wcf "$project_dir" "$changes_folder_rel" "$pr_remote" "$default_branch")
    echo "Working Change Folder: $wcf_name"

    local change_folder_rel="$changes_folder_rel/$wcf_name"

    # Resolve specs folder
    local specs_folder_rel
    context_specs_folder specs_folder_rel

    # Resolve prompts dir
    local prompts_dir
    context_prompts_dir prompts_dir

    # Check impl.md and issue.md existence
    local impl_exists=""
    if [[ -f "$project_dir/$change_folder_rel/impl.md" ]]; then
        impl_exists="1"
    fi
    local issue_exists=""
    if [[ -f "$project_dir/$change_folder_rel/issue.md" ]]; then
        issue_exists="1"
    fi

    # Compute merge-base and diff
    local merge_base
    merge_base=$(git merge-base HEAD "${pr_remote}/${default_branch}")

    local diff_file
    temp_create_file diff_file
    git diff "$merge_base" HEAD -- . ":(exclude)$changes_folder_rel/*" > "$diff_file" || true

    local diff_size
    diff_size=$(wc -c < "$diff_file" | tr -d ' ')
    echo "Diff size: $diff_size bytes"

    local diff_threshold=102400  # 100K

    if [[ "$diff_size" -gt "$diff_threshold" && -z "$opt_yes" ]]; then
        # Large diff without -y: emit gate prompt
        local softeng_sh="$_CTX_SCRIPT_DIR/softeng.sh"
        # shellcheck disable=SC2034
        declare -A gate_vars=(
            [size]="$diff_size"
            [softeng_sh]="$softeng_sh"
        )
        prompt_start_instructions "results"
        emit_prompt "$prompts_dir" "instr_usync_large_diff" gate_vars
        return 0
    fi

    if [[ "$diff_size" -gt "$diff_threshold" ]]; then
        # Large diff with -y: emit file list + instruction
        local file_list
        file_list=$(git diff --name-only "$merge_base" HEAD -- . ":(exclude)$changes_folder_rel/*")
        local softeng_sh="$_CTX_SCRIPT_DIR/softeng.sh"
        # shellcheck disable=SC2034
        declare -A usync_vars=(
            [change_folder]="$change_folder_rel"
            [specs_folder]="$specs_folder_rel"
            [impl_exists]="$impl_exists"
            [issue_exists]="$issue_exists"
            [is_large_diff]="1"
            [softeng_sh]="$softeng_sh"
        )
        prompt_start_instructions "action"
        emit_artifact "usync_file_list" "$file_list" "Changed files since baseline"
        emit_prompt "$prompts_dir" "instr_usync" usync_vars
    else
        # Normal diff (including empty): emit diff + instruction
        local diff_content
        diff_content=$(cat "$diff_file")
        # shellcheck disable=SC2034
        declare -A usync_vars=(
            [change_folder]="$change_folder_rel"
            [specs_folder]="$specs_folder_rel"
            [impl_exists]="$impl_exists"
            [issue_exists]="$issue_exists"
            [is_large_diff]=""
        )
        prompt_start_instructions "action"
        emit_artifact "usync_diff" "$diff_content" "Diff since baseline"
        emit_prompt "$prompts_dir" "instr_usync" usync_vars
    fi
}



# cmd_action_upr
# Full upr flow: validate, detect WCF, check no existing PR, read change.md,
# compute pr_title/commit_message/see_details_line,
# set upstream, squash, force-push, open PR creation in browser, output prompt.
cmd_action_upr() {
    local opt_no_archive=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-archive) opt_no_archive="1"; shift ;;
            *) error "Unknown argument: $1" ;;
        esac
    done

    local project_dir
    context_project_dir project_dir

    prompt_start_log

    # Validate preconditions
    check_prerequisites

    local current_branch
    current_branch=$(git symbolic-ref --short HEAD)

    local pr_remote default_branch
    pr_remote=$(determine_pr_remote)
    default_branch=$(git_default_branch_name)

    git_validate_clean_repo "$current_branch" "$default_branch"

    echo "Branch: $current_branch -> $pr_remote/$default_branch"

    # Fetch remote default branch
    echo "Fetching $pr_remote/$default_branch..."
    quiet git fetch "$pr_remote" "$default_branch"

    # Check for changes since branching
    echo "Checking for changes since branching..."
    local merge_base
    merge_base=$(git merge-base HEAD "${pr_remote}/${default_branch}")
    local diff_stat
    diff_stat=$(git diff --name-only "$merge_base" HEAD)
    if [[ -z "$diff_stat" ]]; then
        error "No changes detected in the current branch since branching from $default_branch"
    fi

    # Detect Working Change Folder
    local changes_folder_rel
    context_changes_folder changes_folder_rel
    local wcf_name
    wcf_name=$(changes_validate_single_wcf "$project_dir" "$changes_folder_rel" "$pr_remote" "$default_branch")

    echo "Working Change Folder: $wcf_name"

    local wcf_path="$project_dir/$changes_folder_rel/$wcf_name"
    local change_file="$wcf_path/change.md"

    if [[ ! -f "$change_file" ]]; then
        error "change.md not found in Working Change Folder: $wcf_path"
    fi

    # Check for uncompleted todo items
    echo "Checking for uncompleted to-do items..."
    changes_validate_todos_completed "$wcf_path" "$project_dir"

    local prompts_dir
    context_prompts_dir prompts_dir

    # Check if PR already exists for this branch
    echo "Checking for existing PR..."
    local pr_state pr_number
    if pr_state=$(gh pr view --json state -q ".state" 2>/dev/null); then
        # PR exists -- check its state
        pr_number=$(gh pr view --json number -q ".number")

        if [[ "$pr_state" == "OPEN" ]]; then
            # PR exists and is OPEN -- open in browser and show message
            local pr_url
            pr_url=$(gh pr view --json url -q ".url")
            quiet gh pr view --web || true

            prompt_start_instructions "results"
            # shellcheck disable=SC2034  # open_vars used via nameref in emit_prompt
            declare -A open_vars=([pr_url]="$pr_url")
            emit_prompt "$prompts_dir" "instr_upr_already_exists" open_vars
            return 0
        elif [[ "$pr_state" == "MERGED" ]]; then
            echo "PR #${pr_number} for this branch was already merged. Proceeding with new PR creation..."
        fi
        # PR exists but is CLOSED -- proceed silently with new PR creation
    fi

    # Read change.md: title and optional issue_url
    local full_title
    full_title=$(md_read_title "$change_file")
    # change_title is text after ":" in the heading, trimmed
    local change_title
    if [[ "$full_title" == *:* ]]; then
        change_title="${full_title#*:}"
        change_title="${change_title#"${change_title%%[![:space:]]*}"}"
    else
        change_title="$full_title"
    fi

    local issue_url pr_title commit_message see_details_line
    issue_url=$(md_read_frontmatter_field "$change_file" "issue_url" 2>/dev/null) || true

    see_details_line="See change.md for details"

    if [[ -n "$issue_url" ]]; then
        local issue_id
        issue_id=$(extract_issue_id "$issue_url")
        pr_title="[${issue_id}] ${change_title}"
        commit_message="Closes #${issue_id}: ${change_title}"$'\n'"${see_details_line}"
    else
        pr_title="${change_title}"
        commit_message="${change_title}"$'\n'"${see_details_line}"
    fi

    # Archive WCF if active and --no-archive not set
    if [[ -z "$opt_no_archive" && -d "$wcf_path" && "$wcf_name" != archive/* ]]; then
        echo "Archiving WCF $wcf_name..."
        local archived_path
        changes_archive "$project_dir" "$changes_folder_rel" "$changes_folder_rel/$wcf_name" "1" archived_path

        # Update change_file to archived location
        change_file="$project_dir/$archived_path/change.md"

        if [[ -n $(git status --porcelain) ]]; then
            quiet git add -A
            quiet git commit -m "Archive $wcf_name"
        fi
    fi

    # Count commits since merge-base to decide whether to squash
    local commit_count
    commit_count=$(git rev-list --count "$merge_base"..HEAD)

    # Set upstream if not already set
    if ! git rev-parse --abbrev-ref "@{upstream}" >/dev/null 2>&1; then
        quiet git push -u origin "$current_branch"
    fi

    echo "PR title: $pr_title"
    echo "Commits since merge-base: $commit_count"

    local pre_push_head=""
    if [[ "$commit_count" -gt 1 ]]; then
        # Record pre-push HEAD for branch restoration
        pre_push_head=$(git rev-parse HEAD)

        # Squash branch into single commit
        echo "Squashing $commit_count commits into one..."
        quiet git reset --soft "$merge_base"
        quiet git commit -m "$commit_message"

        # Register branch restoration handler in case force-push fails
        atexit_push "git reset --hard ${pre_push_head}"

        # Force-push
        echo "Force-pushing squashed commit..."
        quiet git push --force

        # Force-push succeeded -- remove restoration handler
        atexit_pop
    else
        # Already a single commit -- skip squash and force-push
        echo "Single commit, pushing..."
        quiet git push
    fi

    # Prepare PR body: wrap YAML frontmatter (when present, opened on line 1) in a
    # ```yaml code fence and emit only the Why, What and How sections from change.md.
    # Missing or unclosed frontmatter is tolerated -- whatever parts are recognisable
    # are emitted, and an orphan opening fence is closed in END.
    local pr_body_file
    temp_create_file pr_body_file
    local pr_body_max_lines=40
    local pr_body_max_chars=4000
    awk '
        BEGIN { in_frontmatter=0; in_why_what_how=0 }
        NR==1 && /^---$/ { in_frontmatter=1; print "```yaml"; next }
        in_frontmatter && /^---$/ { in_frontmatter=0; print "```"; next }
        in_frontmatter { print; next }
        {
            if (/^## /) {
                in_why_what_how = ($0 ~ /^## (Why|What|How)[[:space:]]*$/) ? 1 : 0
            }
            if (in_why_what_how) print
        }
        END { if (in_frontmatter) print "```" }
    ' "$change_file" > "$pr_body_file"
    local pr_body_truncated=false
    local pr_body_lines
    pr_body_lines=$(wc -l < "$pr_body_file")
    if (( pr_body_lines > pr_body_max_lines )); then
        head -n "$pr_body_max_lines" "$pr_body_file" > "${pr_body_file}.tmp"
        mv "${pr_body_file}.tmp" "$pr_body_file"
        pr_body_truncated=true
    fi
    local pr_body_size
    pr_body_size=$(wc -c < "$pr_body_file")
    if (( pr_body_size > pr_body_max_chars )); then
        local truncated
        truncated=$(head -c "$pr_body_max_chars" "$pr_body_file")
        printf '%s' "$truncated" > "$pr_body_file"
        pr_body_truncated=true
    fi
    if [[ "$pr_body_truncated" == "true" ]]; then
        printf '\n\n---\n(truncated -- see change.md for full details)\n' >> "$pr_body_file"
    fi

    # Create PR via gh CLI
    echo "Creating PR..."
    local pr_url
    pr_url=$(gh_create_pr "$pr_remote" "$default_branch" "$current_branch" "$pr_title" < "$pr_body_file")

    # Open the created PR in browser
    echo "Opening PR in browser..."
    quiet gh pr view --web || true

    prompt_start_instructions "results"

    # Output success prompt
    if [[ -n "$pre_push_head" ]]; then
        declare -A vars=([pre_push_head]="$pre_push_head" [pr_url]="$pr_url")
        emit_prompt "$prompts_dir" "instr_upr_success" vars
    else
        # shellcheck disable=SC2034  # vars used via nameref
        declare -A vars=([pr_url]="$pr_url")
        emit_prompt "$prompts_dir" "instr_upr_success_no_squash" vars
    fi
}

# cmd_action_umergepr
# Full umergepr flow: validate, detect WCF, check PR state, handle branches,
# archive WCF if active, attempt merge, handle failure, branch cleanup.
cmd_action_umergepr() {
    local project_dir
    context_project_dir project_dir

    prompt_start_log

    # Validate preconditions
    check_prerequisites

    local current_branch
    current_branch=$(git symbolic-ref --short HEAD)

    local pr_remote default_branch
    pr_remote=$(determine_pr_remote)
    default_branch=$(git_default_branch_name)

    git_validate_clean_repo "$current_branch" "$default_branch"

    echo "Branch: $current_branch -> $pr_remote/$default_branch"

    # Check upstream
    if ! git rev-parse --abbrev-ref "@{upstream}" >/dev/null 2>&1; then
        error "Current branch '$current_branch' has no upstream"
    fi

    # Fetch remote default branch
    echo "Fetching $pr_remote/$default_branch..."
    quiet git fetch "$pr_remote" "$default_branch"

    # Detect Working Change Folder
    local changes_folder_rel
    context_changes_folder changes_folder_rel
    local wcf_name
    wcf_name=$(changes_validate_single_wcf "$project_dir" "$changes_folder_rel" "$pr_remote" "$default_branch")
    echo "Working Change Folder: $wcf_name"

    local prompts_dir
    context_prompts_dir prompts_dir

    # Check PR state
    echo "Checking PR state..."
    local pr_state pr_number
    if ! pr_state=$(gh pr view --json state -q ".state" 2>/dev/null); then
        # No PR found
        prompt_start_instructions "results"
        emit_prompt "$prompts_dir" "instr_umergepr_no_pr"
        return 0
    fi

    pr_number=$(gh pr view --json number -q ".number")
    local pr_url
    pr_url=$(gh pr view --json url -q ".url")

    echo "PR #$pr_number state: $pr_state"

    if [[ "$pr_state" != "OPEN" ]]; then
        # PR is not in OPEN state
        quiet gh pr view --web || true

        local branch_head
        branch_head=$(git rev-parse HEAD)

        # Delete local branch, upstream and remote tracking ref (errors ignored)
        quiet git checkout "$default_branch" || true
        git branch -D "$current_branch" >/dev/null 2>&1 || true
        git branch -dr "origin/$current_branch" >/dev/null 2>&1 || true

        # shellcheck disable=SC2034  # vars used via nameref
        declare -A vars=(
            [pr_number]="$pr_number"
            [pr_state]="$pr_state"
            [branch_name]="$current_branch"
            [branch_head]="$branch_head"
        )
        prompt_start_instructions "results"
        emit_prompt "$prompts_dir" "instr_umergepr_not_open" vars
        return 0
    fi

    # PR is in OPEN state
    # Archive WCF if active
    local wcf_path="$project_dir/$changes_folder_rel/$wcf_name"
    local archived_path=""
    if [[ -d "$wcf_path" && ! "$wcf_path" == */archive/* ]]; then
        echo "Archiving WCF $wcf_name..."
        changes_archive "$project_dir" "$changes_folder_rel" "$changes_folder_rel/$wcf_name" "1" archived_path

        # Commit the archive
        if [[ -n $(git status --porcelain) ]]; then
            quiet git add -A
            quiet git commit -m "Archive $wcf_name"
            echo "Pushing archive commit..."
            quiet git push || true
        fi
    fi

    # Sync PR branch with latest base branch (handles "base branch was modified" error)
    echo "Updating PR branch with latest base..."
    quiet gh pr update-branch || echo "Warning: gh pr update-branch failed (may not be needed)"

    # Record branch HEAD before merge deletes it
    local branch_head
    branch_head=$(git rev-parse HEAD)

    # Attempt merge with squash and delete branch
    echo "Merging PR #$pr_number (squash)..."
    if ! quiet gh pr merge --squash --delete-branch; then
        # Merge failed
        quiet gh pr view --web || true

        # shellcheck disable=SC2034  # vars used via nameref
        declare -A fail_vars=([pr_number]="$pr_number")
        prompt_start_instructions "results"
        emit_prompt "$prompts_dir" "instr_umergepr_merge_failed" fail_vars
        return 0
    fi

    # Merge succeeded -- cleanup
    echo "Merge succeeded, cleaning up..."
    # gh pr merge --delete-branch switches to default branch and deletes local branch,
    # but in fork workflows (crossRepoPR) it skips remote branch deletion by design.
    # Explicitly delete the branch on origin (the fork) and clean up tracking ref.
    if git ls-remote --exit-code --heads origin "$current_branch" >/dev/null 2>&1; then
        echo "Deleting branch $current_branch from origin..."
        quiet git push origin --delete "$current_branch" || echo "Warning: failed to delete $current_branch from origin"
    fi
    git branch -dr "origin/$current_branch" >/dev/null 2>&1 || true

    # When upstream remote exists, fast-forward local default branch.
    # Retry fetch+ff for up to 5 seconds -- the squashed commit may not appear
    # immediately due to eventual consistency.
    if [[ "$pr_remote" == "upstream" ]]; then
        echo "Syncing local $default_branch with $pr_remote/$default_branch..."
        # Already in project root
        # Ensure we are on the default branch (gh pr merge should have switched,
        # but be explicit to avoid accidentally fast-forwarding a wrong branch).
        quiet git checkout "$default_branch" || true

        echo "Fetching $pr_remote/$default_branch..."
        quiet git fetch "$pr_remote" "$default_branch"

        if ! git merge-base --is-ancestor HEAD "$pr_remote/$default_branch" 2>/dev/null; then
            # Local branch has diverged from upstream -- log and skip sync entirely
            echo "Warning: local $default_branch has diverged from $pr_remote/$default_branch, skipping sync"
            echo "  local HEAD: $(git rev-parse --short HEAD)"
            echo "  $pr_remote/$default_branch: $(git rev-parse --short "$pr_remote/$default_branch")"
            echo "  merge-base: $(git merge-base HEAD "$pr_remote/$default_branch" | cut -c1-7)"
            echo "  local-only commits:"
            git log --oneline "$pr_remote/$default_branch..HEAD" 2>&1 | sed 's/^/    /'
        else
            # Fast-forward is possible -- retry ff+WCF detection for up to 5 seconds
            # (squashed commit may not appear immediately due to eventual consistency)
            local _wcf_check_path="$project_dir/${archived_path:-$changes_folder_rel/$wcf_name}"
            local _wcf_found=false
            for _attempt in 1 2 3 4 5; do
                echo "Fast-forwarding $default_branch (attempt $_attempt)..."
                quiet git fetch "$pr_remote" "$default_branch"
                quiet git merge --ff-only "$pr_remote/$default_branch"
                quiet git push origin "$default_branch" || echo "Warning: failed to push $default_branch to origin"
                if [[ -d "$_wcf_check_path" ]]; then
                    _wcf_found=true
                    break
                fi
                sleep 1
            done
            if [[ "$_wcf_found" != "true" ]]; then
                echo "Warning: WCF not detected in $default_branch after 5 seconds"
            fi
        fi
    fi

    # shellcheck disable=SC2034  # vars used via nameref
    declare -A success_vars=(
        [pr_number]="$pr_number"
        [pr_url]="$pr_url"
        [branch_name]="$current_branch"
        [branch_head]="$branch_head"
    )
    prompt_start_instructions "results"
    emit_prompt "$prompts_dir" "instr_umergepr_success" success_vars
}

main() {
    git_path

    if [ $# -lt 1 ]; then
        error "Usage: softeng <command> [args...]"
    fi

    local command="$1"
    shift

    case "$command" in
        action)
            if [ $# -lt 1 ]; then
                error "Usage: softeng action <keyword>"
            fi
            local keyword="$1"
            shift
            case "$keyword" in
                uchange)
                    cmd_action_uchange "$@"
                    ;;
                uimpl)
                    cmd_action_uimpl "$@"
                    ;;
                uarchive)
                    cmd_action_uarchive "$@"
                    ;;
                upr)
                    cmd_action_upr "$@"
                    ;;
                umergepr)
                    cmd_action_umergepr "$@"
                    ;;
                usync)
                    cmd_action_usync "$@"
                    ;;
                *)
                    error "Unknown action keyword: $keyword. Available: uchange, uimpl, uarchive, upr, umergepr, usync"
                    ;;
            esac
            ;;
        change)
            if [ $# -lt 1 ]; then
                error "Usage: softeng change <subcommand> [args...]"
            fi
            local subcommand="$1"
            shift

            case "$subcommand" in
                list-wcf)
                    cmd_change_list_wcf "$@"
                    ;;
                *)
                    error "Unknown change subcommand: $subcommand. Available: list-wcf"
                    ;;
            esac
            ;;
        diff)
            if [ $# -lt 1 ]; then
                error "Usage: softeng diff <target>"
            fi
            local target="$1"
            shift

            case "$target" in
                specs)
                    local specs_folder_rel
                    context_specs_folder specs_folder_rel
                    git_diff "$specs_folder_rel" "$@"
                    ;;
                file)
                    if [ $# -lt 1 ]; then
                        error "Usage: softeng diff file <path>"
                    fi
                    local file_path="$1"
                    shift
                    local _pr_remote _default_branch _merge_base
                    _pr_remote=$(determine_pr_remote)
                    _default_branch=$(git_default_branch_name)
                    quiet git fetch "$_pr_remote" "$_default_branch"
                    _merge_base=$(git merge-base HEAD "${_pr_remote}/${_default_branch}")
                    git diff "$_merge_base" HEAD -- "$file_path"
                    ;;
                *)
                    error "Unknown diff target: $target. Available: specs, file"
                    ;;
            esac
            ;;
        *)
            error "Unknown command: $command"
            ;;
    esac
}

main "$@"
