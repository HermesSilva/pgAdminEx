# pgAdminEx

A working fork of [pgAdmin 4](https://github.com/pgadmin-org/pgadmin4), the management tool
for [PostgreSQL](http://www.postgresql.org). It tracks upstream `master` and carries fixes
and improvements that are intended to go back upstream as Pull Requests.

This is **not** a rebrand. The application still builds, installs and identifies itself as
pgAdmin 4; only the repository differs. Nothing here changes `web/branding.py`, the
copyright, or the on-disk layout, so a checkout of this fork is a drop-in replacement for a
checkout of upstream.

Current version: see `APP_RELEASE` / `APP_REVISION` in
[`web/version.py`](web/version.py).

## Downloads

Every push to `master` builds the installers and publishes them:

**[→ Latest release](https://github.com/HermesSilva/pgAdminEx/releases/latest)** ·
[all releases](https://github.com/HermesSilva/pgAdminEx/releases)

| Platform | File | Install |
|---|---|---|
| Windows x64 | `pgadmin4-*-x64.exe` | Run the installer |
| Any (pip) | `pgadmin4-*.whl` | `pip install pgadmin4-*.whl` |
| Source | `pgadmin4-*.tar.gz` | Build from source, as below |

Releases are versioned `<upstream version>.<build>` — `9.18.42` is the 42nd build of
upstream 9.18. `web/version.py` is left untouched, so the fork stays rebaseable.

The Windows installer is **unsigned**: GitHub's runners have no code signing certificate,
so SmartScreen warns on first run — choose *More info*, then *Run anyway*. To produce a
signed build, run [`build-installer.cmd`](build-installer.cmd) locally with a certificate
in your store.

## What this fork changes

The work concentrates on three fronts.

### Security hardening

The largest share. pgAdmin runs external binaries (`pg_dump`, `pg_restore`, `psql`) with
the user's credentials, which makes argument and connection-string handling security
critical. Fixes carried here, all assigned CVEs and documented in
[`docs/en_US/release_notes_9_18.rst`](docs/en_US/release_notes_9_18.rst):

| Area | Flaw | Fix |
|---|---|---|
| Webserver authentication | `get_user()` fell back to reading `WEBSERVER_REMOTE_USER` from request headers when absent from the WSGI environment, letting any client that could reach pgAdmin assert any identity, including an administrator's (CVE-2026-86863). | Header-asserted identity is opt-in, restricted to configured trusted proxies with an optional shared secret, and refused for accounts whose authentication source is not `webserver`. |
| Backup tool | The client-supplied database name was appended to the `pg_dump` argv as a bare positional argument; `getopt_long` permutes arguments, so a value starting with a dash supplied further options such as `--file`, and a value containing `=` was expanded by libpq into a full connection string (CVE-2026-86864). | The database name is passed through the `PGDATABASE` environment variable. |
| Restore and Maintenance tools | The database name was passed straight to `--dbname`, where an embedded connection string overrode `--host`/`--port` and redirected the connection — and the password exported in `PGPASSWORD` — to a server of the caller's choosing (CVE-2026-86862). | Same `PGDATABASE` treatment, plus rejection of an empty or missing database, which otherwise fell back to the role name. |
| File Manager | `save_file`, which backs saving from the Query Tool and ERD, validated the path with `check_access_permission()` and then opened it with a plain `open()`; a symlink planted in between was followed, writing outside the storage directory (CVE-2026-86861). | The check-then-open window is closed. |

Every one of these ships with a regression test that fails without the fix.

Alongside those: per-request CSP nonce removing `unsafe-inline` / `unsafe-eval`; external
auth providers gated behind `SERVER_MODE` in desktop mode; no HTTP redirect following on
LLM API requests; supply-chain tightening in `web/` and `runtime/` (install scripts off by
default, `checksumBehavior` set to throw, a release-age gate for npm packages, narrowed
approved git repositories).

### Correctness fixes

Schema Diff received sustained attention — false SERIAL/BIGSERIAL differences and the
invalid `ALTER COLUMN ... TYPE bigserial` it generated, lost dependency ordering of the
generated script, whitespace injected into applied function bodies, and a regression test
that silently swallowed its own output and now asserts it. Other fixes span the Table
dialog (inherited-column state, Definition-tab type restriction), the UDF/procedure
argument grid, `AsyncDictServerCursor`, generated index SQL, server import, and the Helm
chart.

### Features, performance and packaging

Collapsing the Object Explorer by re-clicking the current workspace icon, with a
configurable `toggle_object_explorer` keyboard shortcut. Deferred cloud SDK imports so the
cost is paid only when a cloud wizard is used. Deduplicated concurrent
`getNodeAjaxOptions()` requests. Packaging fixes for the Windows build.

## Architecture

pgAdmin 4 is a web application: Python (Flask) on the server side, ReactJS with HTML5 and
CSS on the client. It can be deployed on a web server and used through a browser, or run
standalone on a workstation — [`runtime/`](runtime/) holds an Electron application that
forks the Python server process and displays the UI.

| Path | Contents |
|---|---|
| `web/pgadmin/` | The Flask + React application. |
| `web/pgadmin/browser/server_groups/servers/` | Object Explorer nodes, each a Python module with versioned SQL templates and JS. |
| `web/pgadmin/tools/` | Backup, restore, maintenance, sqleditor, erd, schema_diff, debugger, psql, import/export. |
| `web/migrations/` | Alembic migrations for the configuration database. |
| `web/regression/` | Python test suite (API, `re_sql`, Selenium feature tests). |
| `pkg/` | Packaging for win32, mac, debian, redhat, docker, helm, pip and source. |
| `docs/en_US/` | Sphinx documentation and release notes. |

A fuller introduction is in [`docs/en_US/code_overview.rst`](docs/en_US/code_overview.rst).

## Contributing to this fork

Changes should be written so that upstream would take them: follow the existing patterns,
keep commits focused, and avoid unrelated refactoring in the same commit. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) and, for agent-assisted work, [`CLAUDE.md`](CLAUDE.md).

Two conventions matter more than the rest:

- Python is checked with `pycodestyle` against [`.pycodestyle`](.pycodestyle) — **79
  columns**. This is the most common CI failure on a new patch.
- Every user-visible change gets an entry in the release notes for the current version,
  in the right section, citing the `pgadmin-org` issue. Security entries cite the CVE and
  credit the reporter.

---

# Building from source

In the following, *$PGADMIN4_SRC/* denotes the top-level directory of the source tree.

## Prerequisites

1. Node.js 20 or above (https://nodejs.org/en/download)
2. yarn (https://yarnpkg.com/getting-started/install)
3. Python 3.9 or above (https://www.python.org/downloads/)
4. A PostgreSQL server (https://www.postgresql.org/download)

Start by enabling Corepack, if it isn't already; this adds the yarn binary to your PATH:

```bash
corepack enable
```

## Quick start on Windows

[`dev-run.cmd`](dev-run.cmd) does the whole development cycle — virtual environment,
dependencies, web bundle — and starts pgAdmin in desktop mode:

```
D:\...\pgAdminEx> dev-run.cmd --setup    :: first run: create venv, install everything
D:\...\pgAdminEx> dev-run.cmd            :: thereafter: bundle and run
```

| Flag | Effect |
|---|---|
| `--setup` | (Re)create `venv\` and install the Python and JavaScript dependencies |
| `--check` | Run ESLint, Jest and pycodestyle before starting |
| `--no-bundle` | Skip the webpack bundle (fastest; for Python-only changes) |
| `--no-run` | Build only |
| `--no-browser` | Run without opening a browser |

It serves on <http://127.0.0.1:5050>, keeps its data in `dev-data\` and writes a
git-ignored `web\config_local.py` on first run. A PostgreSQL installation is required:
`psycopg` compiles against its `pg_config` and loads its `libpq.dll` at run time. The
script finds it under `C:\Program Files\PostgreSQL\`, or you can set
`PGADMIN_POSTGRES_DIR`.

This is not the packaging build — for the Windows installer, see `Make.bat` and
[`pkg/win32/README.md`](pkg/win32/README.md). The manual steps behind all of this are
below.

## Building the web assets

pgAdmin depends on a number of third-party JavaScript libraries. These, along with its own
JavaScript code, CSS and images, must be compiled into a "bundle" transferred to the
browser — far more efficient than requesting each asset as the client needs it.

On a *nix system:

```bash
$ cd $PGADMIN4_SRC
$ make install-node
$ make bundle
```

On Windows, where `make` is not available:

```
C:\> cd $PGADMIN4_SRC\web
C:\$PGADMIN4_SRC\web> yarn install
C:\$PGADMIN4_SRC\web> yarn run bundle
```

## Configuring the Python environment

Python 3.9 and later are supported. Use a virtual environment rather than the system
Python. On Linux and macOS — adapt as required for your distribution:

1. Create a virtual environment. The last argument is its name:

   ```bash
   $ python3 -m venv venv
   ```

2. Activate it:

   ```bash
   $ source venv/bin/activate
   ```

3. Some components require a very recent *pip*, so update it:

   ```bash
   (venv) $ pip install --upgrade pip
   ```

4. Ensure a PostgreSQL installation's `bin/` directory is on the path, so `pg_config` can
   be found for building psycopg3, and install the required packages:

   ```bash
   (venv) $ PATH=$PATH:/usr/local/pgsql/bin pip install -r $PGADMIN4_SRC/requirements.txt
   ```

   To run the regression tests, also install:

   ```bash
   (venv) $ pip install -r $PGADMIN4_SRC/web/regression/requirements.txt
   ```

5. Create a local configuration file. Edit `$PGADMIN4_SRC/web/config_local.py` and add any
   desired options, using `config.py` as a reference — settings duplicated in
   `config_local.py` override those in `config.py`. A typical development configuration:

   ```python
   import os
   import logging

   # Change pgAdmin data directory
   DATA_DIR = '/Users/myuser/.pgadmin_dev'

   # Change pgAdmin server and port
   DEFAULT_SERVER = '127.0.0.1'
   DEFAULT_SERVER_PORT = 5051

   # Switch between server and desktop mode
   SERVER_MODE = True

   # Change pgAdmin config DB path in case an external DB is used.
   CONFIG_DATABASE_URI="postgresql://postgres:postgres@localhost:5436/pgadmin"

   # Set up SMTP
   MAIL_SERVER = 'smtp.gmail.com'
   MAIL_PORT = 465
   MAIL_USE_SSL = True
   MAIL_USERNAME = 'user@gmail.com'
   MAIL_PASSWORD = 'xxxxxxxxxx'

   # Change log level
   CONSOLE_LOG_LEVEL = logging.INFO
   FILE_LOG_LEVEL = logging.INFO

   # Use a different config DB for each server mode.
   if SERVER_MODE == False:
     SQLITE_PATH = os.path.join(
         DATA_DIR,
         'pgadmin4-desktop.db'
     )
   else:
     SQLITE_PATH = os.path.join(
         DATA_DIR,
         'pgadmin4-server.db'
     )
   ```

   This allows easy switching between server and desktop modes for testing.

6. Initial setup of the configuration database is interactive in server mode and
   non-interactive in desktop mode. Run either:

   ```bash
   (venv) $ python3 $PGADMIN4_SRC/web/setup.py
   ```

   or start pgAdmin 4:

   ```bash
   (venv) $ python3 $PGADMIN4_SRC/web/pgAdmin4.py
   ```

Setup can be run automatically in desktop mode by starting the runtime, but not in server
mode — the runtime does not allow command line interaction with the setup program.

At this point pgAdmin 4 runs from the command line in either mode, reachable from a browser
at the URL shown in the terminal.

Setting up an environment on Windows is more involved; see
[`pkg/win32/README.md`](pkg/win32/README.md) for details.

## Running the tests

```bash
(venv) $ cd $PGADMIN4_SRC/web
(venv) $ python regression/runtests.py --exclude feature_tests   # Python, fast cycle
(venv) $ yarn run test:js-once                                   # Jest
(venv) $ yarn run linter                                         # ESLint
(venv) $ pycodestyle --config=../.pycodestyle ../web             # Python style
```

`feature_tests` drive a browser through Selenium and need a real server; they are excluded
from the fast cycle above. The GitHub Actions workflows in
[`.github/workflows/`](.github/workflows/) run the same checks.

## Building the documentation

Building the docs needs an additional package in the virtual environment:

```bash
$ source venv/bin/activate
(venv) $ pip install Sphinx
(venv) $ pip install sphinxcontrib-youtube
```

Then:

```bash
(venv) $ make docs
```

Output lands in `$PGADMIN4_SRC/docs/en_US/_build/html/index.html`.

## Building the runtime

Change into `runtime/` and run `yarn install` to fetch the dependencies.

To use the runtime in a development environment, copy `dev_config.json.in` to
`dev_config.json` and edit the paths to the Python executable and `pgAdmin.py`; otherwise
the runtime uses the default paths it expects in the standard package for your platform.

Then:

```bash
yarn run start
```

## Building packages

Most packages build via the Makefile, provided the setup above is complete.

A source tarball:

```bash
(venv) $ make src
```

A PIP wheel, from an activated virtual environment with all required packages:

```bash
(venv) $ make pip
```

For the macOS AppBundle see [`pkg/mac/README.md`](pkg/mac/README.md).

The Windows installer is built by `Make.bat`, which
[`build-installer.cmd`](build-installer.cmd) drives:

```
D:\...\pgAdminEx> build-installer.cmd --check    :: report on the prerequisites
D:\...\pgAdminEx> build-installer.cmd            :: build; lands in dist\
D:\...\pgAdminEx> build-installer.cmd --clean    :: remove the build directories
```

The wrapper adds no packaging logic of its own. It locates what is installed and exports
the `PGADMIN_*` variables `Make.bat` reads, so the build does not depend on that script's
hard-coded version numbers, and it reports anything it cannot resolve up front — with
what to install and which variable to set — instead of failing mid-build. It also works
around three things `Make.bat` assumes but Windows does not provide:

- **`wget`**, used to fetch Electron and rcedit. A compiled shim
  ([`pkg/win32/wget_shim.cs`](pkg/win32/wget_shim.cs)) forwards to `curl`, which Windows
  ships. It has to be an executable: `Make.bat` invokes `wget` without `CALL`, and a
  batch file invoked that way never returns to its caller — and the download sits in a
  retry loop with no limit, so the build would spin forever.
- **`vc_redist.x64.exe`**, normally taken from a Visual Studio installation. Without one
  it is downloaded from Microsoft and its Authenticode signature checked.
- **`signtool /sm`**, which searches only the LocalMachine certificate store. A second
  shim ([`pkg/win32/signtool_shim.cs`](pkg/win32/signtool_shim.cs)) drops `/sm` so a
  certificate in the current user's store is found as well.

Beyond the development prerequisites it needs **Inno Setup 6**
(`winget install JRSoftware.InnoSetup`), **MIT Kerberos for Windows**
(`winget install MIT.Kerberos`) and **a code signing certificate**.

Signing is not optional: `pkg/win32/installer.iss.in` sets `SignTool` and
`SignedUninstaller` unconditionally, and Inno Setup verifies afterwards that the file
really was signed, so a build without a certificate aborts with *Value of [Setup] section
directive "SignTool" is invalid*. The wrapper picks up any code signing certificate with
a usable private key; set `PGADMIN_WINDOWS_CSC` to a certificate name to choose one
explicitly.

For the details of what gets staged, see [`pkg/win32/README.md`](pkg/win32/README.md).

Signing is optional in this fork: `pkg/win32/installer.iss.in` guards the `SignTool` and
`SignedUninstaller` directives behind an `#ifdef SIGNED`, which `Make.bat` passes only
when `PGADMIN_WINDOWS_CSC` names a certificate. Upstream declares them unconditionally,
so a build without a certificate aborts with *Value of [Setup] section directive
"SignTool" is invalid* — which is what CI would hit.

## Continuous delivery

[`.github/workflows/release.yml`](.github/workflows/release.yml) builds all of the above
on every push to `master` and publishes a GitHub Release. It reuses the upstream
`Makefile` and `Make.bat` rather than reimplementing the packaging, installing the tools
the runner lacks (Inno Setup, MIT Kerberos, the VC++ redistributable) and compiling the
same `wget` shim that [`build-installer.cmd`](build-installer.cmd) uses.

## Creating database migrations

To change the SQLite configuration database, from the `web` directory:

```bash
(venv) $ cd $PGADMIN4_SRC/web
(venv) $ FLASK_APP=pgAdmin4.py flask db revision
```

This creates a file in `$PGADMIN4_SRC/web/migrations/versions/`. Add the changes to the
`upgrade` function and increment `SCHEMA_VERSION` in
`$PGADMIN4_SRC/web/pgadmin/model/__init__.py`. There is no need to increment
`SETTINGS_SCHEMA_VERSION`.

---

# Security issues

To report a security issue in pgAdmin itself, email **security (at) pgadmin (dot) org**, as
described in [`SECURITY.md`](SECURITY.md). That address is for vulnerabilities in the
design or code of pgAdmin, pgAgent and the pgAdmin website — not for security questions.

For an issue specific to this fork, open an issue at
https://github.com/HermesSilva/pgAdminEx.

# Upstream project

pgAdmin 4 lives at https://github.com/pgadmin-org/pgadmin4. Changes meant for pgAdmin
itself should be submitted as Pull Requests against the *master* branch of that repository.
Discussion happens on the pgAdmin Hackers mailing list, pgadmin-hackers@postgresql.org, and
support options are listed at https://www.pgadmin.org/support/.

# License

pgAdmin is released under the PostgreSQL Licence; see [`LICENSE`](LICENSE).
