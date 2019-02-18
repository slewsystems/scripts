# Scripts
General purpose scripts to automate common tasks.

- Git
    - [`branch-tidy`](#branch-tidy)
    - [`inplace-pull`](#inplace-pull)

## Git
### `branch-tidy.sh`
Find local branches that are merged (or have been squashed into a single merge commit) into master then prompt to delete them or all of them.

This is useful when you are merging PRs from another service (Github, etc) and want to also clean up your local branches that are completed (merged). If you use squash commit merges then this script becomes increasingly helpful as it can check for squashed branches too.

#### Example Output
```bash
$ ../branch-tidy.sh
Running in directory: /Users/brandon/foo_project
Fetching master...
  squashed      gql/fix-dup-error-part-two
not merged      hot-keys
not merged      item-progress/aggregate-checks
not merged      item-progress/identify-when-missing-values
  squashed      my-items/support-flex-items
  squashed      nb/validate-sale-messages
    merged      queues/cleanup-for-aaron
not merged      stale/braze/email-changed-notification
not merged      stale/ia/item-assignments/remove-item-ass-from-get-next-ass
not merged      stale/ia/item-assignments/remove-item-ass-from-my-items
not merged      stale/ia/item-assignments/remove-item-ass-from-queues
not merged      stale/rollbar/category-admin-setting-description-fix
not merged      tests/fix-flex-tests

Delete all 4 merged/squashed branches? [y/N]
```

#### Invoke Externally (macOS)
Use the `extern-branch-tidy.sh` file. This will run a JSX command to create a new terminal session and execute the shell script then exit the session.

This is useful for tools like [Fork](https://git-fork.com/) wher you can invoke custom scripts but doesn't support user input. Spawing a terminal window is a way to work around that limitation.

### `inplace-pull.sh`
Pull a branch down without losing your current state. This will stash your current changes and re-apply them after pulling down the target branch (or master if not defined).

This is useful to run when you've been working on your local branch and are now a few commits behind the current master and want to rebase. Run this then rebase your branch to catch it back up.

#### Example Output
```bash
$ ../inplace-pull.sh
No target branch specified. Will use master instead
Stashing current changes: DEE55FE5-32CE-4A22-B5BC-5346E08F1B84...
Pulling master...
Restoring original state of item-progress/aggregate-checks...
Done!
```
