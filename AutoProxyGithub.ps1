# =================================================================================================
# AutoProxy - A PowerShell script to configure Windows proxy settings based on the network.
# DEFAULT BEHAVIOR: Proxy is DISABLED unless a matching profile is found.
#
# This script should handle most network names, insert your own Network name (the network you want to connect to) in the name and identifier area inbetween the brackets. for proxyserver in the put the ip address and port you need in in the form of ip:port
# =================================================================================================

# --- 1. USER CONFIGURATION (Networks where Proxy is ENABLED) ---
# This section is configured for your specific network.

$NetworkProfiles = @(
    @{
        Name          = "Name of Network"
        Type          = "SSID"
        Identifier    = "Also name of network/ssid"
        ProxyEnabled  = $true
        ProxyServer   = "IP address:port"
        AutoConfigURL = ""
        # Using "<local>" is recommended to prevent the proxy from interfering with local network devices.
        BypassList    = "<local>"
    }
)

# --- 2. DEFAULT CONFIGURATION (Applied when NO match is found) ---
# This profile ensures the proxy is DISABLED for all other networks.
$DefaultProfile = @{
    Name          = "Default (Proxy Disabled)"
    ProxyEnabled  = $false
    ProxyServer   = ""
    AutoConfigURL = ""
    BypassList    = ""
}


# --- 3. SCRIPT LOGIC (Functions) ---

function Get-CurrentNetworkIdentifier {
    # This function attempts to find the most reliable identifier for the current network.
    $activeAdapter = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' } | Sort-Object -Property InterfaceMetric | Select-Object -First 1
    if ($activeAdapter) {
        # Check for WiFi/Wireless
        if ($activeAdapter.InterfaceDescription -like "*Wireless*" -or $activeAdapter.InterfaceDescription -like "*Wi-Fi*") {
            try {
                $ssidOutput = (get-NetConnectionProfile -InterfaceIndex $ActiveAdapter.InterfaceIndex).Name
                if ($ssidOutput) {
                    $ssid = ([regex]::match($ssidOutput, '^[\w-_]+')).Value
                    return @{ Type = "SSID"; Identifier = $ssid }
                }
            }
            catch { Write-Warning "Could not determine WiFi SSID." }
        }
        # Assume Wired/Other (use Network Profile Name which is often the DNS Suffix)
        else {
            try {
                $ipconfig = Get-NetIPConfiguration -InterfaceIndex $activeAdapter.ifIndex
                # Use the Network Profile Name as the DNS Suffix identifier
                if ($ipconfig.NetProfile.Name) {
                    return @{ Type = "DNSSuffix"; Identifier = $ipconfig.NetProfile.Name }
                }
            }
            catch { Write-Warning "Could not determine DNS Suffix/Network Profile Name." }
        }
    }
    return $null
}

function Set-ProxySettings {
    param (
        [Parameter(Mandatory=$true)]
        [psobject]$Profile
    )

    $regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

    if ($Profile.ProxyEnabled) {
        Write-Host "Proxy ENABLED for network: $($Profile.Name)"
        Set-ItemProperty -Path $regKey -Name ProxyEnable -Value 1

        if ($Profile.AutoConfigURL) {
            Write-Host "  Setting AutoConfigURL: $($Profile.AutoConfigURL)"
            Set-ItemProperty -Path $regKey -Name AutoConfigURL -Value $Profile.AutoConfigURL
            Set-ItemProperty -Path $regKey -Name ProxyServer -Value "" # Clear static proxy
        }
        else {
            Write-Host "  Setting ProxyServer: $($Profile.ProxyServer)"
            Set-ItemProperty -Path $regKey -Name ProxyServer -Value $Profile.ProxyServer
            if ($Profile.BypassList) {
                Write-Host "  Setting ProxyOverride: $($Profile.BypassList)"
                Set-ItemProperty -Path $regKey -Name ProxyOverride -Value $Profile.BypassList
            }
            Set-ItemProperty -Path $regKey -Name AutoConfigURL -Value "" # Clear auto-config URL
        }
    }
    else {
        Write-Host "Proxy DISABLED for network: $($Profile.Name)"
        # This is the key action: setting ProxyEnable to 0
        Set-ItemProperty -Path $regKey -Name ProxyEnable -Value 0
        Set-ItemProperty -Path $regKey -Name ProxyServer -Value ""
        Set-ItemProperty -Path $regKey -Name AutoConfigURL -Value ""
    }
}

# --- 4. MAIN EXECUTION ---

$currentNetwork = Get-CurrentNetworkIdentifier

if ($currentNetwork) {
    Write-Host "Current network detected: $($currentNetwork.Identifier) ($($currentNetwork.Type))"
    
    # Check for a match in the enabled profiles list
    $matchedProfile = $NetworkProfiles | Where-Object { 
        $_.Type -eq $currentNetwork.Type -and $_.Identifier -eq $currentNetwork.Identifier 
    }

    if ($matchedProfile) {
        # A specific, proxy-enabled network was found
        Set-ProxySettings -Profile $matchedProfile
    }
    else {
        # No match found, apply the default (disabled) profile
        Write-Host "No matching network profile found. Applying default settings (Proxy Disabled)."
        Set-ProxySettings -Profile $DefaultProfile
    }
}
else {
    Write-Warning "No active network connection found. Applying default settings."
    Set-ProxySettings -Profile $DefaultProfile
}