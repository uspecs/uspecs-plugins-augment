# Next steps after PR creation

## data

PR has been created: ${pr_url}

To restore branch to its pre-squash state, if needed:

```text
git reset --hard ${pre_push_head}
git push --force
```

Next steps:

- Fix any issues raised during review
- Run `umergepr` once the PR is approved and ready to merge
