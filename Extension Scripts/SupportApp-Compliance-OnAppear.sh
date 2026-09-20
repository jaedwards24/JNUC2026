#!/bin/zsh

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Author: Jacob Edwards, Mac Admins Slack: @jacobaedwards
#
# Purpose: This is the OnAppear script for a Support.app Compliance custom extension. It checks the current compliance status 
# (Jamf Device Compliance, PCM integration) of the logged in user and updates the Support App preference plist with the status to 
# be displayed in the UI.
#
# This script should be deployed to the Mac to your preferred location. The Support.app configuration profile will reference this 
# location. 
# 
# # Pre-requisites and assumptions:
# 1. You have deployed Microsoft SSOe or Platform SSO to your macOS devices.
# 2. If Platform SSO is deployed, you're using Secure Enclave Key (SEK). I have not tested this with any other Platform SSO config.
# 3. A smart group is setup with Criteria: Device Compliance Status - Compliance Status is Compliant
# 4. A configuration profile is scoped to that smart group. The profile domain is set in compliancePlistPath below 
#    with a custom setting key named "compliantGroup" and a boolean value of true.
# 5. Another configuration profile is scoped to Macs in the compliance group designated in 
#    https://JamfProURL/view/settings/global-management/conditional-access/device-compliance. The profile domain is set in 
#    compliancePlistPath below with a custom setting key named "compliance" and a boolean value of true.
# 6. A Jamf policy that runs a script and has a custom trigger. See run_gatheraadinfo function below. You may have already set this
#    up for the Registration OnAppear script.
# 
# NOTE: For my environment, if a user is not registered, I did not check compliance status and instead display "Not Registered" 
# in the compliance extension. 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Works in conjunction with a Jamf configuration profile with custom settings that is scoped to your compliant devices
# The profile should write a key named "compliance" with a boolean value of true for compliant devices. Non-compliant devices should
# not be scoped to the profile. The preference domain used in the profile should be set in the compliancePlist variable below.

# # # # # VARIABLES TO EDIT # # # # #
compliancePlistPath="/Library/Managed Preferences/com.jnuc.devicecompliance.plist"
# Use color indicators for compliance status
color_indicators="true"  # Set to "true" to use the color circle emojis, "false" or anything else for no emojis
# OPTIONAL, see run_gatherAADInfo function
policy_trigger="run-gatherAADInfo"
# # # # END VARIABLES TO EDIT # # # # 

# Extension ID added for Support app 3.x config
extension_id="compliance"

# Initialize extension alert variable.
extAlert=false

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
defaults write "${preference_file_location}" "${extension_id}" -string "Checking status"

# Keep loading effect active for at least the specified sleep time
sleep 0.2

registrationStatus=$(defaults read "${preference_file_location}" "registration" 2> /dev/null)
# Wait for registration tile to be determined before checking compliance status
until [[ "$registrationStatus" != "Checking status" ]] && [[ "$registrationStatus" != "" ]]; do
    sleep 0.1
    registrationStatus=$(defaults read "${preference_file_location}" "registration" 2> /dev/null)
done

