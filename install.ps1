# Personal AI OS 一键安装（PowerShell 5.1+，Windows 自带）
# 用法：
#   双击 install.bat                    —— 交互模式（检测已有仓库，或新建）
#   powershell -File install.ps1 -VaultPath "C:\某个库"   —— 直接装入指定仓库
#   测试专用参数：-ConfigPath <路径>  -NoOpen  -NewVaultPath <路径>
param(
  [string]$VaultPath = "",
  [string]$ConfigPath = "",
  [string]$NewVaultPath = "",
  [switch]$NewVault,
  [switch]$NoOpen,
  [string]$RepoZip = "https://github.com/Jingangster/personal-ai-os/archive/refs/heads/main.zip"
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = $PSScriptRoot
$VaultSrc = Join-Path $Root "vault"

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "  [!] $m" -ForegroundColor Yellow }

# ---------- 1. 模板来源：本地优先，否则下载（多源容错，适配国内网络） ----------
if (-not (Test-Path (Join-Path $VaultSrc "00 首页"))) {
  Write-Step "本地没有模板，开始下载（自动尝试多个下载源）"
  $tmpZip = Join-Path $env:TEMP ("paios-" + [guid]::NewGuid().ToString("N") + ".zip")
  $mirrors = @(
    $RepoZip,
    ("https://ghfast.top/" + $RepoZip),
    ("https://gh-proxy.com/" + $RepoZip),
    ("https://ghproxy.net/" + $RepoZip)
  )
  $done = $false
  foreach ($m in $mirrors) {
    try {
      Write-Host "  尝试: $m"
      Invoke-WebRequest -Uri $m -OutFile $tmpZip -UseBasicParsing -TimeoutSec 60
      if ((Get-Item $tmpZip).Length -gt 10000) { $done = $true; break }
    } catch { Write-Warn2 ("失败: " + $_.Exception.Message) }
  }
  if (-not $done) {
    Write-Host "全部下载源失败。请手动下载 ZIP 并解压，然后双击解压出来的 install.bat（离线安装）。" -ForegroundColor Red
    exit 1
  }
  $tmpDir = "$tmpZip.extract"
  Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
  $inner = Get-ChildItem $tmpDir | Where-Object { $_.PSIsContainer } | Select-Object -First 1
  $VaultSrc = Join-Path $inner.FullName "vault"
  if (-not (Test-Path $VaultSrc)) { Write-Host "ZIP 内容异常（没找到 vault 文件夹）" -ForegroundColor Red; exit 1 }
  Write-Ok "下载并解压完成"
} else {
  Write-Ok "检测到本地模板（离线安装模式）"
}

# ---------- 2. 选定目标 Obsidian 库 ----------
if (-not $ConfigPath) { $ConfigPath = Join-Path $env:APPDATA "obsidian\obsidian.json" }

if (-not $VaultPath -and -not $NewVault -and (Test-Path $ConfigPath)) {
  try {
    $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $existing = @()
    if ($cfg.vaults) {
      foreach ($p in $cfg.vaults.PSObject.Properties) {
        $dir = $p.Value.path
        if ($dir -and (Test-Path $dir)) { $existing += $dir }
      }
    }
    if ($existing.Count -gt 0) {
      Write-Step "检测到现有的 Obsidian 仓库"
      for ($i = 0; $i -lt $existing.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $existing[$i]) }
      Write-Host "  [0] 新建一个干净的仓库（推荐新手）"
      $sel = Read-Host "输入编号后回车（直接回车 = 新建）"
      if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $existing.Count) {
        $VaultPath = $existing[[int]$sel - 1]
      }
    }
  } catch { Write-Warn2 ("读取 Obsidian 配置失败，将新建仓库: " + $_.Exception.Message) }
}

if (-not $VaultPath) {
  if ($NewVaultPath) { $VaultPath = $NewVaultPath }
  else { $VaultPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PersonalAIOS" }
  New-Item -ItemType Directory -Force -Path $VaultPath | Out-Null
  if (Test-Path $ConfigPath) {
    $bak = "$ConfigPath.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item $ConfigPath $bak -Force
    Write-Ok ("已备份 Obsidian 配置: " + $bak)
    $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
  } else {
    $cfg = [pscustomobject]@{ vaults = [pscustomobject]@{} }
  }
  $key = -join ((1..16) | ForEach-Object { "{0:x}" -f (Get-Random -Maximum 16) })
  $props = @{}
  foreach ($p in $cfg.vaults.PSObject.Properties) { $props[$p.Name] = $p.Value }
  $props[$key] = [pscustomobject]@{ path = $VaultPath; ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); open = $true }
  [pscustomobject]@{ vaults = [pscustomobject]$props } |
    ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
  Write-Ok ("新仓库已登记进 Obsidian: " + $VaultPath)
  if (Get-Process Obsidian -ErrorAction SilentlyContinue) {
    Write-Warn2 "Obsidian 正在运行：新仓库若没自动出现，重启一次 Obsidian 即可。"
  }
}

New-Item -ItemType Directory -Force -Path $VaultPath | Out-Null

# ---------- 3. 复制模板（文件名都带 -模板，不会覆盖你已有的笔记） ----------
Write-Step ("复制模板到 " + $VaultPath)
Copy-Item (Join-Path $VaultSrc "*") $VaultPath -Recurse -Force
Write-Ok "00 首页 / 30 个人 / 90 AI 已就位"

# ---------- 4. 下一步 ----------
Write-Host ""
Write-Host "================ 安装完成 ================" -ForegroundColor Green
Write-Host " 下一步（三选一）："
Write-Host "  A. 把 prompts/00-工作模式.md 全文粘贴给任意 AI，让它接管（推荐）"
Write-Host "  B. 把 prompts/01-启动会话.md + 协议全文粘贴给 AI"
Write-Host "  C. 先自己看看 docs/小白指南.md"
Write-Host "=========================================="

if (-not $NoOpen) {
  $name = Split-Path $VaultPath -Leaf
  try { Start-Process ("obsidian://open?vault=" + [uri]::EscapeDataString($name)) } catch { }
}
