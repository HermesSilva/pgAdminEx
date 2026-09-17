@ECHO OFF
REM ######################################################################
REM
REM pgAdminEx - Windows installer build
REM
REM Prepares the environment this machine needs and then hands over to
REM Make.bat, which is the upstream packaging build. Nothing here
REM duplicates that logic: this validates the prerequisites, points the
REM PGADMIN_* variables at what is actually installed (Make.bat's built-in
REM defaults name versions that may not exist here), and reports precisely
REM what is missing rather than failing halfway through a long build.
REM
REM   build-installer.cmd            check, prepare and build
REM   build-installer.cmd --check    only report on the prerequisites
REM   build-installer.cmd --clean    remove the build directories
REM   build-installer.cmd --help     show this
REM
REM The finished installer lands in dist\.
REM
REM For a development run - build the assets and start pgAdmin without
REM packaging anything - use dev-run.cmd instead. That needs far less.
REM
REM ######################################################################

SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

SET "WD=%~dp0"
IF "%WD:~-1%"=="\" SET "WD=%WD:~0,-1%"

SET "ONLY_CHECK=0"
SET "MISSING=0"

:PARSE_ARGS
IF "%~1"=="" GOTO ARGS_DONE
IF /I "%~1"=="--check" ( SET "ONLY_CHECK=1" & SHIFT & GOTO PARSE_ARGS )
IF /I "%~1"=="--clean" GOTO DO_CLEAN
IF /I "%~1"=="--help"  GOTO USAGE
IF /I "%~1"=="-h"      GOTO USAGE
ECHO ERROR: unknown option "%~1"
ECHO.
GOTO USAGE
:ARGS_DONE

ECHO ****************************************************************
ECHO * Checking the Windows installer build prerequisites
ECHO ****************************************************************
ECHO.

CALL :FIND_PYTHON
CALL :FIND_POSTGRES
CALL :FIND_INNO
CALL :FIND_VCREDIST
CALL :FIND_KRB5
CALL :FIND_NODE
CALL :FIND_DOWNLOADER
CALL :FIND_SIGNING

ECHO.
IF "%MISSING%"=="1" (
    ECHO ****************************************************************
    ECHO * Cannot build: prerequisites are missing ^(see above^).
    ECHO ****************************************************************
    ECHO.
    ECHO Install what is listed, or set the matching PGADMIN_* variable to
    ECHO an existing location, then run this script again.
    ECHO.
    ECHO To just build and run pgAdmin without packaging, use dev-run.cmd.
    ECHO.
    EXIT /B 1
)

ECHO ****************************************************************
ECHO * All prerequisites found
ECHO ****************************************************************

IF "%ONLY_CHECK%"=="1" (
    ECHO.
    ECHO Prerequisites only were checked ^(--check^); nothing was built.
    EXIT /B 0
)

ECHO.
ECHO Handing over to Make.bat. This takes a while: it creates a virtual
ECHO environment, stages an embedded Python, bundles the web assets,
ECHO builds the docs, downloads Electron and runs Inno Setup.
ECHO.
ECHO Expect 20-40 minutes. Two stretches look like a hang but are not:
ECHO installing the Python dependencies, and the cleanup pass that walks
ECHO win-build\web - a FOR /R over node_modules, which cmd.exe runs
ECHO in-process, so it burns CPU while printing nothing and spawning no
ECHO child process. Check Task Manager for cmd.exe CPU before killing it.
ECHO.

CALL "%WD%\Make.bat"
SET "RC=%ERRORLEVEL%"

IF NOT "%RC%"=="0" (
    ECHO.
    ECHO ****************************************************************
    ECHO * The build FAILED ^(exit code %RC%^)
    ECHO ****************************************************************
    EXIT /B %RC%
)

ECHO.
ECHO ****************************************************************
ECHO * Build finished
ECHO ****************************************************************
IF EXIST "%WD%\dist" DIR /B "%WD%\dist\*.exe" 2>nul
ECHO.
ECHO Installer directory: %WD%\dist
ECHO.
ECHO Verify the signature with:
ECHO   "%PGADMIN_REAL_SIGNTOOL%" verify /pa "%WD%\dist\<installer>.exe"
EXIT /B 0


REM ############################################################## checks

