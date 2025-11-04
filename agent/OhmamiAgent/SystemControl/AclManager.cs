using System;
using System.IO;
using System.Security.AccessControl;
using System.Security.Principal;

namespace OhmamiAgent.SystemControl
{
    public class AclManager
    {
        private readonly SecurityIdentifier _sid;

        public AclManager()
        {
            _sid = WindowsIdentity.GetCurrent().User!;
        }

        public string Normalize(string path)
        {
            if (string.IsNullOrWhiteSpace(path))
                throw new ArgumentException("Path is required.", nameof(path));
            var full = Path.GetFullPath(path);
            if (full.Length > 3 && full.EndsWith(Path.DirectorySeparatorChar.ToString()))
                full = full.TrimEnd(Path.DirectorySeparatorChar);
            return full;
        }

        public void BlockExe(string exePath)
        {
            ApplyFileDeny(exePath, FileSystemRights.ReadAndExecute);
        }

        public void BlockPath(string path)
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

        public void Unblock(string path)
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

        private void ApplyFileDeny(string filePath, FileSystemRights rights)
        {
            var info = new FileInfo(filePath);
            var acl = info.GetAccessControl(AccessControlSections.Access);
            var rule = new FileSystemAccessRule(_sid, rights, AccessControlType.Deny);
            acl.AddAccessRule(rule);
            info.SetAccessControl(acl);
        }

        private void ApplyDirectoryDeny(string dirPath, FileSystemRights rights)
        {
            var info = new DirectoryInfo(dirPath);
            var acl = info.GetAccessControl(AccessControlSections.Access);
            var rule = new FileSystemAccessRule(
                _sid,
                rights,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                PropagationFlags.None,
                AccessControlType.Deny);
            acl.AddAccessRule(rule);
            info.SetAccessControl(acl);
        }

        private void RemoveOurDenyRules(FileSystemSecurity acl)
        {
            var rules = acl.GetAccessRules(true, true, typeof(SecurityIdentifier));
            foreach (FileSystemAccessRule r in rules)
            {
                if (r.AccessControlType == AccessControlType.Deny && r.IdentityReference == _sid)
                {
                    acl.RemoveAccessRule(r);
                }
            }
        }
    }
}


