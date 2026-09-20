#!/bin/zsh

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Author: Jacob Edwards, Mac Admins Slack: @jacobaedwards
# Purpose: This is the OnAppear script for a Support.app Registration custom extension. It checks the current registration status 
# (Platform SSO or Jamf Device Compliance, PCM integration) of the logged in user and updates the Support App preference plist 
# with the status to be displayed in the UI. Since Microsoft changed the location of the Workplace Join Key for device compliance
# registration, the detection of registration status is more complicated (see Jamf tech thoughts link below). I tried my best to
# incorporate ideas from Ben Whitis' script, but I have not tested all of the various registration states. Your mileage may vary. 
# We have moved on to Platform SSO and I did not spend a lot of time testing traditional registration.
#
# This script should be deployed to the Mac to your preferred location. The Support.app configuration profile will reference this 
# location. 
#
# Reading and references:
# https://community.jamf.com/tech-thoughts-180/upcoming-change-device-compliance-integration-for-macos-sso-extension-required-53476
# https://github.com/benwhitis/Jamf_Conditional_Access/blob/main/EA_RegistrationStatus_preview.sh
#
# Pre-requisites and assumptions:
# 1. You have deployed Microsoft SSOe or Platform SSO to your macOS devices.
# 2. If Platform SSO is deployed, you're using Secure Enclave Key (SEK). I have not tested this with any other Platform SSO config.
# 3. A smart group is setup with Criteria: Device Compliance Status - Registration Status is Registered
# 4. A configuration profile is scoped to the smart group. The profile domain is set in compliancePlistPath below 
#    with a custom setting key named "registeredGroup" and a boolean value of true.
# 5. A Jamf policy that runs a script and has a custom trigger. See run_gatheraadinfo function below.
#
# NOTE: There are probably better descriptions for some of the registration error states, but I've had trouble reliably reproducing 
# the various error states to determine the exact cause of the error status. So for now, any state that isn't a clear pass will be 
# marked as "Error" until I can get more specific.
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # VARIABLES TO EDIT # # # # #
compliancePlistPath="/Library/Managed Preferences/com.jnuc.devicecompliance.plist"
# Use color indicators for compliance status
color_indicators="true"  # Set to "true" to use the color circle emojis, "false" or anything else for no emojis
# See run_gatherAADInfo function for more info
policy_trigger="run-gatherAADInfo"
# # # # END VARIABLES TO EDIT # # # # 

# Extension ID added for Support app 3.x config
extension_id="registration"

if [[ "$color_indicators" == "true" ]]; then
    green_circle="🟢 "      # The [Space] after color circle is intentional
    yellow_circle="🟡 "
    red_circle="🔴 "
else
    green_circle=""
    yellow_circle=""
    red_circle=""
fi

# Support App preference plist
preference_file_location="/Library/Preferences/nl.root3.support.plist"

# Initialize extension alert variable.
extAlert=false

# Start spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool true

# Replace value with placeholder while loading
defaults write "${preference_file_location}" "${extension_id}" -string "Checking status"

# Keep loading effect active for at least the specified sleep time
sleep 0.2

