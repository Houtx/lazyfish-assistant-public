param(
    [ValidateSet("deploy", "start", "stop", "status")]
    [string]$Action = "deploy"
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
$ComposeFile = Join-Path $RootDir "docker-compose.yml"
$VncComposeFile = Join-Path $RootDir "docker-compose.vnc.yml"
$EnvFile = Join-Path $RootDir ".env"
$AppUrl = ""
$NoVncUrl = ""
$VncPasswordPath = ""

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "[懒鱼助手] $Message" -ForegroundColor Cyan
}

function Add-DockerToPath {
    if (Get-Command docker.exe -ErrorAction SilentlyContinue) {
        return
    }

    $Candidates = @(
        (Join-Path $env:ProgramFiles "Docker\Docker\resources\bin"),
        (Join-Path $env:LOCALAPPDATA "Docker\resources\bin")
    )
    foreach ($Candidate in $Candidates) {
        if (Test-Path (Join-Path $Candidate "docker.exe")) {
            $env:Path = "$Candidate;$env:Path"
            return
        }
    }
}

function Test-DockerReady {
    & docker info *> $null
    return $LASTEXITCODE -eq 0
}

function Ensure-Docker {
    Add-DockerToPath
    if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
        Write-Step "尚未安装 Docker Desktop，正在打开官方下载页面。"
        Start-Process "https://www.docker.com/products/docker-desktop/"
        throw "请先安装并启动 Docker Desktop，然后重新双击本脚本。"
    }

    if (-not (Test-DockerReady)) {
        $DockerDesktop = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
        if (-not (Test-Path $DockerDesktop)) {
            throw "找不到 Docker Desktop，请先完成安装。"
        }
        Write-Step "正在启动 Docker Desktop，请稍候..."
        Start-Process $DockerDesktop
        for ($Attempt = 0; $Attempt -lt 90; $Attempt++) {
            Start-Sleep -Seconds 2
            if (Test-DockerReady) {
                break
            }
        }
        if (-not (Test-DockerReady)) {
            throw "Docker Desktop 启动超时。请确认它已正常运行后重试。"
        }
    }

    & docker compose version *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "当前 Docker 不支持 Compose v2，请升级 Docker Desktop。"
    }
}

function Ensure-Config {
    if (-not (Test-Path $EnvFile)) {
        Copy-Item (Join-Path $RootDir ".env.example") $EnvFile
        $UsedPorts = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners().Port
        $Port = 9000..9099 | Where-Object { $UsedPorts -notcontains $_ } | Select-Object -First 1
        if (-not $Port) {
            throw "9000-9099 端口均被占用，请联系卖家协助处理。"
        }
        $Config = [System.IO.File]::ReadAllText($EnvFile)
        $Config = [regex]::Replace($Config, '(?m)^APP_PORT=.*$', "APP_PORT=$Port")
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($EnvFile, $Config, $Utf8NoBom)
        Write-Step "已生成本机配置 .env。"
        if ($Port -ne 9000) {
            Write-Step "端口 9000 已被占用，已自动改用端口 ${Port}。"
        }
    }
}

function Get-EnvValue([string]$Key) {
    $Line = Get-Content $EnvFile | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
    if (-not $Line) {
        return ""
    }
    return ($Line -replace "^[^=]*=", "").Trim()
}

function Test-EnvKey([string]$Key) {
    $Pattern = "^$([regex]::Escape($Key))="
    $Match = Get-Content $EnvFile | Where-Object { $_ -match $Pattern } | Select-Object -First 1
    return $null -ne $Match
}

function Add-EnvDefault([string]$Key, [string]$Value) {
    if (Test-EnvKey $Key) {
        return
    }

    $Prefix = ""
    if ((Test-Path $EnvFile) -and (Get-Item $EnvFile).Length -gt 0) {
        $Stream = [System.IO.File]::Open(
            $EnvFile,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        try {
            [void]$Stream.Seek(-1, [System.IO.SeekOrigin]::End)
            $LastByte = $Stream.ReadByte()
        } finally {
            $Stream.Dispose()
        }
        if ($LastByte -ne 10 -and $LastByte -ne 13) {
            $Prefix = "`r`n"
        }
    }

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($EnvFile, "${Prefix}${Key}=${Value}`r`n", $Utf8NoBom)
}

function Update-VncEnvDefaults {
    Add-EnvDefault "VNC_PASSWORD_FILE" "./secrets/vnc_password.txt"
    Add-EnvDefault "NOVNC_PORT" "6080"
    $NoVncPort = Get-EnvValue "NOVNC_PORT"
    Add-EnvDefault `
        "MANUAL_VERIFICATION_URL" `
        "http://127.0.0.1:${NoVncPort}/vnc.html?autoconnect=1&resize=scale"
    Add-EnvDefault "XY_MANUAL_SLIDER_TAKEOVER_TIMEOUT" "450"
}

function Resolve-VncPasswordPath {
    $ConfiguredPath = Get-EnvValue "VNC_PASSWORD_FILE"
    if (-not $ConfiguredPath) {
        $ConfiguredPath = "./secrets/vnc_password.txt"
    }
    if ([System.IO.Path]::IsPathRooted($ConfiguredPath)) {
        $script:VncPasswordPath = $ConfiguredPath
    } else {
        $RelativePath = $ConfiguredPath -replace '^[.][\\/]', ''
        $script:VncPasswordPath = Join-Path $RootDir $RelativePath
    }
}

function Protect-VncSecret([string]$DirectoryPath, [string]$FilePath) {
    $CurrentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $DirectoryPath /inheritance:r /grant:r "*${CurrentSid}:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "无法保护 noVNC 密码目录权限。"
    }
    & icacls.exe $FilePath /inheritance:r /grant:r "*${CurrentSid}:F" "*S-1-5-18:F" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "无法保护 noVNC 密码文件权限。"
    }
}

