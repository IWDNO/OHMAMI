using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using System;
using System.IO;
using System.Threading.Tasks;
using System.Collections.Generic;
using OhmamiAgent.SystemControl.FileSystem;

namespace OhmamiAgent.Api
{
    [ApiController]
    [Route("")]
    public class FileController : ControllerBase
    {
        private readonly FileSystemManager _fs;

        public FileController(FileSystemManager fs)
        {
            _fs = fs;
        }

        [HttpGet("fs/ls")]
        public IActionResult List([FromQuery] string? path = null)
        {
            try
            {
                var data = _fs.List(path);
                return Ok(new { status = "ok", data });
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

        [HttpGet("fs/download")]
        public IActionResult Download([FromQuery] string path)
        {
            try
            {
                var full = _fs.NormalizeForRead(path);
                if (!System.IO.File.Exists(full))
                    return NotFound(new { status = "error", message = "File not found" });

                var fileName = System.IO.Path.GetFileName(full);
                return PhysicalFile(full, "application/octet-stream", fileName, enableRangeProcessing: true);
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

        [HttpPost("fs/upload")]
        [RequestSizeLimit(104857600)]
        public async Task<IActionResult> Upload([FromQuery] string dest, [FromForm] IFormFile file)
        {
            try
            {
                if (file == null || file.Length == 0)
                    return BadRequest(new { status = "error", message = "Empty file" });

                var finalPath = _fs.PrepareUploadPath(dest, file.FileName);

                using (var stream = new FileStream(finalPath, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    await file.CopyToAsync(stream);
                }
                return Ok(new { status = "ok", message = "Uploaded", path = finalPath });
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

        public sealed class RemoteUploadRequest
        {
            public string? FileName { get; set; }
            public string? ContentBase64 { get; set; }
        }

        [HttpPost("fs/upload-base64")]
        [RequestSizeLimit(104857600)]
        public async Task<IActionResult> UploadBase64([FromQuery] string dest, [FromBody] RemoteUploadRequest request)
        {
            try
            {
                if (request == null || string.IsNullOrWhiteSpace(request.FileName) || string.IsNullOrWhiteSpace(request.ContentBase64))
                    return BadRequest(new { status = "error", message = "FileName and ContentBase64 are required" });

                byte[] bytes;
                try
                {
                    bytes = Convert.FromBase64String(request.ContentBase64);
                }
                catch (FormatException)
                {
                    return BadRequest(new { status = "error", message = "Invalid base64 content" });
                }

                var finalPath = _fs.PrepareUploadPath(dest, request.FileName);

                await System.IO.File.WriteAllBytesAsync(finalPath, bytes);
                return Ok(new { status = "ok", message = "Uploaded", path = finalPath });
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

        [HttpPost("fs/mkdir")]
        public IActionResult Mkdir([FromQuery] string path)
        {
            try
            {
                _fs.CreateDirectory(path);
                return Ok(new { status = "ok", message = "Directory created" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpDelete("fs/rm")]
        public IActionResult RemoveFile([FromQuery] string path)
        {
            try
            {
                _fs.DeleteFile(path);
                return Ok(new { status = "ok", message = "File deleted" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpDelete("fs/rmdir")]
        public IActionResult RemoveDir([FromQuery] string path, [FromQuery] bool recursive = false)
        {
            try
            {
                _fs.DeleteDirectory(path, recursive);
                return Ok(new { status = "ok", message = "Directory deleted" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }

        [HttpGet("fs/special-folders")]
        public IActionResult GetSpecialFolders()
        {
            try
            {
                var folders = _fs.GetSpecialFolders();
                return Ok(new { status = "ok", data = folders });
            }
            catch (Exception ex)
            {
                return BadRequest(new { status = "error", message = ex.Message });
            }
        }
    }
}
