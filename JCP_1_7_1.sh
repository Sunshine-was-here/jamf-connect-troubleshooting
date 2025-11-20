#!/bin/bash
# Jamf Connect Troubleshooting Script
# Version: 1.7.1
# Last Updated: 11/18/2025
# Author: Ellie Romero
# Email: ellie.romero@jamf.com
#
# High-level features:
#   1.  Check App Status (JCMB/JCLW, LaunchAgent, PAM, Daemon, Login Window, Kerberos)
#   2.  Validate License (status, expiration, days remaining, grace period)
#   3.  View Configured Profile Keys (Menu Bar, Login Window, authchanger)
#   4.  Restart Jamf Connect
#   5.  Modify Login Window Settings (enable/disable)
#   6.  View Authorization Database (mechanisms summary or full)
#   7.  Collect Historical Debug Logs (Official/Manual/Live streaming)
#   8.  Documentation & Resources (Jamf docs, support portal, community, error codes, GitHub)
#   9.  Check Local Network Permission (TCC diagnostics)
#   10. Kerberos Troubleshooting (Advanced diagnostics)
#   11. Privilege Elevation Control (CLI management)
#   12. Update Jamf Connect (download & install latest)
#   13. Uninstall Jamf Connect (complete removal)
#   14. Comprehensive User Analysis (JC migration, MDM status, mobile accounts, AD demobilization)
#   15. Exit

##############################################################################
# Global Colors
##############################################################################

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
purple='\033[0;35m'
cyan='\033[0;36m'
nc='\033[0m' # no color

##############################################################################
# Script Metadata / Globals
##############################################################################

readonly SCRIPT_VERSION="1.7.1"
readonly MIN_OS_VERSION="13.0"
DEBUG_MODE=0

readonly JAMF_CONNECT_APP="/Applications/Jamf Connect.app"
readonly SSP_APP="/Applications/Self Service+.app"
readonly AUTHCHANGER_BIN="/usr/local/bin/authchanger"
readonly PAM_MODULE="/usr/local/lib/pam/pam_saml.so.2"

# Managed preference plists
readonly MENU_PLIST_DEF="/Library/Managed Preferences/com.jamf.connect.plist"
readonly LOGIN_PLIST_DEF="/Library/Managed Preferences/com.jamf.connect.login.plist"
readonly AUTHCHANGER_PLIST_DEF="/Library/Managed Preferences/com.jamf.connect.authchanger.plist"

# LaunchAgent/Daemon paths
readonly JC_LAUNCHAGENT="/Library/LaunchAgents/com.jamf.connect.plist"
readonly JC_DAEMON_CLASSIC="/Library/LaunchDaemons/com.jamf.connect.daemon.plist"
readonly JC_DAEMON_SSP="/Library/LaunchDaemons/com.jamf.connect.daemon.ssp.plist"

# Privilege Elevation logs
readonly PRIVILEGE_LOG="/Library/Logs/JamfConnect/UserElevationReasons.log"

# Log directory base
LOG_BASE="/tmp"
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"

# URLs
readonly JAMF_ACCOUNT_URL="https://account.jamf.com/"

##############################################################################
# Jamf Connect Classic vs SSP Threshold + Helpers
##############################################################################

readonly THRESHOLD="2.45.1"  # Classic cutoff - versions above this are SSP/Stand-alone

version_gt() {
  # Returns true (0) if $1 > $2 using semantic version comparison
  local v1="$1" v2="$2"
  [ -z "$v1" ] && return 1
  if [ "$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -n1)" != "$v1" ]; then
    return 0
  else
    return 1
  fi
}

get_ver() {
  # Safely read CFBundleShortVersionString from a plist if it exists
  local plist="$1"
  if [ -f "$plist" ]; then
    /usr/bin/defaults read "$plist" CFBundleShortVersionString 2>/dev/null
  fi
}

classify_jcmb() {
  # Classify Jamf Connect Menu Bar as SSP vs Classic using THRESHOLD
  # Versions > 2.45.1 are SSP
  local v="$1"
  if version_gt "$v" "$THRESHOLD"; then
    echo "SSP"
  else
    echo "Classic"
  fi
}

classify_jclw() {
  # Classify Jamf Connect Login Window as Stand-alone vs Classic using THRESHOLD
  # Versions > 2.45.1 are Stand-alone
  local v="$1"
  if version_gt "$v" "$THRESHOLD"; then
    echo "Stand-alone"
  else
    echo "Classic"
  fi
}

##############################################################################
# Jamf Connect App / JCMB / JCLW Paths
##############################################################################

# Menu Bar (JCMB)
# JC 3.0+ menu bar is embedded within Self Service+
readonly SSP_MB_PLIST="/Applications/Self Service+.app/Contents/MacOS/Jamf Connect.app/Contents/Info.plist"
# JC 2.x classic menu bar
readonly LEGACY_MB_PLIST="/Applications/Jamf Connect.app/Contents/Info.plist"

# Login Window (JCLW)
# JC 3.0+ uses dedicated bundle
readonly JCLW_BUNDLE_PLIST="/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle/Contents/Info.plist"
# JC 2.x can also provide version info from the main app
readonly LEGACY_JC_PLIST="/Applications/Jamf Connect.app/Contents/Info.plist"

##############################################################################
# JCMB / JCLW Detection Helpers
##############################################################################

detect_jcmb_status() {
  local ssp_ver legacy_raw classic_ver ssp_legacy_ver jcmb_primary_type jcmb_primary_ver output

  # SSP-hosted Jamf Connect Menu Bar (JC 3.0+) at proper SSP path
  ssp_ver="$(get_ver "$SSP_MB_PLIST")"

  # Legacy Jamf Connect.app path - could be Classic OR SSP
  legacy_raw="$(get_ver "$LEGACY_MB_PLIST")"
  classic_ver=""
  ssp_legacy_ver=""
  
  if [ -n "$legacy_raw" ]; then
    if ! version_gt "$legacy_raw" "$THRESHOLD"; then
      # Version <= 2.45.1 = Classic JCMB
      classic_ver="$legacy_raw"
    else
      # Version > 2.45.1 at legacy path = SSP menu bar (at legacy location)
      ssp_legacy_ver="$legacy_raw"
    fi
  fi

  # No JCMB installed
  if [ -z "$ssp_ver" ] && [ -z "$classic_ver" ] && [ -z "$ssp_legacy_ver" ]; then
    echo "JCMB: None detected"
    return
  fi

  # Determine primary JCMB
  # Priority: SSP at correct path > SSP at legacy path > Classic
  if [ -n "$ssp_ver" ]; then
    jcmb_primary_type="SSP"
    jcmb_primary_ver="$ssp_ver"
  elif [ -n "$ssp_legacy_ver" ]; then
    jcmb_primary_type="SSP"
    jcmb_primary_ver="$ssp_legacy_ver"
  else
    jcmb_primary_type="Classic"
    jcmb_primary_ver="$classic_ver"
  fi

  output="JCMB ${jcmb_primary_type} ${jcmb_primary_ver}"

  # Note if both SSP and Classic exist
  # Note if both SSP and Classic exist (only report Classic if truly Classic)
  if [ -n "$ssp_ver" ] && [ -n "$classic_ver" ]; then
    output="${output} (also found JCMB Classic ${classic_ver})"
  elif [ -n "$ssp_legacy_ver" ] && [ -n "$classic_ver" ]; then
    output="${output} (also found JCMB Classic ${classic_ver})"
  fi
  
  # Handle case where SSP exists at both locations
  # If same version at both: common/expected (symlink or post-install state), don't clutter output
  # If different versions: unusual, should note it
  if [ -n "$ssp_ver" ] && [ -n "$ssp_legacy_ver" ]; then
    if [ "$ssp_ver" != "$ssp_legacy_ver" ]; then
      output="${output} (also found JCMB SSP ${ssp_legacy_ver} at legacy path)"
    fi
    # If same version at both paths, don't report - it's expected/normal
  fi

  echo "$output"
}

detect_jclw_status() {
  local bundle_ver legacy_ver jclw_ver jclw_type

  # JC 3.0+ Stand-alone JCLW bundle - this is the authoritative source for JCLW version
  bundle_ver="$(get_ver "$JCLW_BUNDLE_PLIST")"
  
  # JC 2.x ONLY - can report version from main app
  # For JC 3.0+, the legacy path may contain SSP menu bar, NOT login window
  legacy_ver="$(get_ver "$LEGACY_JC_PLIST")"

  # No JCLW installed
  if [ -z "$bundle_ver" ] && [ -z "$legacy_ver" ]; then
    echo "JCLW: None detected"
    return
  fi

  # If bundle exists, use it as authoritative JCLW version
  # (JC 3.0+ has dedicated JCLW bundle separate from menu bar)
  if [ -n "$bundle_ver" ]; then
    jclw_ver="$bundle_ver"
    jclw_type="$(classify_jclw "$jclw_ver")"
    echo "JCLW ${jclw_type} ${jclw_ver}"
    return
  fi

  # If no bundle but legacy_ver exists, we're in JC 2.x territory
  # Only use legacy path if version is <= THRESHOLD (2.45.1)
  if [ -n "$legacy_ver" ]; then
    # Verify this is actually a login window version (not SSP menu bar)
    if ! version_gt "$legacy_ver" "$THRESHOLD"; then
      jclw_ver="$legacy_ver"
      jclw_type="$(classify_jclw "$jclw_ver")"
      echo "JCLW ${jclw_type} ${jclw_ver}"
    else
      # Version > 2.45.1 from legacy path = SSP menu bar, not JCLW
      echo "JCLW: None detected (found SSP menu bar at legacy path)"
    fi
    return
  fi
}

##############################################################################
# Generic Helpers
##############################################################################

version_lt() {
  # Returns true if $1 is less than $2 (macOS style)
  local greaterValue
  greaterValue=$(printf '%s\n' "$@" | sort -rV | head -n 1)
  [ "$greaterValue" != "$1" ]
}

days_between() {
  # days_between "YYYY-MM-DD" "YYYY-MM-DD"
  local start="$1" end="$2"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$start" "$end" << 'PYEOF'
import sys, datetime
s, e = sys.argv[1], sys.argv[2]
sd = datetime.date.fromisoformat(s)
ed = datetime.date.fromisoformat(e)
print((ed - sd).days)
PYEOF
  else
    # Fallback: use date -j -f
    local s_epoch e_epoch
    s_epoch=$(date -j -f "%Y-%m-%d" "$start" "+%s" 2>/dev/null || echo 0)
    e_epoch=$(date -j -f "%Y-%m-%d" "$end" "+%s" 2>/dev/null || echo 0)
    if [ "$s_epoch" -eq 0 ] || [ "$e_epoch" -eq 0 ]; then
      echo 0
    else
      echo $(( (e_epoch - s_epoch) / 86400 ))
    fi
  fi
}

