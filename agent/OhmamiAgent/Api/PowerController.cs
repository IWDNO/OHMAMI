using Microsoft.AspNetCore.Mvc;
using OhmamiAgent.SystemControl.Power;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace OhmamiAgent.Api
{
    [ApiController]
    [Route("")]
    public class PowerController : ControllerBase
    {

        [HttpGet("shutdown")]
        public IActionResult Shutdown()
        {
            try
            {
                PowerManager.Shutdown();
                return Ok(new { status = "ok", message = "Shutdown" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpGet("restart")]
        public IActionResult Restart()
        {
            try
            {
                PowerManager.Restart();
                return Ok(new { status = "ok", message = "Restart" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpGet("sleep")]
        public IActionResult Sleep()
        {
            try
            {
                PowerManager.Sleep();
                return Ok(new { status = "ok", message = "Restart" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpGet("hibernate")]
        public IActionResult Hibernate()
        {
            try
            {
                PowerManager.Hibernate();
                return Ok(new { status = "ok", message = "Restart" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }
    }
}
