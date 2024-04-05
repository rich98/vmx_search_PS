# Check if /debug is passed as an argument
$debug = $false
if ($args -contains "/debug") {
    $debug = $true
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

# Loop through each drive
foreach ($drive in $drives) {
    # Get the drive letter
    $driveLetter = $drive.DeviceID

    # Search for VMX files in the drive
    $vmx_files = Get-ChildItem -Path $driveLetter -Filter "*.vmx" -Recurse -ErrorAction SilentlyContinue

    # Loop through each VMX file
    foreach ($vmx_file in $vmx_files) {
        # Increment the total VM count
        $total_vms_found++

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
        "--------------------------------------------------------------------------------"

        # Debug option: Print the entire VMX values hashtable if /debug is passed
        if ($debug) {
            "VMX Values: "
            $vmx_values
            "--------------------------------------------------------------------------------"

            # Create a debug file named with the hostname
            $debugFile = "$hostname-debug.txt"

            # Write the VMX values to the debug file
            $vmx_values | Out-File $debugFile -Append
        }
    }  # This is where the missing closing curly brace for the inner foreach loop should be
}  # This is where the missing closing curly brace for the outer foreach loop should be

# Output the total number of VMs found
"Total VMs Found: $total_vms_found"

# Pause to keep the PowerShell console window open
Read-Host "Press Enter to exit..."