sanitize_path_input() {
  # Validate user input for file paths - only allow safe characters
  local input="$1"
  if [[ -n "$input" ]] && [[ ! "$input" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
    echo ""
    return 1
  fi
  echo "$input"
}

##############################################################################
##############################################################################
# EA TEMPLATE ENHANCEMENTS - System Account Filtering
##############################################################################

# System accounts to exclude from user checks (customizable for your environment)
readonly SYSTEM_ACCOUNTS=("jamfManagement" "_mbsetupuser" "root" "daemon" "nobody")

##############################################################################
# EA TEMPLATE ENHANCEMENTS - Helper Functions
##############################################################################

is_system_account() {
  # Check if a user is a system/management account that should be excluded
  local user="$1"
  for sys_account in "${SYSTEM_ACCOUNTS[@]}"; do
    if [[ "$user" == "$sys_account" ]]; then
      return 0  # Is system account
    fi
  done
  return 1  # Not system account
}

check_jamf_connect_attributes() {
  # ENHANCED: Check ALL Jamf Connect attributes for comprehensive detection
  # Returns: 0 if user is JC user, 1 if not
  # Also sets global variables with attribute details
  local user="$1"
  
  # Check all possible JC attributes
  local network_user oidc_provider azure_user okta_user network_signin
  
  network_user=$(dscl . -read /Users/"$user" NetworkUser 2>/dev/null | grep "NetworkUser:" | awk '{print $2}')
  oidc_provider=$(dscl . -read /Users/"$user" OIDCProvider 2>/dev/null | grep "OIDCProvider:" | awk '{print $2}')
  azure_user=$(dscl . -read /Users/"$user" AzureUser 2>/dev/null | grep "AzureUser:" | awk '{print $2}')
  okta_user=$(dscl . -read /Users/"$user" OktaUser 2>/dev/null | grep "OktaUser:" | awk '{print $2}')
  network_signin=$(dscl . -read /Users/"$user" NetworkSignIn 2>/dev/null | grep "NetworkSignIn:" | awk '{print $2}')
  
  # Export findings for detailed reporting
  export JC_ATTR_NETWORK_USER="$network_user"
  export JC_ATTR_OIDC_PROVIDER="$oidc_provider"
  export JC_ATTR_AZURE_USER="$azure_user"
  export JC_ATTR_OKTA_USER="$okta_user"
  export JC_ATTR_NETWORK_SIGNIN="$network_signin"
  
  # User is a JC user if ANY of these attributes exist
  if [ -n "$network_user" ] || [ -n "$oidc_provider" ] || [ -n "$azure_user" ] || [ -n "$okta_user" ]; then
    return 0  # Is JC user
  else
    return 1  # Not JC user
  fi
}

get_user_aliases() {
  # Get all aliases for a user account (helpful for troubleshooting)
  local user="$1"
  local aliases
  
  aliases=$(dscl . read /Users/"$user" RecordName 2>/dev/null | tail -n +2 | tr '\n' ' ' | xargs)
  echo "$aliases"
}

check_mobile_account() {
  # Check if user is a mobile/network account (AD-bound) using OriginalNodeName
  local user="$1"
  local original_node
  
  original_node=$(dscl . -read /Users/"$user" OriginalNodeName 2>/dev/null | grep "OriginalNodeName:" | awk '{print $2}')
  
  if [ -n "$original_node" ]; then
    export MOBILE_ACCOUNT_NODE="$original_node"
    return 0  # Is mobile account
  else
    return 1  # Not mobile account
  fi
}

get_all_users_with_passwords() {
  # Get list of all users who have passwords (excludes service accounts)
  dscl . list /Users Password | awk '$2 != "*" {print $1}'
}

# Cleanup trap
##############################################################################

cleanup() {
  rm -f /tmp/JamfConnect.dmg 2>/dev/null
}

trap cleanup EXIT

##############################################################################
# Debug Flag
##############################################################################

if [[ "$1" == "--debug" || "$1" == "-d" ]]; then
  DEBUG_MODE=1
  set -x
fi

##############################################################################
# Root privilege check
##############################################################################

if [ "$EUID" -ne 0 ] && [[ "$1" != "--help" ]] && [[ "$1" != "-h" ]]; then
  echo -e "${red}This script requires root privileges for most functions.${nc}"
  echo -e "${yellow}Please run with: sudo $0${nc}"
  exit 1
fi

##############################################################################
# Pre-compute OS version status
##############################################################################

CURRENT_OS_VERSION="$(sw_vers -productVersion)"
if version_lt "$CURRENT_OS_VERSION" "$MIN_OS_VERSION"; then
  OS_STATUS_MSG="${yellow}Warning: macOS version ${CURRENT_OS_VERSION} is less than the minimum requirement of ${MIN_OS_VERSION}.${nc}"
else
  OS_STATUS_MSG="${green}macOS version ${CURRENT_OS_VERSION} meets the minimum requirement of ${MIN_OS_VERSION}.${nc}"
fi

##############################################################################
# Function 1: Check App Status
##############################################################################
fn_01_check_app_status() {
  echo -e "${purple}=== Function 1: Check App Status ===${nc}"
  echo "Checking for Jamf Connect and components."
  echo ""

  # 1. JCMB / Menu Bar (including SSP)
  local jcmb_status jclw_status
  jcmb_status="$(detect_jcmb_status)"
  jclw_status="$(detect_jclw_status)"

  echo "$jcmb_status"
  echo "$jclw_status"
  echo ""

  # 2. Self Service+ Integration Check (JC 3.0+)
  if [ -d "$SSP_APP" ]; then
    local ssp_ver
    ssp_ver=$(/usr/bin/defaults read "${SSP_APP}/Contents/Info" CFBundleShortVersionString 2>/dev/null)
    if [ -n "$ssp_ver" ]; then
      echo "Self Service+ is installed. Version: ${ssp_ver}"
      if [ -f "$MENU_PLIST_DEF" ]; then
        echo -e "  ${cyan}└─ Jamf Connect features integrated into Self Service+${nc}"
        echo -e "  ${cyan}└─ Classic menu bar app automatically removed (if SSP installed with JC profile)${nc}"
      fi
    fi
  fi
  echo ""

  # 3. Jamf Connect.app presence & version (classic path or JC 3.x)
  if [ -d "$JAMF_CONNECT_APP" ]; then
    local app_ver
    app_ver=$(/usr/bin/defaults read "${JAMF_CONNECT_APP}/Contents/Info" CFBundleShortVersionString 2>/dev/null)
    if [ -n "$app_ver" ]; then
      echo "Jamf Connect.app is present. Version: ${app_ver}"
      
      # Check if JC 3.x
      if version_gt "$app_ver" "3.0.0"; then
        echo -e "  ${cyan}└─ Note: JC 3.x Login is separate from menu bar${nc}"
      fi
    else
      echo "Jamf Connect.app is present but version could not be determined."
    fi
  else
    echo "Jamf Connect.app is NOT present in /Applications."
  fi
  echo ""

  # 4. PAM module check
  if [ -f "$PAM_MODULE" ]; then
    echo "PAM module (pam_saml.so.2) is present."
  else
    echo "PAM module (pam_saml.so.2) is NOT present."
  fi
  echo ""

  # 5. LaunchAgent check (PKG-installed)
  if [ -f "$JC_LAUNCHAGENT" ]; then
    echo "Jamf Connect LaunchAgent (PKG) is installed."
    if launchctl list | grep -q "com.jamf.connect"; then
      echo "  └─ Status: Running"
    else
      echo "  └─ Status: Not running"
    fi
  else
    echo "Jamf Connect LaunchAgent is NOT installed."
  fi
  echo ""

  # 6. Daemon check (Classic vs SSP)
  # JC 3.0+ uses daemon.ssp.plist, JC 2.x uses daemon.plist
  if [ -f "$JC_DAEMON_SSP" ]; then
    echo "Jamf Connect Daemon (SSP/JC 3.0+) is present."
    if launchctl list | grep -q "com.jamf.connect.daemon.ssp"; then
      echo "  └─ Status: Running"
    else
      echo "  └─ Status: Not running"
    fi
  elif [ -f "$JC_DAEMON_CLASSIC" ]; then
    echo "Jamf Connect Daemon (Classic/JC 2.x) is present."
    if launchctl list | grep -q "com.jamf.connect.daemon"; then
      echo "  └─ Status: Running"
    else
      echo "  └─ Status: Not running"
    fi
  else
    echo "Jamf Connect Daemon is NOT present."
  fi
  echo ""

  # 7. Login Window status via authchanger
  if [ -x "$AUTHCHANGER_BIN" ]; then
    local auth_output
    auth_output=$("$AUTHCHANGER_BIN" -print 2>&1)

    if echo "$auth_output" | grep -iq -- "-JamfConnect"; then
      echo "Login Window Status: Jamf Connect login window is ENABLED."
    else
      echo "Login Window Status: Jamf Connect login window is DISABLED."
    fi
  else
    echo "Login Window Status: authchanger tool not found at $AUTHCHANGER_BIN."
  fi
  echo ""

  # 8. Kerberos configuration check
  local realm
  realm=$(/usr/libexec/PlistBuddy -c "Print :Kerberos:Realm" "$MENU_PLIST_DEF" 2>/dev/null)

  if [ -n "$realm" ]; then
    echo "Kerberos realm configured: ${realm}"
    if klist &>/dev/null 2>&1; then
      local ticket_count
      ticket_count=$(klist 2>/dev/null | grep -c "krbtgt")
      echo "  └─ Status: Active tickets present (${ticket_count} ticket(s))"
    else
      echo "  └─ Status: No active tickets"
    fi
  else
    echo "Kerberos: Not configured"
  fi
  echo ""
}

##############################################################################
# Function 2: Validate License
##############################################################################
fn_02_validate_license() {
  echo -e "${purple}=== Function 2: Validate License ===${nc}"

  local plist="$MENU_PLIST_DEF"
  if [ ! -f "$plist" ]; then
    echo -e "${yellow}No Jamf Connect managed preferences found at ${plist}.${nc}"
    echo -e "${cyan}Note: Jamf Connect runs in trial mode without a license (30 days from release date).${nc}"
    echo ""
    return
  fi

  local license_encoded
  license_encoded=$(/usr/bin/defaults read "$plist" LicenseFile 2>/dev/null)

  if [ -z "$license_encoded" ]; then
    echo -e "${yellow}No LicenseFile key found in ${plist}.${nc}"
    echo -e "${cyan}Note: Jamf Connect is running in trial mode (30 days from release date).${nc}"
    echo ""
    return
  fi

  local license_decoded
  license_decoded=$(printf "%s" "$license_encoded" | /usr/bin/base64 --decode 2>/dev/null)
  if [ -z "$license_decoded" ]; then
    echo -e "${red}Failed to decode LicenseFile from ${plist}.${nc}"
    echo ""
    return
  fi

  # Validate XML structure
  if ! printf "%s" "$license_decoded" | /usr/bin/xmllint --noout - 2>/dev/null; then
    echo -e "${red}Invalid XML format in LicenseFile.${nc}"
    echo ""
    return
  fi

  # Extract fields from XML
  local issued email expires clients
  issued=$(printf "%s" "$license_decoded" | /usr/bin/xmllint --xpath 'string(//key[.="DateIssued"]/following-sibling::*[1])' - 2>/dev/null | sed 's/ .*$//')
  email=$(printf "%s" "$license_decoded" | /usr/bin/xmllint --xpath 'string(//key[.="Email"]/following-sibling::*[1])' - 2>/dev/null)
  expires=$(printf "%s" "$license_decoded" | /usr/bin/xmllint --xpath 'string(//key[.="ExpirationDate"]/following-sibling::*[1])' - 2>/dev/null | sed 's/ .*$//')
  clients=$(printf "%s" "$license_decoded" | /usr/bin/xmllint --xpath 'string(//key[.="NumberOfClients"]/following-sibling::*[1])' - 2>/dev/null)

  if [ -z "$expires" ]; then
    echo -e "${yellow}Jamf Connect License found, but expiration date could not be determined.${nc}"
    echo ""
    return
  fi

  local today days_remaining status_text status_color
  today="$(date +%Y-%m-%d)"
  days_remaining="$(days_between "$today" "$expires" 2>/dev/null || echo 0)"

  # Jamf Connect 2.43+ includes 14-day grace period
  if [ "$days_remaining" -ge 0 ]; then
    status_text="Active"
    status_color="$green"
  elif [ "$days_remaining" -ge -14 ]; then
    status_text="Grace Period"
    status_color="$yellow"
  else
    status_text="Expired"
    status_color="$red"
  fi

  echo "Jamf Connect License found."
  echo -e "Status: ${status_color}${status_text}${nc}"
  echo "Issued On: ${issued}"
  echo "Licensed To: ${email}"
  echo "Expires On: ${expires}"
  echo "Client Limit: ${clients}"
  echo "Days Remaining: ${days_remaining}"
  echo ""

  if [ "$status_text" = "Grace Period" ]; then
    echo -e "${yellow}License is in 14-day grace period (requires Jamf Connect 2.43+).${nc}"
    echo "Please renew your license soon to avoid service interruption."
    echo "Jamf Account URL: ${JAMF_ACCOUNT_URL}"
    echo ""
  elif [ "$status_text" = "Expired" ]; then
    echo -e "${red}License has expired beyond the grace period.${nc}"
    echo -e "${yellow}For assistance, log in to Jamf Account with your Jamf ID and click 'Get Help ?' in the top-right corner.${nc}"
    echo "Jamf Account URL: ${JAMF_ACCOUNT_URL}"
    echo ""
  fi
}

##############################################################################
# Function 3: View Configured Profile Keys
##############################################################################

jc_detect_menu_idp() {
  local plist="$MENU_PLIST_DEF"
  if [ ! -f "$plist" ]; then
    echo ""
    return
  fi
  /usr/libexec/PlistBuddy -c "Print :IdPSettings:Provider" "$plist" 2>/dev/null
}

jc_detect_login_idp() {
  local plist="$LOGIN_PLIST_DEF"
  if [ ! -f "$plist" ]; then
    echo ""
    return
  fi
  /usr/bin/defaults read "$plist" OIDCProvider 2>/dev/null
}

jc_min_menu_keys_for_idp() {
  local idp="$1"
  case "$idp" in
    Microsoft|Entra|EntraID)
      echo "Provider ROPGID TenantID"
      ;;
    Google|GoogleID)
      echo "Provider"
      ;;
    IBM|IBMCI)
      echo "Provider ROPGID TenantID"
      ;;
    Okta)
      echo "Provider OktaAuthServer"
      ;;
    OktaIdentityEngine)
      echo "Provider TenantID OIDCClientID ROPGID"
      ;;
    "Okta OpenID Connect"|Okta-OIDC)
      echo "Provider TenantID ROPGID"
      ;;
    OneLogin)
      echo "Provider ROPGID TenantID SuccessCodes"
      ;;
    PingFederate|Custom)
      echo "Provider ROPGID DiscoveryURL"
      ;;
    *)
      echo "Provider ROPGID TenantID"
      ;;
  esac
}

