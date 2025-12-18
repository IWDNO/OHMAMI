using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Management;
using System.ServiceProcess;

namespace OhmamiForm
{
    public partial class Form1 : Form
    {
        private const string ServiceName = "OhmamiAgent";
        public Form1()
        {
            InitializeComponent();
        }


        private void btnStart_Click(object sender, EventArgs e)
        {
            try
            {
                using (var sc = new ServiceController(ServiceName))
                {
                    if (sc.Status == ServiceControllerStatus.Stopped ||
                        sc.Status == ServiceControllerStatus.Paused)
                    {
                        sc.Start();
                        sc.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(10));
                    }
                }

                RefreshStatus();
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Ошибка запуска службы: {ex.Message}");
            }
        }

        private void btnStop_Click(object sender, EventArgs e)
        {
            try
            {
                using (var sc = new ServiceController(ServiceName))
                {
                    if (sc.Status == ServiceControllerStatus.Running)
                    {
                        sc.Stop();
                        sc.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(10));
                    }
                }

                RefreshStatus();
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Ошибка остановки службы: {ex.Message}");
            }
        }

        private void chkAutoStart_CheckedChanged(object sender, EventArgs e)
        {
            try
            {
                SetServiceStartMode(chkAutoStart.Checked);
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Не удалось изменить режим запуска: {ex.Message}");
                // откат флажка к реальному состоянию
                RefreshStatus();
            }
        }

        private void RefreshStatus()
        {
            try
            {
                using (var sc = new ServiceController(ServiceName))
                {
                    lblStatus.Text = $"Статус: {sc.Status}";

                    // читаем текущий StartMode через WMI
                    using (var service = new ManagementObject($"Win32_Service.Name='{ServiceName}'"))
                    {
                        service.Get();
                        var startMode = (string)service["StartMode"]; // "Automatic", "Manual", "Disabled"

                        chkAutoStart.Checked = string.Equals(startMode, "Automatic",
                            StringComparison.OrdinalIgnoreCase);
                    }

                    btnStart.Enabled = sc.Status == ServiceControllerStatus.Stopped ||
                                       sc.Status == ServiceControllerStatus.Paused;
                    btnStop.Enabled = sc.Status == ServiceControllerStatus.Running;
                }
            }
            catch
            {
                lblStatus.Text = "Служба не установлена";
                chkAutoStart.Checked = false;
                btnStart.Enabled = false;
                btnStop.Enabled = false;
            }
        }

        private static void SetServiceStartMode(bool auto)
        {
            using (var service = new ManagementObject($"Win32_Service.Name='{ServiceName}'"))
            {
                var inParams = service.GetMethodParameters("ChangeStartMode");
                inParams["StartMode"] = auto ? "Automatic" : "Manual";

                service.InvokeMethod("ChangeStartMode", inParams, null);
            }
        }

        private void Form1_Load(object sender, EventArgs e)
        {
            RefreshStatus();
        }
    }
}
