# Scripts
General purpose scripts to automate common tasks.

- Git
    - [`branch-tidy`](#branch-tidysh)
    - [`inplace-pull`](#inplace-pullsh)
- Plantuml
    - [`_default_styles`](#_default_stylespuml)

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

# Plantuml
## `_default_styles.puml`
You can include this file into your Plantuml diagrams to opt into some better looking styles and some common diagram components. To start using this today in the easier manner you can append the following to the very top of your diagram (within `@startuml`):
```
!includeurl https://raw.githubusercontent.com/slewsystems/scripts/master/plantuml/_default_styles.puml
```

### Styles
Add `USE_DEFAULT_STYLES()` into your diagram to style Component, Sequence, Activity, and Class Diagrams! See ERD section below for adding styles for ER diagrams. If you would like to opt-in to word wrapping of notes, descriptions and arrow lines you can add `USE_WORD_WRAP()`. This will default to 125 characters, you can change this by passing a parameter, for example: `USE_WORD_WRAP(100)`

### Common Components
#### Header
To stamp your diagram with your name, company, and a revision number you can add `header STD_HEADER` into your diagram. To set your name simply add `!define AUTHOR_NAME First Last` to your diagram and replace "First Last" with your own name. To set a company name add `!define COMPANY_NAME Company Name` to your diagram and replace "Company Name" with your own company name.

#### Footer
To stamp your diagram with a confidential notice you can add `footer STD_FOOTER` into your diagram. To set a company name add `!define COMPANY_NAME Company Name` to your diagram and replace "Company Name" with your own company name.

### ERD
Due to some styling conflicts and limitations from Plantuml we must also append `USE_ERD_STYLES()` after adding `USE_DEFAULT_STYLES()` to correctly style ER diagrams without breaking existing Class Diagrams.

A new object type is added called `table`. You can use it like this:

```puml
USE_DEFAULT_STYLES()
USE_ERD_STYLES()

enum_mapping(REPORT_STATUS_ENUM, INT(11)) {
    incomplete: 0
    complete: 1
    not_applicable: 2
}

table(items) {
    column_pk()
    omitted_columns()
}

table(items_progress_report_caches) {
    column_pk()
    timestamps()
    column_fk(item_id)

    column_non_nullable(photos_uploaded, REPORT_STATUS_ENUM)
    column_non_nullable(photo_editing_work, REPORT_STATUS_ENUM)
    column_non_nullable(attribution_work, REPORT_STATUS_ENUM)
    column_non_nullable(remote_cataloging_work, REPORT_STATUS_ENUM)
    column_non_nullable(required_attributes_defined, REPORT_STATUS_ENUM)
    column_non_nullable(description_defined, REPORT_STATUS_ENUM)
    column_non_nullable(contract_defined, REPORT_STATUS_ENUM)
    column_non_nullable(condition_defined, REPORT_STATUS_ENUM)
    column_non_nullable(measurements_defined, REPORT_STATUS_ENUM)
    column_non_nullable(active, REPORT_STATUS_ENUM)
    column_non_nullable(origin_type_defined, REPORT_STATUS_ENUM)
    column_non_nullable(parcels_created, REPORT_STATUS_ENUM)
    column_non_nullable(editing_completed, REPORT_STATUS_ENUM)
}

has_one(items_progress_report_caches, items)
```
