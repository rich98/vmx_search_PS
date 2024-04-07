# Check if /debug is passed as an argument
$debug = $false
$sql = $false
if ($args -contains "/debug") {
    $debug = $true
}
if ($args -contains "/sql") {
    $sql = $true
}

# Set console background color to blue if debug mode is enabled
if ($debug) {
    $Host.UI.RawUI.BackgroundColor = "Blue"
    Clear-Host
}

# Function to search for vmrun.exe across all drives
function Find-VMRun {
    $drives = Get-WmiObject -Class Win32_LogicalDisk | Where-Object {$_.DriveType -eq 3} | Select-Object -ExpandProperty DeviceID

    foreach ($drive in $drives) {
        $vmrunPath = Get-ChildItem -Path "$drive\Program Files (x86)\VMware\VMware Workstation\vmrun.exe" -ErrorAction SilentlyContinue
        if ($vmrunPath) {
            return $vmrunPath.FullName
        }
    }

    return $null
}

# Set vmrun path
$vmrunPath = Find-VMRun

if ($vmrunPath -eq $null) {
    Write-Host "vmrun.exe not found on any drives."
    exit 1  # Exit with error code 1 if vmrun.exe is not found
} else {
    Write-Host "vmrun.exe found at: $vmrunPath"

    # Create a function to start a VM
    function Start-VM {
        param([string]$vmxPath)

        # Check if VMX file exists
        if (Test-Path $vmxPath) {
            Write-Host "Starting VM: $vmxPath"
            # Invoke command to start the VM
            & $vmrunPath start "$vmxPath" nogui
        } else {
            Write-Host "VMX file not found: $vmxPath"
        }
    }
}

# Get the host computer name
$hostname = [System.Net.Dns]::GetHostName()

# Get the local drives using WMIC
$drives = Get-WmiObject -Class Win32_LogicalDisk | Where-Object {$_.DriveType -eq 3}

# Define a hashtable for VMware hardware compatibility versions
$vmware_versions = @{
    "21" = "ESXi 8.0 U2 (8.0.2), Fusion 13.5, Workstation Pro 17.5, Workstation Player 17.5"
    "20" = "ESXi 8.0, Fusion 13.x, Workstation Pro 17.x, Workstation Player 17.x"
    "19" = "ESXi 7.0 U2 (7.0.2), Fusion 12.2.x, Workstation Pro 16.2.x, Workstation Player 16.2.x"
    "18" = "ESXi 7.0 U1 (7.0.1), Fusion 12.x, Workstation Pro 16.x, Workstation Player 16.x"
    "17" = "ESXi 7.0 (7.0.0)"
    "16" = "Fusion 11.x, Workstation Pro 15.x, Workstation Player 15.x"
    "15" = "ESXi 6.7 U2"
    "14" = "ESXi 6.7, Fusion 10.x, Workstation Pro 14.x, Workstation Player 14.x"
    "13" = "ESXi 6.5"
    "12" = "Fusion 8.x, Workstation Pro 12.x, Workstation Player 12.x"
    "11" = "ESXi 6.0, Fusion 7.x, Workstation 11.x, Player 7.x"
    "10" = "ESXi 5.5, Fusion 6.x, Workstation 10.x, Player 6.x"
    "9" = "ESXi 5.1, Fusion 5.x, Workstation 9.x, Player 5.x"
    "8" = "ESXi 5.0, Fusion 4.x, Workstation 8.x, Player 4.x"
    "7" = "ESXi/ESX 4.x, Fusion 3.x, Fusion 2.x, Workstation 7.x, Workstation 6.5.x, Player 3.x, Server 2.x"
    "6" = "Workstation 6.0.x"
    "4" = "ESX 3.x, ACE 2.x, Fusion 1.x, Player 2.x"
}

# Create a counter for the total number of VMs found
$total_vms_found = 0

# Logfile path
$logFilePath = "$hostname-VM-Info.log"

# CSV file path for ServiceNow import
$csvFilePath = "$hostname-VM-Info.csv"

# Clear arrays to prevent duplication
$vmxFilePaths = @()
$startedVMs = @()

