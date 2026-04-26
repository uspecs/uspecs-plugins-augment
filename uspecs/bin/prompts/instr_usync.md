# Align Working Change Folder specs with source changes

## data

Update the implementation plan (to-do items) in the following files to reflect source changes:

- `${change_folder}/change.md`
- `${change_folder}/impl.md` (?impl_exists)

Implementation plan should mention all changed files except files inside `${change_folder}`.

If the implementation plan references specifications (located in `${specs_folder}`), align those specifications with the source changes made outside `${specs_folder}`.

Report contradictions between `${change_folder}/issue.md` and implementation in the output (do not modify `issue.md`). (?issue_exists)

Rules:

- Max 5 new sub-items per to-do item per sync
- Never remove correct items to reduce count

### Source changes

- Source changes are provided in `@artdef_usync_diff`. (?!is_large_diff)
- Source changes are provided as a list of changed files in `@artdef_usync_file_list`. (?is_large_diff)
- For each listed file, read its per-file diff by running `${softeng_sh} diff file <path>`, then apply the rules above to that file. (?is_large_diff)