jc_min_login_keys_for_idp() {
  local idp="$1"
  case "$idp" in
    Microsoft|Entra|EntraID)
      echo "OIDCProvider OIDCClientID OIDCRedirectURI OIDCTenant OIDCROPGID"
      ;;
    Google|GoogleID)
      echo "OIDCProvider OIDCClientID OIDCClientSecret OIDCRedirectURI"
      ;;
    IBM|IBMCI)
      echo "OIDCProvider OIDCClientID OIDCTenant OIDCRedirectURI OIDCROPGID"
      ;;
    Okta)
      echo "OIDCProvider AuthServer"
      ;;
    OktaIdentityEngine)
      echo "OIDCTenant OIDCClientID"
      ;;
    "Okta OpenID Connect"|Okta-OIDC)
      echo "OIDCProvider OIDCClientID OIDCTenant OIDCROPGID"
      ;;
    OneLogin)
      echo "OIDCProvider OIDCClientID OIDCTenant ROPGSuccessCodes OIDCRedirectURI OIDCROPGID"
      ;;
    PingFederate)
      echo "OIDCProvider OIDCClientID OIDCDiscoveryURL OIDCRedirectURI OIDCROPGID"
      ;;
    Custom)
      echo "OIDCProvider OIDCClientID OIDCRedirectURI OIDCDiscoveryURL OIDCROPGID"
      ;;
    *)
      echo "OIDCProvider OIDCClientID OIDCTenant OIDCROPGID"
      ;;
  esac
}

fn_03_view_configured_profile_keys() {
  echo -e "${purple}=== Function 3: View Configured Profile Keys ===${nc}"
  echo "Which profile configuration would you like to view?"
  echo "  1. Menu Bar"
  echo "  2. Login Window"
  echo "  3. authchanger Configuration"
  echo "  4. Return to main menu"
  read -r -p "Select an option (1-4): " opt
  echo ""

  case "$opt" in
    1)
      if [ ! -f "$MENU_PLIST_DEF" ]; then
        echo -e "${yellow}No Menu Bar configuration found at ${MENU_PLIST_DEF}.${nc}"
        echo ""
        return
      fi
      echo "Menu Bar Configuration (Full):"
      if ! /usr/bin/defaults read "$MENU_PLIST_DEF" 2>/dev/null; then
        echo -e "${red}Unable to read Menu Bar plist at ${MENU_PLIST_DEF}${nc}"
        echo "This may indicate a permissions issue or corrupted file."
      fi
      echo ""

      local idp keys key value
      idp="$(jc_detect_menu_idp)"
      if [ -n "$idp" ]; then
        echo "Detected Identity Provider: ${idp}"
      else
        echo -e "${yellow}Detected Identity Provider: Unknown${nc}"
      fi

      echo ""
      echo "Minimum Authentication Settings:"
      keys="$(jc_min_menu_keys_for_idp "$idp")"
      for key in $keys; do
        if [[ "$key" == "Provider" || "$key" == "OktaAuthServer" || "$key" == "ROPGID" || "$key" == "TenantID" || "$key" == "SuccessCodes" || "$key" == "DiscoveryURL" ]]; then
          value=$(/usr/libexec/PlistBuddy -c "Print :IdPSettings:${key}" "$MENU_PLIST_DEF" 2>/dev/null)
        elif [[ "$key" == "OIDCClientID" ]]; then
          value=$(/usr/libexec/PlistBuddy -c "Print :IdPSettings:OIDCClientID" "$MENU_PLIST_DEF" 2>/dev/null)
        else
          value=$(/usr/bin/defaults read "$MENU_PLIST_DEF" "$key" 2>/dev/null)
        fi

        if [ -n "$value" ]; then
          echo -e "${green}${key}:${nc} Present (Value: ${value})"
        else
          echo -e "${red}${key}:${nc} Missing"
        fi
      done
      echo ""
      ;;
    2)
      if [ ! -f "$LOGIN_PLIST_DEF" ]; then
        echo -e "${yellow}No Login Window configuration found at ${LOGIN_PLIST_DEF}.${nc}"
        echo ""
        return
      fi
      echo "Login Window Configuration (Full):"
      if ! /usr/bin/defaults read "$LOGIN_PLIST_DEF" 2>/dev/null; then
        echo -e "${red}Unable to read Login Window plist at ${LOGIN_PLIST_DEF}${nc}"
        echo "This may indicate a permissions issue or corrupted file."
      fi
      echo ""

      local lidp lkeys lkey lvalue
      lidp="$(jc_detect_login_idp)"
      if [ -n "$lidp" ]; then
        echo "Detected Identity Provider: ${lidp}"
      else
        echo -e "${yellow}Detected Identity Provider: Unknown${nc}"
      fi

      echo ""
      echo "Minimum Authentication Settings:"
      lkeys="$(jc_min_login_keys_for_idp "$lidp")"
      for lkey in $lkeys; do
        lvalue=$(/usr/bin/defaults read "$LOGIN_PLIST_DEF" "$lkey" 2>/dev/null)
        if [ -n "$lvalue" ]; then
          echo -e "${green}${lkey}:${nc} Present (Value: ${lvalue})"
        else
          echo -e "${red}${lkey}:${nc} Missing"
        fi
      done
      echo ""
      ;;
    3)
      if [ ! -f "$AUTHCHANGER_PLIST_DEF" ]; then
        echo -e "${yellow}No authchanger configuration found at ${AUTHCHANGER_PLIST_DEF}.${nc}"
        echo -e "${cyan}Note: authchanger can be configured via command line or configuration profile.${nc}"
        echo ""
        return
      fi
      echo "authchanger Configuration:"
      /usr/bin/defaults read "$AUTHCHANGER_PLIST_DEF" 2>/dev/null || echo "Unable to read authchanger plist."
      echo ""
      ;;
    4)
      return
      ;;
    *)
      echo -e "${red}Invalid option. Returning to main menu.${nc}"
      echo ""
      ;;
  esac
}

##############################################################################
# Function 4: Restart Jamf Connect
##############################################################################
fn_04_restart_jamf_connect() {
  echo -e "${purple}=== Function 4: Restart Jamf Connect ===${nc}"
  read -r -p "Are you sure you want to restart Jamf Connect? (y/n): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${yellow}Restart cancelled. Returning to main menu.${nc}"
    echo ""
    return
  fi

  # Check for both classic and SSP installations
  local jc_exists=0
  if [ -d "$JAMF_CONNECT_APP" ]; then
    jc_exists=1
  fi
  
  if [ -d "$SSP_APP" ]; then
    # Check if SSP has JC embedded
    if [ -d "/Applications/Self Service+.app/Contents/MacOS/Jamf Connect.app" ]; then
      jc_exists=1
    fi
  fi

  if [ "$jc_exists" -eq 0 ]; then
    echo -e "${red}Jamf Connect not found.${nc}"
    echo ""
    return
  fi

  # Create symlink if needed (ensure /usr/local/bin exists)
  if [ ! -L "/usr/local/bin/jamfconnect" ] && [ -f "${JAMF_CONNECT_APP}/Contents/MacOS/jamfconnect_tool" ]; then
    mkdir -p "/usr/local/bin"
    ln -s -f "${JAMF_CONNECT_APP}/Contents/MacOS/jamfconnect_tool" "/usr/local/bin/jamfconnect"
  fi

  # Kill all Jamf Connect processes
  pkill 'Jamf Connect' 2>/dev/null || true
  sleep 3
  
  # Restart based on what's installed
  if [ -d "$JAMF_CONNECT_APP" ]; then
    open -a "Jamf Connect"
    echo -e "${green}Jamf Connect restarted.${nc}"
  elif [ -d "/Applications/Self Service+.app/Contents/MacOS/Jamf Connect.app" ]; then
    open -a "Self Service+"
    echo -e "${green}Self Service+ (with Jamf Connect) restarted.${nc}"
  fi
  echo ""
}

##############################################################################
# Function 5: Modify Login Window Settings
##############################################################################
fn_05_modify_login_window() {
  echo -e "${purple}=== Function 5: Modify Login Window Settings ===${nc}"

  if [ ! -x "$AUTHCHANGER_BIN" ]; then
    echo -e "${red}authchanger not found at ${AUTHCHANGER_BIN}.${nc}"
    echo ""
    return
  fi

  echo "   1. Enable Jamf Connect Login Window"
  echo "   2. Disable Jamf Connect Login Window (restore default macOS loginwindow)"
  echo "   3. Return to main menu"
  read -r -p "Select an option: " choice

  case "$choice" in
    1)
      if "$AUTHCHANGER_BIN" -reset -jamfconnect; then
        echo -e "${green}Jamf Connect Login Window has been enabled.${nc}"
      else
        echo -e "${red}Failed to enable Jamf Connect Login Window.${nc}"
      fi
      echo ""
      ;;
    2)
      if "$AUTHCHANGER_BIN" -reset; then
        echo -e "${green}Default macOS loginwindow has been restored.${nc}"
      else
        echo -e "${red}Failed to restore default macOS loginwindow.${nc}"
      fi
      echo ""
      ;;
    3)
      return
      ;;
    *)
      echo -e "${red}Invalid option.${nc}"
      echo ""
      ;;
  esac
}

##############################################################################
# Function 6: View Authorization Database
##############################################################################
fn_06_view_auth_db() {
  echo -e "${purple}=== Function 6: View Authorization Database ===${nc}"

  if [ ! -x "$AUTHCHANGER_BIN" ]; then
    echo -e "${red}authchanger not found at ${AUTHCHANGER_BIN}.${nc}"
    echo ""
    return
  fi

  local auth_output
  auth_output=$("$AUTHCHANGER_BIN" -print 2>&1)

  read -r -p "Would you like to view the Authorization Database? (S)ummary, (F)ull, or (N)o: " db_choice
  echo ""
  case "$db_choice" in
    [Ss]*)
      echo "Authorization Database Mechanisms Summary:"
      printf "%s\n" "$auth_output" | awk '
        /Entry[[:space:]]+system\.login\.console/ { in_block=1; next }
        /^Entry[[:space:]]+/ { in_block=0 }
        in_block && /mechanisms/ { in_mech=1; next }
        in_block && in_mech {
          if ($1 ~ /^[[:space:]]*$/) next
          if ($1 ~ /^shared$/ || $1 ~ /^created$/ || $1 ~ /^modified$/) in_mech=0
          else print
        }
      '
      echo ""
      ;;
    [Ff]*)
      echo "Full Authorization Database:"
      printf "%s\n" "$auth_output"
      echo ""
      ;;
    *)
      echo "Skipping Authorization Database view."
      echo ""
      ;;
  esac
}

##############################################################################
# Function 7: Collect Historical Debug Logs
##############################################################################

find_jamfconnect_command() {
  if [ -x "/usr/local/bin/jamfconnect" ]; then
    echo "/usr/local/bin/jamfconnect"
  elif [ -x "${JAMF_CONNECT_APP}/Contents/MacOS/jamfconnect_tool" ]; then
    echo "${JAMF_CONNECT_APP}/Contents/MacOS/jamfconnect_tool"
  else
    echo ""
  fi
}

