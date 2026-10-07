// RoboGo launcher. A tiny Windows program whose only job is to start RoboGo.ps1 without
// a console window, and to pass on a folder it was started with. Built by build.cmd with the C# compiler that ships with Windows
// (.NET Framework 4.x), so the code stays within C# 5.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("RoboGo")]
[assembly: AssemblyProduct("RoboGo")]
[assembly: AssemblyDescription("Starts RoboGo, a small window around robocopy.")]
[assembly: AssemblyVersion("0.3.0.0")]
[assembly: AssemblyFileVersion("0.3.0.0")]

internal static class RoboGoLauncher
{
    // PowerShell 7 is preferred (newer folder picker). It is found through PATH.
    private static string FindOnPath(string name)
    {
        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (string dir in path.Split(Path.PathSeparator))
        {
            if (dir.Trim().Length == 0) { continue; }
            try
            {
                string candidate = Path.Combine(dir.Trim(), name);
                if (File.Exists(candidate)) { return candidate; }
            }
            catch (ArgumentException) { }
        }
        return null;
    }

    [STAThread]
    private static int Main(string[] args)
    {
        string home = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(home, "RoboGo.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("RoboGo.ps1 was not found next to RoboGo.exe.", "RoboGo", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        // Windows PowerShell 5.1 is part of every Windows 10 and 11.
        string host = FindOnPath("pwsh.exe") ?? Path.Combine(Environment.SystemDirectory, "WindowsPowerShell\\v1.0\\powershell.exe");
        ProcessStartInfo info = new ProcessStartInfo(host, "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File \"" + script + "\"");
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.WorkingDirectory = home;
        // A folder dropped on the launcher, or sent to it from Explorer's Send to menu,
        // travels in the environment: no quoting can break it there.
        if (args.Length > 0) { info.EnvironmentVariables["ROBOGO_SOURCE"] = args[0]; }
        else { info.EnvironmentVariables.Remove("ROBOGO_SOURCE"); }
        try
        {
            Process.Start(info);
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show("RoboGo could not start PowerShell.\n\n" + error.Message, "RoboGo", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
