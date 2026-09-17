##########################################################################
#
# pgAdmin 4 - PostgreSQL Tools
#
# Copyright (C) 2013 - 2026, The pgAdmin Development Team
# This software is released under the PostgreSQL Licence
#
##########################################################################
#
# Prints the name of a usable code signing certificate, or nothing.
#
# The Windows installer build has to sign: installer.iss.in carries
# 'SignTool=pgAdminSigntool' and 'SignedUninstaller=yes' unconditionally,
# and Inno Setup verifies afterwards that the file really was signed.
# build-installer.cmd calls this to fill PGADMIN_WINDOWS_CSC when the user
# has not set it.
#
# CurrentUser is searched as well as LocalMachine, because a developer
# certificate installed without elevation only lives in the former.
#
# Kept in its own file rather than inlined in the .cmd: quoting a pipeline
# with $, | and () through cmd's FOR /F is unreadable and easy to get
# subtly wrong.
#

$ErrorActionPreference = 'SilentlyContinue'

$cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My `
            -CodeSigningCert |
        Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

if ($cert) {
    # signtool /n matches on the common name.
    $cert.Subject -replace '^CN=', '' -replace ',.*$', ''
}
