# Complete to-do items

## data

- Complete ONLY the to-do items listed below (from `${change_folder}/${impl_file}`):

```markdown
${unchecked_items}
```

- Do not perform work outside this list. If scope seems incomplete relative to narrative sections ("Why"/"What"), stop and inform the user rather than expanding scope.
- Stop on the ${review_item} item -- it is a human review checkpoint, do not implement it (?has_review)
- If possible process items in parallel using subagents
- Immediately after completing each item, check it as completed in the file
- After completing all items, inform the user that the review checkpoint has been reached (?has_review)
