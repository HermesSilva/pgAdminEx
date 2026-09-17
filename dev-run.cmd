@ECHO OFF
REM ######################################################################
REM
REM pgAdminEx - development build & run
REM
REM Builds the web assets and starts pgAdmin in desktop mode for testing.
REM This is NOT the packaging build: for the Windows installer use Make.bat,
REM which additionally needs Inno Setup, Kerberos, Electron and a signing
REM certificate. This script only needs Python, Node and yarn.
REM
REM   dev-run.cmd              bundle the web assets and run
REM   dev-run.cmd --setup      (re)create the venv and install dependencies
REM   dev-run.cmd --check      lint and run the test suites, then run
REM   dev-run.cmd --no-bundle   skip the bundle (fastest; Python changes only)
REM   dev-run.cmd --no-run      build only, do not start the server
REM   dev-run.cmd --no-browser  run, but do not open the browser
REM   dev-run.cmd --help        show this
REM
REM ######################################################################

SETLOCAL ENABLEEXTENSIONS

SET "WD=%~dp0"
IF "%WD:~-1%"=="\" SET "WD=%WD:~0,-1%"

SET "VENV=%WD%\venv"
SET "PORT=5050"
SET "DO_SETUP=0"
SET "DO_CHECK=0"
SET "DO_BUNDLE=1"
SET "DO_RUN=1"
SET "DO_BROWSER=1"

REM ---------------------------------------------------------------- args
:PARSE_ARGS
IF "%~1"=="" GOTO ARGS_DONE
IF /I "%~1"=="--setup"     ( SET "DO_SETUP=1"  & SHIFT & GOTO PARSE_ARGS )
IF /I "%~1"=="--check"     ( SET "DO_CHECK=1"  & SHIFT & GOTO PARSE_ARGS )
IF /I "%~1"=="--no-bundle" ( SET "DO_BUNDLE=0" & SHIFT & GOTO PARSE_ARGS )
IF /I "%~1"=="--no-run"    ( SET "DO_RUN=0"    & SHIFT & GOTO PARSE_ARGS )
IF /I "%~1"=="--no-browser" ( SET "DO_BROWSER=0" & SHIFT & GOTO PARSE_ARGS )
IF /I "%~1"=="--help"      GOTO USAGE
IF /I "%~1"=="-h"          GOTO USAGE
ECHO ERROR: unknown option "%~1"
ECHO.
GOTO USAGE
:ARGS_DONE

CALL :CHECK_TOOLS      || EXIT /B 1
CALL :FIND_POSTGRES    || EXIT /B 1
CALL :ENSURE_VENV      || EXIT /B 1
CALL :ENSURE_CONFIG    || EXIT /B 1
CALL :ENSURE_NODE_DEPS || EXIT /B 1

IF "%DO_CHECK%"=="1"  ( CALL :RUN_CHECKS || EXIT /B 1 )
IF "%DO_BUNDLE%"=="1" ( CALL :BUNDLE     || EXIT /B 1 )

IF "%DO_RUN%"=="0" (
    ECHO.
    ECHO Build complete. Skipping run ^(--no-run^).
    EXIT /B 0
)

CALL :RUN_SERVER
EXIT /B %ERRORLEVEL%


REM ################################################################ steps

:CHECK_TOOLS
    WHERE python >nul 2>&1 || (
        ECHO ERROR: python was not found on PATH.
        ECHO Install Python 3.9+ from https://www.python.org/downloads/
        EXIT /B 1
    )
    WHERE node >nul 2>&1 || (
        ECHO ERROR: node was not found on PATH.
        ECHO Install Node.js 20+ from https://nodejs.org/en/download
        EXIT /B 1
    )
    WHERE yarn >nul 2>&1 || (
        ECHO ERROR: yarn was not found on PATH.
        ECHO Run "corepack enable" to make it available.
        EXIT /B 1
    )
    EXIT /B 0


