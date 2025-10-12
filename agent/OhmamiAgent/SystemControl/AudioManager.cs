using NAudio.CoreAudioApi;
using System;
using System.Collections.Generic;
using System.Text;

namespace OhmamiAgent.SystemControl
{
    public class AudioManager : IDisposable
    {
        private readonly MMDeviceEnumerator enumerator;
        private MMDevice? cachedDevice;

        public AudioManager()
        {
            enumerator = new MMDeviceEnumerator();
        }

        private MMDevice GetDefaultDevice()
        {
            cachedDevice ??= enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            if (cachedDevice == null)
                throw new InvalidOperationException("Default audio endpoint not found");
            return cachedDevice;
        }

        public (int level, bool muted) GetVolume()
        {
            var dev = GetDefaultDevice();
            var vol = dev.AudioEndpointVolume;
            float scalar = vol.MasterVolumeLevelScalar;
            bool muted = vol.Mute;
            int percent = (int)Math.Round(scalar * 100);
            return (percent, muted);
        }

        public void SetVolume(int percent)
        {
            if (percent < 0 || percent > 100)
                throw new ArgumentOutOfRangeException(nameof(percent), "percent must be between 0 and 100");
            var dev = GetDefaultDevice();
            var vol = dev.AudioEndpointVolume;
            vol.MasterVolumeLevelScalar = percent / 100f;
        }

        public void SetMute(bool mute)
        {
            var dev = GetDefaultDevice();
            var vol = dev.AudioEndpointVolume;
            vol.Mute = mute;
        }

        public void Dispose()
        {
            cachedDevice?.Dispose();
            enumerator.Dispose();
        }
    }
}