fn_07_collect_logs() {
  echo -e "${purple}=== Function 7: Collect Historical Debug Logs ===${nc}"
  echo "Jamf Connect provides multiple log collection methods."
  echo ""
  echo "Choose collection method:"
  echo "  1. Use Official Jamf Connect Log Collection (Recommended - last 30 min)"
  echo "  2. Manual Historical Log Collection (Menu Bar - last 24h)"
  echo "  3. Manual Historical Log Collection (Login Window - last 24h)"
  echo "  4. Manual Historical Log Collection (All Components + State)"
  echo "  5. Stream Live Logs (Real-time monitoring)"
  echo "  6. Return to main menu"
  echo ""
  
  read -r -p "Select an option (1-6): " opt
  echo ""

  case "$opt" in
    1)
      local jamfconnect_cmd
      jamfconnect_cmd="$(find_jamfconnect_command)"
      
      if [ -z "$jamfconnect_cmd" ]; then
        echo -e "${red}jamfconnect command not found.${nc}"
        echo "Locations checked:"
        echo "  - /usr/local/bin/jamfconnect"
        echo "  - ${JAMF_CONNECT_APP}/Contents/MacOS/jamfconnect_tool"
        echo ""
        echo "Please ensure Jamf Connect is installed or run Function 4 to create the symlink."
        echo ""
        return
      fi
      
      echo "Collecting logs using official Jamf Connect command..."
      echo "This will collect logs from the past 30 minutes including:"
      echo "  - authchanger output"
      echo "  - Kerberos tickets (klist)"
      echo "  - All PLIST files from Jamf Connect subsystems"
      echo "  - User's ID token (when available)"
      echo "  - Installed version"
      echo ""
      
      if "$jamfconnect_cmd" logs; then
        echo -e "${green}Logs collected successfully!${nc}"
        echo "Default location: /Library/Application Support/JamfConnect/Logs"
        echo ""
        echo "Tip: Use 'jamfconnect help logs' for more options"
      else
        echo -e "${red}Failed to collect logs using jamfconnect command.${nc}"
      fi
      echo ""
      ;;
      
    2)
      echo "Capturing Jamf Connect Menu Bar Historical Logs (last 24h)..."
      read -r -p "Enter directory path to save logs (default: ${LOG_BASE}): " user_log_dir
      local validated_dir
      validated_dir="$(sanitize_path_input "$user_log_dir")"
      if [ -z "$validated_dir" ] && [ -n "$user_log_dir" ]; then
        echo -e "${red}Invalid directory path. Using default.${nc}"
        validated_dir="$LOG_BASE"
      fi
      local base_dir="${validated_dir:-$LOG_BASE}"
      local log_dir="${base_dir}/jamfconnect_logs_${TIMESTAMP}"
      mkdir -p "$log_dir"
      
      log show --style compact --predicate 'subsystem == "com.jamf.connect"' --debug --last "1d" > "${log_dir}/JamfConnect_MenuBar.log" 2>&1
      echo -e "${green}Logs saved to: ${log_dir}${nc}"
      echo ""
      ;;
      
    3)
      echo "Capturing Jamf Connect Login Window Historical Logs (last 24h)..."
      read -r -p "Enter directory path to save logs (default: ${LOG_BASE}): " user_log_dir
      local validated_dir
      validated_dir="$(sanitize_path_input "$user_log_dir")"
      if [ -z "$validated_dir" ] && [ -n "$user_log_dir" ]; then
        echo -e "${red}Invalid directory path. Using default.${nc}"
        validated_dir="$LOG_BASE"
      fi
      local base_dir="${validated_dir:-$LOG_BASE}"
      local log_dir="${base_dir}/jamfconnect_logs_${TIMESTAMP}"
      mkdir -p "$log_dir"
      
      log show --style compact --predicate 'subsystem == "com.jamf.connect.login"' --debug --last "1d" > "${log_dir}/JamfConnect_LoginWindow.log" 2>&1
      echo -e "${green}Logs saved to: ${log_dir}${nc}"
      echo ""
      ;;
      
    4)
      echo "Capturing ALL Jamf Connect logs and related state..."
      read -r -p "Enter directory path to save logs (default: ${LOG_BASE}): " user_log_dir
      local validated_dir
      validated_dir="$(sanitize_path_input "$user_log_dir")"
      if [ -z "$validated_dir" ] && [ -n "$user_log_dir" ]; then
        echo -e "${red}Invalid directory path. Using default.${nc}"
        validated_dir="$LOG_BASE"
      fi
      local base_dir="${validated_dir:-$LOG_BASE}"
      local log_dir="${base_dir}/jamfconnect_logs_${TIMESTAMP}"
      mkdir -p "$log_dir"
      
      echo "Collecting comprehensive logs..."
      
      # Menu Bar
      log show --style compact --predicate 'subsystem == "com.jamf.connect"' --debug --last "1d" > "${log_dir}/JamfConnect_MenuBar.log" 2>&1
      
      # Login Window
      log show --style compact --predicate 'subsystem == "com.jamf.connect.login"' --debug --last "1d" > "${log_dir}/JamfConnect_LoginWindow.log" 2>&1
      
      # jamf_login.log (most recent logs)
      if [ -f "/private/tmp/jamf_login.log" ]; then
        cp "/private/tmp/jamf_login.log" "${log_dir}/"
        echo "  ✓ Copied jamf_login.log (most recent logs)"
      fi
      
      # Privilege Elevation Logs - use BOTH subsystems
      log show --style compact --predicate '((subsystem == "com.jamf.connect.daemon") OR (subsystem == "com.jamf.connect")) && (category == "PrivilegeElevation")' --debug --last "1h" > "${log_dir}/PrivilegeElevation_Combined.log" 2>&1
      
      # User Elevation Reasons log file
      if [ -f "$PRIVILEGE_LOG" ]; then
        cp "$PRIVILEGE_LOG" "${log_dir}/"
        echo "  ✓ Copied User Elevation Reasons log"
      fi
      
      # Heimdal (Kerberos) logs
      log show --style compact --predicate 'subsystem == "com.apple.Heimdal"' --debug --last "1h" > "${log_dir}/Heimdal_Kerberos.log" 2>&1
      echo "  ✓ Captured Heimdal/Kerberos logs"
      
      # Current Kerberos tickets
      if klist &>/dev/null; then
        klist > "${log_dir}/klist_current.txt" 2>&1
        echo "  ✓ Captured current Kerberos tickets"
      else
        echo "No Kerberos tickets" > "${log_dir}/klist_current.txt"
      fi
      
      # User-specific files
      local consoleUser homePath statePlist
      consoleUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
      if [ -n "$consoleUser" ]; then
        homePath=$(dscl . -read "/Users/${consoleUser}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
        if [ -n "$homePath" ]; then
          # State plist
          statePlist="${homePath}/Library/Preferences/com.jamf.connect.state.plist"
          if [ -f "$statePlist" ]; then
            cp "$statePlist" "${log_dir}/"
            echo "  ✓ Copied com.jamf.connect.state.plist"
          fi
          
          # User Promotion Count
          local promo_count
          promo_count=$(defaults read "${homePath}/Library/Preferences/com.jamf.connect.plist" UserPromotionCount 2>/dev/null)
          if [ -n "$promo_count" ]; then
            echo "User ${consoleUser} Promotion Count: ${promo_count}" > "${log_dir}/UserPromotionCount.txt"
            echo "  ✓ Captured User Promotion Count: ${promo_count}"
          fi
          
          # Offline MFA configuration
          if defaults read "${homePath}/Library/Preferences/com.jamf.connect.plist" OfflineMFA &>/dev/null; then
            echo "Offline MFA Status:" > "${log_dir}/OfflineMFA_Status.txt"
            defaults read "${homePath}/Library/Preferences/com.jamf.connect.plist" OfflineMFA >> "${log_dir}/OfflineMFA_Status.txt" 2>&1
            echo "  ✓ Captured Offline MFA configuration"
          fi
          
          # Kerberos configuration and shortnames
          {
            echo "=== Kerberos Configuration ==="
            defaults read "$MENU_PLIST_DEF" Kerberos 2>&1
            echo ""
            echo "=== User Shortnames ==="
            defaults read "${statePlist}" UserShortName 2>&1
            defaults read "${statePlist}" CustomShortName 2>&1
          } > "${log_dir}/Kerberos_Info.txt"
          echo "  ✓ Captured Kerberos configuration"
        else
          echo -e "  ${yellow}⚠ Unable to determine home directory for user ${consoleUser}${nc}"
        fi
      else
        echo -e "  ${yellow}⚠ No console user detected. Skipping user-specific files.${nc}"
      fi
      
      # authchanger print
      if [ -x "$AUTHCHANGER_BIN" ]; then
        "$AUTHCHANGER_BIN" -print > "${log_dir}/authchanger_print.txt" 2>&1
        echo "  ✓ Captured authchanger database"
      fi
      
      # profiles
      profiles -C -o stdout > "${log_dir}/profiles_stdout.txt" 2>&1
      echo "  ✓ Captured installed profiles"
      
      echo ""
      echo -e "${green}Comprehensive logs saved to: ${log_dir}${nc}"
      echo ""
      ;;
      
    5)
      echo -e "${cyan}=== Live Log Streaming (Press Ctrl-C to stop) ===${nc}"
      echo ""
      echo "Which subsystem would you like to stream?"
      echo "  1. Menu Bar (com.jamf.connect)"
      echo "  2. Login Window (com.jamf.connect.login)"
      echo "  3. All Jamf Connect subsystems"
      echo "  4. Kerberos (Heimdal)"
      echo "  5. Privilege Elevation"
      read -r -p "Select an option (1-5): " stream_opt
      echo ""
      
      case "$stream_opt" in
        1)
          echo "Streaming Menu Bar logs (Ctrl-C to stop)..."
          log stream --style compact --predicate 'subsystem == "com.jamf.connect"' --debug
          ;;
        2)
          echo "Streaming Login Window logs (Ctrl-C to stop)..."
          log stream --style compact --predicate 'subsystem == "com.jamf.connect.login"' --debug
          ;;
        3)
          echo "Streaming all Jamf Connect logs (Ctrl-C to stop)..."
          log stream --style compact --predicate 'subsystem CONTAINS "com.jamf.connect"' --debug
          ;;
        4)
          echo "Streaming Kerberos/Heimdal logs (Ctrl-C to stop)..."
          log stream --style compact --predicate 'subsystem == "com.apple.Heimdal"' --debug
          ;;
        5)
          echo "Streaming Privilege Elevation logs (Ctrl-C to stop)..."
          log stream --style compact --predicate '((subsystem == "com.jamf.connect.daemon") OR (subsystem == "com.jamf.connect")) && (category == "PrivilegeElevation")' --debug
          ;;
        *)
          echo -e "${red}Invalid option.${nc}"
          ;;
      esac
      echo ""
      ;;
      
    6)
      return
      ;;
      
    *)
      echo -e "${red}Invalid option.${nc}"
      echo ""
      ;;
  esac
}

##############################################################################
# Function 8: Documentation & Resources
##############################################################################
fn_08_documentation_and_resources() {
  echo -e "${purple}=== Function 8: Documentation & Resources ===${nc}"
  echo ""
  echo "Select a resource category to open:"
  echo ""
  echo -e "${cyan}Jamf Connect Documentation:${nc}"
  echo "  1. Jamf Connect Known Issues"
  echo "  2. Minimum Authentication Settings per IDP"
  echo "  3. Jamf Connect Login Window Settings"
  echo "  4. Jamf Connect Menu Bar Settings"
  echo ""
  echo -e "${cyan}Support:${nc}"
  echo "  5. Jamf Nation Community"
  echo "  6. Jamf Feature Request Portal"
  echo "  7. Jamf Support Portal"
  echo ""
  echo -e "${cyan}Other Resources:${nc}"
  echo "  8. Microsoft Entra Authentication & Authorization Error Codes (AADSTS)"
  echo "  9. Jamf Connect GitHub Repository"
  echo ""
  echo "  0. Open all documentation links"
  echo "  b. Go back to main menu"
  echo ""
  read -r -p "Enter your choice: " doc_choice
  echo ""
  
  case "$doc_choice" in
    1)
      echo "Opening Jamf Connect Known Issues..."
      open "https://learn.jamf.com/en-US/bundle/jamf-connect-release-notes/page/Known_Issues.html"
      ;;
    2)
      echo "Opening Minimum Authentication Settings per IDP..."
      open "https://learn.jamf.com/en-US/bundle/jamf-connect-documentation-current/page/Authentication_Settings.html"
      ;;
    3)
      echo "Opening Jamf Connect Login Window Settings..."
      open "https://learn.jamf.com/en-US/bundle/jamf-connect-documentation-current/page/Login_Window_Preferences.html"
      ;;
    4)
      echo "Opening Jamf Connect Menu Bar Settings..."
      open "https://learn.jamf.com/en-US/bundle/jamf-connect-documentation-current/page/Menu_Bar_App_Preferences.html"
      ;;
    5)
      echo "Opening Jamf Nation Community..."
      open "https://community.jamf.com/"
      ;;
    6)
      echo "Opening Jamf Feature Request Portal..."
      open "https://ideas.jamf.com"
      ;;
    7)
      echo "Opening Jamf Support Portal..."
      open "https://account.jamf.com"
      ;;
    8)
      echo "Opening Microsoft Entra Error Codes (AADSTS)..."
      open "https://learn.microsoft.com/en-us/entra/identity-platform/reference-error-codes"
      ;;
    9)
      echo "Opening Jamf Connect GitHub Repository..."
      open "https://github.com/jamf/jamfconnect"
      ;;
    0)
      echo "Opening all documentation links..."
      echo ""
      open "https://learn.jamf.com/en-US/bundle/jamf-connect-release-notes/page/Known_Issues.html"
      sleep 1
      open "https://learn.jamf.com/en-US/bundle/jamf-connect-documentation-current/page/Authentication_Settings.html"
      sleep 1
      open "https://learn.jamf.com/en-US/bundle/jamf-connect-documentation-current/page/Login_Window_Preferences.html"
      sleep 1
      open "https://learn.jamf.com/en-US/bundle/jamf-connect-documentation-current/page/Menu_Bar_App_Preferences.html"
      sleep 1
      open "https://community.jamf.com/"
      sleep 1
      open "https://ideas.jamf.com"
      sleep 1
      open "https://account.jamf.com"
      sleep 1
      open "https://learn.microsoft.com/en-us/entra/identity-platform/reference-error-codes"
      sleep 1
      open "https://github.com/jamf/jamfconnect"
      echo -e "${green}All documentation links opened!${nc}"
      ;;
    [Bb])
      echo -e "${yellow}Returning to menu...${nc}"
      echo ""
      return
      ;;
    *)
      echo -e "${red}Invalid option.${nc}"
      ;;
  esac
  
  echo ""
  read -r -p "Press Enter to continue..."
  echo ""
}

