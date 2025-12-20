using Microsoft.AspNetCore.Mvc;
using OhmamiAgent.SystemControl.Security;

namespace OhmamiAgent.Api
{
    [ApiController]
    [Route("")]
    public class HostsController : ControllerBase
    {
        private readonly HostsManager _hostsManager;

        public HostsController(HostsManager hostsManager)
        {
            _hostsManager = hostsManager;
        }

        [HttpGet("security/blocked-sites")]
        public IActionResult GetBlockedSites()
        {
            try
            {
                var data = _hostsManager.GetBlockedSites();
                return Ok(new { status = "ok", data });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpPost("security/block-site")]
        public IActionResult BlockSite([FromQuery] string domain)
        {
            if (string.IsNullOrWhiteSpace(domain))
                return BadRequest(new { status = "error", message = "domain is required" });

            try
            {
                var success = _hostsManager.BlockSite(domain);
                if (success)
                {
                    return Ok(new { status = "ok", domain });
                }
                else
                {
                    return BadRequest(new { status = "error", message = "Failed to block site. Check if you have administrator rights." });
                }
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

        [HttpDelete("security/unblock-site")]
        public IActionResult UnblockSite([FromQuery] string domain)
        {
            if (string.IsNullOrWhiteSpace(domain))
                return BadRequest(new { status = "error", message = "domain is required" });

            try
            {
                var success = _hostsManager.UnblockSite(domain);
                if (success)
                {
                    return Ok(new { status = "ok", domain });
                }
                else
                {
                    return BadRequest(new { status = "error", message = "Site was not blocked or failed to unblock. Check if you have administrator rights." });
                }
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