:ENSURE_VENV
    REM Recreate on --setup, or create on first run. The venv is deliberately
    REM kept out of the tree the app serves; .gitignore already excludes it.
    IF "%DO_SETUP%"=="1" (
        IF EXIST "%VENV%" (
            ECHO Removing the existing virtual environment...
            RD /S /Q "%VENV%" || EXIT /B 1
        )
    )

    IF NOT EXIST "%VENV%\Scripts\python.exe" (
        ECHO Creating the virtual environment in %VENV% ...
        python -m venv "%VENV%" || EXIT /B 1
        SET "DO_SETUP=1"
    )

    REM Activating in this shell keeps python/pip pointed at the venv for
    REM every step below, including the server itself.
    CALL "%VENV%\Scripts\activate.bat" || EXIT /B 1

    IF "%DO_SETUP%"=="1" (
        ECHO Installing Python dependencies ^(this takes a few minutes^)...
        python -m pip install --upgrade pip || EXIT /B 1
        python -m pip install -r "%WD%\requirements.txt" || EXIT /B 1
        python -m pip install -r "%WD%\web\regression\requirements.txt" || EXIT /B 1
        EXIT /B 0
    )

    REM Not a full setup run: make sure the environment is actually usable
    REM rather than failing later with a stack trace from the server.
    python -c "import flask, psycopg" >nul 2>&1 || (
        ECHO.
        ECHO ERROR: the Python dependencies are missing or incomplete.
        ECHO Run "dev-run.cmd --setup" to install them.
        EXIT /B 1
    )
    EXIT /B 0


