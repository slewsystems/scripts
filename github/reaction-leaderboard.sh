#!/usr/bin/env bash
set -e

# ---------------------------
# Author: Brandon Patram
# Date: 2025-05-04
#
# Description: Fetch all PRs for a GitHub organization within a given duration,
# including title, description, author, status, and reactions. Writes results
# to a JSON file named after the organization (in snake_case).
#
# Usage: reaction-leaderboard.sh [fetch|analyze|report|report_html] --org <org_name> [--days <days>]
# Options:
#  --org:  GitHub organization name (required)
#  --days: Duration in days to look back (default: 90)
# ---------------------------

function echo_error() { echo -e "\\033[0;31m[ERROR] $*\\033[0m"; }
function echo_warn() { echo -e "\\033[0;33m[WARN] $*\\033[0m"; }
function echo_success() { echo -e "\\033[0;32m$*\\033[0m"; }
function echo_info() { echo -e "$*\\033[0m"; }

function ensure_requirements() {
    local command="$1"

    if ! [ -x "$(command -v jq)" ]; then
        echo_error "Missing jq command. To install run: brew install jq"
        return 1
    fi

    if [[ "$command" == "fetch" ]]; then
        if ! [ -x "$(command -v gh)" ]; then
            echo_error "Missing gh command. To install run: brew install gh"
            return 1
        fi

        if ! gh auth status &>/dev/null; then
            echo_error "Not authenticated with GitHub CLI. Run: gh auth login"
            return 1
        fi
    fi

    if [[ "$command" == "report" || "$command" == "report_html" ]]; then
        if ! [ -x "$(command -v claude)" ]; then
            echo_error "Missing claude command. To install see: https://docs.anthropic.com/en/docs/claude-cli"
            return 1
        fi
    fi

    if [[ "$command" == "report_html" ]]; then
        if ! [ -x "$(command -v npx)" ]; then
            echo_error "Missing npx command. Install Node.js first."
            return 1
        fi
    fi
}

function ensure_data_file() {
    local output_file="$1"

    if [[ ! -f "$output_file" ]]; then
        echo_error "Data file not found: $output_file"
        echo_error "Run 'fetch' first to generate the data."
        return 1
    fi
}

function to_snake_case() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//'
}

function get_since_date() {
    local days="$1"

    if date --version &>/dev/null 2>&1; then
        # GNU date
        date -d "-${days} days" +%Y-%m-%d
    else
        # macOS date
        date -v-"${days}"d +%Y-%m-%d
    fi
}

function fetch_pr_reactions() {
    local owner repo pr_number
    owner="$1"
    repo="$2"
    pr_number="$3"

    # shellcheck disable=SC2016
    gh api graphql --paginate -f query='
    query($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
        repository(owner: $owner, name: $repo) {
            pullRequest(number: $number) {
                reactions(first: 100, after: $cursor) {
                    pageInfo { hasNextPage endCursor }
                    nodes {
                        user { login }
                        content
                    }
                }
            }
        }
    }' -f owner="$owner" -f repo="$repo" -F number="$pr_number" \
        --jq '.data.repository.pullRequest.reactions.nodes | map({user: .user.login, emoji: .content})'
}

function advance_date() {
    local date_str="$1"
    local days="$2"

    if date --version &>/dev/null 2>&1; then
        date -d "$date_str + ${days} days" +%Y-%m-%d
    else
        date -j -v+"${days}"d -f "%Y-%m-%d" "$date_str" +%Y-%m-%d
    fi
}

function fetch_prs_window() {
    local org="$1"
    local since="$2"
    local until="$3"

    gh search prs --owner "$org" --updated "$since..$until" --limit 1000 \
        --json repository,number,title,body,author,state \
        --jq '.'
}

