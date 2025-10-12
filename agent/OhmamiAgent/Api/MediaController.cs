using Microsoft.AspNetCore.Mvc;
using OhmamiAgent.SystemControl;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace OhmamiAgent.Api
{
    [ApiController]
    [Route("")]
    public class MediaController : ControllerBase
    {
        private readonly AudioManager _audio;
        private readonly MediaManager _media;


        public MediaController(AudioManager audio, MediaManager media)
        {
            _audio = audio;
            _media = media;

        }

        [HttpGet("volume")]
        public IActionResult GetVolumeInfo()
        {
            try
            {
                var (level, muted) = _audio.GetVolume();
                return Ok(new { status = "ok", data = new { level, muted } });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpPost("volume/set")]
        public IActionResult SetVolumeLevel([FromQuery] int level)
        {
            try
            {
                _audio.SetVolume(level);
                return Ok(new { status = "ok", message = $"Volume set to {level}%" });
            }
            catch (ArgumentOutOfRangeException ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpPost("volume/mute")]
        public IActionResult MuteVolume()
        {
            try
            {
                _audio.SetMute(true);
                return Ok(new { status = "ok", message = "Volume muted" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpPost("volume/unmute")]
        public IActionResult UnmuteVolume()
        {
            try
            {
                _audio.SetMute(false);
                return Ok(new { status = "ok", message = "Volume unmuted" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        //-----------------

        [HttpGet("media/info")]
        public async Task<IActionResult> Info()
        {
            var data = await _media.GetStatusAsync();
            return Ok(new { status = "ok", data = data });
        }

        [HttpPost("media/play")]
        public async Task<IActionResult> Play()
        {
            await _media.PlayAsync();
            return Ok(new { status = "ok", message = "Playback started" });
        }

        [HttpPost("media/pause")]
        public async Task<IActionResult> Pause()
        {
            await _media.PauseAsync();
            return Ok(new { status = "ok", message = "Playback paused" });
        }

        [HttpPost("media/next")]
        public async Task<IActionResult> Next()
        {
            await _media.NextAsync();
            return Ok(new { status = "ok", message = "Skipped to next track" });
        }

        [HttpPost("media/previous")]
        public async Task<IActionResult> Previous()
        {
            await _media.PreviousAsync();
            return Ok(new { status = "ok", message = "Skipped to previous track" });
        }
    }
}
