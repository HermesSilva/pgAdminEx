//////////////////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2026, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////////////////
//
// A signtool stand-in for the Windows installer build.
//
// Make.bat always signs with 'signtool sign /sm ...'. The /sm switch makes
// signtool look for the certificate in the LocalMachine store only, so a
// certificate held in the current user's store - the usual case for a
// developer certificate, and the only place one can be installed without
// elevation - is never found, and the build fails at the Inno Setup step.
//
// Signing cannot simply be skipped: pkg\win32\installer.iss.in carries
// 'SignTool=pgAdminSigntool' and 'SignedUninstaller=yes' unconditionally,
// and Inno Setup verifies afterwards that the file really was signed.
//
// This forwards every argument to the real signtool.exe except /sm, so the
// certificate is looked up in both stores. Everything else - the
// certificate name, timestamp URL, digest algorithms - is passed through
// untouched. build-installer.cmd compiles it and points
// PGADMIN_SIGNTOOL_DIR at it; Make.bat itself is unchanged.
//

using System;
using System.Diagnostics;
using System.IO;
using System.Text;

class SignToolShim
{
    static int Main(string[] args)
    {
        string real = Environment.GetEnvironmentVariable(
            "PGADMIN_REAL_SIGNTOOL");

        if (string.IsNullOrEmpty(real) || !File.Exists(real))
        {
            Console.Error.WriteLine(
                "signtool shim: PGADMIN_REAL_SIGNTOOL is not set to an " +
                "existing signtool.exe");
            return 2;
        }

        StringBuilder cmdline = new StringBuilder();
        foreach (string a in args)
        {
            // Drop /sm so the CurrentUser store is searched too.
            if (string.Equals(a, "/sm", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (cmdline.Length > 0)
            {
                cmdline.Append(' ');
            }

            if (a.IndexOf(' ') >= 0 && !a.StartsWith("\""))
            {
                cmdline.Append('"').Append(a).Append('"');
            }
            else
            {
                cmdline.Append(a);
            }
        }

        ProcessStartInfo psi =
            new ProcessStartInfo(real, cmdline.ToString());
        psi.UseShellExecute = false;

        using (Process p = Process.Start(psi))
        {
            p.WaitForExit();
            return p.ExitCode;
        }
    }
}