# Loop through each drive
foreach ($drive in $drives) {
    # Get the drive letter
    $driveLetter = $drive.DeviceID

    # Debug: Print the directory being searched
    Write-Host "Searching in $driveLetter"

    # Search for VMX files in the root of the drive
    $vmx_files = Get-ChildItem -Path "$driveLetter\*.vmx" -Recurse -ErrorAction SilentlyContinue

    # Debug: Print out the contents of $vmx_files
    Write-Host "VMX search dione $($driveLetter):"
    $vmx_files

    # Loop through each VMX file
    foreach ($vmx_file in $vmx_files) {
        # Increment the total VM count
        $total_vms_found++
        
        # Add the VMX file path to the array if not already added
        if ($vmxFilePaths -notcontains $vmx_file.FullName) {
            $vmxFilePaths += $vmx_file.FullName

            # Read the VMX file content
            $content = Get-Content $vmx_file.FullName

            # Initialize a hashtable to store the keys and values
            $vmx_values = @{}

            # Loop through each line in the content
            foreach ($line in $content) {
                # Split the line into key and value
                $splitLine = $line -split ' = ', 2

                # Check if the split operation resulted in two parts
                if ($splitLine.Count -eq 2) {
                    $key, $value = $splitLine

                    # Remove the quotes around the value
                    $value = $value.Trim('"')

                    # Add the key and value to the hashtable
                    $vmx_values[$key] = $value
                } else {
                    Write-Host "Invalid line format in $($vmx_file.FullName): $line"
                }
            }

            # Check if this VM has already been started
            $started = $false
            if ($startedVMs -contains $vmx_file.FullName) {
                $started = $true
            }

            # Get the compatibility version text if the key exists
            if ($vmx_values.ContainsKey("virtualHW.version")) {
                $compatibility_version = $vmware_versions[$vmx_values["virtualHW.version"]]
            } else {
                $compatibility_version = "Compatibility version not found"
            }

            # Print the border, the host computer name, and the values of the specified keys
            "--------------------------------------------------------------------------------"
            "Host machine: $hostname"
            "VMX File: $($vmx_file.FullName)"
            "Display Name: $($vmx_values["displayName"])"
            "OS Type: $($vmx_values["guestOS"])"
            "Memory: $($vmx_values["memsize"])"
            "Ethernet Present: $($vmx_values["ethernet0.present"])"
            "Guest MAC: $($vmx_values["ethernet0.generatedAddress"])"
            "Ethernet Connection Type: $($vmx_values["ethernet0.connectionType"])"
            "Second Ethernet Adapter Present?: $(if ($vmx_values.ContainsKey("ethernet1.present")) { $($vmx_values["ethernet1.present"]) } else { "No Second adapter found" })"

            # Check if a second Ethernet adapter is present
            if ($vmx_values.ContainsKey("ethernet1.present") -and $vmx_values["ethernet1.present"] -eq "true") {
                # Display details of the second Ethernet adapter
                "Second Adapter Guest MAC: $($vmx_values["ethernet1.generatedAddress"])"
                "Second Adapter Ethernet Connection Type: $($vmx_values["ethernet1.connectionType"])"
            }

            "USB Present: $($vmx_values["usb.present"])"
            "Firmware: $($vmx_values["firmware"])"
            "Extended Config File: $($vmx_values["extendedConfigFile"])"
            "Hardware Compatibility: $($vmx_values["virtualHW.version"]) = ($compatibility_version)"
            "Started: $($started.ToString())"  # Display if the VM has been started
            "--------------------------------------------------------------------------------"

            # Log the information to the file if debug mode is enabled
            if ($debug) {
                $output = @"
--------------------------------------------------------------------------------
Host machine: $hostname
VMX File: $($vmx_file.FullName)
Display Name: $($vmx_values["displayName"])"
OS Type: $($vmx_values["guestOS"])"
Memory: $($vmx_values["memsize"])"
Ethernet Present: $($vmx_values["ethernet0.present"])"
Guest MAC: $($vmx_values["ethernet0.generatedAddress"])"
Ethernet Connection Type: $($vmx_values["ethernet0.connectionType"])"
Second Ethernet Adapter Present?: $(if ($vmx_values.ContainsKey("ethernet1.present")) { $($vmx_values["ethernet1.present"]) } else { "No Second adapter found" })"

            # Check if a second Ethernet adapter is present
            if ($vmx_values.ContainsKey("ethernet1.present") -and $vmx_values["ethernet1.present"] -eq "true") {
                # Display details of the second Ethernet adapter
                $output += @"
Second Adapter Guest MAC: $($vmx_values["ethernet1.generatedAddress"])"
                "Second Adapter Ethernet Connection Type: $($vmx_values["ethernet1.connectionType"])"
            }

            $output += @"
USB Present: $($vmx_values["usb.present"])"
            "Firmware: $($vmx_values["firmware"])"
            "Extended Config File: $($vmx_values["extendedConfigFile"])"
            "Hardware Compatibility: $($vmx_values["virtualHW.version"]) = ($compatibility_version)"
            "Started: $($started.ToString())"  # Display if the VM has been started
            "--------------------------------------------------------------------------------

"@
                Add-Content -Path $logFilePath -Value $output

                # Log the entire content of the VMX file
                Add-Content -Path $logFilePath -Value "VMX File Content:"
                Add-Content -Path $logFilePath -Value (Get-Content $vmx_file.FullName)
                Add-Content -Path $logFilePath -Value "--------------------------------------------------------------------------------`n"
            }
            
            # Clear the $output variable to free up memory
            $output = $null
        }
    }
}

