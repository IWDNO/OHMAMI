using Microsoft.AspNetCore.Mvc;
using OhmamiAgent.SystemControl;
using OhmamiAgent.SystemControl.FileSystem;
using OhmamiAgent.SystemControl.Security;

namespace OhmamiAgent.Api
{
    [ApiController]
    [Route("")]
    public class BlockController : ControllerBase
    {
        private readonly BlocklistStore _store;

        public BlockController(BlocklistStore store)
        {
            _store = store;
        }

        [HttpGet("security/blocked")]
        public IActionResult GetBlocked()
        {
            var data = _store.List();
            return Ok(new { status = "ok", data });
        }

        [HttpPost("security/block/app")]
        public IActionResult BlockApp([FromQuery] string path)
        {
            if (string.IsNullOrWhiteSpace(path))
                return BadRequest(new { status = "error", message = "path is required" });

            try
            {
                var exe = ShortcutResolver.ResolveTargetPath(path);
                var norm = PathHelper.NormalizeRequired(exe);
                AclManager.BlockExe(norm);
                _store.Add(norm);
                return Ok(new { status = "ok", exe = norm });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpPost("security/block/path")]
        public IActionResult BlockPath([FromQuery] string path)
        {
            if (string.IsNullOrWhiteSpace(path))
                return BadRequest(new { status = "error", message = "path is required" });

            try
            {
                var norm = PathHelper.NormalizeRequired(path);
                AclManager.BlockPath(norm);
                _store.Add(norm);
                return Ok(new { status = "ok", path = norm });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpDelete("security/unblock")]
        public IActionResult Unblock([FromQuery] string path)
        {
            if (string.IsNullOrWhiteSpace(path))
                return BadRequest(new { status = "error", message = "path is required" });

            try
            {
                var norm = PathHelper.NormalizeRequired(path);
                AclManager.Unblock(norm);
                _store.Remove(norm);
                return Ok(new { status = "ok", path = norm });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }
    }
}
