using System.Runtime.InteropServices;

namespace OhmamiAgent.SystemControl
{
    public class PowerManager
    {
        // Flags для ExitWindowsEx
        private const uint EWX_LOGOFF = 0x00000000;
        private const uint EWX_SHUTDOWN = 0x00000001;
        private const uint EWX_REBOOT = 0x00000002;
        private const uint EWX_FORCE = 0x00000004;
        private const uint EWX_POWEROFF = 0x00000008;
        private const uint EWX_FORCEIFHUNG = 0x00000010;

        [DllImport("PowrProf.dll", SetLastError = true)]
        private static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool ExitWindowsEx(uint uFlags, uint dwReason);

        // Для прав
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("advapi32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges,
            ref TOKEN_PRIVILEGES NewState, uint Zero, IntPtr Null1, IntPtr Null2);

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID
        {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TOKEN_PRIVILEGES
        {
            public uint PrivilegeCount;
            public LUID Luid;
            public uint Attributes;
        }

        private const uint TOKEN_ADJUST_PRIVILEGES = 0x00000020;
        private const uint TOKEN_QUERY = 0x00000008;
        private const uint SE_PRIVILEGE_ENABLED = 0x00000002;

        public static void EnableShutdownPrivilege()
        {
            if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out var tokenHandle))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "OpenProcessToken failed");

            if (!LookupPrivilegeValue(null, "SeShutdownPrivilege", out var luid))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "LookupPrivilegeValue failed");

            var tp = new TOKEN_PRIVILEGES
            {
                PrivilegeCount = 1,
                Luid = luid,
                Attributes = SE_PRIVILEGE_ENABLED
            };

            if (!AdjustTokenPrivileges(tokenHandle, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "AdjustTokenPrivileges failed");
        }

        public static void Shutdown(bool force = false)
        {
            EnableShutdownPrivilege();
            uint flags = EWX_SHUTDOWN | EWX_POWEROFF;
            if (force) flags |= EWX_FORCE;
            if (!ExitWindowsEx(flags, 0))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "ExitWindowsEx Shutdown failed");
        }

        public static void Restart(bool force = false)
        {
            EnableShutdownPrivilege();
            uint flags = EWX_REBOOT;
            if (force) flags |= EWX_FORCE;
            if (!ExitWindowsEx(flags, 0))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "ExitWindowsEx Reboot failed");
        }

        public static void Logoff(bool force = false)
        {
            uint flags = EWX_LOGOFF;
            if (force) flags |= EWX_FORCE;
            if (!ExitWindowsEx(flags, 0))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "ExitWindowsEx Logoff failed");
        }

        /// <summary>
        /// Переводит в спящий режим (S1-S3 — зависит от системы).
        /// </summary>
        public static bool Sleep()
        {
            // hibernate = false, forceCritical = false, disableWakeEvent = false
            return SetSuspendState(false, false, false);
        }

        /// <summary>
        /// Гибернация (hibernate = true). Гибернация должна быть включена в системе.
        /// </summary>
        public static bool Hibernate()
        {
            return SetSuspendState(true, false, false);
        }
    }
}
