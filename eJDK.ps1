# eJDK.ps1
# 高级 Windows JDK 管理工具
# 支持参数：
#   -list      列出所有 JDK
#   -use <jdkName>  切换到指定 JDK
#   -current   显示当前 JAVA_HOME 和 java 版本
#   -path <customPath>  使用自定义 JDK 根目录（可选）
# 直接修改注册表 PATH，立即在当前 PowerShell 会话生效
# 需要管理员权限

param(
    [switch]$list,
    [string]$use,
    [switch]$current,
    [string]$path
)

# 检查管理员权限
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "请使用管理员权限运行此脚本。" -ForegroundColor Red
    exit 1
}

# 约定 JDK 根目录，优先使用 -path 参数
if ([string]::IsNullOrEmpty($path)) {
    $JdkRoot = "C:\Users\dragonkeep\Environment\jdk"
} else {
    $JdkRoot = $path
}

# 获取所有 JDK 目录
function Get-JDKDirs {
    if (-not (Test-Path $JdkRoot)) { return @() }
    return Get-ChildItem -Path $JdkRoot -Directory | Where-Object { Test-Path "$($_.FullName)\bin\java.exe" }
}

$jdkDirs = Get-JDKDirs

# 显示当前 JDK
function Current-JDK {
    $current = [System.Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if ([string]::IsNullOrEmpty($current)) {
        Write-Host "当前未设置 JAVA_HOME" -ForegroundColor Yellow
    } else {
        Write-Host "当前 JAVA_HOME: $current" -ForegroundColor Cyan
        try { 
            & "$current\bin\java.exe" -version 
        } catch { 
            Write-Host "无法执行 java -version" -ForegroundColor Red 
        }
        
        # 显示当前JAR文件关联
        $jarAssoc = Get-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\jarfile\shell\open\command" -Name "(default)" -ErrorAction SilentlyContinue
        if ($jarAssoc) {
            Write-Host "当前 JAR 文件关联: $($jarAssoc.'(default)')" -ForegroundColor Cyan
        } else {
            Write-Host "未找到 JAR 文件关联" -ForegroundColor Yellow
        }
    }
}

# 列出所有 JDK
function List-JDKs {
    Write-Host "检测到以下 JDK:"
    foreach ($jdk in $jdkDirs) {
        Write-Host " - $($jdk.Name)"
    }
}

# 更新 JAR 文件关联
function Update-JarFileAssociation($jdkPath) {
    $javawPath = "$jdkPath\bin\javaw.exe"
    
    if (-not (Test-Path $javawPath)) {
        Write-Host "警告: 未找到 javaw.exe，跳过 JAR 文件关联更新" -ForegroundColor Yellow
        return
    }
    
    try {
        # 设置 JAR 文件关联
        $command = "`"$javawPath`" -jar `"%1`""
        
        # 创建/更新注册表项 - 使用完整的注册表路径
        # 1. 设置 .jar 扩展名关联
        if (-not (Test-Path "Registry::HKEY_CLASSES_ROOT\.jar")) {
            New-Item -Path "Registry::HKEY_CLASSES_ROOT\.jar" -Force | Out-Null
        }
        Set-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\.jar" -Name "(default)" -Value "jarfile" -Force
        
        # 2. 设置 jarfile 类型的命令
        if (-not (Test-Path "Registry::HKEY_CLASSES_ROOT\jarfile\shell\open\command")) {
            New-Item -Path "Registry::HKEY_CLASSES_ROOT\jarfile\shell\open\command" -Force | Out-Null
        }
        Set-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\jarfile\shell\open\command" -Name "(default)" -Value $command -Force
        
        # 3. 设置默认图标
        if (-not (Test-Path "Registry::HKEY_CLASSES_ROOT\jarfile\DefaultIcon")) {
            New-Item -Path "Registry::HKEY_CLASSES_ROOT\jarfile\DefaultIcon" -Force | Out-Null
        }
        Set-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\jarfile\DefaultIcon" -Name "(default)" -Value "$javawPath,0" -Force
        
        Write-Host "已更新 JAR 文件关联到: $javawPath" -ForegroundColor Green
    }
    catch {
        Write-Host "更新 JAR 文件关联失败: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 切换 JDK
function Use-JDK($version) {
    $target = $jdkDirs | Where-Object { $_.Name -eq $version }
    if (-not $target) {
        Write-Host "未找到 JDK: $version" -ForegroundColor Red
        Write-Host "运行 -list 查看可用版本"
        exit 1
    }

    $selectedJDK = $target.FullName

    # 设置 JAVA_HOME 注册表
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" `
        -Name "JAVA_HOME" -Value $selectedJDK

    # 更新 PATH：移除旧 JDK bin 路径
    $path = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name Path).Path
    $pathParts = $path -split ";"
    $pathParts = $pathParts | Where-Object {$_ -notmatch "\\Environment\\jdk.*\\bin"}
    $newPath = "$($selectedJDK)\bin;" + ($pathParts -join ";")

    # 写回注册表
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" `
        -Name "Path" -Value $newPath

    # 更新 JAR 文件关联
    Update-JarFileAssociation -jdkPath $selectedJDK

    # 立即更新当前 PowerShell 会话环境变量
    $env:JAVA_HOME = $selectedJDK
    $env:Path = $newPath

    Write-Host "已切换到 JDK: $version" -ForegroundColor Green
    Write-Host "JAVA_HOME: $selectedJDK" -ForegroundColor Green
    
    # 验证切换
    Write-Host "`n验证当前Java版本:"
    try {
        & "$selectedJDK\bin\java.exe" -version
    } catch {
        Write-Host "Java版本验证失败" -ForegroundColor Red
    }
    
    Write-Host "`n验证javaw版本:"
    try {
        & "$selectedJDK\bin\javaw.exe" -version
    } catch {
        Write-Host "javaw版本验证失败" -ForegroundColor Red
    }
}

# 参数逻辑
if ($current) {
    Current-JDK
} elseif ($list) {
    List-JDKs
} elseif ($use) {
    Use-JDK $use
} else {
    # 交互模式
    if ($jdkDirs.Count -eq 0) {
        Write-Host "在 $JdkRoot 下未发现任何 JDK，请检查目录。" -ForegroundColor Red
        exit 1
    }

    Write-Host "检测到以下 JDK:"
    for ($i=0; $i -lt $jdkDirs.Count; $i++) {
        Write-Host "[$i] $($jdkDirs[$i].Name)"
    }

    $choice = Read-Host "`n请输入要切换的序号"
    if ($choice -notmatch '^\d+$' -or [int]$choice -ge $jdkDirs.Count) {
        Write-Host "输入无效" -ForegroundColor Red
        exit 1
    }

    Use-JDK $jdkDirs[$choice].Name
}