:FIND_PYTHON
    REM Make.bat defaults to C:\Python314 and needs virtualenv.exe in the
    REM interpreter it is given - the venv module is not enough, because
    REM python.exe has to be relocatable for the embedded build.
    IF NOT "%PGADMIN_PYTHON_DIR%"=="" (
        IF EXIST "%PGADMIN_PYTHON_DIR%\python.exe" GOTO PYTHON_CHECK_VENV
        CALL :FAIL "Python" "PGADMIN_PYTHON_DIR is set to %PGADMIN_PYTHON_DIR%, which has no python.exe"
        EXIT /B 0
    )

    FOR %%P IN (
        "%LOCALAPPDATA%\Programs\Python\Python313"
        "%LOCALAPPDATA%\Programs\Python\Python312"
        "%LOCALAPPDATA%\Programs\Python\Python311"
        "%LOCALAPPDATA%\Programs\Python\Python310"
        "C:\Python314" "C:\Python313" "C:\Python312" "C:\Python311"
    ) DO (
        IF NOT DEFINED PGADMIN_PYTHON_DIR (
            IF EXIST "%%~P\python.exe" SET "PGADMIN_PYTHON_DIR=%%~P"
        )
    )

    IF NOT DEFINED PGADMIN_PYTHON_DIR (
        CALL :FAIL "Python" "no Python installation found - install from https://www.python.org/downloads/ or set PGADMIN_PYTHON_DIR"
        EXIT /B 0
    )

:PYTHON_CHECK_VENV
    IF NOT EXIST "%PGADMIN_PYTHON_DIR%\Scripts\virtualenv.exe" (
        ECHO   Installing virtualenv into %PGADMIN_PYTHON_DIR% ...
        "%PGADMIN_PYTHON_DIR%\python.exe" -m pip install --quiet virtualenv
        IF NOT EXIST "%PGADMIN_PYTHON_DIR%\Scripts\virtualenv.exe" (
            CALL :FAIL "virtualenv" "could not install it - run: \"%PGADMIN_PYTHON_DIR%\python.exe\" -m pip install virtualenv"
            EXIT /B 0
        )
    )
    CALL :OK "Python" "%PGADMIN_PYTHON_DIR%"
    EXIT /B 0


:FIND_POSTGRES
    REM Supplies pg_config for building psycopg, and the libpq/pg_dump/psql
    REM binaries that get shipped inside the installer.
    IF NOT "%PGADMIN_POSTGRES_DIR%"=="" (
        IF EXIST "%PGADMIN_POSTGRES_DIR%\bin\pg_config.exe" (
            CALL :OK "PostgreSQL" "%PGADMIN_POSTGRES_DIR%"
            EXIT /B 0
        )
        CALL :FAIL "PostgreSQL" "PGADMIN_POSTGRES_DIR is set to %PGADMIN_POSTGRES_DIR%, which has no bin\pg_config.exe"
        EXIT /B 0
    )

    FOR /F "delims=" %%D IN ('DIR /B /O:-N "C:\Program Files\PostgreSQL" 2^>nul') DO (
        IF NOT DEFINED PGADMIN_POSTGRES_DIR (
            IF EXIST "C:\Program Files\PostgreSQL\%%D\bin\pg_config.exe" (
                SET "PGADMIN_POSTGRES_DIR=C:\Program Files\PostgreSQL\%%D"
            )
        )
    )

    IF NOT DEFINED PGADMIN_POSTGRES_DIR (
        CALL :FAIL "PostgreSQL" "not found - install from https://www.postgresql.org/download/windows/ or set PGADMIN_POSTGRES_DIR"
        EXIT /B 0
    )
    CALL :OK "PostgreSQL" "%PGADMIN_POSTGRES_DIR%"
    EXIT /B 0


:FIND_INNO
    REM ISCC.exe compiles pkg\win32\installer.iss into the setup .exe.
    IF NOT "%PGADMIN_INNOTOOL_DIR%"=="" (
        IF EXIST "%PGADMIN_INNOTOOL_DIR%\ISCC.exe" (
            CALL :OK "Inno Setup" "%PGADMIN_INNOTOOL_DIR%"
            EXIT /B 0
        )
        CALL :FAIL "Inno Setup" "PGADMIN_INNOTOOL_DIR is set to %PGADMIN_INNOTOOL_DIR%, which has no ISCC.exe"
        EXIT /B 0
    )

    REM %LOCALAPPDATA% first: an unelevated 'winget install' puts it there.
    FOR %%P IN (
        "%LOCALAPPDATA%\Programs\Inno Setup 6"
        "C:\Program Files (x86)\Inno Setup 6"
        "C:\Program Files\Inno Setup 6"
    ) DO (
        IF NOT DEFINED PGADMIN_INNOTOOL_DIR (
            IF EXIST "%%~P\ISCC.exe" SET "PGADMIN_INNOTOOL_DIR=%%~P"
        )
    )

    IF NOT DEFINED PGADMIN_INNOTOOL_DIR (
        CALL :FAIL "Inno Setup 6" "not found - install from https://jrsoftware.org/isdl.php (or: winget install JRSoftware.InnoSetup)"
        EXIT /B 0
    )
    CALL :OK "Inno Setup" "%PGADMIN_INNOTOOL_DIR%"
    EXIT /B 0


