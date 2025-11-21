using System;
using System.IO;
using System.Security.AccessControl;
using System.Security.Principal;
using OhmamiAgent.SystemControl.FileSystem;

namespace OhmamiAgent.SystemControl.Security
{
    public static class AclManager
    {
        private static SecurityIdentifier GetCurrentUserSid()
        {
            return WindowsIdentity.GetCurrent().User!;
        }

        public static void BlockExe(string exePath)
        {
            ApplyFileDeny(exePath, FileSystemRights.ReadAndExecute);
        }

        public static void BlockPath(string path)
        {
            if (Directory.Exists(path))
            {
                ApplyDirectoryDeny(path, FileSystemRights.Modify);
            }
            else
            {
                ApplyFileDeny(path, FileSystemRights.Modify);
            }
        }

        public static void Unblock(string path)
        {
            if (Directory.Exists(path))
            {
                var d = new DirectoryInfo(path);
                var acl = d.GetAccessControl(AccessControlSections.Access);
                RemoveOurDenyRules(acl);
                d.SetAccessControl(acl);
            }
            else
            {
                var f = new FileInfo(path);
                var acl = f.GetAccessControl(AccessControlSections.Access);
                RemoveOurDenyRules(acl);
                f.SetAccessControl(acl);
            }
        }

        private static void ApplyFileDeny(string filePath, FileSystemRights rights)
        {
            var info = new FileInfo(filePath);
            var acl = info.GetAccessControl(AccessControlSections.Access);
            var rule = new FileSystemAccessRule(GetCurrentUserSid(), rights, AccessControlType.Deny);
            acl.AddAccessRule(rule);
            info.SetAccessControl(acl);
        }

        private static void ApplyDirectoryDeny(string dirPath, FileSystemRights rights)
        {
            var info = new DirectoryInfo(dirPath);
            var acl = info.GetAccessControl(AccessControlSections.Access);
            var rule = new FileSystemAccessRule(
                GetCurrentUserSid(),
                rights,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                PropagationFlags.None,
                AccessControlType.Deny);
            acl.AddAccessRule(rule);
            info.SetAccessControl(acl);
        }

        private static void RemoveOurDenyRules(FileSystemSecurity acl)
        {
            var rules = acl.GetAccessRules(true, true, typeof(SecurityIdentifier));
            foreach (FileSystemAccessRule r in rules)
            {
                if (r.AccessControlType == AccessControlType.Deny && r.IdentityReference == GetCurrentUserSid())
                {
                    acl.RemoveAccessRule(r);
                }
            }
        }
    }
}


