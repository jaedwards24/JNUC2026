#!/bin/zsh

# THIS IS A TEMPLATE. YOU'LL NEED TO EDIT AND TEST FOR YOUR ENVIRONMENT.
# Support.app extension to update info in Support.app at the time the user clicks on the menu bar icon
#
# REQUIREMENTS:
# - Jamf Pro Binary
# - RegEx or other logic to identify IP Addresses in your VPN IP address ranges. See check_corporate_vpn function


# # # # # VARIABLES TO SET # # # # #
fqdn_or_host="HOSTNAME"         # Host or FQDN to check for corporate network presence. Should be something that is always available but only accessible when on the corporate network, such as a domain controller or intranet site.
expected_ip_prefix="111.222."   # Expected prefix of the resolved IP address for the above host. This is used to help confirm that the host is actually resolving to an internal IP address
                                # EXAMPLES: 10.150. | 10.200.25.
test_count=3                    # Number of ping attempts to make to the host. The script will try to ping the host this many times before determining that it is unreachable.
# # # # END VARIABLES TO SET # # # #

# Extension ID added for Support app 3.0 config
extension_id="corpnetwork"
extension_title="Corp Network"      # Requires Support App 3.0.4

# Use color indicators for compliance status
color_indicators="true"  # Set to "true" to use the color circle emojis, "false" or anything else for no emojis
if [[ "$color_indicators" == "true" ]]; then
    green_circle="🟢 "
    yellow_circle="🟡 "
    red_circle="🔴 "
else
    green_circle=""
    yellow_circle=""
    red_circle=""
fi

# Support App preference plist
preference_file_location="/Library/Preferences/nl.root3.support.plist"

# Start spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool true

# Replace value with placeholder while loading
defaults write "${preference_file_location}" "${extension_id}" -string "Checking network"

# Reset title
defaults write "${preference_file_location}" "${extension_id}_title" -string "$extension_title"

# Keep loading effect active specified time
sleep 0.25

# # # # # # #
# FUNCTIONS #
# # # # # # #
# Example:
#   if corporate_network_reachable "corp.example.com" "10.20."; then
#       echo "Corporate network reachable"
#   else
#       echo "Corporate network not reachable"
#   fi
#
# Expected IP match examples:
#   "10.20."        matches 10.20.x.x
#   "192.168.50."   matches 192.168.50.x
#   "172.16."       matches 172.16.x.x
#
# This function returns:
#   0 = reachable
#   1 = not reachable