function fetch_prs() {
    local org="$1"
    local since_date="$2"
    local end_date
    end_date=$(date +%Y-%m-%d)

    echo_info "Searching for PRs in org \"$org\" since $since_date..." >&2

    local prs_tmpfile
    prs_tmpfile=$(mktemp)

    local window_start="$since_date"
    local window_days=14

    while [[ "$window_start" < "$end_date" || "$window_start" == "$end_date" ]]; do
        local window_end
        window_end=$(advance_date "$window_start" "$window_days")

        # clamp to end_date
        if [[ "$window_end" > "$end_date" ]]; then
            window_end="$end_date"
        fi

        echo_info "  Fetching $window_start .. $window_end" >&2

        local batch
        batch=$(fetch_prs_window "$org" "$window_start" "$window_end")

        local batch_count
        batch_count=$(echo "$batch" | jq 'length')

        if [[ "$batch_count" -ge 1000 ]]; then
            echo_warn "  Window $window_start..$window_end hit 1000 result limit, some PRs may be missing. Consider a shorter --days range." >&2
        fi

        # append each PR as a JSON line for deduplication later
        echo "$batch" | jq -c '.[]' >> "$prs_tmpfile"

        window_start=$(advance_date "$window_end" 1)
    done

    # deduplicate by repository+number and output as single array
    local result
    result=$(jq -s 'group_by(.repository.nameWithOwner + "#" + (.number | tostring)) | map(.[0])' "$prs_tmpfile")
    rm -f "$prs_tmpfile"

    local total
    total=$(echo "$result" | jq 'length')
    echo_info "  Total unique PRs found: $total" >&2

    echo "$result"
}

function cmd_fetch() {
    local org="$1"
    local days="$2"
    local output_file="$3"

    local since_date
    since_date=$(get_since_date "$days")

    local prs
    prs=$(fetch_prs "$org" "$since_date")

    local pr_count
    pr_count=$(echo "$prs" | jq 'length')
    echo_info "Found $pr_count PRs. Fetching reactions..."

    local tmpfile
    tmpfile=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$tmpfile'" EXIT

    local i=0

    while IFS= read -r pr; do
        i=$((i + 1))
        local repo_full repo_name pr_number title body author state

        repo_full=$(echo "$pr" | jq -r '.repository.nameWithOwner')
        repo_name=$(echo "$pr" | jq -r '.repository.name')
        pr_number=$(echo "$pr" | jq -r '.number')
        title=$(echo "$pr" | jq -r '.title')
        body=$(echo "$pr" | jq -r '.body')
        author=$(echo "$pr" | jq -r '.author.login')
        state=$(echo "$pr" | jq -r '.state')

        echo_info "  [$i/$pr_count] $repo_full#$pr_number"

        local reactions
        reactions=$(fetch_pr_reactions "$org" "$repo_name" "$pr_number" 2>/dev/null || echo "[]")

        # Flatten paginated results into a single array
        reactions=$(echo "$reactions" | jq -s 'flatten')

        jq -n -c \
            --arg title "$title" \
            --arg body "$body" \
            --arg author "$author" \
            --arg state "$state" \
            --arg repo "$repo_full" \
            --argjson number "$pr_number" \
            --argjson reactions "$reactions" \
            '{
                repository: $repo,
                number: $number,
                title: $title,
                description: $body,
                author: $author,
                status: $state,
                reactions: $reactions
            }' >> "$tmpfile"
    done < <(echo "$prs" | jq -c '.[]')

    local end_date
    end_date=$(date +%Y-%m-%d)

    jq -n \
        --arg since "$since_date" \
        --arg until "$end_date" \
        --slurpfile prs "$tmpfile" \
        '{since: $since, until: $until, prs: $prs}' > "$output_file"
    echo_success "Done! Results written to $output_file"
}