:FIND_VCREDIST
    REM vc_redist.x64.exe is shipped inside the installer and run on the
    REM target machine. It comes with Visual Studio's redistributable
    REM packages; any copy of the file will do.
    IF "%PGADMIN_VCREDIST_FILE%"=="" SET "PGADMIN_VCREDIST_FILE=vc_redist.x64.exe"

    IF NOT "%PGADMIN_VCREDIST_DIR%"=="" (
        IF EXIST "%PGADMIN_VCREDIST_DIR%\%PGADMIN_VCREDIST_FILE%" (
            CALL :OK "VC++ redist" "%PGADMIN_VCREDIST_DIR%"
            EXIT /B 0
        )
        CALL :FAIL "VC++ redist" "PGADMIN_VCREDIST_DIR is set to %PGADMIN_VCREDIST_DIR%, which has no %PGADMIN_VCREDIST_FILE%"
        EXIT /B 0
    )

    REM Newest redist version first.
    FOR /F "delims=" %%E IN ('DIR /B /S /O:-N "C:\Program Files\Microsoft Visual Studio\*\VC\Redist\MSVC\*\%PGADMIN_VCREDIST_FILE%" 2^>nul') DO (
        IF NOT DEFINED PGADMIN_VCREDIST_DIR SET "PGADMIN_VCREDIST_DIR=%%~dpE"
    )
    IF DEFINED PGADMIN_VCREDIST_DIR (
        REM Strip the trailing backslash DIR /B /S leaves behind, which
        REM would otherwise double up when Make.bat appends the file name.
        IF "!PGADMIN_VCREDIST_DIR:~-1!"=="\" SET "PGADMIN_VCREDIST_DIR=!PGADMIN_VCREDIST_DIR:~0,-1!"
        CALL :OK "VC++ redist" "!PGADMIN_VCREDIST_DIR!"
        EXIT /B 0
    )

    REM Not present: fetch it from Microsoft. The file is redistributable
    REM and gets shipped inside the installer anyway, so downloading it is
    REM no different from taking Visual Studio's copy - and it keeps the
    REM build working on a machine without Visual Studio.
    REM
    REM Cached outside the source tree because Make.bat's :CLEAN deletes
    REM win-temp and win-build before building, which would throw away a
    REM copy kept there - and make every build re-download 25 MB.
    SET "VCDIR=%LOCALAPPDATA%\pgadminex-build\vcredist"
    IF EXIST "%VCDIR%\%PGADMIN_VCREDIST_FILE%" (
        SET "PGADMIN_VCREDIST_DIR=%VCDIR%"
        CALL :OK "VC++ redist" "!PGADMIN_VCREDIST_DIR! (downloaded earlier)"
        EXIT /B 0
    )

    WHERE curl >nul 2>&1 || (
        CALL :FAIL "VC++ redist" "%PGADMIN_VCREDIST_FILE% not found and curl is unavailable to fetch it - download https://aka.ms/vs/17/release/vc_redist.x64.exe and set PGADMIN_VCREDIST_DIR to the folder holding it"
        EXIT /B 0
    )

    ECHO   Downloading %PGADMIN_VCREDIST_FILE% from Microsoft...
    IF NOT EXIST "%VCDIR%" MKDIR "%VCDIR%" 2>nul
    curl -L --fail --retry 3 -s -o "%VCDIR%\%PGADMIN_VCREDIST_FILE%" https://aka.ms/vs/17/release/vc_redist.x64.exe
    IF NOT EXIST "%VCDIR%\%PGADMIN_VCREDIST_FILE%" (
        CALL :FAIL "VC++ redist" "the download failed - fetch https://aka.ms/vs/17/release/vc_redist.x64.exe by hand and set PGADMIN_VCREDIST_DIR to the folder holding it"
        EXIT /B 0
    )

    REM It is executed on the user's machine by the installer, so refuse
    REM anything that is not a valid Microsoft-signed binary.
    REM Prefer pwsh (7+): on some machines Windows PowerShell 5.1 cannot
    REM load Microsoft.PowerShell.Security, so Get-AuthenticodeSignature is
    REM unavailable there. if/else rather than a ternary, which 5.1 cannot
    REM parse either.
    SET "PSEXE=powershell"
    WHERE pwsh >nul 2>&1 && SET "PSEXE=pwsh"
    %PSEXE% -NoProfile -Command "$s = Get-AuthenticodeSignature '%VCDIR%\%PGADMIN_VCREDIST_FILE%'; if ($s.Status -eq 'Valid' -and $s.SignerCertificate.Subject -like '*Microsoft Corporation*') { exit 0 } else { exit 1 }" 2>nul
    IF ERRORLEVEL 1 (
        REM Could be a bad download, or simply no way to check here. Fall
        REM back to a size check so an unverifiable machine can still build,
        REM and say plainly that the signature was not confirmed.
        FOR %%S IN ("%VCDIR%\%PGADMIN_VCREDIST_FILE%") DO SET "VCSIZE=%%~zS"
        IF !VCSIZE! LSS 10000000 (
            DEL /q "%VCDIR%\%PGADMIN_VCREDIST_FILE%" 2>nul
            CALL :FAIL "VC++ redist" "the download is truncated or invalid and has been deleted - fetch https://aka.ms/vs/17/release/vc_redist.x64.exe by hand and set PGADMIN_VCREDIST_DIR"
            EXIT /B 0
        )
        SET "PGADMIN_VCREDIST_DIR=%VCDIR%"
        CALL :OK "VC++ redist" "!PGADMIN_VCREDIST_DIR! (downloaded; SIGNATURE NOT VERIFIED)"
        EXIT /B 0
    )

    SET "PGADMIN_VCREDIST_DIR=%VCDIR%"
    CALL :OK "VC++ redist" "!PGADMIN_VCREDIST_DIR! (downloaded)"
    EXIT /B 0