# Output the total number of VMs found
"Total VMs Found: $total_vms_found"

# Generate CSV file for ServiceNow import if /sql argument is passed
if ($sql) {
    $csvContent = @()
    foreach ($vmx in $vmxFilePaths) {
        $vmxContent = Get-Content $vmx -Raw
        $vmxValues = ConvertFrom-StringData $vmxContent
        $csvContent += [PSCustomObject]@{
            "Host machine" = $hostname
            "VMX File" = $vmx
            "Display Name" = $vmxValues.displayName
            "OS Type" = $vmxValues.guestOS
            "Memory" = $vmxValues.memsize
            "Ethernet Present" = $vmxValues.'ethernet0.present'
            "Guest MAC" = $vmxValues.'ethernet0.generatedAddress'
            "Ethernet Connection Type" = $vmxValues.'ethernet0.connectionType'
            "Second Ethernet Adapter Present?" = if ($vmxValues.'ethernet1.present') { $vmxValues.'ethernet1.present' } else { "No Second adapter found" }
            "Second Adapter Guest MAC" = if ($vmxValues.'ethernet1.present') { $vmxValues.'ethernet1.generatedAddress' } else { $null }
            "Second Adapter Ethernet Connection Type" = if ($vmxValues.'ethernet1.present') { $vmxValues.'ethernet1.connectionType' } else { $null }
            "USB Present" = $vmxValues.'usb.present'
            "Firmware" = $vmxValues.firmware
            "Extended Config File" = $vmxValues.extendedConfigFile
            "Hardware Compatibility" = "$($vmxValues.'virtualHW.version') = $($vmware_versions[$vmxValues.'virtualHW.version'])"
            "Started" = if ($startedVMs -contains $vmx) { $true } else { $false }
        }
    }
    $csvContent | Export-Csv -Path $csvFilePath -NoTypeInformation
    Write-Host "CSV file generated for ServiceNow import: $csvFilePath"
}

# Display a menu to start VMs
do {
    if ($vmxFilePaths.Count -gt 0) {
        Write-Host "Select a VM to start:"
        for ($i = 0; $i -lt $vmxFilePaths.Count; $i++) {
            $startedText = ""
            $vmxFileName = (Get-Item $vmxFilePaths[$i]).BaseName
            if ($startedVMs -contains $vmxFilePaths[$i]) {
                $startedText = "[Started]"
            }
            Write-Host "$($i + 1). $vmxFileName $startedText"
        }

        $choice = Read-Host "Enter the number of the VM to start (or 'q' to quit):"
        if ($choice -ne 'q') {
            $index = [int]$choice - 1
            if ($index -ge 0 -and $index -lt $vmxFilePaths.Count) {
                # Check if the VM has already been started
                if ($startedVMs -notcontains $vmxFilePaths[$index]) {
                    Start-VM -vmxPath $vmxFilePaths[$index]
                    # Add the started VM to the list
                    $startedVMs += $vmxFilePaths[$index]
                } else {
                    Write-Host "VM has already been started."
                }

                # Ask if the user wants to start another VM
                $startAnother = Read-Host "Would you like to start another VM? (y/n)"
                if ($startAnother -eq 'n') {
                    break  # Exit the loop if the user chooses not to start another VM
                } elseif ($startAnother -eq 'y') {
                    Clear-Host  # Clear the screen if the user chooses to start another VM
                }
            } else {
                Write-Host "Invalid selection."
            }
        } else {
            break  # Exit the loop if the user chooses to quit
        }
    } else {
        Write-Host "No VMs found to start."
        break  # Exit the loop if
    }
} while ($true)

# Set console background color to blue if debug mode is enabled
if ($debug) {
    $Host.UI.RawUI.BackgroundColor = "Black"
    Clear-Host
}