function cmd_analyze() {
    local output_file="$1"

    local since until
    since=$(jq -r '.since // empty' "$output_file" 2>/dev/null)
    until=$(jq -r '.until // empty' "$output_file" 2>/dev/null)

    echo_info "Analyzing data from $output_file"
    if [[ -n "$since" && -n "$until" ]]; then
        echo_info "Date range: $since to $until"
    fi
    echo ""

    # PRs with and without reactions per author
    echo_info "=== PRs Per Author (with/without reactions) ==="
    echo ""
    jq -r '
        .prs | group_by(.author) | sort_by(-length) | .[] |
        .[0].author as $author |
        length as $total |
        [.[] | select(.reactions | length > 0)] | length as $with_reactions |
        "\($author): \($total) PRs total, \($with_reactions) with reactions, \($total - $with_reactions) without"
    ' "$output_file"

    echo ""
    echo_info "=== Reaction Breakdown Per Author (on their PRs) ==="
    echo ""
    jq -r '
        .prs | group_by(.author) | sort_by(-length) | .[] |
        .[0].author as $author |
        [.[] | .reactions[]] as $all_reactions |
        if ($all_reactions | length) == 0 then
            "\($author): no reactions received"
        else
            "\($author):",
            (
                [$all_reactions | group_by(.emoji) | .[] |
                    {emoji: .[0].emoji, count: length, users: [.[].user] | unique | join(", ")}
                ] | sort_by(-.count) | .[] |
                "  \(.emoji) x\(.count) (from: \(.users))"
            )
        end
    ' "$output_file"
}

