#!/bin/zsh

# Support.app extension description
# What does the extension accomplish



# Extension ID added for Support app 3.x config
extension_id="extension_id_here"
title="DEFAULT_TITLE_HERE"      ## REQUIRES Support App 3.0.4+

# Support App preference plist
preference_file_location="/Library/Preferences/nl.root3.support.plist"

# Start spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool true

# Replace value with placeholder while loading
defaults write "${preference_file_location}" "${extension_id}" -string "placeholder-text"

# Reset title
defaults write "${preference_file_location}" "${extension_id}_title" -string "$title"

# Keep loading effect active specified time
sleep 0.25      # This is a personal preference. .25 to .5 is a good range, but adjust to your liking.


# GET CREATIVE. DEFINE AND SOLVE A PROBLEM.

# AS PART OF SOLVING THE PROBLEM, DETERMINE THE FOLLOWING
extension_status=""     # Text you want displayed on the tile beneath the extension title. 
                        # You have 22-24 characters across 2 lines.
                        # It's important to account for all outcomes

# DETERMINE ANY OR NONE OF THE FOLLOWING. THESE ARE OPTIONAL.
# Using these can avoid the need for a click or action script.
# https://github.com/root3nl/SupportApp/wiki/Extensions
action_type=""      # App | URL | Command | PrivilegedScript
action=""           # bundleID | URL to open | command run as user | command or script run with privileges
symbol=""           # Any SF Symbol string. https://developer.apple.com/sf-symbols/
title=""            # Adjust the extension title if desired. REQUIRES Support App 3.0.4+
alert_status=""     # true | false


# Action Types: App, URL, User Command, Privileged Script
defaults write "${preference_file_location}" "${extension_id}_action_type" -string "$action_type"

# Action: bundle ID of app to open, URL to open, or command to run when the tile is clicked.
defaults write "${preference_file_location}" "${extension_id}_action" -string "$action"

# Symbol: Any SF Symbol string
defaults write "${preference_file_location}" "${extension_id}_symbol" -string "$symbol"

# Set extension title. REQUIRES Support App 3.0.4+
defaults write "${preference_file_location}" "${extension_id}_title" -string "$title"

# Set or unset the alert badge
defaults write "${preference_file_location}" "${extension_id}_alert" -bool "$alert_status"

# Write Corp Network Status to Support App preference plist
defaults write "${preference_file_location}" "${extension_id}" -string "$extension_status"

# Stop spinning indicator
defaults write "${preference_file_location}" "${extension_id}_loading" -bool false

exit