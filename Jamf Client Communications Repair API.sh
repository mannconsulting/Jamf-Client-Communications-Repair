#!/bin/zsh
###############################################################################
# Name:     Jamf Client Communications Repair API
# Creator:  Mann Consulting
# Summary:  Repairs broken Jamf communications
##
# Documentation: https://mann.com/docs
#
# Note:     This script is part of Mann Consulting's Jamf Pro Workflows Subscription.
#           Mann Consulting is not responsible for data loss or other damages caused by use of these documents.
#           if you woud like support sign up at https://mann.com/jamf or email support@mann.com for more details.
################################################################################
echo -n "Please enter your Jamf Pro server URL (i.e. https://company.jamfcloud.com/) : "
read jamfpro_url
echo -n "Please enter your Jamf Pro user account : "
read jamfpro_user
echo -n "Please enter the password for the $jamfpro_user account: "
read -s jamfpro_password
echo

jamfpro_url=${jamfpro_url%%/}
fulltoken=$(curl -s -X POST -u "${jamfpro_user}:${jamfpro_password}" "${jamfpro_url}/api/v1/auth/token")
authorizationToken=$(plutil -extract token raw - <<< "$fulltoken" )

mdmComputerGroup=$(curl -s -X GET "$jamfpro_url/JSSResource/computergroups/name/Jamf%20Client%20Communications%20Repair%20MDM%20%3D%20Needed" -H "accept: application/xml" -H "Authorization: Bearer $authorizationToken" | xmllint --format -| grep -m1 id | cut -d '>' -f2 | cut -d '<' -f1)
binaryComputerGroup=$(curl -s -X GET "$jamfpro_url/JSSResource/computergroups/name/Jamf%20Client%20Communications%20Repair%20Binary%20%3D%20Needed" -H "accept: application/xml" -H "Authorization: Bearer $authorizationToken" | xmllint --format -| grep -m1 id | cut -d '>' -f2 | cut -d '<' -f1)
echo "Recalculating Group Memberships..."
curl -s -X POST "$jamfpro_url/api/v1/smart-computer-groups/${binaryComputerGroup}/recalculate" -H "accept: application/json" -H "Authorization: Bearer $authorizationToken"
echo
curl -s -X POST "$jamfpro_url/api/v1/smart-computer-groups/${mdmComputerGroup}/recalculate" -H "accept: application/json" -H "Authorization: Bearer $authorizationToken"
echo
binaryComputers=($(curl -s -X GET "$jamfpro_url/JSSResource/computergroups/id/$binaryComputerGroup" -H "accept: application/xml" -H "Authorization: Bearer $authorizationToken" | xmllint --format - | grep id | cut -d '>' -f 2 | cut -d '<' -f 1 | tail -n +3 | tr '\n' ' '))
mdmComputers=($(curl -s -X GET "$jamfpro_url/JSSResource/computergroups/id/$mdmComputerGroup" -H "accept: application/xml" -H "Authorization: Bearer $authorizationToken" | xmllint --format - | grep id | cut -d '>' -f 2 | cut -d '<' -f 1 | tail -n +3 | tr '\n' ' '))

if [[ ${#mdmComputers[@]} -gt 0 ]]; then
  echo "Flushing pending MDM commands for MDM Repair..."
  curl -s -X DELETE "$jamfpro_url/JSSResource/commandflush/computergroups/id/$mdmComputerGroup/status/Pending+Failed" -H "accept: application/xml" -H "Authorization: Bearer $authorizationToken"
  echo
else
  echo "No computers need MDM flushed"
fi

if [[ ${#binaryComputers[@]} -eq 0 ]]; then
  echo "No computers need a redeploy"
  exit
fi

echo "Flushing pending MDM commands for Binary Repair..."
curl -s -X DELETE "$jamfpro_url/JSSResource/commandflush/computergroups/id/$binaryComputerGroup/status/Pending+Failed" -H "accept: application/xml" -H "Authorization: Bearer $authorizationToken"
echo
for i in $binaryComputers; do
  echo "Reinstalling Framework for Computer ID $i"
  echo -n
  curl -X POST "$jamfpro_url/api/v1/jamf-management-framework/redeploy/$i" -H "accept: application/json" -H "Authorization: Bearer $authorizationToken"
  echo
  sleep 1
done