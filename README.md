# Jamf Connect Troubleshooting Script (JCP)

[![Version](https://img.shields.io/badge/version-1.7.1-blue.svg)](https://github.com/yourusername/yourrepo)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-orange.svg)](LICENSE)
[![ShellCheck](https://img.shields.io/badge/shellcheck-passing-brightgreen.svg)](https://www.shellcheck.net/)

A comprehensive diagnostic and troubleshooting tool for Jamf Connect on macOS. Supports both Jamf Connect 2.x (Classic) and 3.x (Self Service+ integration).

---

## 📋 Table of Contents

- [Features](#-features)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Usage](#-usage)
- [Functions Overview](#-functions-overview)
- [Screenshots](#-screenshots)
- [Documentation](#-documentation)
- [Changelog](#-changelog)
- [Contributing](#-contributing)
- [License](#-license)
- [Author](#-author)

---

## ✨ Features

### 🔍 **Diagnostics & Status**
- **Comprehensive App Status Check** - Detects JCMB/JCLW, LaunchAgents, PAM modules, daemons, login window integration, and Kerberos
- **License Validation** - Status, expiration date, days remaining, grace period tracking
- **Profile Configuration Viewer** - Display Menu Bar, Login Window, and authchanger settings
- **Authorization Database Inspection** - View system.login.console mechanisms

### 🛠️ **Operations**
- **Restart Jamf Connect** - Quick restart for troubleshooting
- **Modify Login Window** - Enable/disable Jamf Connect login window
- **Log Collection** - Official, manual, and live streaming debug logs
- **Update & Uninstall** - Download latest version or completely remove Jamf Connect

### 📚 **Resources & Documentation**
- **9 Resource Links** - Official docs, support portals, community, error codes, GitHub
- **Jamf Connect Known Issues** - Direct access to release notes
- **Minimum IDP Settings** - Authentication configuration reference
- **AADSTS Error Codes** - Microsoft Entra troubleshooting

### 🔐 **Advanced Troubleshooting**
- **Local Network Permission (TCC)** - macOS 14+ Sonoma privacy diagnostics
- **Kerberos Troubleshooting** - Advanced diagnostics for domain authentication
- **Privilege Elevation Control** - CLI-based account promotion management

### 👥 **User Management**
- **Comprehensive User Analysis** - JC migration status, MDM enrollment, mobile accounts, AD demobilization readiness
- **Migration Progress Tracking** - Visual progress bar showing JC adoption
- **Mobile Account Detection** - Identify accounts needing demobilization before AD unbinding
- **MDM Status Checking** - Verify user-level profile capability

---

## 📋 Requirements

- **macOS:** 13.0+ (Ventura or later)
- **Jamf Connect:** 2.x or 3.x (automatically detected)
- **Privileges:** Root/sudo access (script checks and prompts)
- **Shell:** Bash 4.0+

### Tested On:
- ✅ macOS 13 (Ventura)
- ✅ macOS 14 (Sonoma)
- ✅ macOS 15 (Sequoia)

---

## 🚀 Installation

### Quick Install

```bash
# Download script
curl -O https://raw.githubusercontent.com/yourusername/yourrepo/main/JCP_1_7_1.sh

# Make executable
chmod +x JCP_1_7_1.sh

# Run with sudo
sudo ./JCP_1_7_1.sh
```

### Via Git

```bash
# Clone repository
git clone https://github.com/yourusername/yourrepo.git

# Navigate to directory
cd yourrepo

# Run script
sudo ./JCP_1_7_1.sh
```

---

## 💻 Usage

### Basic Usage

```bash
sudo ./JCP_1_7_1.sh
```

The script displays an interactive menu with 15 functions:

```
╔════════════════════════════════════════════════════════════╗
║     Jamf Connect Troubleshooting Menu v1.7.1              ║
╚════════════════════════════════════════════════════════════╝

Status & Configuration:
  1. Check App Status
  2. Validate License
  3. View Configured Profile Keys

Operations:
  4. Restart Jamf Connect
  5. Modify Login Window Settings
  6. View Authorization Database

Troubleshooting:
  7.  Collect Historical Debug Logs
  8.  Documentation & Resources
  9.  Check Local Network Permission
  10. Kerberos Troubleshooting
  11. Privilege Elevation Control

Maintenance:
  12. Update Jamf Connect
  13. Uninstall Jamf Connect

User Management:
  14. Comprehensive User Analysis

  15. Exit

Select an option:
```

### Common Workflows

#### 🔍 **Quick Health Check**
```bash
sudo ./JCP_1_7_1.sh
# Select: 1 (Check App Status)
```

#### 📊 **User Migration Analysis**
```bash
sudo ./JCP_1_7_1.sh
# Select: 14 (Comprehensive User Analysis)
```

#### 🐛 **Collect Logs for Support**
```bash
sudo ./JCP_1_7_1.sh
# Select: 7 (Collect Historical Debug Logs)
```

#### 🔄 **Update Jamf Connect**
```bash
sudo ./JCP_1_7_1.sh
# Select: 12 (Update Jamf Connect)
```

---

## 📖 Functions Overview

### 1️⃣ Check App Status
**What it does:**
- Detects Jamf Connect Menu Bar (Self Service+ or Legacy)
- Checks Jamf Connect Login Window
- Validates LaunchAgent and LaunchDaemon
- Inspects PAM modules
- Verifies login window integration
- Tests Kerberos configuration

**Use when:**
- Initial troubleshooting
- Verifying installation
- Checking version/architecture

---

### 2️⃣ Validate License
**What it does:**
- Checks license status (Licensed/Evaluation/Expired)
- Shows expiration date
- Calculates days remaining
- Tracks grace period

**Use when:**
- License issues reported
- Planning renewals
- Deployment validation

---

### 3️⃣ View Configured Profile Keys
**What it does:**
- Displays Menu Bar settings
- Shows Login Window configuration
- Lists authchanger settings
- Identifies key profiles

**Use when:**
- Configuration review
- Troubleshooting auth issues
- Documentation

---

### 4️⃣ Restart Jamf Connect
**What it does:**
- Quits all Jamf Connect processes
- Restarts LaunchAgent
- Re-launches menu bar app

**Use when:**
- Quick fix for stuck processes
- After configuration changes
- General troubleshooting

---

### 5️⃣ Modify Login Window Settings
**What it does:**
- Enables/disables Jamf Connect login window
- Manages authchanger configuration
- Updates login window mechanisms

**Use when:**
- Switching between JC and standard login
- Testing configurations
- Emergency recovery

---

### 6️⃣ View Authorization Database
**What it does:**
- Shows system.login.console mechanisms
- Identifies authentication flow
- Highlights Jamf Connect integration

**Use when:**
- Login issues
- Auth flow debugging
- Verifying configuration

---

### 7️⃣ Collect Historical Debug Logs
**What it does:**
- **Official:** Uses `jamfconnect app -log` command
- **Manual:** Tails unified log for JC subsystems
- **Live:** Real-time streaming with grep filtering

**Use when:**
- Submitting support tickets
- Detailed troubleshooting
- Reproducing issues

---

### 8️⃣ Documentation & Resources
**What it does:**
- Opens 9 curated resource links
- Jamf documentation (4 links)
- Support portals (3 links)
- Other resources (2 links)
- "Open all" power feature

**Use when:**
- Need official documentation
- Looking up error codes
- Setting up new deployment
- Community support

---

### 9️⃣ Check Local Network Permission
**What it does:**
- Checks TCC.db for Local Network permission
- macOS 14+ (Sonoma) specific
- Diagnoses connectivity issues
- Provides remediation steps

**Use when:**
- Network connectivity problems
- macOS 14+ deployments
- IdP connection failures

---

### 🔟 Kerberos Troubleshooting
**What it does:**
- Advanced Kerberos diagnostics
- Ticket inspection (klist)
- Password expiration checking
- Network authentication testing

**Use when:**
- Password expiration not working
- File share access issues
- Certificate deployment problems

---

### 1️⃣1️⃣ Privilege Elevation Control
**What it does:**
- CLI-based account promotion
- Manages `jamfconnect acc-promo` commands
- Elevation requests

**Use when:**
- Granting admin rights
- Testing privilege workflows
- Alternative to GUI

---

### 1️⃣2️⃣ Update Jamf Connect
**What it does:**
- Downloads latest JamfConnect.dmg
- Installs automatically
- Verifies installation

**Use when:**
- Updating to new version
- Applying bug fixes
- Feature updates

---

### 1️⃣3️⃣ Uninstall Jamf Connect
**What it does:**
- Stops all JC processes
- Removes applications
- Cleans LaunchAgents/Daemons
- Removes profiles and preferences
- Resets authorization database

**Use when:**
- Complete removal needed
- Switching auth solutions
- Clean reinstall

**⚠️ Warning:** This is destructive!

---

### 1️⃣4️⃣ Comprehensive User Analysis
**What it does:**
- **Part 1:** Console user MDM status
- **Part 2:** All users JC migration status
- **Part 3:** Mobile account detection
- **Part 4:** Migration progress tracking
- **Part 5:** Context-aware recommendations

**Analyzes:**
- Jamf Connect attributes per user
- MDM enrollment status
- Mobile accounts (AD demobilization)
- IdP type (Azure/Okta/OIDC)
- Admin vs standard accounts

**Use when:**
- Planning JC migration
- AD unbinding preparation
- User troubleshooting
- Deployment validation

---

## 📸 Screenshots

### Main Menu
```
╔════════════════════════════════════════════════════════════╗
║     Jamf Connect Troubleshooting Menu v1.7.1              ║
╚════════════════════════════════════════════════════════════╝

macOS Version: 14.1 (Sonoma) [Supported ✓]

Status & Configuration:
  1. Check App Status
  ...
```

### App Status Output
```
=== Function 1: Check App Status ===

[Jamf Connect Menu Bar]
✓ App Status: Running (Self Service+ Architecture)
✓ Version: 3.1.0
✓ Path: /Applications/Self Service+.app/Contents/PlugIns/Jamf Connect.appex
✓ LaunchAgent: Loaded (com.jamf.connect)
...
```

### User Analysis
```
╔═══════════════════════════════════════════════════════════╗
║                    SUMMARY                                ║
╚═══════════════════════════════════════════════════════════╝

Total User Accounts:          10
✓ Jamf Connect Users:         7
⚠ Unmigrated Users:           3
⚠ Mobile Accounts (AD):       2

Migration Progress: 70%
[==============------] 70%
```

---

## 📚 Documentation

Full documentation available in the `docs/` directory:

- **[Testing Report](docs/JCP_v1_7_1_TESTING_REPORT.md)** - Comprehensive testing validation
- **[Version Explanation](docs/VERSION_1_7_1_EXPLANATION.md)** - Why version 1.7.1
- **[Function Merges](docs/FUNCTION_MERGE_EXPLANATION.md)** - How functions were consolidated
- **[Documentation Resources](docs/DOCUMENTATION_RESOURCES_MERGE.md)** - Resource hub details
- **[Version Detection](docs/VERSION_DETECTION_EXPLAINED.md)** - Technical deep dive
- **[ShellCheck Fixes](docs/SHELLCHECK_FIXES.md)** - Code quality improvements
- **[Improvement Analysis](docs/IMPROVEMENT_ANALYSIS.md)** - Optimization opportunities

---

## 📝 Changelog

### v1.7.1 (2025-11-20)
**🎉 Major Update - Function Consolidation**

**Added:**
- ✨ Merged Functions 15 & 16 into comprehensive user analysis
- ✨ Merged Functions 8 & 9 into documentation resources hub (9 URLs!)
- ✨ MDM status checking integrated into user analysis
- ✨ "Open all" feature for documentation links

**Improved:**
- 🔧 Reduced function count from 17 to 15
- 🔧 Fixed all shellcheck warnings (SC2034)
- 🔧 Better context-aware recommendations
- 🔧 Progressive disclosure in complex functions

**Fixed:**
- 🐛 Removed unused URL constants
- 🐛 Removed unused function parameters
- 🐛 Marked intentionally unused variables with `_`

**Documentation:**
- 📖 10 comprehensive documentation files
- 📖 Complete testing report
- 📖 Version explanations
- 📖 Function merge rationale

---

### v1.7.0-Enhanced (2025-11-18)
- Initial enhanced version with sophisticated version detection
- Support for both JC 2.x and 3.x
- Self Service+ architecture detection
- 17 functions

---

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

### Reporting Issues
1. Check existing issues first
2. Provide clear description
3. Include macOS version
4. Include Jamf Connect version
5. Attach relevant logs if possible

### Pull Requests
1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Test thoroughly
4. Run shellcheck
5. Update documentation
6. Commit changes (`git commit -m 'Add AmazingFeature'`)
7. Push to branch (`git push origin feature/AmazingFeature`)
8. Open Pull Request

### Coding Standards
- Use `bash -n` for syntax validation
- Run `shellcheck` and fix warnings
- Follow existing code style
- Add comments for complex logic
- Use local variables in functions
- Quote all variables

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👤 Author

**Ellie Romero**
- Email: ellie.romero@jamf.com
- GitHub: [@yourusername](https://github.com/yourusername)

---

## 🙏 Acknowledgments

- Jamf Connect team for excellent documentation
- macOS community for troubleshooting insights
- ShellCheck for code quality validation

---

## 🔗 Related Resources

### Official Jamf Resources
- [Jamf Connect Documentation](https://learn.jamf.com/jamf-connect)
- [Jamf Nation Community](https://community.jamf.com/)
- [Jamf Support Portal](https://account.jamf.com)

### Technical Resources
- [Jamf Connect GitHub](https://github.com/jamf/jamfconnect)
- [Microsoft Entra Error Codes](https://learn.microsoft.com/en-us/entra/identity-platform/reference-error-codes)
- [Apple Platform Deployment](https://support.apple.com/guide/deployment/)

---

## ⚠️ Disclaimer

This script is provided as-is for troubleshooting purposes. Always test in a non-production environment first. The author and contributors are not responsible for any issues that may arise from using this tool.

---

## 🌟 Star History

If you find this tool useful, please consider giving it a star! ⭐

---

**Made with ❤️ for the Jamf Connect community**
