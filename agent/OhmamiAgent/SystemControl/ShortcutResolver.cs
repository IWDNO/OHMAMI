using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace OhmamiAgent.SystemControl
{
    public class ShortcutResolver
    {
        public string ResolveTargetPath(string shortcutPath)
        {
            if (string.IsNullOrWhiteSpace(shortcutPath))
                throw new ArgumentException("Path is required.", nameof(shortcutPath));

            var full = Path.GetFullPath(shortcutPath);
            if (!File.Exists(full))
                throw new FileNotFoundException("Shortcut not found.", full);

            // Resolve via WScript.Shell on an STA thread
            var tcs = new TaskCompletionSource<string>();

            var thread = new Thread(() =>
            {
                try
                {
                    var type = Type.GetTypeFromProgID("WScript.Shell");
                    if (type == null)
                        throw new InvalidOperationException("WScript.Shell COM is not available.");

                    var shell = Activator.CreateInstance(type);
                    if (shell == null)
                        throw new InvalidOperationException("Failed to create WScript.Shell instance.");

                    dynamic wsh = shell;
                    var shortcut = wsh.CreateShortcut(full);
                    string target = (string)shortcut.TargetPath;

                    if (string.IsNullOrWhiteSpace(target))
                        throw new InvalidOperationException("Shortcut has empty TargetPath.");

                    // Normalize target path
                    target = Path.GetFullPath(target);
                    tcs.SetResult(target);
                }
                catch (Exception ex)
                {
                    tcs.SetException(ex);
                }
            });

            thread.SetApartmentState(ApartmentState.STA);
            thread.IsBackground = true;
            thread.Start();

            return tcs.Task.GetAwaiter().GetResult();
        }
    }
}