##############################################################################
# Function 9: Check Local Network Permission (TCC) - Enhanced
##############################################################################
fn_09_check_local_network_permission() {
  echo -e "${purple}=== Function 10: Local Network Permission Check ===${nc}"
  echo ""
  echo -e "${cyan}What is Local Network Permission?${nc}"
  echo "Starting in macOS 14 (Sonoma), apps need explicit permission to access"
  echo "local network resources. This is critical for Jamf Connect to communicate"
  echo "with on-premises resources like domain controllers or file servers."
  echo ""
  
  # Determine bundle ID
  local bundle_id
  if [ -d "$SSP_MB_PLIST" ]; then
    bundle_id=$(/usr/bin/defaults read "$SSP_MB_PLIST" CFBundleIdentifier 2>/dev/null)
  fi
  if [ -z "$bundle_id" ] && [ -d "$JAMF_CONNECT_APP" ]; then
    bundle_id=$(/usr/bin/defaults read "${JAMF_CONNECT_APP}/Contents/Info" CFBundleIdentifier 2>/dev/null)
  fi
  if [ -z "$bundle_id" ]; then
    bundle_id="com.jamf.connect"
  fi
  
  # Sanitize bundle_id
  bundle_id="${bundle_id//\'/}"

  echo -e "${yellow}Checking permission for: ${bundle_id}${nc}"
  echo ""

  # Find console user
  local console_user console_home
  console_user=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" \
    | /usr/bin/awk '/Name :/ && $3 != "loginwindow" { print $3 }')

  if [ -n "$console_user" ]; then
    console_home=$(/usr/bin/dscl . -read "/Users/${console_user}" NFSHomeDirectory 2>/dev/null \
      | /usr/bin/awk '{print $2}')
  fi

  local tcc_user_db=""
  local tcc_system_db="/Library/Application Support/com.apple.TCC/TCC.db"

  if [ -n "$console_home" ]; then
    tcc_user_db="${console_home}/Library/Application Support/com.apple.TCC/TCC.db"
  fi

  local service="kTCCServiceLocalNetwork"
  local user_status="Not Configured"
  local system_status="Not Configured"
  local tcc_access_error="0"
  local found_any_entry="0"
  local can_open_settings=false

  _jc_tcc_interpret_auth_value() {
    case "$1" in
      2) echo "Allowed" ;;
      0) echo "Denied" ;;
      *) echo "Unknown" ;;
    esac
  }

  _jc_tcc_check_db_for_bundle() {
    local db_path="$1"
    local is_user_db="$3"

    if [ ! -f "$db_path" ]; then
      return
    fi

    local schema has_allowed has_prompt has_auth_value
    schema=$(sqlite3 "$db_path" "PRAGMA table_info(access);" 2>&1)

    if [ -z "$schema" ] || echo "$schema" | grep -qi "error"; then
      if [ "$is_user_db" = "true" ]; then
        tcc_access_error="1"
      fi
      return
    fi

    has_allowed=$(echo "$schema" | awk -F'|' '$2=="allowed"{print "yes"}')
    has_prompt=$(echo "$schema" | awk -F'|' '$2=="prompt_count"{print "yes"}')
    has_auth_value=$(echo "$schema" | awk -F'|' '$2=="auth_value"{print "yes"}')

    local row status

    if [ "$has_auth_value" = "yes" ]; then
      row=$(sqlite3 "$db_path" \
        "SELECT auth_value, client_type, last_modified \
         FROM access \
         WHERE client='$bundle_id' AND service='$service' \
         ORDER BY client_type ASC, last_modified DESC \
         LIMIT 1;")

      if [ -z "$row" ]; then
        return
      fi

      found_any_entry="1"

      local auth_value _ _
      IFS='|' read -r auth_value _ _ <<< "$row"
      status=$(_jc_tcc_interpret_auth_value "$auth_value")

      if [ "$is_user_db" = "true" ]; then
        user_status="$status"
      else
        system_status="$status"
      fi

    elif [ "$has_allowed" = "yes" ]; then
      if [ "$has_prompt" = "yes" ]; then
        row=$(sqlite3 "$db_path" \
          "SELECT allowed, prompt_count \
           FROM access \
           WHERE client='$bundle_id' AND service='$service' \
           ORDER BY last_modified DESC \
           LIMIT 1;")
      else
        row=$(sqlite3 "$db_path" \
          "SELECT allowed \
           FROM access \
           WHERE client='$bundle_id' AND service='$service' \
           ORDER BY last_modified DESC \
           LIMIT 1;")
      fi

      if [ -z "$row" ]; then
        return
      fi

      found_any_entry="1"

      local allowed _
      if [ "$has_prompt" = "yes" ]; then
        IFS='|' read -r allowed _ <<< "$row"
      else
        allowed="$row"
      fi

      if [ "$allowed" = "1" ]; then
        status="Allowed"
      else
        status="Denied"
      fi

      if [ "$is_user_db" = "true" ]; then
        user_status="$status"
      else
        system_status="$status"
      fi
    fi
  }

  # Check both databases
  if [ -n "$console_user" ]; then
    _jc_tcc_check_db_for_bundle "$tcc_user_db" "User TCC DB" "true"
  fi
  _jc_tcc_check_db_for_bundle "$tcc_system_db" "System TCC DB" "false"

  # Determine overall status
  local overall_status final_status_color
  if [ "$tcc_access_error" = "1" ]; then
    overall_status="Unable to Check"
    final_status_color="${red}"
  elif [ "$found_any_entry" != "1" ]; then
    overall_status="Not Configured"
    final_status_color="${yellow}"
  elif [ "$user_status" = "Allowed" ] || [ "$system_status" = "Allowed" ]; then
    overall_status="Allowed"
    final_status_color="${green}"
    can_open_settings=true
  elif [ "$user_status" = "Denied" ] || [ "$system_status" = "Denied" ]; then
    overall_status="Denied"
    final_status_color="${red}"
    can_open_settings=true
  else
    overall_status="Unknown"
    final_status_color="${yellow}"
  fi

  # Display human-friendly results
  echo -e "${purple}╔═══════════════════════════════════════════════════════════╗${nc}"
  echo -e "${purple}║            LOCAL NETWORK PERMISSION STATUS               ║${nc}"
  echo -e "${purple}╚═══════════════════════════════════════════════════════════╝${nc}"
  echo ""
  
  if [ -n "$console_user" ]; then
    echo -e "${cyan}Current User:${nc} $console_user"
  fi
  echo -e "${cyan}App:${nc} Jamf Connect ($bundle_id)"
  echo ""
  
  echo -e "${cyan}Permission Status:${nc}"
  echo -e "  Overall: ${final_status_color}${overall_status}${nc}"
  
  if [ "$user_status" != "Not Configured" ]; then
    local user_color="${green}"
    [ "$user_status" = "Denied" ] && user_color="${red}"
    [ "$user_status" = "Unknown" ] && user_color="${yellow}"
    echo -e "  User Level: ${user_color}${user_status}${nc}"
  fi
  
  if [ "$system_status" != "Not Configured" ]; then
    local system_color="${green}"
    [ "$system_status" = "Denied" ] && system_color="${red}"
    [ "$system_status" = "Unknown" ] && system_color="${yellow}"
    echo -e "  System Level: ${system_color}${system_status}${nc}"
  fi
  echo ""

  # Provide context and recommendations
  case "$overall_status" in
    "Allowed")
      echo -e "${green}✓ Local Network Access is ENABLED${nc}"
      echo "Jamf Connect can communicate with local network resources."
      ;;
    "Denied")
      echo -e "${red}✗ Local Network Access is DENIED${nc}"
      echo ""
      echo -e "${yellow}Impact:${nc}"
      echo "  • Cannot reach on-premises domain controllers"
      echo "  • Network file shares may not work"
      echo "  • Kerberos authentication may fail"
      echo ""
      echo -e "${yellow}Action Required:${nc}"
      echo "  Enable Local Network permission in System Settings"
      ;;
    "Not Configured")
      echo -e "${yellow}⚠ Local Network Permission NOT CONFIGURED${nc}"
      echo ""
      echo "macOS will prompt the user when Jamf Connect first attempts"
      echo "to access local network resources."
      echo ""
      echo -e "${yellow}Recommendation:${nc}"
      echo "  Pre-approve via Configuration Profile (MDM) or manually enable"
      ;;
    "Unable to Check")
      echo -e "${red}✗ Unable to Check Permission Status${nc}"
      echo ""
      echo -e "${yellow}Reason:${nc}"
      echo "  This script lacks Full Disk Access to read TCC database"
      echo ""
      echo -e "${yellow}To Fix:${nc}"
      echo "  1. Open System Settings > Privacy & Security"
      echo "  2. Click Full Disk Access"
      echo "  3. Add Terminal (or this script's parent app)"
      echo "  4. Re-run this check"
      ;;
    *)
      echo -e "${yellow}⚠ Unknown Permission Status${nc}"
      ;;
  esac
  echo ""

  # Offer to open System Settings
  if [ "$can_open_settings" = true ] || [ "$overall_status" = "Denied" ] || [ "$overall_status" = "Not Configured" ]; then
    echo ""
    read -r -p "Would you like to open System Settings to manage this permission? (y/n/b to go back): " open_settings
    case "$open_settings" in
      [Yy])
        echo ""
        echo "Opening System Settings > Privacy & Security > Local Network..."
        echo ""
        
        # Try to open directly to Local Network settings
        # Note: Direct deep-linking may vary by macOS version
        if [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ]; then
          # macOS 13+ (Ventura and later)
          open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
        else
          # Older macOS
          open "x-apple.systempreferences:com.apple.preference.security"
        fi
        
        echo -e "${cyan}In System Settings:${nc}"
        echo "  1. Navigate to: Privacy & Security > Local Network"
        echo "  2. Find: Jamf Connect"
        echo "  3. Toggle: ON (enable)"
        echo ""
        echo "Press Enter after making changes to continue..."
        read -r
        ;;
      [Bb])
        echo -e "${yellow}Returning to menu...${nc}"
        echo ""
        return
        ;;
      *)
        echo ""
        ;;
    esac
  fi

  echo ""
  read -r -p "Press Enter to return to menu (or 'b' to go back): " return_choice
  if [[ ! "$return_choice" =~ ^[Bb]$ ]]; then
    echo ""
  fi
}

