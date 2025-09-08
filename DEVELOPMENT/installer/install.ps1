$_prefix = "PYS:"

# check for env variable PYTHON_VERSION_PS
# if it isn't set set it to 3.11
if (-not $env:PYTHON_VERSION_PS) {
    $env:PYTHON_VERSION_PS = "3.11"
}

Write-Output "$_prefix Python installation"


# Function to refresh environment variables in the current session
function Refresh-Env {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
}

# Function to handle errors and exit
function Exit-Message {
    Write-Output "Oh no! Something went wrong."
    Write-Output "Please visit the following web page for more info:"
    Write-Output ""
    Write-Output "   https://pythonsupport.dtu.dk/install/windows/automated-error.html "
    Write-Output ""
    Write-Output "or contact the Python Support Team:"
    Write-Output ""
    Write-Output "   pythonsupport@dtu.dk"
    Write-Output ""
    Write-Output "Or visit us during our office hours"
    Read-Host 'Press Enter to exit'
    exit 1
}

# Check and set execution policy if necessary
$executionPolicies = Get-ExecutionPolicy -List
$currentUserPolicy = $executionPolicies | Where-Object { $_.Scope -eq "CurrentUser" } | Select-Object -ExpandProperty ExecutionPolicy
$localMachinePolicy = $executionPolicies | Where-Object { $_.Scope -eq "LocalMachine" } | Select-Object -ExpandProperty ExecutionPolicy

if ($currentUserPolicy -ne "RemoteSigned" -and $currentUserPolicy -ne "Bypass" -and $currentUserPolicy -ne "Unrestricted" -and
    $localMachinePolicy -ne "RemoteSigned" -and $localMachinePolicy -ne "Unrestricted" -and $localMachinePolicy -ne "Bypass") {
    Set-ExecutionPolicy -WarningAction:SilentlyContinue RemoteSigned -Scope CurrentUser -Force
}

# Check if Miniconda or Anaconda is already installed
$minicondaPath1 = "$env:USERPROFILE\Miniconda3"
$minicondaPath2 = "C:\ProgramData\Miniconda3"
$anacondaPath1 = "$env:USERPROFILE\Anaconda3"
$anacondaPath2 = "C:\ProgramData\Anaconda3"