function generate_stats_json() {
    local output_file="$1"

    jq '
    .since as $since | .until as $until |
    .prs as $all_prs |
    {
        meta: {
            since: $since,
            until: $until,
            total_prs: ($all_prs | length),
            total_with_reactions: ([$all_prs[] | select(.reactions | length > 0)] | length),
            total_without_reactions: ([$all_prs[] | select(.reactions | length == 0)] | length)
        },
        per_author: (
            [$all_prs | group_by(.author) | .[] |
                .[0].author as $author |
                length as $total |
                [.[] | select(.reactions | length > 0)] as $reacted |
                [.[] | select(.status == "open")] as $open |
                [.[] | select(.status == "merged")] as $merged |
                [.[] | select(.status == "closed")] as $closed |
                [.[] | .reactions[]] as $all_reactions |
                {
                    author: $author,
                    total_prs: $total,
                    prs_with_reactions: ($reacted | length),
                    prs_without_reactions: ($total - ($reacted | length)),
                    prs_open: ($open | length),
                    prs_merged: ($merged | length),
                    prs_closed: ($closed | length),
                    total_reactions_received: ($all_reactions | length),
                    reactions_by_emoji: (
                        if ($all_reactions | length) == 0 then []
                        else
                            [$all_reactions | group_by(.emoji) | .[] |
                                {emoji: .[0].emoji, count: length}
                            ] | sort_by(-.count)
                        end
                    ),
                    reactions_by_user: (
                        if ($all_reactions | length) == 0 then []
                        else
                            [$all_reactions | group_by(.user) | .[] |
                                {user: .[0].user, count: length, emojis: ([.[].emoji] | unique)}
                            ] | sort_by(-.count)
                        end
                    )
                }
            ] | sort_by(-.total_prs)
        ),
        top_reactors: (
            [$all_prs[] | .reactions[] | {user: .user, emoji: .emoji}] |
            group_by(.user) | [.[] |
                {user: .[0].user, total_reactions_given: length, emojis: ([.[].emoji] | group_by(.) | [.[] | {emoji: .[0], count: length}] | sort_by(-.count))}
            ] | sort_by(-.total_reactions_given)
        ),
        emoji_summary: (
            [$all_prs[] | .reactions[]] |
            if length == 0 then []
            else
                group_by(.emoji) | [.[] |
                    {emoji: .[0].emoji, total_uses: length, unique_users: ([.[].user] | unique | length)}
                ] | sort_by(-.total_uses)
            end
        ),
        repos: (
            [$all_prs | group_by(.repository) | .[] |
                {
                    repository: .[0].repository,
                    total_prs: length,
                    total_reactions: ([.[] | .reactions | length] | add // 0)
                }
            ] | sort_by(-.total_prs)
        )
    }' "$output_file"
}

function cmd_report() {
    local org="$1"
    local output_file="$2"
    local stats_file="${output_file%.json}_stats.json"
    local report_file="${output_file%.json}_report.md"

    echo_info "Generating stats from $output_file..."
    generate_stats_json "$output_file" > "$stats_file"
    echo_success "Stats written to $stats_file"

    echo_info "Generating markdown report via Claude (this may take many minutes)..."

    local prompt
    prompt="You are given two JSON files about GitHub PR reaction statistics for the organization \"$org\".

The first file (stats) contains pre-aggregated metrics: per-author PR counts, reaction breakdowns, top reactors, emoji summaries, and per-repo stats. Use the stats file as the primary source for sections 1-7 — the data is already aggregated for you.
The second file (raw) contains the full PR data including titles, descriptions, authors, statuses, and individual reactions. Only reference this file for section 8 (content analysis).

IMPORTANT: For efficiency, use the Bash tool with jq commands to query and extract data from these JSON files rather than reading the entire files into context. For example, use jq to filter PRs with/without reactions, extract title patterns, count keywords, etc. This is especially important for the content analysis section.

Generate a polished markdown report with the following:

1. A title and summary section with the date range and high-level stats
2. A leaderboard section ranked by authors who received the most reactions on their PRs. Show their rank, name, total reactions received, and a breakdown of which emojis they received.
3. A mermaid xychart-beta bar chart showing PRs per author (with vs without reactions)
4. A mermaid pie chart showing the distribution of emoji reactions across the org
5. A single consolidated author breakdown table with one row per author showing: total PRs, PRs with reactions, PRs without, total reactions received, most used emoji on their PRs, and their top reactor
6. A mermaid xychart-beta bar chart showing top reactors (people who give the most reactions)
7. A table of repos ranked by total PRs and reactions
8. Analyze the PR titles, descriptions, and purpose of PRs that received reactions vs those that did not. Use jq to compare titles/descriptions of reacted vs non-reacted PRs. Look for patterns like: word frequency differences, title length, presence of keywords (fix, feature, refactor, bug, etc), PR description length, etc. Dedicate a section to this analysis with specific examples from the data.
9. Any other interesting insights or visualizations you think would be valuable

Use actual Unicode emoji characters (e.g. 👍 ❤️ 🚀 🎉 😄 👀 😕 👎) when displaying reaction types. Map the GitHub API reaction content names as follows: THUMBS_UP=👍, THUMBS_DOWN=👎, LAUGH=😄, HOORAY=🎉, CONFUSED=😕, HEART=❤️, ROCKET=🚀, EYES=👀. Do NOT use :colon_shortcodes:.
Only output the raw markdown content, nothing else. Do not wrap in a code fence."

    # echo_info "Running: claude -p \"$prompt\" $stats_file $output_file"
    claude -p "$prompt" "$stats_file" "$output_file" | tee "$report_file"

    echo_success "Done! Report written to $report_file"
}

function cmd_report_html() {
    local org="$1"
    local output_file="$2"
    local report_file="${output_file%.json}_report.md"
    local rendered_file="${output_file%.json}_report_rendered.md"
    local html_file="${output_file%.json}_report.html"

    if [[ ! -f "$report_file" ]]; then
        echo_info "No report markdown found. Generating report first..."
        cmd_report "$org" "$output_file" || return 1
    fi

    echo_info "Rendering mermaid diagrams..."
    npx -y @mermaid-js/mermaid-cli -i "$report_file" -o "$rendered_file" -e svg

    echo_info "Inlining SVG diagrams..."
    local rendered_dir
    rendered_dir="$(dirname "$rendered_file")"

    # Replace ![alt](file.svg) references with inline SVG content
    local tmpfile
    tmpfile=$(mktemp)
    while IFS= read -r line; do
        if [[ "$line" =~ ^\!\[.*\]\((.+\.svg)\)$ ]]; then
            local svg_path="${BASH_REMATCH[1]}"
            # resolve relative to rendered markdown location
            if [[ "$svg_path" != /* ]]; then
                svg_path="$rendered_dir/$svg_path"
            fi
            if [[ -f "$svg_path" ]]; then
                cat "$svg_path" >> "$tmpfile"
                echo "" >> "$tmpfile"
            else
                echo "$line" >> "$tmpfile"
            fi
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$rendered_file"
    mv "$tmpfile" "$rendered_file"

    echo_info "Converting to self-contained HTML..."

    local report_css
    report_css='
body {
  max-width: 960px;
  margin: 0 auto;
  padding: 40px 60px;
  background-color: #faf9f6;
  color: #2d2d2d;
  font-family: Georgia, "Times New Roman", serif;
  font-size: 16px;
  line-height: 1.7;
}
h1, h2, h3, h4, h5, h6 {
  font-family: Georgia, "Times New Roman", serif;
  color: #1a1a1a;
  margin-top: 1.8em;
  margin-bottom: 0.6em;
  border-bottom: 1px solid #e0ddd8;
  padding-bottom: 0.3em;
}
h1 { font-size: 2em; }
h2 { font-size: 1.5em; }
h3 { font-size: 1.25em; border-bottom: none; }
table {
  width: 100%;
  border-collapse: collapse;
  margin: 1.5em 0;
  font-size: 0.92em;
}
th, td {
  padding: 10px 14px;
  text-align: left;
  border: 1px solid #ddd8d0;
}
th {
  background-color: #eae6df;
  font-weight: bold;
  color: #1a1a1a;
}
tr:nth-child(even) {
  background-color: #f4f2ed;
}
blockquote {
  border-left: 4px solid #c0b9ab;
  margin: 1.5em 0;
  padding: 0.5em 1.2em;
  background-color: #f0ede6;
  color: #4a4a4a;
  font-style: italic;
}
code {
  font-family: "SFMono-Regular", Menlo, monospace;
  background-color: #edeae4;
  padding: 2px 6px;
  border-radius: 3px;
  font-size: 0.88em;
}
pre {
  background-color: #edeae4;
  padding: 16px;
  border-radius: 6px;
  overflow-x: auto;
}
pre code {
  background: none;
  padding: 0;
}
hr {
  border: none;
  border-top: 1px solid #d5d0c8;
  margin: 2em 0;
}
svg {
  max-width: 100%;
  height: auto;
  display: block;
  margin: 1.5em auto;
}
p { margin: 1em 0; }
ul, ol { padding-left: 1.6em; }
li { margin: 0.3em 0; }
a { color: #4a6fa5; text-decoration: none; }
a:hover { text-decoration: underline; }
'

    npx -y md-to-pdf --as-html \
        --css "$report_css" \
        --highlight-style 'github' \
        "$rendered_file"

    # md-to-pdf --as-html outputs .html alongside the input file
    local generated_html="${rendered_file%.md}.html"
    if [[ -f "$generated_html" && "$generated_html" != "$html_file" ]]; then
        mv "$generated_html" "$html_file"
    fi

    # clean up intermediate files
    rm -f "$rendered_file"
    rm -f "${output_file%.json}_report_rendered"*.svg

    echo_success "Done! HTML report written to $html_file"
}

function main() {
    local org="" days=90 command=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --org) org="$2"; shift 2 ;;
            --days) days="$2"; shift 2 ;;
            --*) echo_error "Unknown option: $1" && exit 1 ;;
            *) command="$1"; shift ;;
        esac
    done

    if [[ -z "$command" ]]; then
        echo_error "Usage: $0 [fetch|analyze|report|report_html] --org <org_name> [--days <days>]"
        exit 1
    fi

    if [[ -z "$org" ]]; then
        echo_error "Missing organization name! Use --org flag"
        exit 1
    fi

    local output_dir
    output_dir="$(cd "$(dirname "$0")" && pwd)/reports"
    mkdir -p "$output_dir"

    local output_file
    output_file="$output_dir/$(to_snake_case "$org").json"

    ensure_requirements "$command" || exit 1

    if [[ "$command" != "fetch" ]]; then
        ensure_data_file "$output_file" || exit 1
    fi

    case "$command" in
        fetch) cmd_fetch "$org" "$days" "$output_file" || exit 1 ;;
        analyze) cmd_analyze "$output_file" || exit 1 ;;
        report) cmd_report "$org" "$output_file" || exit 1 ;;
        report_html) cmd_report_html "$org" "$output_file" || exit 1 ;;
        *) echo_error "Invalid command: $command. Use 'fetch', 'analyze', 'report', or 'report_html'." && exit 1 ;;
    esac
}
main "$@"