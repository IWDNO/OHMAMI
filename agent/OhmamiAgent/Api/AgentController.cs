using Microsoft.AspNetCore.Mvc;
using System;
using System.Collections.Generic;
using System.Text;

namespace OhmamiAgent.Api
{
    [ApiController]
    [Route("")]
    public class AgentController : ControllerBase
    {
        private readonly Ws.WebSocketManager _wsManager;

        public AgentController(Ws.WebSocketManager wsManager)
        {
            _wsManager = wsManager;
        }

        [HttpGet("ping")]
        public IActionResult Ping()
        {
            return Ok(new { status = "ok", msg = "agent alive" });
        }

        [HttpGet("ws")]
        public async Task GetWs()
        {
            if (HttpContext.WebSockets.IsWebSocketRequest)
            {
                using var ws = await HttpContext.WebSockets.AcceptWebSocketAsync();
                await _wsManager.HandleConnectionAsync(ws, HttpContext.RequestAborted);
            }
            else
            {
                HttpContext.Response.StatusCode = 400;
            }
        }
    }
}
