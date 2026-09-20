#!/bin/zsh

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Author: Jacob Edwards, Mac Admins Slack: @jacobaedwards
#
# Purpose: This is the Click script for a Support.app Compliance custom extension. It retrieves the compliance status determined by
# the the OnAppear script. 
# Ultimately you will need to carefully outline your compliance requirements, determine the best way to verify each. Our requirements
# consist of a minimum macOS version and FileVault (or an exception). You may need to adjust these or add other items. A smart group 
# was created for each compliance component. Then a configuration profile scoped to that smart group distributes a key value. After 
# retrieiving those key values, I show the user their status in a Swift Dialog prompt
#
# This script should be deployed to the Mac to your preferred location. The Support.app configuration profile will reference this 
# location. 
#
# NOTE: For my environment, if a user is not registered, I did not check compliance status any further and instead displayed
# "Not Registered" in the compliance extension. 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Extension IDs added for Support app 3.0 config
extension_id="compliance"

# Support App preference plist
preference_file_location="/Library/Preferences/nl.root3.support.plist"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#   VARIABLES TO SET
# 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# NOT REGISTERED
## pSSO Profile present: retrigger the Company Portal registration notification
#### NAME OR PARTIAL NAME OF YOUR PLATFORM SSO CONFIGURATION PROFILE
psso_profile="Platform SSO"
## No pSSO Profile present: open the Self Service registration policy. Alternatively, you could encourage the user to opt-in for pSSO 
#### Jamf Policy ID of Self Service traditional registration policy
policy_id="####"                    # Jamf Pro policy ID number
policy_action="view"			    # "view" or "execute"
# path to and name of plist storing the compliance status and component key values.
compliancePlistPath="/Library/Managed Preferences/com.jnuc.devicecompliance.plist"
# path to Icons directory for icons used on the swift dialog compliance report. 
iconPath="/Library/Application Support/JNUC/Icons"
# overlay icon for the Swift Dialog compliance report.
overlay_icon="${iconPath}/JNUC-icon.png"
### icon file names. I created icons using custom SF Symbols and deployed them via a package alongside our Support.app 3.x rollout
compliant_icon="compliant.png"
not_compliant_icon="not-compliant.png"
component_compliant_icon="compliant-component.png"
component_not_compliant_icon="not-compliant-component.png"
registered_icon="registered.png"
not_registered_icon="not-registered.png"
info_icon="info.png"
# text on dialogs
not_compliant_infobox_message="This Mac **does not meet** compliance requirements.\n\nThis status may not reflect recent changes. If you are having problems with device compliance, please contact the Help Desk."
compliant_infobox_message="This Mac **meets** compliance requirements.\n\nThis status may not reflect recent changes. If you are having problems with device compliance, please contact the Help Desk."
not_registered_message="This Mac is **not registered**. Please register the Mac to generate a compliance report."
# # # # END VARIABLES TO SET # # # #

dialog_json="/tmp/dialogjson.json"
# Using this icon 2x on the dialog--primary dialog icon and also for the Mac Name list item
dialog_icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/com.apple.macbookpro-14-2021-silver.icns"

# Start spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool true

# Get the compliance and registration status
complianceStatus=$(defaults read "${preference_file_location}" "$extension_id" 2> /dev/null)
registrationStatus=$(defaults read "${preference_file_location}" "registration" 2> /dev/null)
# Wait for compliance and registration tiles before proceeding
until [[ "$complianceStatus" != "Checking status" ]] && [[ "$complianceStatus" != "" ]]; do
    sleep 0.1
    complianceStatus=$(defaults read "${preference_file_location}" "$extension_id" 2> /dev/null)
   registrationStatus=$(defaults read "${preference_file_location}" "registration" 2> /dev/null)
done


filevaultDeferredStatus () {
    fdesetupStatus=$(fdesetup status)

    # Check if FileVault is in deferred enablement status
    if [[ $fdesetupStatus == *"Deferred enablement appears to be active"* ]]; then
        # Extract the username using awk
        username=$(echo "$fdesetupStatus" | awk -F"'" '{print $2}')
        
        # Remove any white space characters (if present)
        deferredStatusResult=$(printf '%s\n' "$username" | tr -d '[:space:]')
        
        # Check if result is blank
        if [[ -z "$deferredStatusResult" ]]; then
            #Deferred enablement is active, but username is not known
            deferredStatusResult="Undetermined User"
        fi

    else
        #Deferred enablement not active
        deferredStatusResult="NONE"
    fi

}

