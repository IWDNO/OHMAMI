using Microsoft.AspNetCore.Mvc;
using OhmamiAgent.SystemControl;

namespace OhmamiAgent.Api
{
    [ApiController]
    [Route("")]
    public class BlockController : ControllerBase
    {
        private readonly ShortcutResolver _shortcutResolver;
        private readonly BlocklistStore _store;
        private readonly AclManager _acl;

        public BlockController(ShortcutResolver shortcutResolver, BlocklistStore store, AclManager acl)
        {
            _shortcutResolver = shortcutResolver;
            _store = store;
            _acl = acl;
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
                var exe = _shortcutResolver.ResolveTargetPath(path);
                var norm = _acl.Normalize(exe);
                _acl.BlockExe(norm);
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
                var norm = _acl.Normalize(path);
                _acl.BlockPath(norm);
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
                var norm = _acl.Normalize(path);
                _acl.Unblock(norm);
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
