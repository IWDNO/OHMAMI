using Microsoft.AspNetCore.Mvc;
using OhmamiAgent.Remote;

namespace OhmamiAgent.Api
{
    [ApiController]
    [Route("")]
    public class RemoteController : ControllerBase
    {
        private readonly RemotePairingService _pairingService;

        public RemoteController(RemotePairingService pairingService)
        {
            _pairingService = pairingService;
        }

        [HttpPost("remote/pairing-code")]
        public async Task<IActionResult> CreatePairingCode(CancellationToken ct)
        {
            try
            {
                var result = await _pairingService.CreatePairingCodeAsync(ct);
                return Ok(new { status = "ok", data = result });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }
    }
}
