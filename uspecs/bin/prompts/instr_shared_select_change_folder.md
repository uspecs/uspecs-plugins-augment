# Select change folder

## data

There are multiple Change Folders to work with. You need to identify which one should be used.

Try to infer the correct Change Folder from the context. If it is clear, run `${next_command} --change-folder {selected_folder}` and stop.

If it is not clear, ask the user which Change Folder should be used from the list:

${folder_list}

Present the numbered list in a user-friendly way, with "Cancel" as the last option, example:

```markdown
1. 2603281354-uchange-uimpl-softeng-dispatch
2. 2604140718-add-readme-line
3. Cancel
```

If the user selects a folder, run the `${next_command}` as explained above. If the user selects "Cancel", stop with no action.