##############################################################################
# Function 10: Kerberos Troubleshooting (Advanced)
##############################################################################
fn_10_kerberos_troubleshooting() {
  echo -e "${purple}=== Function 10: Kerberos Troubleshooting ===${nc}"
  echo "Advanced Kerberos diagnostics for Jamf Connect"
  echo ""
  echo -e "${cyan}Kerberos is required for:${nc}"
  echo "  • Password expiration (except pure Okta with ExpirationManualOverrideDays)"
  echo "  • Network file shares"
  echo "  • User certificates"
  echo ""
  
  # Check if Kerberos is configured
  local realm
  realm=$(/usr/libexec/PlistBuddy -c "Print :Kerberos:Realm" "$MENU_PLIST_DEF" 2>/dev/null)
  
  if [ -z "$realm" ]; then
    echo -e "${yellow}No Kerberos realm configured in Jamf Connect.${nc}"
    echo "Kerberos configuration not found in: $MENU_PLIST_DEF"
    echo ""
    return
  fi
  
  echo "Detected Kerberos Realm: ${realm}"
  echo ""
  
  # Step 1: Check domain reachability
  echo -e "${cyan}Step 1: Checking domain reachability...${nc}"
  local ldap_servers
  ldap_servers=$(dig +short -t SRV "_ldap._tcp.${realm}" 2>/dev/null)
  
  if [ -z "$ldap_servers" ]; then
    echo -e "${red}✗ Cannot reach domain ${realm}${nc}"
    echo "  Possible causes:"
    echo "    - Not on VPN"
    echo "    - DNS misconfigured"
    echo "    - Network connectivity issues"
    echo ""
    return
  else
    echo -e "${green}✓ Domain ${realm} is reachable${nc}"
    echo "LDAP Servers:"
    echo "$ldap_servers" | head -n3
    echo ""
  fi
  
  # Step 2: Check for existing tickets
  echo -e "${cyan}Step 2: Checking for existing Kerberos tickets...${nc}"
  if ! klist &>/dev/null; then
    echo -e "${yellow}✗ No Kerberos tickets found${nc}"
    echo ""
    read -r -p "Would you like to attempt manual ticket acquisition? (y/n): " manual_kinit
    if [[ "$manual_kinit" =~ ^[Yy]$ ]]; then
      echo "Run: kinit"
      echo "Then retry this function"
    fi
    echo ""
    return
  else
    echo -e "${green}✓ Kerberos tickets found${nc}"
    klist
    echo ""
  fi
  
  # Step 3: Check com.jamf.connect.state plist
  echo -e "${cyan}Step 3: Checking com.jamf.connect.state plist...${nc}"
  local consoleUser homePath statePlist
  consoleUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
  
  if [ -z "$consoleUser" ]; then
    echo -e "${yellow}No console user detected${nc}"
    echo ""
    return
  fi
  
  homePath=$(dscl . -read "/Users/${consoleUser}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
  if [ -z "$homePath" ]; then
    echo -e "${yellow}Unable to determine home directory${nc}"
    echo ""
    return
  fi
  
  statePlist="${homePath}/Library/Preferences/com.jamf.connect.state.plist"
  if [ ! -f "$statePlist" ]; then
    echo -e "${red}✗ State plist not found at ${statePlist}${nc}"
    echo ""
    return
  fi
  
  echo -e "${green}✓ State plist found${nc}"
  echo ""
  
  # Extract shortnames from state plist
  local userShortName customShortName
  userShortName=$(defaults read "$statePlist" UserShortName 2>/dev/null)
  customShortName=$(defaults read "$statePlist" CustomShortName 2>/dev/null)
  
  echo "Shortname Information:"
  if [ -n "$userShortName" ]; then
    echo "  UserShortName: ${userShortName}"
  fi
  if [ -n "$customShortName" ]; then
    echo "  CustomShortName: ${customShortName}"
    echo -e "  ${cyan}(CustomShortName takes precedence)${nc}"
  fi
  echo ""
  
  # Step 4: Compare shortname from ticket vs state plist
  echo -e "${cyan}Step 4: Comparing Kerberos ticket principal with state plist...${nc}"
  local ticket_principal ticket_shortname ticket_realm
  ticket_principal=$(klist 2>/dev/null | grep "Principal:" | awk '{print $2}')
  ticket_shortname=$(echo "$ticket_principal" | cut -d'@' -f1)
  ticket_realm=$(echo "$ticket_principal" | cut -d'@' -f2)
  
  echo "From Kerberos Ticket:"
  echo "  Principal: ${ticket_principal}"
  echo "  Shortname: ${ticket_shortname}"
  echo "  Realm: ${ticket_realm}"
  echo ""
  
  # Determine which shortname JC will use
  local jc_shortname
  if [ -n "$customShortName" ]; then
    jc_shortname="$customShortName"
  elif [ -n "$userShortName" ]; then
    jc_shortname="$userShortName"
  else
    jc_shortname="Unknown"
  fi
  
  echo "Jamf Connect will use: ${jc_shortname}"
  echo ""
  
  # Validate match
  if [ "$ticket_shortname" = "$jc_shortname" ]; then
    echo -e "${green}✓ Shortnames MATCH - Kerberos should work${nc}"
  else
    echo -e "${red}✗ SHORTNAME MISMATCH DETECTED${nc}"
    echo ""
    echo -e "${yellow}Fix Required:${nc}"
    echo "The shortname in your Kerberos ticket (${ticket_shortname}) does not match"
    echo "what Jamf Connect is using (${jc_shortname})."
    echo ""
    echo "Solutions:"
    echo "  1. Add 'AskForShortName' key to Kerberos configuration"
    echo "  2. Set 'ShortName' key to: ${ticket_shortname}"
    echo "  3. Reset state plist:"
    echo "     defaults delete ${statePlist} CustomShortName"
    echo "     defaults delete ${statePlist} DisplayName"
    echo ""
  fi
  
  # Step 5: Check Kerberos configuration keys
  echo -e "${cyan}Step 5: Checking Kerberos configuration...${nc}"
  local kerb_keys=("Realm" "AutoRenewTickets" "CacheTicketsOnNetworkChange" "AskForShortName" "ShortName")
  
  for key in "${kerb_keys[@]}"; do
    local value
    value=$(/usr/libexec/PlistBuddy -c "Print :Kerberos:${key}" "$MENU_PLIST_DEF" 2>/dev/null)
    if [ -n "$value" ]; then
      echo -e "  ${green}${key}:${nc} ${value}"
    else
      echo -e "  ${yellow}${key}:${nc} Not configured"
    fi
  done
  echo ""
  
  # Step 6: Offer to test ticket acquisition
  echo -e "${cyan}Step 6: Test Jamf Connect ticket acquisition${nc}"
  read -r -p "Force Jamf Connect to fetch tickets? (y/n): " force_fetch
  if [[ "$force_fetch" =~ ^[Yy]$ ]]; then
    echo "Destroying existing tickets..."
    kdestroy 2>/dev/null
    
    echo "Triggering Jamf Connect ticket fetch..."
    open "jamfconnect://gettickets"
    
    sleep 3
    echo ""
    echo "Checking for new tickets..."
    if klist &>/dev/null; then
      echo -e "${green}✓ Tickets successfully acquired!${nc}"
      klist
    else
      echo -e "${red}✗ Failed to acquire tickets${nc}"
      echo ""
      echo "Troubleshooting steps:"
      echo "  1. Check Heimdal logs:"
      echo "     log stream --style compact --predicate 'subsystem == \"com.apple.Heimdal\"'"
      echo "  2. Check Jamf Connect logs:"
      echo "     log stream --style compact --predicate 'subsystem == \"com.jamf.connect\"'"
      echo "  3. Verify network connectivity to domain"
      echo "  4. Ensure Jamf Connect keychain item exists"
    fi
  fi
  
  echo ""
  echo -e "${cyan}Useful Commands:${nc}"
  echo "  kinit                          - Manually fetch Kerberos tickets"
  echo "  klist                          - List current Kerberos tickets"
  echo "  kdestroy                       - Destroy all Kerberos tickets"
  echo "  dig +short -t SRV _ldap._tcp.${realm} - Check LDAP servers"
  echo "  open jamfconnect://gettickets  - Force JC to fetch tickets"
  echo ""
}

##############################################################################
# Function 11: Privilege Elevation Control
##############################################################################
fn_11_privilege_elevation_control() {
  echo -e "${purple}=== Function 11: Privilege Elevation Control ===${nc}"
  echo "Control privilege elevation via command line"
  echo ""
  echo "  1. Elevate current user"
  echo "  2. Demote current user" 
  echo "  3. Check elevation status"
  echo "  4. View elevation logs"
  echo "  5. Return to main menu"
  read -r -p "Select an option: " choice
  
  case "$choice" in
    1)
      if ! command -v jamfconnect >/dev/null 2>&1; then
        echo -e "${red}jamfconnect command not found.${nc}"
        echo "Run Function 4 to create the symlink or ensure Jamf Connect is installed."
        echo ""
        return
      fi
      
      echo "Sending elevation request..."
      if jamfconnect acc-promo --elevate; then
        echo -e "${green}Elevation request sent successfully.${nc}"
        echo "Check Jamf Connect menu for authentication prompts."
      else
        echo -e "${red}Elevation failed. Check logs for details.${nc}"
      fi
      ;;
    2)
      if ! command -v jamfconnect >/dev/null 2>&1; then
        echo -e "${red}jamfconnect command not found.${nc}"
        echo ""
        return
      fi
      
      echo "Demoting user to standard..."
      if jamfconnect acc-promo --demote; then
        echo -e "${green}User demoted to standard successfully.${nc}"
      else
        echo -e "${red}Demotion failed.${nc}"
      fi
      ;;
    3)
      echo "Checking current elevation status..."
      echo ""
      
      # Check if user is admin
      local consoleUser
      consoleUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
      
      if [ -z "$consoleUser" ]; then
        echo "No console user detected."
        echo ""
        return
      fi
      
      if groups "$consoleUser" | grep -q '\badmin\b'; then
        echo -e "${green}User ${consoleUser} currently has ADMIN privileges${nc}"
      else
        echo -e "${yellow}User ${consoleUser} currently has STANDARD privileges${nc}"
      fi
      echo ""
      
      # Check promotion count
      local homePath promo_count
      homePath=$(dscl . -read "/Users/${consoleUser}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
      if [ -n "$homePath" ]; then
        promo_count=$(defaults read "${homePath}/Library/Preferences/com.jamf.connect.plist" UserPromotionCount 2>/dev/null)
        if [ -n "$promo_count" ]; then
          echo "Promotion count this month: ${promo_count}"
        fi
      fi
      ;;
    4)
      echo "Recent elevation events:"
      echo ""
      if [ -f "$PRIVILEGE_LOG" ]; then
        tail -n 20 "$PRIVILEGE_LOG"
      else
        echo "No elevation log found at $PRIVILEGE_LOG"
        echo ""
        echo "Checking unified logs for recent elevations..."
        log show --style compact --predicate '((subsystem == "com.jamf.connect.daemon") OR (subsystem == "com.jamf.connect")) && (category == "PrivilegeElevation")' --last "1h" 2>&1 | tail -n 20
      fi
      ;;
    5)
      return
      ;;
    *)
      echo -e "${red}Invalid option.${nc}"
      ;;
  esac
  echo ""
}

##############################################################################
# Function 12: Update Jamf Connect
##############################################################################
fn_12_update_jamf_connect() {
  echo -e "${purple}=== Function 12: Update Jamf Connect ===${nc}"
  read -r -p "This will download and install the latest Jamf Connect. Proceed? (y/n): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${yellow}Update cancelled. Returning to main menu.${nc}"
    echo ""
    return
  fi

  local dmg="/tmp/JamfConnect.dmg"
  echo "Downloading Jamf Connect DMG..."
  if ! curl -L "https://files.jamfconnect.com/JamfConnect.dmg" -o "$dmg"; then
    echo -e "${red}Failed to download JamfConnect.dmg.${nc}"
    echo ""
    return
  fi

  echo "Mounting DMG..."
  local mountpoint
  mountpoint=$(hdiutil attach -nobrowse -quiet "$dmg" | grep '/Volumes/' | awk -F'\t' '{print $3}' | head -n1)
  if [ -z "$mountpoint" ]; then
    echo -e "${red}Failed to mount JamfConnect.dmg.${nc}"
    rm -f "$dmg"
    echo ""
    return
  fi

  echo "Installing Jamf Connect package..."
  if ! /usr/sbin/installer -pkg "${mountpoint}/JamfConnect.pkg" -target / >/dev/null 2>&1; then
    echo -e "${red}Jamf Connect installation failed.${nc}"
    hdiutil detach "$mountpoint" -quiet
    rm -f "$dmg"
    echo ""
    return
  fi

  hdiutil detach "$mountpoint" -quiet
  rm -f "$dmg"

  # Verify installation (check both locations for JC 2.x and 3.x)
  local installed_ver=""
  if [ -d "$JAMF_CONNECT_APP" ]; then
    installed_ver=$(/usr/bin/defaults read "${JAMF_CONNECT_APP}/Contents/Info" CFBundleShortVersionString 2>/dev/null)
  elif [ -d "/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle" ]; then
    installed_ver=$(get_ver "$JCLW_BUNDLE_PLIST")
  fi
  
  if [ -n "$installed_ver" ]; then
    echo -e "${green}Jamf Connect ${installed_ver} installed successfully!${nc}"
  else
    echo -e "${yellow}Installation completed. Please verify Jamf Connect components.${nc}"
  fi
  echo ""
}

