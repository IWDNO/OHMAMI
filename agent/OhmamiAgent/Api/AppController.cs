using Microsoft.AspNetCore.Mvc;
using OhmamiAgent.SystemControl.FileSystem;

namespace OhmamiAgent.Api
{
    [ApiController]
    [Route("")]
    public class AppController : ControllerBase
    {
        private readonly ApplicationManager _apps;

        public AppController(ApplicationManager apps)
        {
            _apps = apps;
        }

        [HttpGet("apps")]
        public IActionResult GetApps()
        {
            try
            {
                var data = _apps.ListApps();
                return Ok(new { status = "ok", data });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpGet("apps/search")]
        public IActionResult Search([FromQuery] string q)
        {
            try
            {
                var data = _apps.Search(q);
                return Ok(new { status = "ok", data });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        public class LaunchRequest
        {
            public string? Path { get; set; }
        }

        [HttpPost("apps/launch")]
        public IActionResult Launch([FromQuery] string? path = null)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(path))
                    return BadRequest(new { status = "error", message = "Path is required (body.path or ?path=...)." });

                _apps.Launch(path);
                return Ok(new { status = "ok", message = "Launched" });
            }
            catch (UnauthorizedAccessException ex)
            {
                return StatusCode(403, new { status = "error", message = ex.Message });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }
    }
}
