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
  [string]$RepoZip = "https://github.com/Jingangster/personal-ai-os/archive/refs/heads/main.zip",
  [string]$ObsidianExeUrl = "https://github.com/obsidianmd/obsidian-releases/releases/download/v1.15.1/Obsidian-1.15.1.exe"
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = $PSScriptRoot
$VaultSrc = Join-Path $Root "vault"
$PromptsSrc = Join-Path $Root "prompts"

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "  [!] $m" -ForegroundColor Yellow }

# 通用多镜像下载（直连 → 国内加速镜像依次尝试）
function Invoke-Download($url, $out, $minSize) {
  $mirrors = @(
    $url,
    ("https://ghfast.top/" + $url),
    ("https://gh-proxy.com/" + $url),
    ("https://ghproxy.net/" + $url)
  )
  foreach ($m in $mirrors) {
    try {
      Write-Host "  尝试: $m"
      Invoke-WebRequest -Uri $m -OutFile $out -UseBasicParsing -TimeoutSec 120
      if ((Get-Item $out).Length -gt $minSize) { return $true }
    } catch { Write-Warn2 ("失败: " + $_.Exception.Message) }
  }
  return $false
}

# ---------- 0. Obsidian 本体：没装就自动静默安装 ----------
$obsidianExe = Join-Path $env:LOCALAPPDATA "Obsidian\Obsidian.exe"
if (-not (Test-Path $obsidianExe)) {
  foreach ($root_ in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
                       "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
                       "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
    try {
      Get-ItemProperty (Join-Path $root_ "*") -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "Obsidian*" -and $_.InstallLocation } |
        ForEach-Object {
          $cand = Join-Path $_.InstallLocation "Obsidian.exe"
          if (Test-Path $cand) { $obsidianExe = $cand }
        }
    } catch { }
    if (Test-Path $obsidianExe) { break }
  }
}
if (Test-Path $obsidianExe) {
  Write-Ok ("已检测到 Obsidian: " + $obsidianExe)
} else {
  Write-Step "没检测到 Obsidian，自动下载官方安装包并静默安装（约 1–2 分钟，取决于网速）"
  $dl = Join-Path $env:TEMP "Obsidian-setup.exe"
  if (Invoke-Download $ObsidianExeUrl $dl 50000000) {
    Write-Ok "安装包下载完成，开始静默安装"
    try { Start-Process $dl "/S" -Wait } catch { Write-Warn2 ("安装启动失败: " + $_.Exception.Message) }
    $deadline = (Get-Date).AddSeconds(120)
    while (-not (Test-Path $obsidianExe) -and (Get-Date) -lt $deadline) { Start-Sleep 5 }
    if (Test-Path $obsidianExe) { Write-Ok "Obsidian 安装完成" }
    else { Write-Warn2 "自动安装未完成。不影响本系统：模板已装好；请稍后去 obsidian.md 手动安装 Obsidian。" }
  } else {
    Write-Warn2 "下载失败。不影响本系统：模板已装好；请稍后去 obsidian.md 手动安装 Obsidian。"
  }
}

# ---------- 1. 模板来源：本地优先，否则下载（多镜像容错） ----------
if (-not (Test-Path (Join-Path $VaultSrc "00 首页"))) {
  Write-Step "本地没有模板，开始下载（自动尝试多个下载源）"
  $tmpZip = Join-Path $env:TEMP ("paios-" + [guid]::NewGuid().ToString("N") + ".zip")
  if (-not (Invoke-Download $RepoZip $tmpZip 10000)) {
    Write-Host "全部下载源失败。请手动下载 ZIP 并解压，然后双击解压出来的 install.bat（离线安装）。" -ForegroundColor Red
    exit 1
  }
  $tmpDir = "$tmpZip.extract"
  Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
  $inner = Get-ChildItem $tmpDir | Where-Object { $_.PSIsContainer } | Select-Object -First 1
  $VaultSrc = Join-Path $inner.FullName "vault"
  $PromptsSrc = Join-Path $inner.FullName "prompts"
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

# ---------- 3. 复制模板 + AI 提示词（文件名都带 -模板，不会覆盖你已有的笔记） ----------
Write-Step ("复制模板到 " + $VaultPath)
Copy-Item (Join-Path $VaultSrc "*") $VaultPath -Recurse -Force
Write-Ok "00 首页 / 30 个人 / 90 AI 已就位"
if (Test-Path $PromptsSrc) {
  Copy-Item $PromptsSrc (Join-Path $VaultPath "prompts") -Recurse -Force
  Write-Ok "prompts（AI 提示词）也放进了库里"
}

# ---------- 4. 下一步 ----------
Write-Host ""
Write-Host "================ 安装完成 ================" -ForegroundColor Green
Write-Host " 下一步（只剩一件事）："
Write-Host "  打开 Obsidian 里的 prompts/00-工作模式.md，"
Write-Host "  全文复制，粘贴给任意 AI（豆包/DeepSeek 都行），发送。"
Write-Host "  它会接管剩下的一切。"
Write-Host "=========================================="

if (-not $NoOpen) {
  $name = Split-Path $VaultPath -Leaf
  try { Start-Process ("obsidian://open?vault=" + [uri]::EscapeDataString($name)) } catch { }
  $promptFile = Join-Path $VaultPath "prompts\00-工作模式.md"
  if (Test-Path $promptFile) { Start-Process notepad.exe $promptFile }
}
