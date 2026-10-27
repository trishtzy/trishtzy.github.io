---
layout: post
title:  "Scaling Solo Development with Agents, devenv and Git Worktrees"
description: "How I use devenv and git worktrees to let coding agents develop and test changes in parallel, so I can review and merge more work with less waiting."
date:   2026-10-27 12:00:00 +0800
tags: [nix, devenv, git-worktree, postgres, go, developer-experience, launchd, nix-darwin, direnv, process-compose]
---

I want to scale what I can ship as an individual developer: more pull requests, more completed features and more commits merged into `master`. Watching [@poteto's talk on building trust in coding agents](https://x.com/poteto/status/2102050467505430555) made that ambition feel practical. A team of coding agents can take on separate changes in parallel, while I direct the work, review the results and decide what ships. The opportunity is to turn one dev's judgment into a larger volume of tested, merged code.

The models have become reliable enough for me to work this way. Towards the end of 2025, I struggled to get Claude Code to write meaningful Playwright end-to-end tests or Go unit tests; it would often take shortcuts to make them pass. Today, I can ask it to build a meaningful test suite, investigate failures and fix the bugs those tests expose. That makes it easier to delegate whole changes, provided each agent can run and test its work independently.

Running a team of agents also means having checks I can trust before shipping to production. CI covers linting, syntax checks, database migrations, schema consistency, unit tests and end-to-end tests. To complement those automated checks, Playwright lets agents open the app in a browser and test their changes interactively, walking through user flows much as I would during manual testing. Go lint and style checks run in a `pre-push` hook rather than on every commit: agents and I can commit freely while working, and simple failures are still caught before they reach CI.

The rest of the post covers my development setup for running a team of agents on [Yellowdex](https://yellowdex.ai), the project I have been actively building. I primarily use [devenv](https://devenv.sh/), a development environment tool built on Nix, alongside git worktrees. Each agent gets its own branch, databases and ports, so several changes can move toward a pull request at once. This lets agents develop and test changes concurrently, so I can move between branches with fewer interruptions rather than waiting for each branch to finish testing.

## Sharing Postgres across worktrees

At a high level, I run one Postgres instance in the background, and each git worktree gets its own development and test databases. The agents share the database server, but each branch has its own data and schema. One agent can apply a migration or reset its database while another continues working on a different feature.

Previously, devenv managed Postgres through `services.postgres`. That worked for a single checkout, but adding worktrees meant either sharing the same databases or starting separate clusters that competed for port `5432`. Moving Postgres out of devenv gave it a lifecycle independent of any branch.

On my Mac, Postgres 18 runs as a launchd user agent managed through nix-darwin, listening on `127.0.0.1:5432`. The whole definition is one module in my nix-darwin configuration, imported by each machine that needs it:

```nix
# Shared local Postgres for dev work (yellowdex-server and its worktrees).
# Runs as a launchd user agent, listening on localhost:5432.
{ config, pkgs, ... }:
let
  home = "/Users/${config.system.primaryUser}";
  dataDir = "${home}/.local/share/postgresql/18";
  logFile = "${home}/Library/Logs/postgresql.log";
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    inherit dataDir;
    settings = {
      # nixpkgs builds Postgres with its socket under /run/postgresql, which a
      # user agent can't create on macOS. Clients connect over TCP
      # (127.0.0.1:5432); the socket is only for a bare `psql -h /tmp`.
      unix_socket_directories = "/tmp";
    };
  };

  # The module sets no log paths; without these a failed start is invisible.
  launchd.user.agents.postgresql.serviceConfig = {
    StandardOutPath = logFile;
    StandardErrorPath = logFile;
  };
}
```
*Figure 1. The nix-darwin module that runs Postgres 18 as a launchd user agent on `127.0.0.1:5432`.*

Two things caught me. The agent runs `initdb` whenever `PG_VERSION` is missing from the data directory, so an existing cluster has to be moved into place before the first `darwin-rebuild switch`, or an empty one appears there within seconds. And the module sets no log paths, so without the two `serviceConfig` lines a Postgres that fails to start leaves no trace.

The development shell still provides the matching Postgres client tools. The two roles the script connects as, `admin` for development databases and `yellowdex_test` for test databases, are created once by hand with `psql`; nix-darwin's module declares `ensureUsers` and `initialScript` but does not implement them, since launchd has no post-start hook. After that, creating another worktree only requires creating another pair of databases.

## Preparing each worktree automatically

The setup lives in `dev/worktree.sh`, a bash script called by devenv's `enterShell`. I keep linked worktrees under `.worktrees/<name>` inside the root checkout. The directory is gitignored and excluded from the Go server's file watcher, so changes in one branch do not restart another branch's server.

The layout, with two worktrees checked out:

```text
yellowdex-server/                    root checkout (slot 0): keeps its own .env, never seeded
├── .git/
│   ├── worktrees/<name>/            git's own metadata for each linked worktree
│   └── yellowdex-worktrees          port-slot registry, one "<slug> <slot>" line per worktree
├── .env                             shared configuration, read by every worktree
├── .envrc                           direnv enters the devenv shell on cd
├── flake.nix                        devenv processes and scripts: wt-new, wt-rm, db-reset, test
├── dev/
│   └── worktree.sh                  bootstrap, env, reconcile, new, rm, db-reset
├── cmd/
│   └── devseed/                     seed data and devseed login | jwt | key
└── .worktrees/                      gitignored, excluded from the file watcher
    ├── feat-fund-flow-graph/        slot 3: ports 3030 / 5203 / 5204 / 5205
    │   ├── .git                     a file pointing at ../../.git/worktrees/feat-fund-flow-graph
    │   ├── .env -> ../../.env       symlinks to the root checkout's files
    │   ├── .envrc -> ../../.envrc
    │   ├── .devenv/state/           this worktree's migration log and test-schema marker
    │   └── …                        the branch's checkout
    └── fix-android-ci/              slot 4: ports 3040 / 5213 / 5214 / 5215
        └── …

Postgres on 127.0.0.1:5432, outside the tree:
  yellowdex, yellowdex_test                       the root checkout's databases
  yellowdex_wt_feat_fund_flow_graph, …_test       tagged yellowdex-worktree:/path/to/yellowdex-server
  yellowdex_wt_fix_android_ci, …_test
```
*Figure 2. The root checkout with two linked worktrees, and the databases each one owns.*

I create a worktree with `wt-new <branch> [name]`, which creates the branch from `origin/master` if needed and links the root checkout's `.env` and `.envrc`. After entering the directory and running `direnv allow`, the shell creates the worktree's databases and claims a port slot on first entry. The same setup runs for worktrees created with plain `git worktree add`. An agent is simply a coding-agent session started inside that directory: it inherits the worktree's databases, ports and URLs through direnv like any other shell, so nothing about its environment needs to be explained to it.

Each worktree gets:

- **A development and a test database**, named `yellowdex_wt_<slug>` and `yellowdex_wt_<slug>_test`. The slug comes from the worktree directory name. The development database is migrated with goose and seeded on creation.
- **Dedicated application ports.** A registry in the shared git directory assigns each worktree a slot. Its ports are the root checkout's ports plus `10 × slot`, so slot 1 moves the server from `3000` to `3010` and the admin UI from `5173` to `5183`.
- **Shared configuration with local overrides.** The shell loads the root's `.env`, then overrides database connections, ports, frontend proxy targets and application URLs for the current worktree.
- **A shared Go module cache**, through `GOMODCACHE`, so every new worktree can reuse dependencies already downloaded by the root checkout.

The `env` subcommand of `dev/worktree.sh` turns a slot into that block of exports, which `enterShell` evaluates on top of the root's `.env`. The excerpt leaves out the application-specific variables (the server's own port and URLs, goose's connection string) and keeps the shape:

```bash
STRIDE=10
ADMIN_PORT_BASE=5173
PUBLIC_PORT_BASE=5174
CHAT_PORT_BASE=5175

cmd_env() {
  local slot server
  server=$(root_env HTTP_PORT)
  server=${server:-3000}
  if is_root; then
    slot=0
  else
    local slug
    slug=$(slug_of "$here")
    slot=$(slot_of "$slug")
    [ -n "$slot" ] || die "no port slot for $slug yet; run: dev/worktree.sh bootstrap"
    server=$((server + STRIDE * slot))
    printf 'export %s=%q\n' \
      YD_WORKTREE "$slug" \
      DATABASE_DSN "$(dev_dsn "$slug")" \
      TEST_DATABASE_DSN "$(test_dsn "$slug")" \
      GOMODCACHE "$root_dir/.devenv/state/go/pkg/mod"
  fi
  printf 'export %s=%q\n' \
    YD_SLOT "$slot" \
    YD_ADMIN_PORT "$((ADMIN_PORT_BASE + STRIDE * slot))" \
    YD_PUBLIC_PORT "$((PUBLIC_PORT_BASE + STRIDE * slot))" \
    YD_CHAT_PORT "$((CHAT_PORT_BASE + STRIDE * slot))" \
    VITE_API_PROXY_TARGET "http://localhost:$server"
}
```
*Figure 3. `cmd_env` in `dev/worktree.sh`: a port slot becomes a worktree's exports.*

`root_env` reads a key from the root checkout's `.env` file rather than the environment, so re-entering a shell that already carries a worktree's overrides cannot offset the ports twice. The exports are printed as shell rather than applied, which keeps the script testable: `dev/worktree.sh env` shows exactly what a worktree will get.

Database setup is handled by two functions in `dev/worktree.sh`. The excerpt uses helpers defined elsewhere in the script:

```bash
tag="yellowdex-worktree:$root_dir"

create_db() {
  local name=$1 owner=$2
  pg "CREATE DATABASE \"$name\" OWNER $owner"
  pg "COMMENT ON DATABASE \"$name\" IS '$tag'"
}

ensure_dbs() {
  local slug=$1
  if ! db_exists "$(dev_db "$slug")"; then
    create_db "$(dev_db "$slug")" admin
    migrate_and_seed "$slug" || warn "migrate/seed of $(dev_db "$slug") failed; fix it and run db-reset"
  fi
  if ! db_exists "$(test_db "$slug")"; then
    create_db "$(test_db "$slug")" yellowdex_test
  fi
}
```
*Figure 4. `create_db` and `ensure_dbs`: creating, tagging, migrating and seeding a worktree's databases.*

On shell entry, the bootstrap allocates a port slot and calls `ensure_dbs`. The test database is left empty: the Go test harness loads `schema.sql` into it, and the `test` command empties it again whenever `schema.sql` changes. This matters when agents are changing migrations: a passing test should reflect the schema on that branch, not the one loaded the first time the tests ran.

The shell prints the databases and URLs on entry, making it clear which environment an agent or I am using:

```text
── yellowdex-server: worktree feat_fund_flow_graph (slot 3) ──
  dev db      yellowdex_wt_feat_fund_flow_graph
  test db     yellowdex_wt_feat_fund_flow_graph_test
  server      http://localhost:3030
  admin       http://localhost:5203
  dashboard   http://localhost:5204
  chat        http://localhost:5205
  docs        http://localhost:8112
```
*Figure 5. The banner the shell prints on entering a worktree.*

## Starting the server and frontends together

With the databases and ports prepared, `devenv up` starts the Go server and frontend apps through [process-compose](https://github.com/F1bonacc1/process-compose).[^1] Each process inherits the worktree's environment, so the server connects to its own database and the frontends send API requests to that server's port.

Startup order matters here. The server has a readiness probe against `/api/v1/health`, and the frontends wait for it through `depends_on` with `condition = "process_healthy"`. The Vite servers also use `--strictPort`, so a port conflict produces an explicit failure instead of silently moving an app to a different URL.

The worktree commands are ordinary devenv scripts with descriptions and declared dependencies. The `commands` script lists them with their descriptions, giving agents one place to discover how to create, start and remove an environment.

![Four terminal panes, one per git worktree, each running process-compose with the server, docs, chat and both dashboards up; every pane's public dashboard listens on a different port: 5194, 5234, 5184 and 5204.](/assets/img/worktree-process-compose-ss.png)
*Figure 6. Four worktrees running `devenv up` side by side, each stack on its own port block.*

## Giving agents a repeatable starting point

Once an app is running, an agent needs a way to put it into a useful state for testing. For an app backed by a database, that means representative records and the relationships between them. The seed data should cover the situations a feature needs to handle, such as an empty list, a populated list or records in different states, so the agent can check the behaviour without first inventing its own test data.

In my setup, a small Go seed program runs when a worktree's development database is created. Each seeded row has a fixed ID, so an agent can refer to the same object in a test or bug report. Inserts use `ON CONFLICT DO NOTHING`, making the seed safe to run again. The implementation can be a script, fixtures or another tool that suits the project; the useful property is being able to recreate a known state.

Agents also need an easy way to recover after changing or deleting that data. My `db-reset` command drops the worktree's databases, recreates them, applies the development database's migrations and runs the seed again:

```text
db-reset
```
*Figure 7. One command restores the worktree's databases and seeds the development data.*

That gives the agent a repeatable starting point for reproducing a bug, checking a fix or walking through the app with Playwright. It also makes the result easier for me to review: I can reset the environment and follow the same steps against the same records.

If the app requires authentication, extend the setup with known test accounts and a way for agents to obtain a session or API key. Keep those credentials confined to local development. For apps with public interfaces, the seed data and reset command may be all an agent needs. The goal is to make the relevant user flows accessible without requiring a person to prepare the environment each time.

## Cleaning up after a pull request is merged

After a pull request is merged, I run `wt-rm <name>` from the root checkout to retire its environment. This devenv command removes the git worktree, drops its development and test databases, and releases its port slot for another branch. If git refuses to remove the worktree because it contains uncommitted changes, nothing is dropped; `wt-rm <name> --force` passes the flag through to git once I have decided those changes can go.

Because the Postgres instance also holds my root checkout's data and other projects, cleanup needs to know which databases it owns. When the script creates a development or test database, it tags it using `COMMENT ON DATABASE`. The tag is `yellowdex-worktree:$root_dir`, where `$root_dir` is the absolute path of the root checkout. For example:

```sql
COMMENT ON DATABASE yellowdex_wt_feat_fund_flow_graph
  IS 'yellowdex-worktree:/path/to/yellowdex-server';
```
*Figure 8. The ownership tag stored as a database comment.*

The database name identifies the worktree, while the comment identifies the checkout that created it. Before dropping a database, the script checks both the `yellowdex_wt_` prefix and the ownership tag, reading the comment through Postgres's `shobj_description`. Matching the prefix alone would be unsafe: another clone could have its own worktree databases on the same server.

The deletion helper enforces both checks:

```bash
drop_tagged_db() {
  local name=$1
  case $name in "$DB_PREFIX"*) ;; *) die "refusing to drop $name: not a worktree database" ;; esac
  [ "$(pg "SELECT shobj_description(oid, 'pg_database') FROM pg_database WHERE datname = '$name'")" = "$tag" ] ||
    die "refusing to drop $name: it was not created for $root_dir"
  pg "DROP DATABASE IF EXISTS \"$name\" WITH (FORCE)"
}
```
*Figure 9. `drop_tagged_db`: the prefix and tag checks that run before any database is dropped.*

Devenv also runs a reconciliation step through `enterShell`. It compares databases tagged for this checkout with the existing worktrees reported by `git worktree list`, drops databases whose worktree directory is gone, and releases unused port slots. If I remove a worktree with git directly, or Postgres is unavailable when `wt-rm` runs, the next shell entry with Postgres available cleans up the leftovers. The trigger is local worktree removal; merging a PR on GitHub alone leaves the environment available until I retire it.

## Making parallel work practical

The four worktrees in the screenshot each have their own running server, frontends and databases. An agent can apply a migration, reset its data or restart its server while the others keep working. I can open a branch's URL to check a change without switching my main checkout or stopping another agent's environment.

That makes it practical for me to delegate several changes at once. Each agent has the environment it needs to take its change through implementation and testing, and I can focus on directing the work, reviewing pull requests and deciding what belongs in `master`. Once a PR is merged, I retire its worktree and reuse the slot for the next change.

# Footnotes

[^1]: This setup pins an older devenv that uses process-compose; newer versions default to a [native process manager](https://devenv.sh/processes/).