corporate_network_reachable() {
    local corporate_host="$1"
    local expected_ip_prefix="$2"

    local resolved_ips
    local ip
    local ip_matches_expected="false"
    local ping_success="false"
    local ping_attempt

    # if [[ -z "$corporate_host" || -z "$expected_ip_prefix" ]]; then
    #     echo "Usage: corporate_network_reachable <host_or_fqdn> <expected_ip_prefix>" >&2
    #     return 1
    # fi

    # Resolve the host.
    # dscacheutil is available on macOS and respects the system resolver configuration.
    resolved_ips=("${(@f)$(dscacheutil -q host -a name "$corporate_host" 2>/dev/null | awk '/ip_address:/ {print $2}')}")

    if (( ${#resolved_ips[@]} == 0 )); then
        # echo "Corporate host not reachable: DNS resolution failed for $corporate_host"
        reachable="false"
        return 1
    fi

    # Confirm that at least one resolved IP roughly matches what is expected.
    for ip in "${resolved_ips[@]}"; do
        if [[ "$ip" == "$expected_ip_prefix"* ]]; then
            ip_matches_expected="true"
            break
        fi
    done

    if [[ "$ip_matches_expected" != "true" ]]; then
        # echo "Corporate host not reachable: resolved IP did not match expected range"
        # echo "Host: $corporate_host"
        # echo "Resolved IPs: ${resolved_ips[*]}"
        # echo "Expected prefix: $expected_ip_prefix"
        reachable="false"
        return 1
    fi

    # Ping up to ${test_count} times.
    # -c 1 = send one packet per attempt
    # -W 1000 = wait up to 1000 ms for a reply on macOS
    for ping_attempt in {1..${test_count}; do
        if /sbin/ping -c 1 -W 1000 "$corporate_host" >/dev/null 2>&1; then
            ping_success="true"
            break
        fi
    done

    if [[ "$ping_success" == "true" ]]; then
        # Corporate host reachable
        reachable="true"
    else
        # Corporate host not reachable: ping failed after 3 attempts
        reachable="false"
    fi
}

check_corporate_vpn() {
  # Logic to check for VPN connection
  # Rewrite as necessary for your organization's VPN
  # MAKE SURE TO SET THE FOLLOWING TWO VARIABLES UNLESS YOU ARE ADJUSTING OTHER PARTS OF THE SCRIPT:
  #CorpVPNIP="[IP_ADDRESS]"         # The IP address of the VPN connection, if connected
  #VPN="true|false"                 # Whether the VPN is connected or not
    for int in $( ifconfig -a | grep "^utun*" | cut -d ":" -f 1 ); do
        Ifconfig_result=$( ifconfig | grep -A2 "$int" )
        utunIP=$(echo "$Ifconfig_result" | awk '/inet / && $2 != "127.0.0.1"{print $2}')
        # Initial screen for expected IP value. 100.64.0.1 is related to Zscaler. Left this as an example, though you may not need it.
        if [[ -n "$utunIP" ]] && [[ "$utunIP" != "100.64.0.1" ]]; then
            # USE REGEX TO SEE IF IP MATCHES ANY OF YOUR VPN IP RANGES
            # THE FOLLOWING RANGES ARE MADE UP AND LEFT AS EXAMPLES OF WHAT THIS COULD LOOK LIKE
            if [[ $utunIP =~ ^10\.3[012]\.20[23]\.[0-9]{1,3}$ ]] \
            || [[ $utunIP =~ ^10\.72\.(17[4-9]|18[0-1])\.[0-9]{1,3}$ ]] \
            || [[ $utunIP =~ ^10\.100\.[4-6][0-9]\.[0-9]{1,3}$ ]]; then
                CorpVPNIP="$utunIP"
            fi
        fi
    done

    if [[ -n "$CorpVPNIP" ]]; then
        VPN="true"
        # Reset title
        extension_title="Corp VPN"
    fi
}

get_corporate_ip() {
  # Get primary active interface
  primaryActiveInterface=$(scutil --nwi | grep "Network interfaces: " | awk '/Network interfaces: /{ print $3 }')
  # Get IP of primary network interface
  CorpIP=$(ipconfig getifaddr $primaryActiveInterface)
}

check_corporate_vpn
corporate_network_reachable "$fqdn_or_host" "$expected_ip_prefix"

# Actions for these statuses are determined and taken by the click script. Support 3.x cannot have the type and action set by the OnAppear script
if [[ "$VPN" == "true" ]]; then
  corpNetworkStatus="${green_circle}$CorpVPNIP VPN"
  # Set action for tile click. When on VPN, open VPN client.
  action_type="App"
  action="net.pulsesecure.Pulse-Secure"
  symbol="lock.shield"

elif [[ "$reachable" == "true" ]]; then
  get_corporate_ip 
  corpNetworkStatus="${green_circle}$CorpIP"
  # Set action for tile click. When on Corp Network, open System Settings > Network
  action_type="Command"
  action="open x-apple.systempreferences:com.apple.Network-Settings.extension"
  symbol="lock.shield"

elif [[ "$reachable" == "false" ]]; then
  corpNetworkStatus="${red_circle}Disconnected"
  # Set action for tile click. When off VPN and not on Corp network, open VPN client.
  action_type="App"
  action="net.pulsesecure.Pulse-Secure"
  symbol="shield.slash"

else
  corpNetworkStatus="${red_circle}Undetermined"
  # Set action for tile click. When undetermined, open System Settings > Network
  action_type="Command"
  action="open x-apple.systempreferences:com.apple.Network-Settings.extension"
  symbol="exclamationmark.shield"
fi

# OPTIONAL: Set custom action type, action, and symbol/icon for the Support App tile. 
# Using these can avoid the need for a click script.
# https://github.com/root3nl/SupportApp/wiki/Extensions
# Action Types: App, URL, User Command, Privileged Script
defaults write "${preference_file_location}" "${extension_id}_action_type" -string "$action_type"

# Action: bundle ID of app to open, URL to open, or command to run when the tile is clicked.
defaults write "${preference_file_location}" "${extension_id}_action" -string "$action"

# Symbol: Any SF Symbol string
defaults write "${preference_file_location}" "${extension_id}_symbol" -string "$symbol"

# Set title
defaults write "${preference_file_location}" "${extension_id}_title" -string "$extension_title"

# Write Corp Network Status to Support App preference plist
defaults write "${preference_file_location}" "${extension_id}" -string "${corpNetworkStatus}"

# Stop spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool false

exit