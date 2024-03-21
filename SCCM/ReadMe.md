# FFU Management PowerShell Script

## Overview

This PowerShell script automates the management of FFU (Full Flash Update) files for Windows 10 and Windows 11. It creates new FFU files, copies them to a specified share, renames old FFU files if they exist, and updates SCCM (System Center Configuration Manager) packages with the new FFU files.

## Prerequisites

- Windows 10 and Windows 11 development environment.
- PowerShell with administrative privileges.
- SCCM environment with appropriate permissions for package updates.

## Configuration

1. Set the following variables at the beginning of the script:
   - `$Win10_Folder`: Path to the folder where Windows 10 FFU files will be managed.
   - `$Win11_Folder`: Path to the folder where Windows 11 FFU files will be managed.
   - `$SiteCode`: SCCM site code.
   - `$ProviderMachineName`: SMS Provider machine name.
   - `$initParams`: Optional parameters for script initialization (e.g., verbose logging).

2. Optionally uncomment lines in the script to enable verbose logging or stop the script on errors.

## Usage

1. Run the script in PowerShell with administrative privileges.

2. The script will:
   - Create Windows 11 and Windows 10 FFU files using `BuildFFUVM.ps1`.
   - Copy the latest FFU files to the specified folders and rename old FFU files if present.
   - Connect to SCCM and update packages containing FFU files on distribution points.

## Additional Notes

- Ensure that the `BuildFFUVM.ps1` script is accessible and properly configured for creating FFU files.
- Verify permissions and network connectivity for copying files to shares and updating SCCM packages.