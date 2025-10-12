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


        public MediaController(AudioManager audio)
        {
            _audio = audio;
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
    }
}
