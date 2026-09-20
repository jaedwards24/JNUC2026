#!/bin/zsh
 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Author: Jacob Edwards, Mac Admins Slack: @jacobaedwards
# Purpose: This is the Click script for a Support.app Registration custom extension. It retrieves the registration status determined
# by the OnAppear script and determins an action based on that status. We have both platform SSO and traditionally registered Macs
# so this script attempts to deal with either of these scenarios in addition to Macs that are not yet registered. There are a number
# of different directions you may want to take with this depending on your environment. 
# 
# PLATFORM SSO 
## Registered: Open System Settings > Users & Groups > $loggedInUser's info pane
## Error: Open System Settings > Users & Groups > $loggedInUser's info pane; user can Repair or Reauthenticate
# 
# TRADITIONAL DEVICE COMPLIANCE REGISTRATION (PARTNER COMPLIANCE MANAGED)
## Registered: run Jamf policy that runs jamfAAD gatherAADinfo
registered_policy_trigger="run-gatheraadinfo"
## Error: run Jamf policy that runs a desired remediation script. At the time of this writing, my default registration is
##        Platform SSO and I haven't kept up with all the recent changes to the traditional device compliance registration process. 
##        I haven't fully tested this scenario and don't have a remediation script to share.
error_policy_trigger="repair-device-registration"
#
# NOT REGISTERED
## pSSO Profile present: retrigger the Company Portal registration notification
#### NAME OR PARTIAL NAME OF YOUR PLATFORM SSO CONFIGURATION PROFILE
psso_profile="Platform SSO"
## No pSSO Profile present: open the Self Service registration policy. Alternatively, you could encourage the user to opt-in for pSSO 
#### Jamf Policy ID of Self Service traditional registration policy
policy_id="####"                    # Jamf Pro policy ID number
policy_action="view"			    # "view" or "execute"
#
# REGISTRATION PENDING
registration_pending_message="Your device registration appears to be pending. Please check again in a few minutes."
#
# This script should be deployed to the Mac to your preferred location. The Support.app configuration profile will reference this 
# location. 
#
# NOTE: There are probably better descriptions for some of the registration error states, but I've had trouble reliably reproducing 
# the various error states to determine the exact cause of the error status. So for now, any state that isn't a clear pass will be 
# marked as "Error" until I can get more specific.
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Extension ID added for Support app 3.0 config
extension_id="registration"

# Support App preference plist
preference_file_location="/Library/Preferences/nl.root3.support.plist"

# Get the username of the currently logged in user
loggedInUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
loggedInUserUID=$(id -u "$loggedInUser")
userHome=$(dscl . -read "/Users/$loggedInUser" NFSHomeDirectory | cut -d' ' -f2)

registrationStatus=$(defaults read "${preference_file_location}" "${extension_id}" 2> /dev/null)
until [[ "$registrationStatus" != "Checking status" ]] && [[ "$registrationStatus" != "" ]]; do
    sleep 0.1
    registrationStatus=$(defaults read "${preference_file_location}" "${extension_id}" 2> /dev/null)
done

# Start spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool true

if [[ "$registrationStatus" == *"Error" ]]; then
    if [[ "$registrationStatus" == "Platform SSO"* ]]; then
        # Open System Settings > Users & Groups > $loggedInUser's info pane
        /usr/bin/open "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension?showinfo*user:${loggedInUser}"
    else
        # If traditional registration, kickstart jamfAAD gatherAADinfo. This may or may not help.
        # Haven't found a good way to get into an error state and test remediation.
        # Idea taken from https://github.com/benwhitis/Jamf_Conditional_Access/blob/main/JamfAADActivator.sh
        jamfaad_plist="${userHome}/Library/Preferences/com.jamf.management.jamfAAD.plist"
        su "$loggedInUser" -c "/usr/bin/defaults write $jamfaad_plist have_an_Azure_id -bool true"
        #reset timer to force recurring gatherAADInfo
        su "$loggedInUser" -c "/usr/bin/defaults write $jamfaad_plist last_aad_token_timestamp 0"
        #run recurring gatherAADInfo
        su "$loggedInUser" -c "/Library/Application\ Support/JAMF/Jamf.app/Contents/MacOS/Jamf\ Conditional\ Access.app/Contents/MacOS/Jamf\ Conditional\ Access gatherAADInfo -recurring"

        # You could also move the lines in this else statement into a Jamf script, attach it to a policy, and call that policy here. This gives you the benefit of seeing the policy logs.
        /usr/local/bin/jamf policy -event ${error_policy_trigger}
    fi

elif [[ "$registrationStatus" == *"pending" ]]; then
    # Show dialog to check Support.app again soon. Potential remedial action was taken by the Registration-OnAppear script.
    # Show a Not Registered dialog
    /usr/local/bin/dialog --message "$registration_pending_message" \
    --small --ontop --overlayicon "$overlay_icon" --icon "$dialog_icon" --title "Registration Pending" --moveable

elif [[ "$registrationStatus" == *"Not Registered" ]]; then
    # check for Platform SSO profile presence
    pSSOProfileCheck=$(/usr/bin/profiles -C -v | grep attribute | awk '/name/{$1=$2=$3=""; print $0}' | sed 's/^ *//' | grep -i "${psso_profile}" &> /dev/null && echo "true" || echo "false")
    # if Platform SSO profile is present AND Mac isn't registered
    if [[ "$pSSOProfileCheck" == "true" ]]; then
        # This should cause the Company Portal registration notification to reappear in the upper right corner or in the Notification Center tray
        # General idea from https://github.com/ScottEKendall/Microsoft-Platform-SSO
        pkill -9 -x "AppSSOAgent"
        /usr/bin/app-sso -l > /dev/null 2>&1

    else
        if [[ -d "/Applications/Self Service.app/" ]]; then
            urlScheme="jamfselfservice://"
        elif [[ -d "/Applications/Self Service+.app/" ]]; then
            urlScheme="selfservicecapability://"
        fi

        # Start your traditional device compliance registration policy in Self Service
        selfServicePolicyURL="${urlScheme}content?entity=policy&id=${policy_id}&action=${policy_action}"

        # Open the Self Service registration policy
        if [[ "$policy_action" == "view" ]]; then
            # Open Self Service to the specified policy. User can choose to execute the policy or not.
            su "${loggedInUser}" -c "/usr/bin/open \"${selfServicePolicyURL}\""
        elif [[ "$policy_action" == "execute" ]]; then
            # Open Self Service in the background and execute the specified policy.
            su "${loggedInUser}" -c "/usr/bin/open -j \"${selfServicePolicyURL}\""
        fi
        # Or use this as opportunity to set them up with Platform SSO
     fi

elif [[ "$registrationStatus" == *"Platform SSO" ]]; then
    # Open System Settings > Users & Groups > $loggedInUser's info pane
    /usr/bin/open "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension?showinfo*user:${loggedInUser}"

elif [[ "$registrationStatus" == *"Registered" ]]; then
    # No action is necessary here, but you could do one of several things
    # Run a regular policy in the background
    # Run a Self Service policy
    # You could trigger a dialog here for transitioning to Platform SSO

    /usr/local/bin/jamf policy -event ${registered_policy_trigger} &
    return 0
fi

# Start spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool false

exit