:FIND_POSTGRES
    REM A PostgreSQL bin\ directory is needed on PATH twice over:
    REM   - at install time, for pg_config: requirements.txt pins psycopg[c],
    REM     whose C extension is compiled from source;
    REM   - at run time, for libpq.dll, which that extension loads. Without
    REM     it the server dies on startup with "no pq wrapper available".
    REM So this runs on every invocation, not only under --setup.
    WHERE pg_config >nul 2>&1 && EXIT /B 0

    IF NOT "%PGADMIN_POSTGRES_DIR%"=="" (
        IF EXIST "%PGADMIN_POSTGRES_DIR%\bin\pg_config.exe" (
            ECHO Using PostgreSQL at %PGADMIN_POSTGRES_DIR%
            SET "PATH=%PGADMIN_POSTGRES_DIR%\bin;%PATH%"
            EXIT /B 0
        )
        ECHO ERROR: PGADMIN_POSTGRES_DIR is set, but its bin\pg_config.exe
        ECHO does not exist: %PGADMIN_POSTGRES_DIR%
        EXIT /B 1
    )

    REM Highest version first, so a newer install wins over an older one.
    REM Delayed expansion is required here: %%D is only substituted once the
    REM whole FOR block is parsed, so a plain %PATH% set inside it would be
    REM the pre-loop value.
    SETLOCAL ENABLEDELAYEDEXPANSION
    SET "PGBIN="
    FOR /F "delims=" %%D IN ('DIR /B /O:-N "C:\Program Files\PostgreSQL" 2^>nul') DO (
        IF NOT DEFINED PGBIN (
            IF EXIST "C:\Program Files\PostgreSQL\%%D\bin\pg_config.exe" (
                SET "PGBIN=C:\Program Files\PostgreSQL\%%D\bin"
            )
        )
    )
    IF DEFINED PGBIN (
        ECHO Using PostgreSQL at !PGBIN!
        REM ENDLOCAL discards the inner scope, so carry the value out with it.
        ENDLOCAL & SET "PATH=%PGBIN%;%PATH%" & EXIT /B 0
    )
    ENDLOCAL

    ECHO.
    ECHO ERROR: a PostgreSQL installation was not found.
    ECHO.
    ECHO pgAdmin's psycopg dependency needs pg_config to build and libpq.dll
    ECHO to run. Either install PostgreSQL
    ECHO ^(https://www.postgresql.org/download^), or point at an existing
    ECHO installation, for example:
    ECHO.
    ECHO     SET "PGADMIN_POSTGRES_DIR=C:\Program Files\PostgreSQL\18"
    ECHO.
    EXIT /B 1


:ENSURE_CONFIG
    REM config_local.py overrides config.py and is git-ignored, so this is
    REM the right place for development settings. Never overwrite an
    REM existing one - it is the developer's own file.
    IF EXIST "%WD%\web\config_local.py" EXIT /B 0

    ECHO Creating web\config_local.py for development...
    (
        ECHO import logging
        ECHO import os
        ECHO.
        ECHO # Development configuration, created by dev-run.cmd.
        ECHO # This file is git-ignored; edit it freely.
        ECHO.
        ECHO # Desktop mode: no login screen, single local user.
        ECHO SERVER_MODE = False
        ECHO.
        ECHO # Keep development data out of the installed pgAdmin's data
        ECHO # directory, so testing cannot disturb a real installation.
        ECHO DATA_DIR = os.path.join^(os.path.dirname^(os.path.realpath^(__file__^)^), '..', 'dev-data'^)
        ECHO SQLITE_PATH = os.path.join^(DATA_DIR, 'pgadmin4-dev.db'^)
        ECHO.
        ECHO DEFAULT_SERVER = '127.0.0.1'
        ECHO DEFAULT_SERVER_PORT = %PORT%
        ECHO.
        ECHO CONSOLE_LOG_LEVEL = logging.INFO
        ECHO FILE_LOG_LEVEL = logging.INFO
    ) > "%WD%\web\config_local.py" || EXIT /B 1
    EXIT /B 0


:ENSURE_NODE_DEPS
    IF "%DO_SETUP%"=="0" IF EXIST "%WD%\web\node_modules" EXIT /B 0

    ECHO Installing JavaScript dependencies...
    PUSHD "%WD%\web" || EXIT /B 1
    CALL yarn install
    IF ERRORLEVEL 1 ( POPD & EXIT /B 1 )
    POPD
    EXIT /B 0


:RUN_CHECKS
    ECHO.
    ECHO ==^> Linting JavaScript...
    PUSHD "%WD%\web" || EXIT /B 1
    CALL yarn run linter
    IF ERRORLEVEL 1 ( POPD & ECHO ESLint reported problems. & EXIT /B 1 )

    ECHO.
    ECHO ==^> Running JavaScript tests...
    CALL yarn jest --maxWorkers=50%%
    IF ERRORLEVEL 1 ( POPD & ECHO Jest reported failures. & EXIT /B 1 )
    POPD

    ECHO.
    ECHO ==^> Checking Python style...
    python -m pycodestyle --config="%WD%\.pycodestyle" "%WD%\web" "%WD%\docs" "%WD%\tools" "%WD%\pkg"
    IF ERRORLEVEL 1 (
        ECHO pycodestyle reported problems.
        EXIT /B 1
    )
    EXIT /B 0


:BUNDLE
    ECHO.
    ECHO ==^> Bundling the web assets ^(about a minute^)...
    PUSHD "%WD%\web" || EXIT /B 1
    REM NODE_ENV=production is required, not just preferred: with it unset,
    REM webpack.config.js picks devtool 'eval' (line 39), and since 9.18
    REM serves a CSP with a per-request nonce and no 'unsafe-eval', the
    REM browser blocks those eval() calls. The result is a blank page with
    REM every asset fetched successfully - no server-side error to find.
    REM This mirrors the "bundle" script in web/package.json.
    SET "NODE_ENV=production"
    SET "NODE_OPTIONS=--max-old-space-size=3072"
    CALL yarn run webpacker
    IF ERRORLEVEL 1 ( POPD & ECHO The bundle failed to build. & EXIT /B 1 )
    POPD
    EXIT /B 0


:RUN_SERVER
    ECHO.
    ECHO ****************************************************************
    ECHO * Starting pgAdmin in desktop mode
    ECHO *
    ECHO * URL:       http://127.0.0.1:%PORT%
    ECHO * Data dir:  %WD%\dev-data
    ECHO * Config:    web\config_local.py
    ECHO *
    ECHO * Press Ctrl+C in this window to stop the server.
    ECHO ****************************************************************
    ECHO.

    REM Open the browser once the port is actually accepting connections,
    REM in a detached shell so the server below keeps this window and its
    REM log in the foreground. PING is the wait here rather than TIMEOUT,
    REM which aborts with "Input redirection is not supported" whenever
    REM stdin is not a console - as when this script runs from a pipe or
    REM another tool.
    IF NOT "%DO_BROWSER%"=="1" GOTO SKIP_BROWSER
    START "" /B powershell -NoProfile -WindowStyle Hidden -Command "1..40 | ForEach-Object { if (Test-NetConnection 127.0.0.1 -Port %PORT% -InformationLevel Quiet -WarningAction SilentlyContinue) { Start-Process 'http://127.0.0.1:%PORT%'; break }; Start-Sleep -Milliseconds 500 }"
    :SKIP_BROWSER

    PUSHD "%WD%\web" || EXIT /B 1
    python pgAdmin4.py
    SET "RC=%ERRORLEVEL%"
    POPD

    ECHO.
    ECHO Server stopped.
    EXIT /B %RC%


:USAGE
    ECHO.
    ECHO Build the web assets and run pgAdmin for testing.
    ECHO.
    ECHO   dev-run.cmd                bundle the web assets and run
    ECHO   dev-run.cmd --setup        ^(re^)create the venv and install dependencies
    ECHO   dev-run.cmd --check        lint and run the test suites, then run
    ECHO   dev-run.cmd --no-bundle    skip the bundle ^(fastest; Python changes only^)
    ECHO   dev-run.cmd --no-run       build only, do not start the server
    ECHO   dev-run.cmd --no-browser   run, but do not open the browser
    ECHO   dev-run.cmd --help         show this
    ECHO.
    ECHO The first run creates venv\ and web\config_local.py automatically.
    ECHO For the Windows installer, use Make.bat instead.
    ECHO.
    EXIT /B 1