if ((Test-Path $minicondaPath1) -or (Test-Path $minicondaPath2) -or (Test-Path $anacondaPath1) -or (Test-Path $anacondaPath2)) {
    Write-Output "Miniconda or Anaconda is already installed. Skipping Miniconda installation."
    Write-Output "If you wish to install Miniconda using this script, please uninstall the existing Anaconda/Miniconda installation and run the script again."
} else {
    # Script by Python Installation Support DTU
    Write-Output "This script will install Python along with Visual Studio Code - and everything you need to get started with programming"
    Write-Output "This script will take a while to run, please be patient, and don't close PowerShell before it says 'script finished'."
    Start-Sleep -Seconds 3

    # Download the Miniconda installer
    $minicondaUrl = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
    $minicondaInstallerPath = "$env:USERPROFILE\Downloads\Miniconda3-latest-Windows-x86_64.exe"

    Write-Output "$_prefix Downloading installer for Miniconda..."
    Invoke-WebRequest -Uri $minicondaUrl -OutFile $minicondaInstallerPath
    if (-not $?) {
        Exit-Message
    }

    Write-Output "$_prefix Installing Miniconda..."
    # Install Miniconda
    Start-Process -FilePath $minicondaInstallerPath -ArgumentList "/InstallationType=JustMe /RegisterPython=1 /S /D=$env:USERPROFILE\Miniconda3" -Wait
    if (-not $?) {
        Exit-Message
    }

    # Add miniconda to PATH and refresh environment variables
    function Add-CondaToPath {
        if (Test-Path "$env:USERPROFILE\Miniconda3\condabin") {
            $condaPath = "$env:USERPROFILE\Miniconda3\condabin"
        } elseif (Test-Path "C:\ProgramData\Miniconda3\condabin") {
            $condaPath = "C:\ProgramData\Miniconda3\condabin"
        } else {
            Write-Output "$_prefix Miniconda is not installed."
            Exit-Message
        }

        if (-not ($env:Path -contains $condaPath)) {
            [System.Environment]::SetEnvironmentVariable("Path", $env:Path + ";$condaPath", [System.EnvironmentVariableTarget]::User)
        }
    }


    Write-Output "$_prefix Environment variables refreshed."
    Add-CondaToPath
    Refresh-Env
    if (-not $?) {
        Exit-Message
    }

    # Check conda-paths
    $conda_paths = Get-Command -ErrorAction:SilentlyContinue conda
    if ($?) {
        Write-Output "$conda_paths"

        # Forcefully running the conda.bat file
        & "$env:USERPROFILE\Miniconda3\condabin\conda.bat" activate
    } else {
        conda activate
    }
    if (-not $?) {
        Write-Output "$_prefix Conda base environment failed to activate."
        Exit-Message
    }

    # Anaconda has this package which tracks usage metrics
    # We will disable this, and if it fails, so be it.
    # I.e. we shouldn't check whether it actually succeeds
    conda config --set anaconda_anon_usage off

    # Initialize conda
    Write-Output "$_prefix Initialising conda..."
    conda init
    if (-not $?) {
        Exit-Message
    }

    Write-Output "$_prefix Showing where it is installed:"
    conda info --base
    if (-not $?) {
        Exit-Message
    }


    # Later, we should check if this is even necessary?
    # I can see a few problems:
    # 1. If the user has a previous Conda installation then this will
    #    explicitly install things in the newly installed version.
    # 2. If the above happens there may be some inconsistency between
    #    commands.
    $condaBatPath = "$env:USERPROFILE\Miniconda3\condabin\conda.bat"


    # Ensuring correct channels are set
    Write-Output "$_prefix Removing defaults channel (due to licensing problems)"
    & $condaBatPath config --add channels conda-forge
    if (-not $?) {
        Exit-Message
    }

    # Attempts to remove defaults channel (due to licensing problems
    & $condaBatPath config --remove channels defaults
    if (-not $?) {
       Write-Output "$_prefix Failed to remove defaults channel"
    }

    # Sadly, there can be a deadlock here
    # When channel_priority == strict
    # newer versions of conda will sometimes be unable to downgrade.
    # However, when channel_priority == flexible
    # it will sometimes not revert the libmamba suite which breaks
    # the following conda install commands.
    # Hmmm.... :(
    & $condaBatPath config --set channel_priority flexible
    if (-not $?) {
        Exit-Message
    }

    # Ensures correct version of python
    if (-not $env:PYTHON_INSTALL_COMMAND_EXECUTED) {
        & $condaBatPath install --strict-channel-priority python=$env:PYTHON_VERSION_PS -y
        $retval = $?
        # If it fails, try to use the flexible way, but manually downgrade libmamba to conda-forge
        if ( -not $retval ) {
            Write-Output "$_prefix Trying manual downgrading..."
            & $condaBatPath install python=$env:PYTHON_VERSION_PS conda-forge::libmamba conda-forge::libmambapy -y
            $retval = $?
        }
    } else {
        Write-Output "$_prefix Python installation command has already been executed, skipping..."
        $retval = 0
    }
    if (-not $retval) {
        Exit-Message
    }
    # It has been runned, inform the environment
    $env:PYTHON_INSTALL_COMMAND_EXECUTED = "true"


    # Install packages
    Write-Output "$_prefix Installing packages..."
    & $condaBatPath install dtumathtools pandas scipy statsmodels uncertainties -y
    if (-not $?) {
        Exit-Message
    }
}

Write-Output "$_prefix Installed conda and related packages for 1st year at DTU!"
Read-Host 'Press Enter to exit'
exit 0
