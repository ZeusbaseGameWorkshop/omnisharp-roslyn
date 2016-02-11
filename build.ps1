# Build OmniSharp

$build_tools=".build"
$nuget_path="$build_tools\nuget.exe"
$configuration="Debug" # temporarily setting
$dotnet=".\.dotnet\cli\bin\dotnet.exe"

$artifacts="artifacts"
$publish_output="$artifacts\publish"
$log_output="$artifacts\logs"
$test_output="$artifacts\tests"

function _header($title) {
  Write-Host *** $title ***
}

function _build($project) {
  & $dotnet build src\$project

  if ($LASTEXITCODE -ne 0) {
     Write-Error "Failed to build $project"
     exit 1
  }
}

function _test($project) {
  _test_coreclr $project
  _test_clr $project
}

function _test_coreclr($project) {
  $target="$test_output\$project\coreclr"
  $log="$log_output\$project-core-result.xml"

  Write-Host ""
  Write-Host "$project / CoreCLR"

  & $dotnet publish ./tests/$project --output $target --framework dnxcore50 |
      Out-File "$log_output\$project-core-build.log"

  if ($LASTEXITCODE -ne 0) {
      Write-Error "Failed to build $project under CoreCLR."
      exit 1
  }

  & $target/corerun $target/xunit.console.netcore.exe $target/$project.dll `
     -xml $log -parallel none  -notrait category=failing

  if ($LASTEXITCODE -ne 0) {
      Write-Error "Test failed [Log $log]"
      exit 1
  }
}

function _test_clr($project) {
  $target="$test_output\$project\clr"
  $log="$log_output\$project-clr-result.xml"

  Write-Host ""
  Write-Host "$project / CLR"

  & $dotnet publish ./tests/$project --output $target --framework dnx451 --configuration $configuration |
      Out-File "$log_output\$project-clr-build.log"

  if ($LASTEXITCODE -ne 0) {
      Write-Error "Failed to build $project under CLR."
      exit 1
  }

  cp $build_tools/xunit.runner.console/tools/* $target/

  & $target/xunit.console.x86.exe $target/$project.dll `
     -xml $log -parallel none  -notrait category=failing

  if ($LASTEXITCODE -ne 0) {
      Write-Error "Test failed [Log $log]"
      exit 1
  }
}

function _publish($project) {
  $name = "$project"
  $src = "src\$project"
  $output = "$publish_output\$project"

  & $dotnet publish $src --output $output --configuration $configuration
  ls $src\config.json | % { cp $src\config.json $output\config.json | Out-Null }
}

_header "Cleanup"
rm -r -force artifacts -ErrorAction SilentlyContinue

_header "Pre-requisite"

$env:DOTNET_INSTALL_DIR=$PWD.Path+"\.dotnet"
Start-Process "powershell.exe" -NoNewWindow -Wait -ArgumentList "iex ((new-object net.webclient).DownloadString('https://raw.githubusercontent.com/dotnet/cli/master/scripts/obtain/install.ps1'))"

mkdir $build_tools -ErrorAction SilentlyContinue | Out-Null

# Ensure NuGet is downloaded to .build folder
if (-not (Test-Path $nuget_path)) {
    $nuget_version="latest"
    $cached_nuget="$env:LocalAppData\NuGet\nuget.$nuget_version.exe"
    if (-not (Test-Path $cached_nuget)) {
        if (-not (Test-Path $env:LocalAppData\NuGet)) {
            mkdir $env:LocalAppData\NuGet
        }
        Invoke-WebRequest "https://dist.nuget.org/win-x86-commandline/$nuget_version/nuget.exe" -OutFile $cached_nuget
    }

    cp $cached_nuget $nuget_path | Out-Null
}

mkdir $log_output -ErrorAction SilentlyContinue | Out-Null

if (-not (Test-Path $build_tools/xunit.runner.console)) {
  & $nuget_path install xunit.runner.console -ExcludeVersion -o $build_tools -nocache -pre
}

_header "Restoring"
& $dotnet restore
if ($LASTEXITCODE -ne 0) {
    Write-Error "Fail to restore."
    exit 1
}

_header "Building"
_build "OmniSharp.Abstractions"
_build "OmniSharp.Stdio"
_build "OmniSharp.Roslyn"
_build "OmniSharp.Roslyn.CSharp"
_build "OmniSharp.Dnx"
_build "OmniSharp.Plugins"
_build "OmniSharp.Bootstrap"
_build "OmniSharp.Host"
_build "OmniSharp"

_header "Testing"
_test OmniSharp.Bootstrap.Tests
# TODO: Migrate to use _test once clr xunit behaves
# Failure repo: https://github.com/troydai/loaderfailure
_test_coreclr OmniSharp.Dnx.Tests
_test_clr OmniSharp.MSBuild.Tests
# TODO: Migrate to use _test once clr xunit behaves
# Failure repo: https://github.com/troydai/loaderfailure
_test_coreclr OmniSharp.Roslyn.CSharp.Tests
_test_clr OmniSharp.ScriptCs.Tests
_test OmniSharp.Stdio.Tests

_header "Publishing"
mkdir -p $publish_output -ErrorAction SilentlyContinue | Out-Null
_publish "OmniSharp"

#_header "Packaging"
