# 本地 Docker 部署脚本。
# 用法：
#   .\deploy.ps1 start     启动容器；本地镜像不存在时先构建
#   .\deploy.ps1 restart   重新构建镜像，并重建容器
#   .\deploy.ps1 stop      停止容器，保留数据卷和镜像
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
# PowerShell 7 默认不把外部程序的非零退出码当成终止错误；这里显式关闭，改由下面的退出码检查处理。
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

# 固定到脚本所在的仓库根目录，避免从其他目录执行时找不到 Compose 文件。
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root

# 基础编排加本地构建覆盖。后者把镜像固定为 opencode2api:local。
$ComposeArgs = @('-f', 'compose.yaml', '-f', 'compose.local.yaml')
$LocalImage = 'opencode2api:local'

function Write-Usage {
    Write-Host "用法:"
    Write-Host "  .\deploy.ps1 start     启动容器。本地镜像不存在时会先构建。"
    Write-Host "  .\deploy.ps1 restart   重新构建镜像，并重建容器。"
    Write-Host "  .\deploy.ps1 stop      停止容器。保留数据卷和镜像。"
}

function Invoke-Docker {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    Write-Host (">> docker " + ($ArgumentList -join ' '))
    & docker @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Docker 命令失败，退出码 $LASTEXITCODE"
    }
}

function Assert-Docker {
    # 使用 Compose V2 的 docker compose 子命令，而不是旧的 docker-compose 可执行文件。
    & docker compose version 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "未找到可用的 Docker Compose。请先安装并启动 Docker。"
    }
}

function Ensure-Config {
    $configPath = Join-Path $Root 'config.json'
    if (Test-Path -LiteralPath $configPath) {
        return
    }

    $examplePath = Join-Path $Root 'config.example.json'
    if (-not (Test-Path -LiteralPath $examplePath)) {
        throw "缺少 config.json，并且找不到 config.example.json。"
    }

    # Compose 把宿主机 config.json 作为首次启动的配置种子，文件不存在时无法启动。
    Copy-Item -LiteralPath $examplePath -Destination $configPath
    Write-Warning "已根据 config.example.json 生成 config.json。启动前请填写 Key，并修改 WebUI 密码。"
}

function Test-LocalImage {
    & docker image inspect $LocalImage --format '{{.Id}}' 1>$null 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Build-LocalImage {
    Invoke-Docker (@('compose') + $ComposeArgs + @('build'))
}

function Show-Endpoints {
    $apiPort = if ([string]::IsNullOrWhiteSpace($env:OPENCODE2API_PORT)) { '9090' } else { $env:OPENCODE2API_PORT }
    $webPort = if ([string]::IsNullOrWhiteSpace($env:OPENCODE2API_WEBUI_PORT)) { '9091' } else { $env:OPENCODE2API_WEBUI_PORT }
    Write-Host "API:   http://127.0.0.1:$apiPort"
    Write-Host "WebUI: http://127.0.0.1:$webPort"
}

switch ($Action) {
    'start' {
        Assert-Docker
        Ensure-Config
        if (-not (Test-LocalImage)) {
            Write-Host "本地镜像 $LocalImage 不存在，开始构建。"
            Build-LocalImage
        }
        Invoke-Docker (@('compose') + $ComposeArgs + @('up', '-d'))
        Show-Endpoints
    }
    'restart' {
        Assert-Docker
        Ensure-Config
        Write-Host "重新构建镜像并重建容器。已有数据卷会保留。"
        Build-LocalImage
        # --force-recreate 确保容器换上刚构建的镜像，而不是只重启旧容器。
        Invoke-Docker (@('compose') + $ComposeArgs + @('up', '-d', '--force-recreate'))
        Show-Endpoints
    }
    'stop' {
        Assert-Docker
        Invoke-Docker (@('compose') + $ComposeArgs + @('stop'))
        Write-Host "容器已停止。数据卷和本地镜像已保留。"
    }
    default {
        Write-Usage
        exit 1
    }
}