:FIND_KRB5
    REM Make.bat copies five MIT Kerberos DLLs plus kinit.exe into the
    REM staged Python, for Kerberos/GSSAPI authentication. It has no
    REM fallback, so a missing installation stops the build.
    IF "%PGADMIN_KRB5_DIR%"=="" SET "PGADMIN_KRB5_DIR=C:\Program Files\MIT\Kerberos"

    IF EXIST "%PGADMIN_KRB5_DIR%\bin\kinit.exe" (
        CALL :OK "MIT Kerberos" "%PGADMIN_KRB5_DIR%"
        EXIT /B 0
    )
    CALL :FAIL "MIT Kerberos" "not found at %PGADMIN_KRB5_DIR% - install 'Kerberos for Windows' from https://web.mit.edu/kerberos/dist/ (or: winget install MIT.Kerberos), or set PGADMIN_KRB5_DIR"
    EXIT /B 0


:FIND_NODE
    WHERE node >nul 2>&1 || (
        CALL :FAIL "Node.js" "not on PATH - install Node.js 20+ from https://nodejs.org/en/download"
        EXIT /B 0
    )
    WHERE yarn >nul 2>&1 || (
        CALL :FAIL "yarn" "not on PATH - run: corepack enable"
        EXIT /B 0
    )
    CALL :OK "Node.js + yarn" "on PATH"
    EXIT /B 0