# DETERMINE CURRENT REGISTRATION STATUS
# The initial idea for this was borrowed and adjusted from https://github.com/benwhitis/Jamf_Conditional_Access/blob/main/EA_RegistrationStatus_preview.sh
checkUserRegistration() {
    loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
    loggedInUserID=$(id -u "$loggedInUser")
    userHome=$(dscl . -read "/Users/$loggedInUser" NFSHomeDirectory | cut -d' ' -f2)
    jamfCA="/Library/Application Support/JAMF/Jamf.app/Contents/MacOS/Jamf Conditional Access.app/Contents/MacOS/JAMF Conditional Access"
    jamfaad_plist="$userHome/Library/Preferences/com.jamf.management.jamfAAD.plist"
    
    
    # Check jamfAAD plist for AAD ID
    AAD_ID=$(defaults read "$jamfaad_plist" have_an_Azure_id 2> /dev/null)
    
    #Check if registered via PSSO/SSOe
    ssoStatus=$(/bin/launchctl asuser $loggedInUserID "${jamfCA}" getPSSOStatus | /usr/bin/sed -E 's/AnyHashable\(|\)//g' | /usr/bin/tr ',' '\n')

    # Check Apple Platform SSO registration
    platformStatus=$(su "$loggedInUser" -c "app-sso platform -s" 2>/dev/null | awk '/registration/ {gsub(/,/, ""); print $3}')

    # Check for proxy configuration profile key that is scoped to the registered smart group 
    # Smart Group Criteria: Device Compliance Status - Registration Status is Registered
    [[ $(defaults read "${compliancePlistPath}" "registeredGroup" 2> /dev/null) ]] && registeredGroup="Yes" || registeredGroup="No"


    # Check SSOe/pSSO registration in Secure Enclave
    if [[ $ssoStatus == *"primary_registration_metadata_device_id"* ]]; then
        if [[ "$platformStatus" == "true" ]]; then
            if [[ -f "$jamfaad_plist" ]] && [[ $AAD_ID -eq "1" ]] && [[ "$registeredGroup" == "Yes" ]]; then
                # pSSO registered. Mac is fully registered.
                registrationStatus="${green_circle}Platform SSO"
                symbol="person.text.rectangle"
                return 0
            else
                # pSSO registered, but AAD ID is not present. Treating this as a possible timing issue. 
                # The device may have been registered recently and the AAD ID has not yet been acquired.
                registrationStatus="${yellow_circle}Platform SSO, pending"
                symbol="person.text.rectangle.trianglebadge.exclamationmark"
                kickstartAADInfo="true"
                return 0
            fi
        elif [[ "$platformStatus" == "false" ]]; then
            registrationStatus="${red_circle}Platform SSO, Error"
            symbol="person.text.rectangle.trianglebadge.exclamationmark"
            kickstartAADInfo="true"
            extAlert=true
            return 0
        elif [[ "$platformStatus" == "" ]]; then
            if [[ -f "$jamfaad_plist" ]] && [[ $AAD_ID -eq "1" ]] && [[ "$registeredGroup" == "Yes" ]]; then
                # WPJ is in Secure Enclave. Mac is fully registered. 
                registrationStatus="${green_circle}Registered"
                kickstartAADInfo="true"
                symbol="person.text.rectangle"
                return 0
            else
                # WPJ is in Secure Enclave, but AAD ID is not present. Treating this as a possible timing issue. 
                # The device may have been registered recently and the AAD ID has not yet been acquired.
                registrationStatus="${yellow_circle}Registered, pending"
                symbol="person.text.rectangle.trianglebadge.exclamationmark"
                kickstartAADInfo="true"
                return 0
            fi
        else
            # I don't think we can end up here, but if we do, let's return an registration error status
            registrationStatus="${red_circle}Registered, Error"
            symbol="rectangle.slash"
            extAlert=true
            return 0
        fi
    else
        # fallback to checking WPJ
        WPJKey=$(/bin/launchctl asuser $loggedInUserID "/usr/bin/security find-certificate -a -Z | /usr/bin/grep -B 9 "MS-ORGANIZATION-ACCESS" | /usr/bin/awk '/\"alis\"<blob>=\"/ {print $NF}' | /usr/bin/sed 's/\"alis\"<blob>=\"//;s/.$//'")
        if [[ -n "$WPJKey" ]]; then
            if [[ -f "$jamfaad_plist" ]] && [[ $AAD_ID -eq 1 ]] && [[ "$registeredGroup" == "Yes" ]]; then
                # WPJ found in Keychain. AAD ID is present. Mac is fully registered.
                registrationStatus="${green_circle}Registered"
                #symbol="person.text.rectangle.fill"
                symbol="person.text.rectangle"
                return 0
            else
                # WPJ found, but AAD ID is not present. Treating this as a possible timing issue. 
                # The device may have been registered recently and the AAD ID has not yet been acquired.
                registrationStatus="${yellow_circle}Registered, pending"
                #symbol="person.text.rectangle.trianglebadge.exclamationmark.fill"
                symbol="person.text.rectangle.trianglebadge.exclamationmark"
                kickstartAADInfo="true"
                return 0
            fi
        else
            # Device ID is not in SEK and not in Keychain. Mac is unregistered.
            registrationStatus="${yellow_circle}Not Registered"
            symbol="rectangle.slash"
            # Depending on your environment, you might want to set the extension tile alert status here. If so, uncomment the line below
		    #extAlert=true
            return 0
        fi

        # I don't think we can end up here, but if we do, let's return a not registered status
        registrationStatus="${yellow_circle}Not Registered"
        symbol="rectangle.slash"
        # Depending on your environment, you might want to set the extension tile alert status here. If so, uncomment the line below
		#extAlert=true
        return 0
    fi
}

# Try a few things that may help with the timing issue. 
# You could adjust the following to run from this script. I preferred to capture policy logs for this.
run_gatherAADInfo() {
    # Jamf policy option
    /usr/local/bin/jamf policy -event "${policy_trigger}"

    ##START OF JAMF SCRIPT ATTACHED TO JAMF POLICY WITH CUSTOM TRIGGER.
    ##
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

    # Whether using the Jamf policy or the local script, once Jamf CA has an AAD ID for the user, this has worked pretty consistently 
    # to get the smart group membership update and the configuration profile to install.
    /usr/local/bin/jamf policy &
}

checkUserRegistration

# Write output to Support App preference plist
defaults write "${preference_file_location}" "${extension_id}" -string "${registrationStatus}"

# Set or reset the alert badge for extension
defaults write "${preference_file_location}" "${extension_id}_alert" -bool $extAlert

# Symbol: Any SF Symbol string
defaults write "${preference_file_location}" "${extension_id}_symbol" -string "$symbol"

# Stop spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool false

if [[ "$kickstartAADInfo" == "true" ]]; then
    run_gatherAADInfo
fi

exit