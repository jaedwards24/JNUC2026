#!/bin/zsh

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Author: Jacob Edwards, Mac Admins Slack: @jacobaedwards
#
# Purpose: This is the Click script for a Support.app Replacement custom extension. It retrieves the current replacement status 
# determined by the OnAppear script and determins an action based on that status. We point the user to a Self Service+ policy
# that provides relevant organizational details, links, etc. about getting their Mac replaced. Alternatively, you could show info
# in Swift Dialog, etc.
#
# This script should be deployed to the Mac to your preferred location. The Support.app configuration profile will reference this 
# location. 
#
# NOTE: This Support.app custom extension is dependent on a Jamf Extenstion Attribute and a helper script on a Jamf policy.
# The helper script writes the latest macOS version name and number to a plist on the Mac. Our helper script is a modified version 
# of this: https://github.com/MLBZ521/MacAdmin/blob/master/Jamf%20Pro/Extension%20Attributes/Get-LatestOSSupported.sh. This script
# must be updated each year after WWDC once the new macOS version and supported hardware information is available.
# Separate Jamf EAs read these values into Jamf. FOR THIS SUPPORT.APP EXTENSION, WE ARE ONLY CONCERNED WITH THE LATEST 
# MACOS VERSION NUMBER THAT THE MAC SUPPORTS. 
# The Configuration Profile that includes this tile must be scoped carefully after the latest macOS Version EA Helper Script is 
# updated AND the helper script has run on the Mac. 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # VARIABLES TO EDIT # # # # #
next_summer_policy_id="####"            # The policy IDs referenced have no payload. 
                                        # It shows in Self Service with information about replacement timeline, etc. in the policy description
                                        # Alternative ideas here could include showing info in Swift Dialog or linking a user directly 
                                        # to where they can order a replacement computer. 
this_summer_policy_id="####"
overdue_policy_id="####"
policy_action="view"                    # view or execute
# # # # END VARIABLES TO EDIT # # # #

# Extension ID added for Support app 3.0 config
extension_id="replacement"

# Support App preference plist
preference_file_location="/Library/Preferences/nl.root3.support.plist"

# Start spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool true

# Get the username of the currently logged in user
loggedInUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')

# get the current year
currentYear=$(date +"%Y")
# get the current month without the zero-padding
currentMonth=$(date +"%-m")

extensionValue=$(defaults read "${preference_file_location}" "${extension_id}" 2> /dev/null)
if [[ "$extensionValue" == "" ]]; then
    # This sets the target year out of range for any action below
    targetYear=$(($currentYear+5))
else
    # The target year is the last 4 characters and should always follow after "06/"
    targetYear=${extensionValue#*06/}
fi

if [[ -d "/Applications/Self Service.app/" ]]; then
	urlScheme="jamfselfservice://"
elif [[ -d "/Applications/Self Service+.app/" ]]; then
	urlScheme="selfservicecapability://"
fi


if [[ $targetYear -ge $(($currentYear+3)) ]]; then
    # Mac can run the latest macOS version. No need to configure the Support.app replacement notice tile.
    # We shouldn't end up here if everything is working properly but we'll clear any extension_result just in case
    extension_result=""
    defaults write "${preference_file_location}" "${extension_id}" -string "$extension_result"

    # Stop spinning indicator
    defaults write "${preference_file_location}" "${extension_id}_loading" -bool false

    exit 0

elif [[ $targetYear -eq $(($currentYear+2)) ]]; then
    # Mac can run the latest macOS version. No need to configure the Support.app replacement notice tile.
    # We shouldn't end up here if everything is working properly but it's probably fine to show a target replacement date
    extension_result="Replace by 06/$targetYear"
    defaults write "${preference_file_location}" "${extension_id}" -string "$extension_result"

    # Stop spinning indicator
    defaults write "${preference_file_location}" "${extension_id}_loading" -bool false

    exit 0

    # Intentionally skipping over some of the options in the OnAppear script so that we don't have a click action for all possible outcomes. 
    # Click actions will only start about 18 months ahead of the replacement target date

elif [[ $targetYear -eq $(($currentYear+1)) ]]; then
#    extension_result="Recycle by 06/$targetYear"        # month and year when it needs to be out of service
    linkResource="${urlScheme}content?entity=policy&id=${next_summer_policy_id}&action=${policy_action}"

elif [[ $targetYear -eq $currentYear ]] && [[ $currentMonth -le 6 ]]; then
    # Show alert on tile
    defaults write "${preference_file_location}" "${extension_id}_alert" -bool true
    # In June or earlier of the replacement year, the text says to recycle by the target date
#    extension_result="Recycle by 06/$targetYear"        # month and year when it needs to be out of service
    linkResource="${urlScheme}content?entity=policy&id=${this_summer_policy_id}&action=${policy_action}"

elif [[ $targetYear -eq $currentYear ]] && [[ $currentMonth -ge 7 ]]; then
    # Show alert on tile
    defaults write "${preference_file_location}" "${extension_id}_alert" -bool true
    # Beginning in July of the replacement year, the text changes to Overdue
#   extension_result="Overdue, 06/$targetYear"        # month and year when it needs to be out of service
    linkResource="${urlScheme}content?entity=policy&id=${overdue_policy_id}&action=${policy_action}"

elif [[ $targetYear -lt $currentYear ]]; then
    # Show alert on tile
    defaults write "${preference_file_location}" "${extension_id}_alert" -bool true
#    extension_result="Overdue, 06/$targetYear"  # month and year when it needs to be out of service
    linkResource="${urlScheme}content?entity=policy&id=${overdue_policy_id}&action=${policy_action}"

fi

# open the Self Service registration policy?
su "${loggedInUser}" -c "/usr/bin/open \"$linkResource\""

# Stop spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool false

exit