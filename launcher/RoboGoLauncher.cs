// RoboGo launcher. A small Windows program that starts RoboGo.ps1 without a console window
// and passes on a folder it was started with. It also carries the app inside itself, so the
// exe alone is enough: without a RoboGo.ps1 next to it, it unpacks its own copy to
// %TEMP%\RoboGo and starts that. Built by build.cmd with the C# compiler that ships with
// Windows (.NET Framework 4.x), so the code stays within C# 5.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("RoboGo")]
[assembly: AssemblyProduct("RoboGo")]
[assembly: AssemblyDescription("RoboGo, a small window around robocopy.")]
[assembly: AssemblyVersion("0.4.0.0")]
[assembly: AssemblyFileVersion("0.4.0.0")]

internal static class RoboGoLauncher
{
    private const string ScriptName = "RoboGo.ps1";

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

    private static byte[] ReadResource(Assembly assembly, string name)
    {
        using (Stream stream = assembly.GetManifestResourceStream(name))
        using (MemoryStream copy = new MemoryStream())
        {
            stream.CopyTo(copy);
            return copy.ToArray();
        }
    }

    private static bool SameContent(string path, byte[] content)
    {
        if (!File.Exists(path)) { return false; }
        byte[] found = File.ReadAllBytes(path);
        if (found.Length != content.Length) { return false; }
        for (int i = 0; i < found.Length; i++)
        {
            if (found[i] != content[i]) { return false; }
        }
        return true;
    }

    // The files build.cmd put into the exe are resources named by their relative path, with
    // forward slashes ("RoboGo.ps1", "lang/pl.json"). They go to %TEMP%\RoboGo\app-<hash>,
    // where the hash covers every name and every byte: another version gets another folder.
    // A file that is missing or differs from the one in the exe is written again at every
    // start, so the unpacked copy is always exactly what the exe carries.
    private static string Unpack(Assembly assembly)
    {
        string[] names = assembly.GetManifestResourceNames();
        Array.Sort(names, StringComparer.Ordinal);
        byte[][] contents = new byte[names.Length][];
        string hash;
        using (SHA256 sha = SHA256.Create())
        {
            for (int i = 0; i < names.Length; i++)
            {
                contents[i] = ReadResource(assembly, names[i]);
                byte[] label = Encoding.UTF8.GetBytes(names[i] + "\n");
                sha.TransformBlock(label, 0, label.Length, null, 0);
                sha.TransformBlock(contents[i], 0, contents[i].Length, null, 0);
            }
            sha.TransformFinalBlock(new byte[0], 0, 0);
            hash = BitConverter.ToString(sha.Hash, 0, 6).Replace("-", "").ToLowerInvariant();
        }
        string root = Path.Combine(Path.GetTempPath(), "RoboGo");
        string home = Path.Combine(root, "app-" + hash);
        for (int i = 0; i < names.Length; i++)
        {
            if (names[i].Contains("..") || Path.IsPathRooted(names[i])) { continue; }
            string target = Path.Combine(home, names[i].Replace('/', '\\'));
            if (SameContent(target, contents[i])) { continue; }
            Directory.CreateDirectory(Path.GetDirectoryName(target));
            try { File.WriteAllBytes(target, contents[i]); }
            catch (IOException)
            {
                // a second RoboGo that starts at the same moment may have written it already
                if (!SameContent(target, contents[i])) { throw; }
            }
        }
        // What an older version unpacked is not needed any more.
        try
        {
            foreach (string other in Directory.GetDirectories(root, "app-*"))
            {
                if (String.Equals(other, home, StringComparison.OrdinalIgnoreCase)) { continue; }
                try { Directory.Delete(other, true); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        return home;
    }

    [STAThread]
    private static int Main(string[] args)
    {
        Assembly assembly = Assembly.GetExecutingAssembly();
        string exe = assembly.Location;
        string home = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(home, ScriptName);
        bool unpacked = false;
        // A RoboGo.ps1 next to the exe wins: that is the folder of the repository.
        if (!File.Exists(script))
        {
            if (assembly.GetManifestResourceInfo(ScriptName) == null)
            {
                MessageBox.Show("RoboGo.ps1 was not found next to RoboGo.exe.", "RoboGo", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            try
            {
                script = Path.Combine(Unpack(assembly), ScriptName);
                unpacked = true;
            }
            catch (Exception error)
            {
                MessageBox.Show("RoboGo could not unpack itself to the TEMP folder.\n\n" + error.Message, "RoboGo", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
        // "RoboGo.exe /selftest" runs the checks of the app instead of showing the window,
        // passes on what they print and returns their exit code.
        bool selfTest = (args.Length > 0) && String.Equals(args[0], "/selftest", StringComparison.OrdinalIgnoreCase);
        // Windows PowerShell 5.1 is part of every Windows 10 and 11.
        string host = FindOnPath("pwsh.exe") ?? Path.Combine(Environment.SystemDirectory, "WindowsPowerShell\\v1.0\\powershell.exe");
        string arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File \"" + script + "\"";
        if (selfTest) { arguments += " -SelfTest"; }
        ProcessStartInfo info = new ProcessStartInfo(host, arguments);
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.WorkingDirectory = home;
        // The unpacked app learns where the exe is: settings and logs live next to it, and
        // the taskbar and the Send to shortcut start it.
        if (unpacked) { info.EnvironmentVariables["ROBOGO_EXE"] = exe; }
        else { info.EnvironmentVariables.Remove("ROBOGO_EXE"); }
        // A folder dropped on the launcher, or sent to it from Explorer's Send to menu,
        // travels in the environment: no quoting can break it there.
        if ((args.Length > 0) && !selfTest) { info.EnvironmentVariables["ROBOGO_SOURCE"] = args[0]; }
        else { info.EnvironmentVariables.Remove("ROBOGO_SOURCE"); }
        try
        {
            if (!selfTest)
            {
                Process.Start(info);
                return 0;
            }
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            using (Process process = Process.Start(info))
            {
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
                {
                    if (e.Data != null) { Console.Error.WriteLine(e.Data); }
                };
                process.BeginErrorReadLine();
                Console.Out.Write(process.StandardOutput.ReadToEnd());
                process.WaitForExit();
                Console.Out.Flush();
                return process.ExitCode;
            }
        }
        catch (Exception error)
        {
            if (selfTest)
            {
                Console.Error.WriteLine(error.Message);
                return 1;
            }
            MessageBox.Show("RoboGo could not start PowerShell.\n\n" + error.Message, "RoboGo", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
