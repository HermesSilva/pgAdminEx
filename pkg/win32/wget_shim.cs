//////////////////////////////////////////////////////////////////////////
//
// pgAdmin 4 - PostgreSQL Tools
//
// Copyright (C) 2013 - 2026, The pgAdmin Development Team
// This software is released under the PostgreSQL Licence
//
//////////////////////////////////////////////////////////////////////////
//
// A wget stand-in for the Windows installer build.
//
// Make.bat downloads Electron and rcedit with wget, which Windows does not
// ship; curl.exe has been present since Windows 10 1803. This translates
// the two invocations Make.bat makes - 'wget <url> -O <file>' - into the
// equivalent curl call. build-installer.cmd compiles it with the .NET
// Framework compiler that comes with Windows.
//
// It has to be an executable rather than a .cmd: Make.bat invokes wget
// without CALL, and a batch file invoked that way from another batch file
// takes over control and never returns, so the rest of Make.bat would
// never run. Worse, the download sits in a 'GOTO GET_NW' retry loop with
// no limit, so anything that misbehaves here spins forever at full CPU
// while printing nothing.
//

using System;
using System.Diagnostics;
using System.Text;

class WgetShim
{
    static int Main(string[] args)
    {
        string url = null;
        string output = null;

        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "-O" || args[i] == "-o")
            {
                if (++i < args.Length)
                {
                    output = args[i];
                }
            }
            else if (!args[i].StartsWith("-"))
            {
                url = args[i];
            }
        }

        if (url == null)
        {
            Console.Error.WriteLine("wget shim: no URL given");
            return 2;
        }

        StringBuilder cmdline = new StringBuilder();
        cmdline.Append("-L --fail --retry 3 ");
        if (output != null)
        {
            cmdline.Append("-o \"").Append(output).Append("\" ");
        }
        cmdline.Append("\"").Append(url).Append("\"");

        ProcessStartInfo psi =
            new ProcessStartInfo("curl.exe", cmdline.ToString());
        psi.UseShellExecute = false;

        using (Process p = Process.Start(psi))
        {
            p.WaitForExit();
            return p.ExitCode;
        }
    }
}