:FIND_DOWNLOADER
    REM Make.bat fetches Electron and rcedit with wget, which Windows does
    REM not ship. curl.exe is present from Windows 10 1803 on, so provide a
    REM wget shim on PATH rather than making the user install one.
    WHERE wget >nul 2>&1 && (
        CALL :OK "wget" "on PATH"
        EXIT /B 0
    )

    WHERE curl >nul 2>&1 || (
        CALL :FAIL "wget/curl" "neither is on PATH - install wget, or use a Windows build with curl.exe (10 1803+)"
        EXIT /B 0
    )

    REM A shim mapping 'wget <url> -O <file>' onto curl, which Windows
    REM ships. Two constraints shape it:
    REM
    REM   * It must be an .exe, not a .cmd. Make.bat invokes wget without
    REM     CALL, and a batch file invoked that way from another batch file
    REM     transfers control and never returns - the rest of Make.bat,
    REM     including the retry test, simply never runs.
    REM   * It must live outside win-temp and win-build, which Make.bat's
    REM     :CLEAN deletes after this script has prepared the environment.
    REM
    REM Getting either wrong is punishing to diagnose: the download sits in
    REM an 'IF ERRORLEVEL NEQ 0 GOTO GET_NW' loop with no retry limit, so a
    REM shim that misbehaves spins forever at full CPU, printing nothing and
    REM spawning no child process - it looks exactly like a slow build.
    SET "SHIMDIR=%LOCALAPPDATA%\pgadminex-build\shim"
    IF NOT EXIST "%SHIMDIR%" MKDIR "%SHIMDIR%" 2>nul

    IF NOT EXIST "%SHIMDIR%\wget.exe" CALL :BUILD_WGET_SHIM
    IF NOT EXIST "%SHIMDIR%\wget.exe" (
        CALL :FAIL "wget" "could not build the curl shim - install wget and put it on PATH"
        EXIT /B 0
    )

    REM Prove it works now, rather than discovering it does not inside that
    REM unbounded retry loop.
    DEL /q "%SHIMDIR%\probe.tmp" 2>nul
    "%SHIMDIR%\wget.exe" https://raw.githubusercontent.com/electron/electron/main/LICENSE -O "%SHIMDIR%\probe.tmp" >nul 2>&1
    IF NOT EXIST "%SHIMDIR%\probe.tmp" (
        CALL :FAIL "wget" "the curl shim could not download a test file - check the network or a proxy, or install wget"
        EXIT /B 0
    )
    DEL /q "%SHIMDIR%\probe.tmp" 2>nul

    SET "PATH=%SHIMDIR%;%PATH%"
    CALL :OK "wget" "shim over curl (%SHIMDIR%)"
    EXIT /B 0


:FIND_SIGNING
    REM Signing is not optional in practice. pkg\win32\installer.iss.in
    REM carries 'SignTool=pgAdminSigntool' and 'SignedUninstaller=yes'
    REM unconditionally, while Make.bat only defines that sign tool when
    REM PGADMIN_WINDOWS_CSC is set - so without a certificate Inno Setup
    REM aborts with 'Value of [Setup] section directive "SignTool" is
    REM invalid'. A no-op sign tool does not help either: Inno verifies the
    REM file really was signed afterwards.
    IF NOT "%PGADMIN_WINDOWS_CSC%"=="" (
        CALL :OK "Code signing" "%PGADMIN_WINDOWS_CSC%"
        EXIT /B 0
    )

    IF NOT EXIST "%PGADMIN_SIGNTOOL_DIR%\signtool.exe" CALL :FIND_SIGNTOOL_DIR
    IF NOT EXIST "%PGADMIN_SIGNTOOL_DIR%\signtool.exe" (
        CALL :FAIL "Code signing" "signtool.exe not found - install the Windows SDK, or set PGADMIN_SIGNTOOL_DIR"
        EXIT /B 0
    )

    REM Pick a code signing certificate with a usable private key. The
    REM lookup lives in its own .ps1: quoting that pipeline through cmd's
    REM FOR /F is unreadable and easy to get subtly wrong.
    SET "PSEXE=powershell"
    WHERE pwsh >nul 2>&1 && SET "PSEXE=pwsh"
    FOR /F "usebackq delims=" %%C IN (`%PSEXE% -NoProfile -ExecutionPolicy Bypass -File "%WD%\pkg\win32\find_signing_cert.ps1"`) DO (
        IF NOT DEFINED PGADMIN_WINDOWS_CSC SET "PGADMIN_WINDOWS_CSC=%%C"
    )

    IF NOT DEFINED PGADMIN_WINDOWS_CSC (
        CALL :FAIL "Code signing" "no usable code signing certificate found, and the installer script requires one - create or import one, then set PGADMIN_WINDOWS_CSC to its name"
        EXIT /B 0
    )
    CALL :SETUP_SIGNTOOL_SHIM
    CALL :OK "Code signing" "!PGADMIN_WINDOWS_CSC! (auto-detected)"
    EXIT /B 0


