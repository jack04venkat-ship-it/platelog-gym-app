$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$prefix = "http://localhost:4173/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
}
catch {
    Start-Process "http://localhost:4173"
    exit 0
}

Write-Host "PlateLog is running at $prefix"
Start-Process $prefix

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $relative = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart("/"))
        if (-not $relative) { $relative = "index.html" }

        $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
        if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            $context.Response.StatusCode = 403
            $context.Response.Close()
            continue
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $context.Response.StatusCode = 404
            $context.Response.Close()
            continue
        }

        $bytes = [IO.File]::ReadAllBytes($path)
        $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
        $types = @{
            ".html" = "text/html; charset=utf-8"
            ".js" = "text/javascript; charset=utf-8"
            ".css" = "text/css; charset=utf-8"
            ".json" = "application/json"
            ".webmanifest" = "application/manifest+json"
            ".svg" = "image/svg+xml"
        }
        $context.Response.ContentType = $types[$extension]
        if (-not $context.Response.ContentType) { $context.Response.ContentType = "application/octet-stream" }
        $context.Response.Headers.Add("Cache-Control", "no-cache")
        $context.Response.StatusCode = 200
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.OutputStream.Close()
    }
    catch {
        if (-not $listener.IsListening) { break }
    }
}