checkComplianceStatus() {
    # Check for profile indicating that all compliance requirements are met.
    [[ $(defaults read "${compliancePlistPath}" "compliance" 2> /dev/null) ]] && complianceReqs="Yes" || complianceReqs="No"
    # Check for profile indicating that Jamf shows the Device Compliance Status - Compliance Status is Compliant
    [[ $(defaults read "${compliancePlistPath}" "compliantGroup" 2> /dev/null) ]] && compliantGroup="Yes" || compliantGroup="No"
	
    if [[ "$registrationStatus" == *"Not Registered" ]]; then
        # If the Registration tile shows "Not Registered", show the same thing in the Compliance tile. 
        complianceStatus="${yellow_circle}Not Registered"
        #symbol="info.circle.text.page.fill"
        symbol="info.circle.text.page"
        # Depending on your environment, you might want to set the extension tile alert status here. If so, uncomment the line below
		#extAlert=true
        
        # If the Mac is not registered but the compliant group still shows as "Yes", this may help clear it.
        if [[ "$compliantGroup" == "Yes" ]]; then
            kickstartAADInfo="true"
        fi
    elif [[ "$registrationStatus" != *"Not Registered" ]]; then
        # If the Mac has a state other than "Not Registered", determine the compliance status to display.
        if [[ "$complianceReqs" == "Yes" ]] && [[ "$compliantGroup" == "Yes" ]]; then
            # Compliance requirements are met and Jamf shows the device is compliant.
            complianceStatus="${green_circle}Compliant"
            #symbol="checkmark.seal.text.page.fill"
            symbol="checkmark.seal.text.page"
        elif [[ "$complianceReqs" == "Yes" ]] && [[ "$compliantGroup" == "No" ]]; then
            # Compliance requirements are met but Jamf doesn't show the device as compliant.
            complianceStatus="${yellow_circle}Compliant, pending"
            #symbol="questionmark.text.page.fill"
            symbol="questionmark.text.page"
        elif [[ "$complianceReqs" == "No" ]] && [[ "$compliantGroup" == "Yes" ]]; then
            # Compliance requirements are not met but Jamf shows the device as compliant.
            complianceStatus="${yellow_circle}Not Compliant, Error"
            #symbol="exclamationmark.triangle.text.page.fill"
            symbol="exclamationmark.triangle.text.page"
        elif [[ "$complianceReqs" == "No" ]] && [[ "$compliantGroup" == "No" ]]; then
            # Compliance requirements are not met and Jamf doesn't show the device as compliant.
            complianceStatus="${red_circle}Not Compliant"
            #symbol="exclamationmark.triangle.text.page.fill"
            symbol="exclamationmark.triangle.text.page"
        fi
        
        if [[ "$complianceStatus" == *"Not Compliant"* ]] || [[ "$compliantGroup" == "No" ]]; then 
            extAlert=true
            # If the Mac was registered recently, the compliance profile may not have installed yet. 
            # There can be a delay. Updating the Jamf management framework and/or running a policy check-in may help. 
            kickstartAADInfo="true"
        elif [[ "$complianceStatus" == *"Compliant" ]]; then
            extAlert=false
		fi
	else
        # I don't think we can end up here, but if we do, let's return a not registered status
        complianceStatus="${yellow_circle}Not Registered"
        #symbol="info.circle.text.page.fill"
        symbol="info.circle.text.page"
        # Depending on your environment, you might want to set the extension tile alert status here. If so, uncomment the line below
		#extAlert=true
	fi
}

# Try a few things that may help with the timing issue. 
# You could adjust the following to run from this script. I preferred to capture policy logs for this.
run_gatherAADInfo() {
    # Jamf policy option
    /usr/local/bin/jamf policy -event "${policy_trigger}"

    ##START OF JAMF SCRIPT ATTACHED TO JAMF POLICY WITH CUSTOM TRIGGER
    # #!/bin/zsh
    # loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
    # loggedInUserUID=$(id -u "$loggedInUser")
    # jamfCA="/Library/Application Support/JAMF/Jamf.app/Contents/MacOS/Jamf Conditional Access.app/Contents/MacOS/Jamf Conditional Access"
    # plist="/Users/$loggedInUser/Library/Preferences/com.jamf.management.jamfAAD.plist"
    # # Run gatherAADInfo as the user
    # launchctl asuser $loggedInUserUID sudo -u $loggedInUser "${jamfCA}" gatherAADInfo -disable-cache-read -verbose
    # code=$?
    # exit $code
    ##END OF JAMF SCRIPT ATTACHED TO JAMF POLICY WITH CUSTOM TRIGGER

    # Whether using the Jamf policy or the local script, once Jamf CA has an AAD ID for the user, this has worked consistently and promptly
    # to get the smart group membership update and the configuration profile to install.
    /usr/local/bin/jamf policy &
}

checkComplianceStatus

# Write output to Support App preference plist
defaults write "${preference_file_location}" "${extension_id}" -string "${complianceStatus}"

# Set or reset the alert badge for extension
defaults write "${preference_file_location}" "${extension_id}_alert" -bool ${extAlert}

# Symbol: Any SF Symbol string
defaults write "${preference_file_location}" "${extension_id}_symbol" -string "${symbol}"

# Stop spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool false

if [[ "$kickstartAADInfo" == "true" ]]; then
    run_gatherAADInfo
fi

exit