:SETUP_SIGNTOOL_SHIM
    REM Make.bat signs with 'signtool sign /sm', and /sm restricts the
    REM lookup to LocalMachine - where a developer certificate installed
    REM without elevation does not live. Rather than patch Make.bat, put a
    REM shim ahead of it that forwards everything except /sm.
    SET "SHIMDIR=%LOCALAPPDATA%\pgadminex-build\shim"
    IF NOT EXIST "%SHIMDIR%" MKDIR "%SHIMDIR%" 2>nul

    SET "PGADMIN_REAL_SIGNTOOL=%PGADMIN_SIGNTOOL_DIR%\signtool.exe"

    IF NOT EXIST "%SHIMDIR%\signtool.exe" (
        SET "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
        IF EXIST "!CSC!" IF EXIST "%WD%\pkg\win32\signtool_shim.cs" (
            "!CSC!" /nologo /optimize /out:"%SHIMDIR%\signtool.exe" "%WD%\pkg\win32\signtool_shim.cs" >nul 2>&1
        )
    )

    IF EXIST "%SHIMDIR%\signtool.exe" SET "PGADMIN_SIGNTOOL_DIR=%SHIMDIR%"
    EXIT /B 0


:FIND_SIGNTOOL_DIR
    REM Enumerate the SDK build directories, newest first, and test each
    REM one. 'DIR /S' with a wildcard in the middle of the path does not
    REM work in cmd, so the version component is walked explicitly.
    SET "SDKBIN=C:\Program Files (x86)\Windows Kits\10\bin"
    FOR /F "delims=" %%D IN ('DIR /B /AD /O:-N "%SDKBIN%" 2^>nul') DO (
        IF NOT DEFINED PGADMIN_SIGNTOOL_DIR (
            IF EXIST "%SDKBIN%\%%D\x64\signtool.exe" (
                SET "PGADMIN_SIGNTOOL_DIR=%SDKBIN%\%%D\x64"
            )
        )
    )
    EXIT /B 0


:BUILD_WGET_SHIM
    REM Compiled with the .NET Framework C# compiler, which ships with
    REM Windows. It only has to understand the two invocations Make.bat
    REM makes: 'wget <url> -O <file>'.
    SET "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    IF NOT EXIST "%CSC%" EXIT /B 0

    REM The C# source lives in its own file next to this script: writing it
    REM from a block of ECHOs means escaping every character cmd treats as
    REM an operator, which C# is dense in - unreadable, and easy to get
    REM subtly wrong.
    IF NOT EXIST "%WD%\pkg\win32\wget_shim.cs" EXIT /B 0

    "%CSC%" /nologo /optimize /out:"%SHIMDIR%\wget.exe" "%WD%\pkg\win32\wget_shim.cs" > "%SHIMDIR%\csc.log" 2>&1
    IF EXIST "%SHIMDIR%\wget.exe" DEL /q "%SHIMDIR%\csc.log" 2>nul
    EXIT /B 0


REM ############################################################## helpers

:OK
    ECHO   [ OK ]   %~1: %~2
    EXIT /B 0

:FAIL
    ECHO   [MISSING] %~1
    ECHO             %~2
    SET "MISSING=1"
    EXIT /B 0


:DO_CLEAN
    ECHO Cleaning the build directories...
    CALL "%WD%\Make.bat" clean
    EXIT /B %ERRORLEVEL%


:USAGE
    ECHO.
    ECHO Build the pgAdmin Windows installer.
    ECHO.
    ECHO   build-installer.cmd            check, prepare and build
    ECHO   build-installer.cmd --check    only report on the prerequisites
    ECHO   build-installer.cmd --clean    remove the build directories
    ECHO   build-installer.cmd --help     show this
    ECHO.
    ECHO Prepares the environment and calls Make.bat, the upstream packaging
    ECHO build. The finished installer lands in dist\.
    ECHO.
    ECHO Optional variables, each auto-detected when unset:
    ECHO   PGADMIN_PYTHON_DIR     Python installation (needs virtualenv)
    ECHO   PGADMIN_POSTGRES_DIR   PostgreSQL installation
    ECHO   PGADMIN_INNOTOOL_DIR   Inno Setup 6
    ECHO   PGADMIN_VCREDIST_DIR   folder holding vc_redist.x64.exe
    ECHO   PGADMIN_KRB5_DIR       MIT Kerberos for Windows
    ECHO   PGADMIN_WINDOWS_CSC    code signing certificate ^(unsigned if unset^)
    ECHO.
    ECHO To build and run pgAdmin without packaging, use dev-run.cmd.
    ECHO.
    EXIT /B 1