##############################################################################
# Function 14: Comprehensive User Analysis & MDM Status
##############################################################################
fn_14_comprehensive_user_analysis() {
  echo -e "${cyan}═══════════════════════════════════════════════════════════════${nc}"
  echo -e "${cyan}Comprehensive User Analysis & MDM Status${nc}"
  echo -e "${cyan}═══════════════════════════════════════════════════════════════${nc}"
  echo ""
  
  echo "This analysis provides:"
  echo "  • Jamf Connect migration status for all users"
  echo "  • Mobile account detection (AD demobilization readiness)"
  echo "  • MDM-managed user status for console user"
  echo "  • Multi-attribute detection (NetworkUser, Azure, Okta, OIDC)"
  echo ""
  
  # Part 1: Console User MDM Status Check
  echo -e "${purple}═══════════════════════════════════════════════════════════════${nc}"
  echo -e "${purple}PART 1: Console User MDM Status${nc}"
  echo -e "${purple}═══════════════════════════════════════════════════════════════${nc}"
  echo ""
  
  local consoleuser
  consoleuser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
  
  if [ -z "$consoleuser" ]; then
    echo -e "${yellow}No console user detected. Skipping MDM status check.${nc}"
  else
    echo -e "${green}Console User:${nc} $consoleuser"
    echo ""
    
    if command -v profiles >/dev/null 2>&1; then
      # Check MDM enrollment
      local enrollment_output
      enrollment_output=$(sudo -u "$consoleuser" profiles status -type enrollment 2>/dev/null)
      
      if [ -n "$enrollment_output" ]; then
        echo -e "${cyan}MDM Enrollment Status:${nc}"
        echo "$enrollment_output"
        echo ""
      fi
      
      # Check for user enrollment profile
      local user_enrollment
      user_enrollment=$(sudo -u "$consoleuser" profiles list -user "$consoleuser" 2>/dev/null | grep -i "enrollment" | head -1)
      
      if [ -n "$user_enrollment" ]; then
        echo -e "${green}✓ User has enrollment profile${nc}"
      else
        echo -e "${yellow}✗ No user enrollment profile found${nc}"
      fi
      echo ""
      
      # Check for MDM managed preferences
      local user_managed_prefs
      user_managed_prefs=$(sudo -u "$consoleuser" defaults domains 2>/dev/null | grep -c "com.apple.mdm")
      
      if [ "$user_managed_prefs" -gt 0 ]; then
        echo -e "${green}✓ User has MDM managed preferences${nc}"
      else
        echo -e "${yellow}✗ No MDM managed preferences found${nc}"
        echo -e "${yellow}  ⚠️  User-level profiles may not work with this account${nc}"
      fi
      echo ""
    else
      echo -e "${yellow}'profiles' command not available${nc}"
      echo ""
    fi
  fi
  
  # Part 2: All Users Analysis
  echo -e "${purple}═══════════════════════════════════════════════════════════════${nc}"
  echo -e "${purple}PART 2: All Users - Jamf Connect & Mobile Account Status${nc}"
  echo -e "${purple}═══════════════════════════════════════════════════════════════${nc}"
  echo ""
  
  local total_users=0
  local jc_users=0
  local unmigrated_users=0
  local mobile_users=0
  local jc_user_list=()
  local unmigrated_user_list=()
  local mobile_user_list=()
  
  echo -e "${yellow}Scanning user accounts...${nc}"
  echo ""
  
  while IFS= read -r user; do
    if is_system_account "$user"; then
      continue
    fi
    
    local uid
    uid=$(id -u "$user" 2>/dev/null)
    if [ -z "$uid" ] || [ "$uid" -lt 500 ]; then
      continue
    fi
    
    total_users=$((total_users + 1))
    
    # Check if mobile account
    local is_mobile=false
    if check_mobile_account "$user"; then
      is_mobile=true
      mobile_users=$((mobile_users + 1))
      mobile_user_list+=("$user")
    fi
    
    # Check if JC user
    if check_jamf_connect_attributes "$user"; then
      jc_users=$((jc_users + 1))
      jc_user_list+=("$user")
    else
      unmigrated_users=$((unmigrated_users + 1))
      unmigrated_user_list+=("$user")
    fi
  done < <(get_all_users_with_passwords)
  
  # Display Summary
  echo -e "${purple}╔═══════════════════════════════════════════════════════════╗${nc}"
  echo -e "${purple}║                    SUMMARY                                ║${nc}"
  echo -e "${purple}╚═══════════════════════════════════════════════════════════╝${nc}"
  echo ""
  echo "Total User Accounts:          $total_users"
  echo -e "${green}✓ Jamf Connect Users:         $jc_users${nc}"
  echo -e "${yellow}⚠ Unmigrated Users:           $unmigrated_users${nc}"
  echo -e "${cyan}⚠ Mobile Accounts (AD):       $mobile_users${nc}"
  echo ""
  
  # Migration progress
  local percentage=0
  if [ "$total_users" -gt 0 ]; then
    percentage=$((jc_users * 100 / total_users))
  fi
  
  echo "Migration Progress: ${percentage}%"
  local bar_length=20
  local filled=$((percentage * bar_length / 100))
  local empty=$((bar_length - filled))
  printf "["
  for ((i=0; i<filled; i++)); do printf "="; done
  for ((i=0; i<empty; i++)); do printf "-"; done
  printf "] %d%%\n" "$percentage"
  echo ""
  
  # Ask if user wants detailed reports
  read -r -p "View detailed user reports? (y/n/b to go back): " view_details
  
  case "$view_details" in
    [Bb])
      echo -e "${yellow}Returning to menu...${nc}"
      echo ""
      return
      ;;
    [Nn])
      echo -e "${yellow}Skipping detailed reports.${nc}"
      echo ""
      ;;
    [Yy])
      # Show JC users
      if [ "${#jc_user_list[@]}" -gt 0 ]; then
        echo ""
        echo -e "${purple}╔═══════════════════════════════════════════════════════════╗${nc}"
        echo -e "${purple}║              JAMF CONNECT USERS ($jc_users)                       ║${nc}"
        echo -e "${purple}╚═══════════════════════════════════════════════════════════╝${nc}"
        echo ""
        
        for jc_user in "${jc_user_list[@]}"; do
          check_jamf_connect_attributes "$jc_user"
          
          local is_admin is_mobile idp_type="Unknown"
          
          if dsmemberutil checkmembership -U "$jc_user" -G admin 2>/dev/null | grep -q "user is a member"; then
            is_admin="${green}[Admin]${nc}"
          else
            is_admin="[Standard]"
          fi
          
          if check_mobile_account "$jc_user"; then
            is_mobile="[Mobile+JC]"
          else
            is_mobile="[Local+JC]"
          fi
          
          if [ -n "$JC_ATTR_AZURE_USER" ]; then
            idp_type="Azure/Entra"
          elif [ -n "$JC_ATTR_OKTA_USER" ]; then
            idp_type="Okta"
          elif [ -n "$JC_ATTR_OIDC_PROVIDER" ]; then
            idp_type="OIDC"
          fi
          
          echo -e "${green}✓${nc} $jc_user $is_admin $is_mobile ($idp_type)"
          
          [ -n "$JC_ATTR_AZURE_USER" ] && echo "  └─ AzureUser: $JC_ATTR_AZURE_USER"
          [ -n "$JC_ATTR_OKTA_USER" ] && echo "  └─ OktaUser: $JC_ATTR_OKTA_USER"
          [ -n "$JC_ATTR_NETWORK_USER" ] && echo "  └─ NetworkUser: $JC_ATTR_NETWORK_USER"
          [ -n "$JC_ATTR_OIDC_PROVIDER" ] && echo "  └─ OIDCProvider: $JC_ATTR_OIDC_PROVIDER"
          [ -n "$JC_ATTR_NETWORK_SIGNIN" ] && echo "  └─ Last Network SignIn: $JC_ATTR_NETWORK_SIGNIN"
          
          local aliases
          aliases=$(get_user_aliases "$jc_user")
          [ -n "$aliases" ] && echo "  └─ Aliases: $aliases"
          echo ""
        done
      fi
      
      # Show unmigrated users
      if [ "${#unmigrated_user_list[@]}" -gt 0 ]; then
        echo ""
        echo -e "${purple}╔═══════════════════════════════════════════════════════════╗${nc}"
        echo -e "${purple}║           UNMIGRATED USERS ($unmigrated_users)                            ║${nc}"
        echo -e "${purple}╚═══════════════════════════════════════════════════════════╝${nc}"
        echo ""
        
        for unmig_user in "${unmigrated_user_list[@]}"; do
          local is_admin is_mobile
          
          if dsmemberutil checkmembership -U "$unmig_user" -G admin 2>/dev/null | grep -q "user is a member"; then
            is_admin="${yellow}[Admin]${nc}"
          else
            is_admin="[Standard]"
          fi
          
          if check_mobile_account "$unmig_user"; then
            is_mobile="[Mobile]"
          else
            is_mobile="[Local]"
          fi
          
          echo -e "${yellow}✗${nc} $unmig_user $is_admin $is_mobile"
          echo ""
        done
      fi
      
      # Show mobile accounts
      if [ "${#mobile_user_list[@]}" -gt 0 ]; then
        echo ""
        echo -e "${purple}╔═══════════════════════════════════════════════════════════╗${nc}"
        echo -e "${purple}║        MOBILE ACCOUNTS - AD DEMOBILIZATION ($mobile_users)            ║${nc}"
        echo -e "${purple}╚═══════════════════════════════════════════════════════════╝${nc}"
        echo ""
        
        for mobile_user in "${mobile_user_list[@]}"; do
          local node_name uid is_admin is_jc
          
          node_name=$(dscl . -read /Users/"$mobile_user" OriginalNodeName 2>/dev/null | grep "OriginalNodeName:" | awk '{print $2}')
          uid=$(id -u "$mobile_user" 2>/dev/null)
          
          if dsmemberutil checkmembership -U "$mobile_user" -G admin 2>/dev/null | grep -q "user is a member"; then
            is_admin="${green}[Admin]${nc}"
          else
            is_admin="[Standard]"
          fi
          
          if check_jamf_connect_attributes "$mobile_user"; then
            is_jc="${green}[Has JC]${nc}"
          else
            is_jc="${yellow}[No JC]${nc}"
          fi
          
          echo -e "${cyan}⚠${nc} $mobile_user $is_admin $is_jc"
          echo "  └─ AD Node: $node_name"
          echo "  └─ UID: $uid"
          echo ""
        done
        
        echo -e "${yellow}⚠ Action Required:${nc}"
        echo "1. Enable DemobilizeUsers setting in Jamf Connect Login configuration"
        echo "2. Have users authenticate with Jamf Connect to demobilize accounts"
        echo "3. Only unbind from AD after all mobile accounts are demobilized"
        echo ""
      fi
      ;;
  esac
  
  # Recommendations
  if [ "$unmigrated_users" -gt 0 ] || [ "$mobile_users" -gt 0 ]; then
    echo ""
    echo -e "${purple}╔═══════════════════════════════════════════════════════════╗${nc}"
    echo -e "${purple}║                  RECOMMENDATIONS                          ║${nc}"
    echo -e "${purple}╚═══════════════════════════════════════════════════════════╝${nc}"
    echo ""
    
    if [ "$unmigrated_users" -gt 0 ]; then
      echo -e "${yellow}• $unmigrated_users user(s) need Jamf Connect configuration${nc}"
    fi
    
    if [ "$mobile_users" -gt 0 ]; then
      echo -e "${cyan}• $mobile_users mobile account(s) require demobilization before AD unbinding${nc}"
    fi
    
    # MDM recommendation if no user enrollment found
    if [ -n "$consoleuser" ] && [ -z "$user_enrollment" ]; then
      echo -e "${yellow}• Console user is not MDM-managed - consider device-level profiles${nc}"
    fi
    
    if [ "$unmigrated_users" -eq 0 ] && [ "$mobile_users" -eq 0 ] && [ -n "$user_enrollment" ]; then
      echo -e "${green}✓ All user accounts are properly configured!${nc}"
    fi
    echo ""
  fi
  
  # Offer MDM details
  echo ""
  read -r -p "Would you like to view detailed MDM-managed user information? (y/n/b to go back): " view_mdm_info
  
  case "$view_mdm_info" in
    [Bb])
      echo -e "${yellow}Returning to menu...${nc}"
      echo ""
      return
      ;;
    [Yy])
      echo ""
      echo -e "${cyan}═══════════════════════════════════════════════════════════════${nc}"
      echo -e "${cyan}Understanding MDM-Managed Users${nc}"
      echo -e "${cyan}═══════════════════════════════════════════════════════════════${nc}"
      echo ""
      echo -e "${yellow}What is an MDM-Managed User?${nc}"
      echo "An MDM-managed (or MDM-capable/MDM-enabled) user can receive:"
      echo "  • User-level configuration profiles"
      echo "  • User-scoped certificates"
      echo "  • User-specific MDM commands"
      echo ""
      
      echo -e "${yellow}How Users Become MDM-Managed:${nc}"
      echo "  1. First user created by Setup Assistant during Automated Device Enrollment"
      echo "  2. Administrator initiates user enrollment via enrollment URL"
      echo "  3. Mobile accounts (bound to directory) with token registration"
      echo ""
      
      echo -e "${yellow}⚠️  Jamf Connect Limitation:${nc}"
      echo "Jamf Connect creates local accounts AFTER MDM enrollment completes."
      echo "These accounts are NOT MDM-managed by default."
      echo ""
      
      echo -e "${red}Impact:${nc}"
      echo "  ✗ User-level configuration profiles will NOT work"
      echo "  ✗ User-scoped certificates cannot be deployed"
      echo "  ✗ Some MDM features will be unavailable"
      echo ""
      
      echo -e "${yellow}Recommendation:${nc}"
      echo "Treat macOS like iOS/iPadOS - scope all profiles and certificates to"
      echo "the device level (computer groups) instead of user level."
      echo ""
      
      read -r -p "Would you like to view Remediation Options? (y/n/b to go back): " view_remediation
      
      case "$view_remediation" in
        [Bb])
          echo -e "${yellow}Returning to menu...${nc}"
          echo ""
          return
          ;;
        [Yy])
          echo ""
          echo -e "${cyan}═══════════════════════════════════════════════════════════════${nc}"
          echo -e "${cyan}Remediation Options${nc}"
          echo -e "${cyan}═══════════════════════════════════════════════════════════════${nc}"
          echo ""
          
          echo -e "${green}Option 1: Use Device-Level Profiles (Recommended)${nc}"
          echo "  • Scope all configuration profiles to computer groups"
          echo "  • Scope certificates to device level"
          echo "  • This is the Apple-recommended approach for modern macOS"
          echo ""
          
          echo -e "${green}Option 2: Create Managed Users from the Start${nc}"
          echo "  Use Enrollment Customizations (macOS 10.15+):"
          echo "  1. Configure SSO in Jamf Pro"
          echo "  2. Create Enrollment Customization with SSO payload"
          echo "  3. Configure PreStage with:"
          echo "     - Enrollment Customization"
          echo "     - Pre-fill primary account (Device owner's details)"
          echo "     - Lock primary account information"
          echo "  4. Deploy Jamf Connect AFTER enrollment to sync passwords"
          echo ""
          
          echo -e "${green}Option 3: Convert Existing User to Managed${nc}"
          echo "  ⚠️  WARNING: Requires user interaction and may affect workflows"
          echo ""
          echo "  Requirements:"
          echo "    • User must be an administrator"
          echo "    • Machine must be in Apple Business/School Manager"
          echo "    • Machine must be assigned to a PreStage"
          echo "    • User needs MDM enrollment permissions"
          echo ""
          echo "  Command (run as the user):"
          echo -e "    ${cyan}sudo profiles renew -type enrollment${nc}"
          echo ""
          echo "  This will:"
          echo "    • Prompt user to re-enroll via System Settings"
          echo "    • Require MDM credentials if SSO is enabled"
          echo "    • Make the user MDM-managed upon completion"
          echo ""
          
          echo -e "${yellow}⚠️  Note About Demobilization:${nc}"
          echo "If migrating from Active Directory mobile accounts:"
          echo "  • Demobilization removes MDM-capable status"
          echo "  • Transition to device-level profiles BEFORE demobilizing"
          echo "  • See Jamf Pro documentation for migration procedures"
          echo ""
          
          echo -e "${cyan}═══════════════════════════════════════════════════════════════${nc}"
          echo -e "${cyan}Additional Resources${nc}"
          echo -e "${cyan}═══════════════════════════════════════════════════════════════${nc}"
          echo ""
          echo "• Jamf Tech Thoughts: MDM-Capable Users"
          echo "  https://community.jamf.com/tech-thoughts-180/mdm-capable-mdm-enabled-or-mdm-managed-users-why-to-not-use-user-level-configuration-profiles-53431"
          echo ""
          echo "• Apple: Enabling MDM for Local User Accounts"
          echo "  https://support.apple.com/guide/deployment/enabling-mdm-for-local-user-accounts"
          echo ""
          echo "• Jamf Pro: Enrollment Customizations"
          echo "  https://learn.jamf.com/bundle/jamf-pro-documentation/page/Enrollment_Customizations.html"
          echo ""
          ;;
      esac
      ;;
  esac
  
  echo ""
  read -r -p "Press Enter to return to menu (or 'b' to go back): " return_choice
  if [[ ! "$return_choice" =~ ^[Bb]$ ]]; then
    echo ""
  fi
}

