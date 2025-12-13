using Microsoft.AspNetCore.Mvc;
using OhmamiAgent.Stream;

namespace OhmamiAgent.Api
{
    [ApiController]
    [Route("")]
    public class StreamController : ControllerBase
    {
        private readonly ScreenShareService _screenShareService;

        public StreamController(ScreenShareService screenShareService)
        {
            _screenShareService = screenShareService;
        }

        [HttpPost("stream/start")]
        public IActionResult Start()
        {
            try
            {
                var channelId = _screenShareService.Start();
                return Ok(new { status = "ok", data = new { channelId } });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpPost("stream/stop")]
        public IActionResult Stop([FromQuery] string? channelId = null)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(channelId))
                    return BadRequest(new { status = "error", message = "ChannelId is required (?channelId=...)" });

                _screenShareService.Stop(channelId);
                return Ok(new { status = "ok", message = "Stream stopped" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }
    }
}