checkComplianceComponents() {
    computerName=$(scutil --get ComputerName)
    
    # Check for various Configuration Profile key values. These are a proxy for checking everything directly and changes may be delayed until inventory updates and the profiles install or remove
    [[ $(defaults read "${compliancePlistPath}" "compliance" 2> /dev/null) ]] && compliance="Yes" || compliance="No"
    [[ $(defaults read "${compliancePlistPath}" "macos_minimum" 2> /dev/null) ]] && macos_minimum="Yes" || macos_minimum="No"
    [[ $(defaults read "${compliancePlistPath}" "filevault" 2> /dev/null) ]] && filevault="Yes" || filevault="No"
    # We have a small number of Macs where we exclude FileVault for some specific reasons. I decided to leave this here though it may not be applicable for others
    [[ $(defaults read "${compliancePlistPath}" "filevault_exception" 2> /dev/null) ]] && filevault_exception="Yes" || filevault_exception="No"

    # Adjust the icon and title for Swift Dialog based on the status
    if [[ "$registrationStatus" == *"Not Registered" ]]; then
        registrationIcon="$not_registered_icon"
    elif [[ "$registrationStatus" == *"Platform SSO" ]] || [[ "$registrationStatus" == *"Registered" ]]; then
        registrationIcon="$registered_icon"
    fi

    if [[ "$compliance" == "Yes" ]]; then
        complianceIcon="$compliant_icon"
    else
        complianceIcon="$not_compliant_icon"
    fi

    if [[ "$macos_minimum" == "Yes" ]]; then
        macosIcon="$component_compliant_icon"
    else
        macosIcon="$component_not_compliant_icon"
    fi

    if [[ "$filevault" == "Yes" ]]; then
        filevaultTitle="FileVault"
        filevaultIcon="$component_compliant_icon"
        filevaultStatus="$filevault"
    elif [[ "$filevault_exception" == "Yes" ]]; then
        filevaultTitle="FileVault Exception"
        filevaultIcon="$component_compliant_icon"
        filevaultStatus="$filevault_exception"
    else
        filevaultTitle="FileVault"
        filevaultIcon="$component_not_compliant_icon"
        filevaultStatus="No"
        filevaultDeferredStatus
    fi
}

checkComplianceComponents

if [[ "$filevaultStatus" == "No" ]] && [[ "$deferredStatusResult" != "NONE" ]]; then
# Build the Swift Dialog list item content with deferred user info shown
cat << EOF > $dialog_json
{
	"listitem" : [
		{"title" : "Mac Name:", "icon" : "$dialog_icon", "statustext" : "$computerName"},
		{"title" : "Registration:", "icon" : "$iconPath/$registrationIcon", "statustext" : "$registrationStatus"},
        {"title" : "Compliance Status:", "icon" : "$iconPath/$complianceIcon", "statustext" : "$compliance"},
        {"title" : "macOS Minimum:", "icon" : "$iconPath/$macosIcon", "statustext" : "$macos_minimum"},
        {"title" : "$filevaultTitle:", "icon" : "$iconPath/$filevaultIcon", "statustext" : "$filevaultStatus"},
        {"title" : "FileVault deferred for $deferredStatusResult", "icon" : "$info_icon"}
	]
}
EOF

else
# Build the Swift Dialog list item content without the deferred user info
cat << EOF > $dialog_json
{
	"listitem" : [
		{"title" : "Mac Name:", "icon" : "$dialog_icon", "statustext" : "$computerName"},
		{"title" : "Registration:", "icon" : "$iconPath/$registrationIcon", "statustext" : "$registrationStatus"},
        {"title" : "Compliance Status:", "icon" : "$iconPath/$complianceIcon", "statustext" : "$compliance"},
        {"title" : "macOS Minimum:", "icon" : "$iconPath/$macosIcon", "statustext" : "$macos_minimum"},
        {"title" : "$filevaultTitle:", "icon" : "$iconPath/$filevaultIcon", "statustext" : "$filevaultStatus"}
	]
}
EOF

fi


if [[ "$complianceStatus" == *"Not Compliant" ]]; then
    # show component status for compliance
    # macOS version yes/no
    # FileVault or FileVault exception yes/no
    /usr/local/bin/dialog --message "" --width 700 --height 500 --ontop --overlayicon "$overlay_icon" \
    --icon $dialog_icon --title "Compliance Report" --moveable --jsonfile "$dialog_json" \
    --infobox "$not_compliant_infobox_message"

elif [[ "$complianceStatus" == *"Compliant"* ]]; then
    # run gatherAADinfo as user?
    # swift dialog message: Mac appears to be compliant. This status may not reflect recent changes. If you are having problems with device compliance, please contact the Help Desk.
    /usr/local/bin/dialog --message "" --width 700 --height 500 --ontop --overlayicon "$overlay_icon" \
    --icon $dialog_icon --title "Compliance Report" --moveable --jsonfile "$dialog_json" \
    --infobox "$compliant_infobox_message"

elif [[ "$complianceStatus" == *"Not Registered" ]]; then
        # Show a Not Registered dialog
        /usr/local/bin/dialog --message "$not_registered_message" \
        --small --ontop --overlayicon "$overlay_icon" --icon "$dialog_icon" --title "Compliance Report" \
        --moveable --button2text "Register Now"
        
        dialogExitCode=$?

        case "$dialogExitCode" in
            0)
                # User clicked OK
            ;;
                
            2)
                # User clicked Register Now button
                # If pSSO config present, relaunch notification
                # FUTURE CONSIDERATION: If pSSO config not present, show dialog with buttons to switch to pSSO or open traditional registration policy in Self Service
                
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
            ;;

            *)
                # Something else happened
            ;;

        esac
fi

# Stop spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool false

exit