##############################################################################
# Function 13: Uninstall Jamf Connect
##############################################################################
fn_13_uninstall_jamf_connect() {
  echo -e "${purple}=== Function 13: Uninstall Jamf Connect ===${nc}"
  read -r -p "This will remove Jamf Connect apps, login components, and related data. Proceed? (y/n): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${yellow}Uninstall cancelled. Returning to main menu.${nc}"
    echo ""
    return
  fi

  # Quit processes using pkill
  echo "Stopping Jamf Connect processes..."
  pkill 'UnlockToken' 2>/dev/null || true
  pkill 'Jamf Connect' 2>/dev/null || true
  pkill 'Self Service+' 2>/dev/null || true

  /usr/bin/logger 'Killing Jamf Connect processes'

  # Removing unlock pair
  sc_auth unpair 2>/dev/null || true
  rm -rf "/Library/Caches/com.jamf.connect.unlock"
  /usr/bin/logger 'Jamf unlock pair removed'

  pkgutil --regexp --forget 'com.jamf.connect.*' 2>/dev/null || true

  rm -rf "/Library/Managed Preferences/com.jamf.connect.login.plist"
  rm -rf "/Library/Managed Preferences/com.jamf.connect.plist"
  rm -rf "/Library/Managed Preferences/com.jamf.connect.authchanger.plist"
  rm -rf "/Library/Managed Preferences/admin/com.jamf.connect.login.plist"
  rm -rf "/Library/LaunchAgents/com.jamf.connect.unlock.login.plist"
  rm -rf "$HOME/Library/Containers/com.jamf.connect.unlock.login.token"
  rm -rf "$HOME/Library/Application Scripts/com.jamf.connect.unlock.login.token"

  /usr/bin/logger 'starting uninstall script'

  # Paths for launchd items and apps
  local SyncLA VerifyLA Connect2LA DaemonLD DaemonSSP
  SyncLA='/Library/LaunchAgents/com.jamf.connect.sync.plist'
  VerifyLA='/Library/LaunchAgents/com.jamf.connect.verify.plist'
  Connect2LA="$JC_LAUNCHAGENT"
  DaemonLD="$JC_DAEMON_CLASSIC"
  DaemonSSP="$JC_DAEMON_SSP"

  local SyncApp VerifyApp ConfigApp ConnectApp DaemonDir EvaluationAssets ChromeExtensions
  SyncApp='/Applications/Jamf Connect Sync.app/'
  VerifyApp='/Applications/Jamf Connect Verify.app/'
  ConfigApp='/Applications/Jamf Connect Configuration.app/'
  ConnectApp='/Applications/Jamf Connect.app/'
  DaemonDir='/Library/Application Support/JamfConnect'

  EvaluationAssets='/Users/Shared/JamfConnectEvaluationAssets/'
  ChromeExtensions='/Library/Google/Chrome/NativeMessagingHosts/'

  # Console user - with validation
  local consoleuser uid
  consoleuser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
  
  if [ -z "$consoleuser" ]; then
    echo -e "${yellow}No console user detected. Skipping user-specific LaunchAgent unloading.${nc}"
    uid=0
  else
    if ! id "$consoleuser" >/dev/null 2>&1; then
      echo -e "${yellow}Console user ${consoleuser} not found. Skipping user-specific operations.${nc}"
      uid=0
    else
      uid=$(/usr/bin/id -u "$consoleuser" 2>/dev/null || echo 0)
      /usr/bin/logger "Console user is ${consoleuser}, UID: ${uid}"
    fi
  fi

  # Disable and remove LaunchAgents
  if [ -f "$SyncLA" ]; then
    echo "Jamf Connect Sync Launch Agent is present. Unloading & removing..."
    if [ -n "$consoleuser" ] && [ "$uid" -ne 0 ]; then
      /bin/launchctl bootout "gui/${uid}" "$SyncLA" 2>/dev/null || true
    fi
    rm -rf "$SyncLA"
  fi

  if [ -f "$VerifyLA" ]; then
    echo "Jamf Connect Verify Launch Agent is present. Unloading & removing..."
    if [ -n "$consoleuser" ] && [ "$uid" -ne 0 ]; then
      /bin/launchctl bootout "gui/${uid}" "$VerifyLA" 2>/dev/null || true
    fi
    rm -rf "$VerifyLA"
  fi

  if [ -f "$Connect2LA" ]; then
    echo "Jamf Connect Launch Agent is present. Unloading & removing..."
    if [ -n "$consoleuser" ] && [ "$uid" -ne 0 ]; then
      /bin/launchctl bootout "gui/${uid}" "$Connect2LA" 2>/dev/null || true
    fi
    rm -rf "$Connect2LA"
  fi

  # Remove Classic Daemon (JC 2.x)
  if [ -f "$DaemonLD" ]; then
    echo "Jamf Connect Launch Daemon (Classic/JC 2.x) is present. Unloading and removing..."
    /bin/launchctl unload "$DaemonLD" 2>/dev/null || true
    rm -f "$DaemonLD"
  fi

  # Remove SSP Daemon (JC 3.0+)
  if [ -f "$DaemonSSP" ]; then
    echo "Jamf Connect Launch Daemon (SSP/JC 3.0+) is present. Unloading and removing..."
    /bin/launchctl bootout system "$DaemonSSP" 2>/dev/null || true
    rm -f "$DaemonSSP"
  fi

  # Remove daemon directory
  if [ -d "$DaemonDir" ]; then
    rm -rf "$DaemonDir"
  fi

  echo "Jamf Connect LaunchAgents and Daemons removed"
  rm -f "/usr/local/bin/jamfconnect"

  # Reset authentication database
  if [ -f "$AUTHCHANGER_BIN" ]; then
    "$AUTHCHANGER_BIN" -reset 2>/dev/null || true
    echo "Default macOS loginwindow has been restored"
    rm -f "$AUTHCHANGER_BIN"
    rm -f "$PAM_MODULE"
    rm -rf "/Library/Security/SecurityAgentPlugins/JamfConnectLogin.bundle"
    echo "Jamf Connect Login components have been removed"
  else
    echo "Jamf Connect Login not installed; can't delete login components"
  fi

  # Remove Jamf Connect applications
  [ -d "$SyncApp" ] && rm -rf "$SyncApp"
  [ -d "$VerifyApp" ] && rm -rf "$VerifyApp"
  [ -d "$ConfigApp" ] && rm -rf "$ConfigApp"
  [ -d "$ConnectApp" ] && rm -rf "$ConnectApp"
  [ -d "$SSP_APP" ] && rm -rf "$SSP_APP"

  echo "Jamf Connect Applications have been removed"

  # Remove evaluation assets
  if [ -d "$EvaluationAssets" ]; then
    rm -rf "$EvaluationAssets"
    echo "Jamf Connect Evaluation Assets have been removed"
  fi

  # Remove Chrome extensions
  if [ -d "$ChromeExtensions" ]; then
    rm -rf "$ChromeExtensions"
    echo "Jamf Connect Chrome extensions have been removed"
  fi

  # Remove Jamf Connect evaluation profiles
  local profilesArray=()
  local counter=0
  
  while IFS= read -r line; do
    if [[ "$line" =~ attribute:\ profileIdentifier:\ ([^\ ]+) ]]; then
      profilesArray+=("${BASH_REMATCH[1]}")
      ((counter++))
    fi
  done < <(profiles list 2>/dev/null | grep -i com.jamf.connect)

  if [ "$counter" -eq 0 ]; then
    echo "There were 0 Jamf Connect Profiles found. Continuing..."
  else
    echo "There were ${counter} Jamf Connect Profiles found. Removing..."
  fi

  for id in "${profilesArray[@]}"; do
    echo "Removing the profile ${id}..."
    /usr/bin/profiles -R -p "$id" 2>/dev/null || true
  done

  # Remove user defaults
  if [ -n "$consoleuser" ] && id "$consoleuser" >/dev/null 2>&1; then
    echo "Cleaning Jamf Connect user defaults for ${consoleuser}..."
    sudo -u "$consoleuser" bash <<'EOFDEFAULTS'
      defaults delete ~/Library/Group\ Containers/483DWKW443.jamf.connect/Library/Preferences/483DWKW443.jamf.connect 2>/dev/null || true
      defaults delete com.jamf.connect 2>/dev/null || true
      defaults delete com.jamf.connect.state 2>/dev/null || true
      security delete-generic-password -l "Jamf Connect" 2>/dev/null || true
      defaults delete ~/Library/Group\ Containers/group.com.jamf.connect/Library/Preferences/group.com.jamf.connect 2>/dev/null || true
EOFDEFAULTS
  else
    echo -e "${yellow}Cannot clean user defaults: console user not detected or invalid${nc}"
  fi

  echo ""
  echo "${counter} Jamf Connect Profiles have been removed."
  echo "All Jamf Connect components have been removed."
  echo ""
}

##############################################################################
# Function 15: Exit
##############################################################################
fn_15_exit() {
  echo -e "${red}Exiting JCP v${SCRIPT_VERSION}...${nc}"
  exit 0
}

##############################################################################
# Menu / Main Loop
##############################################################################

print_menu() {
  echo -e "${purple}╔════════════════════════════════════════════════════════════╗${nc}"
  echo -e "${purple}║     Jamf Connect Troubleshooting Menu v${SCRIPT_VERSION}          ║${nc}"
  echo -e "${purple}╚════════════════════════════════════════════════════════════╝${nc}"
  echo ""
  if [ "$DEBUG_MODE" -eq 1 ]; then
    echo -e "${red}[DEBUG MODE: ON]${nc}"
  fi
  echo -e "${OS_STATUS_MSG}"
  echo ""
  echo -e "${cyan}Status & Configuration:${nc}"
  echo "  1.  Check App Status (JCMB/JCLW/Components/Kerberos)"
  echo "  2.  Validate License (expiration, days remaining, grace period)"
  echo "  3.  View Configured Profile Keys (IdP settings)"
  echo ""
  echo -e "${cyan}Operations:${nc}"
  echo "  4.  Restart Jamf Connect"
  echo "  5.  Modify Login Window Settings (enable/disable)"
  echo "  6.  View Authorization Database (mechanisms)"
  echo ""
  echo -e "${cyan}Troubleshooting:${nc}"
  echo "  7.  Collect Historical Debug Logs (Official/Manual/Live)"
  echo "  8.  Documentation & Resources (Jamf docs, support, error codes)"
  echo "  9.  Check Local Network Permission (TCC)"
  echo "  10. Kerberos Troubleshooting (Advanced diagnostics)"
  echo "  11. Privilege Elevation Control (CLI management)"
  echo ""
  echo -e "${cyan}Maintenance:${nc}"
  echo "  12. Update Jamf Connect (download & install latest)"
  echo "  13. Uninstall Jamf Connect (complete removal)"
  echo ""
  echo -e "${cyan}User Management & Migration:${nc}"
  echo "  14. Comprehensive User Analysis (JC migration, MDM status, mobile accounts, AD demob)"
  echo ""
  echo "  15. Exit"
  echo ""
  read -r -p "Select an option: " choice
  echo ""
  case "$choice" in
    1)  fn_01_check_app_status ;;
    2)  fn_02_validate_license ;;
    3)  fn_03_view_configured_profile_keys ;;
    4)  fn_04_restart_jamf_connect ;;
    5)  fn_05_modify_login_window ;;
    6)  fn_06_view_auth_db ;;
    7)  fn_07_collect_logs ;;
    8)  fn_08_documentation_and_resources ;;
    9)  fn_09_check_local_network_permission ;;
    10) fn_10_kerberos_troubleshooting ;;
    11) fn_11_privilege_elevation_control ;;
    12) fn_12_update_jamf_connect ;;
    13) fn_13_uninstall_jamf_connect ;;
    14) fn_14_comprehensive_user_analysis ;;
    15) fn_15_exit ;;
    *)  echo -e "${red}Invalid option. Try again.${nc}"; echo "" ;;
  esac
}

##############################################################################
# Main Execution
##############################################################################

# Main loop
while true; do
  print_menu
done
