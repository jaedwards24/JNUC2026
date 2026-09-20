#!/bin/zsh

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Author: Jacob Edwards, Mac Admins Slack: @jacobaedwards
#
# Purpose: This is the OnAppear script for a Support.app Replacement custom extension. It checks the current replacement status 
# for the Mac based on the defined criteria and logic. This may not make sense for organizations with strict replacement cycles. The
# following logic is intended to inform users that they must replace their Mac during the summer of the year that the hardware 
# can no longer upgrade to a newer macOS version that receives security updates. 
#
# This script should be deployed to the Mac to your preferred location. The Support.app configuration profile will reference this 
# location. 
#
# NOTE: This Support.app custom extension is dependent on a Jamf Extenstion Attribute and a helper script on a Jamf policy.
# The helper script writes the latest macOS version name and number to a plist on the Mac. Our helper script is a modified version 
# of this: https://github.com/MLBZ521/MacAdmin/blob/master/Jamf%20Pro/Extension%20Attributes/Get-LatestOSSupported.sh. This script
# must be updated each year after WWDC once the new macOS version and supported hardware information is available.
# Separate Jamf EAs read these values into Jamf; however, for this Support app extension, we are only concerned with the latest 
# macOS version number that the Mac supports.
# Configuration that includes this tile will need to be scoped carefully after the latest macOS Version EA is updated and the helper 
# script has run on the Mac
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# This Support app extension is dependent on a Jamf Extenstion Attribute and a helper script on a Jamf policy.
# The helper script writes the latest macOS version name and number to a plist on the Mac.
# Our helper script is a modified version of this: https://github.com/MLBZ521/MacAdmin/blob/master/Jamf%20Pro/Extension%20Attributes/Get-LatestOSSupported.sh
# Separate Jamf EAs read these values into Jamf; however, for this Support app extension, we are only concerned with the latest macOS version number.

# Update these variables with the appropriate values for your environment and configuration
plist_path="/library/application support/jnuc"      # Update with the path where the helper script writes the plist
plist_name="com.jnuc.computerinfo.plist"            # Update with the name of the plist that the helper script writes
plist="$plist_path/$plist_name"
key="latest_os_supported_number"                    # Update with the key in the plist that contains the latest macOS version number supported by the Mac
helper_policy_trigger="macos-version-ea-helper"     # Update with the custom trigger for the Jamf policy that runs the helper script to update the latest macOS version values on the Mac

# Extension ID added for Support app 3.0 config
extension_id="replacement"

# Support App preference plist
preference_file_location="/Library/Preferences/nl.root3.support.plist"

# Start spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool true

# Reset alert
defaults write "${preference_file_location}" "${extension_id}_alert" -bool false

# Replace value with placeholder while loading
defaults write "${preference_file_location}" "${extension_id}" -string "Checking status"

# Keep loading effect active for at least the specified sleep time
sleep 0.25

# DETERMINE TARGET REPLACEMENT YEAR BASED ON LATEST MACOS VERSION COMPATIBILITY
latestOSNumber=$(defaults read "$plist" "$key" 2> /dev/null)

if [[ -z "$latestOSNumber" ]]; then
    # Run helper policy to update latest macOS version value
    /usr/local/bin/jamf policy -event $helper_policy_trigger
    sleep .5
    latestOSNumber=$(defaults read "$plist" "$key" 2> /dev/null)
fi

#if [[ -n "$latestOSNumber" ]]; then
if [[ $latestOSNumber -gt 10 ]]; then
    # get the current year
    currentYear=$(date +"%Y")
    # get the current month without the zero-padding
    currentMonth=$(date +"%-m")
    
    ## targetYear logic will requires different adjustments for macOS Tahoe and later
    ## Your offset will depend on your organization's replacement cycle and the timing of new macOS releases. 
    ## The example logic below is based on a cycle of replacing devices when they are no longer able to run a macOS version 
    ## that receives security updates, which for many organizations will be around 3 years after the release of a given macOS version. 
    ## The offset values in the example logic are based on the assumption that macOS Sonoma (14) will need to be replaced by June 2026, 
    ## but you may want to adjust these values based on your organization's specific replacement cycle, the timing of new macOS releases, etc.
    if [[ "$latestOSNumber" -ge 26 ]]; then
        offset=2002
    else
        offset=2012
    fi
    targetYear=$(($latestOSNumber+$offset))
    # Sonoma (14), replace by June 2026
    # Sequoia (15), replace by June 2027
    # Tahoe (26), replace by June 2028
    # XXXXX (27), replace by June 2029
fi


if [[ $targetYear -ge $(($currentYear+3)) ]]; then
    # Mac can run the latest macOS version. No need to configure the Support.app replacement notice tile.
    # We shouldn't end up here if everything is working properly
    extension_result=""
    extAlert=false

elif [[ $targetYear -eq $(($currentYear+2)) ]] && [[ $currentMonth -le 9 ]]; then
    # This will prevent showing the "recycle by [date]" until October of a given year when the Mac is a little less than 2 years away from required recycling
    # Delaying this until October allows time for updating the lastest macOS version EA and getting updated values on our Mac fleet
    extension_result=""        # month and year when it needs to be out of service
    extAlert=false

elif [[ $targetYear -eq $(($currentYear+2)) ]] && [[ $currentMonth -ge 10 ]]; then
    # This will start showing the "recycle by [date]" in October of a given year when the Mac is a little less than 2 years away from required recycling
    # Delaying this until October allows time for updating the lastest macOS version EA and getting updated values on our Mac fleet
    extension_result="Recycle by 06/$targetYear"        # month and year when it needs to be out of service
    extAlert=false

elif [[ $targetYear -eq $(($currentYear+1)) ]]; then
    extension_result="Recycle by 06/$targetYear"        # month and year when it needs to be out of service
    extAlert=false

elif [[ $targetYear -eq $currentYear ]] && [[ $currentMonth -le 6 ]]; then
    # In June or earlier of the replacement year, the text says to recycle by the target date
    extension_result="Recycle by 06/$targetYear"        # month and year when it needs to be out of service
    extAlert=true

elif [[ $targetYear -eq $currentYear ]] && [[ $currentMonth -ge 7 ]]; then
    # Beginning in July of the replacement year, the text changes to Overdue
    extension_result="Overdue, 06/$targetYear"        # month and year when it needs to be out of service
    extAlert=true

elif [[ $targetYear -lt $currentYear ]]; then
    # Should already be removed from service
    extension_result="Overdue, 06/$targetYear"  # month and year when it needs to be out of service
    extAlert=true
fi


# Write output to Support App preference plist
defaults write "${preference_file_location}" "${extension_id}" -string "$extension_result"

# Set or reset the alert badge for extension
defaults write "${preference_file_location}" "${extension_id}_alert" -bool $extAlert

# Stop spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool false

exit