function Ensure-VncPassword {
    Resolve-VncPasswordPath
    $SecretDirectory = Split-Path -Parent $VncPasswordPath
    New-Item -ItemType Directory -Force -Path $SecretDirectory | Out-Null

    if (-not (Test-Path $VncPasswordPath) -or (Get-Item $VncPasswordPath).Length -eq 0) {
        $RandomBytes = New-Object byte[] 18
        $Random = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        try {
            $Random.GetBytes($RandomBytes)
        } finally {
            $Random.Dispose()
        }
        $Password = [Convert]::ToBase64String($RandomBytes)
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($VncPasswordPath, "$Password`n", $Utf8NoBom)
    }

    Protect-VncSecret -DirectoryPath $SecretDirectory -FilePath $VncPasswordPath
}

function Set-AppUrl {
    $Port = Get-EnvValue "APP_PORT"
    if ($Port -notmatch '^\d+$') {
        throw ".env 中的 APP_PORT 配置无效。"
    }
    $script:AppUrl = "http://127.0.0.1:$Port"
}

function Set-NoVncUrl {
    $Port = Get-EnvValue "NOVNC_PORT"
    if ($Port -notmatch '^\d+$') {
        throw ".env 中的 NOVNC_PORT 配置无效。"
    }
    $script:NoVncUrl = "http://127.0.0.1:$Port/vnc.html?autoconnect=1&resize=scale"
}

function Open-App {
    if ($env:LAZYFISH_NO_OPEN -ne "true") {
        Start-Process $AppUrl
    }
}

function Invoke-Compose {
    param([Parameter(Mandatory = $true)][string[]]$ComposeArguments)
    & docker compose --project-directory $RootDir --env-file $EnvFile -f $ComposeFile -f $VncComposeFile @ComposeArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Compose 执行失败，请保留窗口中的信息并联系卖家。"
    }
}

function Wait-ForApp {
    for ($Attempt = 0; $Attempt -lt 60; $Attempt++) {
        try {
            $Response = Invoke-WebRequest -UseBasicParsing -Uri "$AppUrl/health" -TimeoutSec 3
            if ($Response.StatusCode -eq 200) {
                return
            }
        } catch {
        }
        Start-Sleep -Seconds 2
    }
    Invoke-Compose -ComposeArguments @("ps")
    throw "服务启动超时，请保留窗口中的信息并联系卖家。"
}

function Show-InitialPassword {
    $Password = & docker compose --project-directory $RootDir --env-file $EnvFile -f $ComposeFile -f $VncComposeFile `
        exec -T lazyfish-assistant sh -c 'cat /app/data/.initial_admin_password 2>/dev/null || true' 2>$null
    if ($LASTEXITCODE -eq 0 -and $Password) {
        Write-Host ""
        Write-Host "首次登录管理员账号：admin" -ForegroundColor Yellow
        Write-Host "首次登录管理员密码：$Password" -ForegroundColor Yellow
        Write-Host "登录后请立即修改密码。" -ForegroundColor Yellow
    }
}

function Show-NoVncAccess {
    $Password = ([System.IO.File]::ReadAllText($VncPasswordPath)).Trim()
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "需要人工处理滑块时，请使用 noVNC 容器浏览器" -ForegroundColor Yellow
    Write-Host "noVNC 入口：$NoVncUrl" -ForegroundColor Yellow
    Write-Host "noVNC 密码：$Password" -ForegroundColor Yellow
    Write-Host "底层 VNC 端口不发布，noVNC 仅绑定本机，不会对局域网或公网开放。" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
}

try {
    Ensure-Docker
    Ensure-Config
    Update-VncEnvDefaults
    if (-not (Test-Path $VncComposeFile)) {
        throw "缺少 docker-compose.vnc.yml，请重新完整解压部署包。"
    }
    Ensure-VncPassword
    Set-AppUrl
    Set-NoVncUrl

    switch ($Action) {
        "deploy" {
            Write-Step "正在拉取最新稳定版本，首次下载可能需要几分钟..."
            Invoke-Compose -ComposeArguments @("pull", "lazyfish-assistant")
            Write-Step "正在启动懒鱼助手..."
            Invoke-Compose -ComposeArguments @("up", "-d", "--remove-orphans", "lazyfish-assistant")
            Wait-ForApp
            Invoke-Compose -ComposeArguments @("ps")
            Show-InitialPassword
            Write-Step "部署完成，访问地址：$AppUrl"
            Show-NoVncAccess
            Open-App
        }
        "start" {
            Write-Step "正在启动懒鱼助手..."
            Invoke-Compose -ComposeArguments @("up", "-d", "lazyfish-assistant")
            Wait-ForApp
            Invoke-Compose -ComposeArguments @("ps")
            Show-InitialPassword
            Show-NoVncAccess
            Open-App
        }
        "stop" {
            Write-Step "正在停止懒鱼助手，客户数据不会被删除..."
            Invoke-Compose -ComposeArguments @("stop", "lazyfish-assistant")
            Invoke-Compose -ComposeArguments @("ps")
        }
        "status" {
            Invoke-Compose -ComposeArguments @("ps")
        }
    }
} catch {
    Write-Host ""
    Write-Host "[错误] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
