﻿function TryCreate-Directory ([Parameter(Mandatory = $True)] [string]$dirName)
{
  $private:dir = Join-Path $baseDir $dirName
  if (-not (Test-Path $dir))
  {
    Write-Output "$dir 不存在，正在创建。"
    mkdir $dir | Out-Null
  }
}

function TryCreate-Directories ()
{
  $dirNames |
  % {
    TryCreate-Directory $_
  }
}

function Remove-Directories ()
{
  $dirNames |
  % {
    $private:dir = Join-Path $baseDir $_
    if (Test-Path $dir)
    {
      Write-Warning "正在移除$dir"
      rm $dir -Recurse
    }
  }
}

function MoveTo-WithRenamming (
  [Parameter(Mandatory = $True)] [System.IO.FileSystemInfo]$item,
  [Parameter(Mandatory = $True)] [string]$targetDir)
{
  function Get-NextFilePath ([string]$dir,[System.IO.FileInfo]$fileInfo)
  {
    $Private:targetFilePath = Join-Path $dir $fileInfo.Name
    if (Test-Path $Private:targetFilePath)
    {
      $Private:index = 1
      do {
        $Private:targetFilePath = Join-Path $dir "$($fileInfo.BaseName) ($index)$($fileInfo.Extension)"
        $Private:index++
      }
      while (Test-Path $Private:targetFilePath)
    }
    return [System.IO.FileInfo]$Private:targetFilePath
  }

  function Get-NextDirectoryPath ([string]$dir,[System.IO.DirectoryInfo]$directoryInfo)
  {
    $Private:targetDirectoryPath = Join-Path $dir $directoryInfo.Name
    if (Test-Path $Private:targetDirectoryPath)
    {
      $Private:index = 1
      do {
        $Private:targetDirectoryPath = Join-Path $dir "$($directoryInfo.Name) ($index)"
        $Private:index++
      }
      while (Test-Path $Private:targetDirectoryPath)
    }
    return [System.IO.DirectoryInfo]$Private:targetDirectoryPath
  }

  Write-Output "正在移动 $item 至 $targetDir 目录"
  if ($item -is [System.IO.FileInfo])
  {
    $Private:targetFilePath = Join-Path $targetDir $item.Name
    if (Test-Path $Private:targetFilePath)
    {
      $Private:targetFilePath = Get-NextFilePath $targetDir $item
      Write-Warning "目标文件已存在，自动改名为$($Private:targetFilePath.Name)"
    }
    Move-Item $item.FullName $Private:targetFilePath | Out-Null
  } elseif ($item -is [System.IO.DirectoryInfo])
  {
    $Private:targetDirectoryPath = Join-Path $targetDir $item.Name
    if (Test-Path $Private:targetDirectoryPath)
    {
      $Private:targetDirectoryPath = Get-NextDirectoryPath $targetDir $item
      Write-Warning "目标文件夹已存在，自动改名为$($Private:targetDirectoryPath.Name)"
    }
    Move-Item $item.FullName $Private:targetDirectoryPath | Out-Null
  }
}

function Process-TomorrowDir
{

  Write-Output "正在将 [TOMORROW] 目录中的内容移至 [TODAY] 目录"
  Get-ChildItem $tomorrowDir |
  % {
    MoveTo-WithRenamming $_ $todayDir
  }
}

function Process-IsolatedItems
{
  Write-Output "正在将游离内容移至 [STUFF] 目录"
  Get-ChildItem $baseDir -Exclude ($dirNames + $reservedFiles) |
  % {
    MoveTo-WithRenamming $_ $stuffDir
  }
}

function Process-ArchiveDir
{
  Write-Output "正在检查 [ARCHIVE] 目录"
  # 移动所有文件到 [STUFF] 目录
  Get-ChildItem $archiveDir -File |
  % {
    MoveTo-WithRenamming $_ $stuffDir
  }

  # 检查目录命名是否符合规范。
  Get-ChildItem $archiveDir -Directory |
  % {
    $regex = [regex]'(?m)^(?<year>19|20\d{2})[-_.](?<month>\d{1,2})$'
    $match = $regex.Match($_.Name)
    if ($match.Success)
    {
      $year = $regex.Match($_.Name).Groups['year'].Value;
      $month = $regex.Match($_.Name).Groups['month'].Value;
      $date = New-Object System.DateTime $year,$month,1
      if ($date -gt (Get-Date))
      {
        Write-Output "[ARCHIVE] 目录下，$($_.Name) 名字不符合规范（存档日期超出当前时间），将移动至 [STUFF] 目录"
        MoveTo-WithRenamming $_ $stuffDir
      }
      else
      {
        $formattedDate = "{0:yyyy.MM}" -f $date
        if ($_.Name -ne $formattedDate)
        {
          $targetDirectory = [System.IO.DirectoryInfo](Join-Path $_.Parent.FullName $formattedDate)
          Write-Warning "将 [ARCHIVE] 下的目录名 $($_.Name) 处理为规范格式 $($targetDirectory.Name)"
          Move-Item $_.FullName $targetDirectory.FullName
        }
      }
    } else
    {
      Write-Output "[ARCHIVE] 目录下，$($_.Name) 名字不符合规范，将移动至 [STUFF] 目录"
      MoveTo-WithRenamming $_ $stuffDir
    }
  }

  # 创建本月目录
  $nowString = "{0:yyyy.MM}" -f (Get-Date)
  $thisMonthDir = Join-Path $archiveDir $nowString
  if (-not (Test-Path $thisMonthDir))
  {
    md $thisMonthDir
  }

  # 移除除本月之外的空目录
  Get-ChildItem $archiveDir -Exclude $nowString -Recurse | 
  Where { $_.PSIsContainer -and @( Get-ChildItem -LiteralPath $_.FullName -Recurse | Where { !$_.PSIsContainer }).Length -eq 0 } |
  % {
    Write-Output "正在删除空目录$($_.FullName)"
    Remove-Item -Recurse
  }
}


$STUFF = "0.STUFF"
$TODAY = "1.TODAY"
$TOMORROW = "2.TOMORROW"
$UPCOMING = "3.UPCOMING"
$SOMEDAY = "4.SOMEDAY"
$ARCHIVE = "5.ARCHIVE"

$stuffDir = Join-Path $baseDir $STUFF
$todayDir = Join-Path $baseDir $TODAY
$tomorrowDir = Join-Path $baseDir $TOMORROW
$archiveDir = Join-Path $baseDir $ARCHIVE

$dirNames = $STUFF,$TODAY,$TOMORROW,$UPCOMING,$SOMEDAY,$ARCHIVE
$reservedFiles = "Get-ThingsDone.ps1","readme.txt","gtd.cmd"

$baseDir = Split-Path $MyInvocation.MyCommand.Path



Write-Output "正在检查目录完整性"
TryCreate-Directories

$null | Set-Content (Join-Path $baseDir "test.txt")
md (Join-Path $baseDir "dir.test") | Out-Null

Process-IsolatedItems
Process-TomorrowDir
Process-ArchiveDir

######################### 开发临时用（在 ISE 中选中并按 F8 执行） #########################
{
  return
  # 对代码排版。
  Import-Module D:\Dropbox\script\DTW.PS.PrettyPrinterV1\DTW.PS.PrettyPrinterV1.psd1
  Edit-DTWCleanScript D:\GTD\Get-ThingsDone.ps1
}

{
  return
  # 移除所有目录
  Remove-Directories
}