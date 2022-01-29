#!/usr/bin/pwsh
Write-Output "Building..."

# adapted from https://github.com/Jan0660/JanD/commit/cf70500b361b17d13d5ffa4471b2ad6b39ecf5bc#diff-79f18082ea4797a811114b32ec44decc7eebf857ddd36f8b39a355cbefb0e88a
function Build()
{
    param(
        [bool] $NativeAOT,
        [string] $Runtime = $null,
        [bool] $SelfContained,
        [bool] $ReadyToRun = $false
    )
    $name = ""
    #    $name = "Benchmark"
    $cmd = "dotnet publish -c release"
    if ($Runtime -ne $null)
    {
        $cmd += " -r $Runtime"
        $name += "$Runtime"
    }
    else
    {
        throw "cannot build without a runtime"
    }
    if ($NativeAOT)
    {
        $name += "-nativeaot"
    }
    if ($NativeAOT -eq $false)
    {
        $cmd += " -p:NoNativeAOTPublish=no"
    }
    if ($NativeAOT -eq $false -and $SelfContained -eq $true)
    {
        $cmd += " -p:PublishSingleFile=true --self-contained";
        $name += "-contained"
    }
    if ($NativeAOT -eq $false -and $SelfContained -eq $false)
    {
        $cmd += " -p:PublishSingleFile=true --no-self-contained -p:PublishTrimmed=false";
        $name += "-fxdependent"
    }
    if ($ReadyToRun)
    {
        $cmd += " -p:PublishReadyToRun=true"
        $name += "-r2r"
    }
    $cmd += " -o bin/bench/$name"
    Write-Output "$( $name ): $cmd"
    Invoke-Expression $cmd
}
function BuildsFor()
{
    param(
        [string]$Runtime
    )
    Build -NativeAot $false -Runtime $Runtime -SelfContained $false
    Build -NativeAot $false -Runtime $Runtime -SelfContained $true
    Build -NativeAot $false -Runtime $Runtime -SelfContained $false -ReadyToRun $true
    Build -NativeAot $false -Runtime $Runtime -SelfContained $true -ReadyToRun $true
    Build -NativeAot $true -Runtime $Runtime -SelfContained $true
}

Remove-Item -Force -Recurse -Path bin/bench

if ($IsWindows)
{
    BuildsFor -Runtime "win-x64"
}
if ($IsLinux)
{
    BuildsFor -Runtime "linux-x64"
}

Write-Output "Cleaning up build results..."
Remove-Item -Force -Recurse -Path bin/bench/*/*.json
Remove-Item -Force -Recurse -Path bin/bench/*/*.pdb

#Write-Output "Build sizes:"
$buildSizes = @{ }
foreach ($dir in (Get-ChildItem ./bin/bench))
{
    $key = 0
    foreach ($file in (Get-ChildItem $dir))
    {
        $key += [IO.FileInfo]::new($file).Length
        # todo: ...
        Move-Item $dir "$( $dir )h"
        Move-Item $file.FullName.Replace($dir.Name, $dir.Name + "h") "./bin/bench/$( $dir.Name )$( if ($IsWindows)
        {
            ".exe"
        } )" -Force
    }
    $buildSizes.Add($dir.Name, $key)
    if ($IsLinux -and $dir.Name.Contains("nativeaot"))
    {
        strip $dir.FullName
        $key = [IO.FileInfo]::new($dir.FullName).Length
        $buildSizes.Add($dir.Name + " stripped", $key)
    }
}

Write-Output "Run Time Benchmarks:"
$files = ""
foreach ($file in (Get-ChildItem ./bin/bench -File))
{
    $files += "$( if ($IsLinux)
    {
        "./"
    } )$( $file.Name ) "
}
cd ./bin/bench
$exp = "hyperfine --export-markdown ./report.md --warmup 8 --min-runs 10 $files"
Write-Output "$( $exp )"
Invoke-Expression $exp
cd ../..

write-output "Markdown:"

Write-Output "#### Run Time"
cat ./bin/bench/report.md
Write-Output "#### Build Sizes"
Write-Output "| Name | Size | Ratio |"
Write-Output "|:--- | ---:| ---:|"
foreach ($key in $buildSizes.Keys)
{
    Write-Output "| ``$key`` | $( $buildSizes[$key] / 1000 )KB | $([math]::Round($( $buildSizes[$key] / $($buildSizes.Values)[0] ), 4)) |"
}
