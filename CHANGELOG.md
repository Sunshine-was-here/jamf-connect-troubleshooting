# Changelog

All notable changes to the Jamf Connect Troubleshooting Script (JCP) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.7.1] - 2025-11-20

### 🎉 Major Update - Function Consolidation & Quality Improvements

### Added
- ✨ **Comprehensive User Analysis** - Merged Functions 15 & 16 into single unified function
  - Integrated MDM status checking with user analysis
  - Added migration progress tracking with visual progress bar
  - Combined console user MDM status with all users JC migration analysis
  - Progressive disclosure with opt-in detailed reports
  
- ✨ **Documentation & Resources Hub** - Merged Functions 8 & 9 with enhanced functionality
  - Added 7 new resource links (total: 9 resources)
  - Jamf Connect documentation (Known Issues, Auth Settings, Login Window, Menu Bar)
  - Support portals (Jamf Nation, Feature Requests, Support Portal)
  - Other resources (Microsoft AADSTS errors, GitHub repository)
  - "Open all" power feature for batch resource access
  
- 📖 **Comprehensive Documentation**
  - 10 detailed documentation files
  - Testing report with full validation
  - Version explanation and rationale
  - Function merge explanations
  - ShellCheck fixes documentation
  - Improvement analysis

### Changed
- 🔄 **Function Count** - Reduced from 17 to 15 functions
  - More streamlined menu
  - Better organization
  - No functionality lost
  
- 🔧 **Function Numbering** - Renumbered Functions 9-15 after merge
  - Function 8: Documentation & Resources (merged 8+9)
  - Function 14: Comprehensive User Analysis (merged 15+16)
  - Function 15: Exit (was 17)

### Fixed
- 🐛 **ShellCheck Warnings** - Fixed all SC2034 warnings
  - Removed unused KNOWN_ISSUES_URL constant
  - Removed unused AADSTS_URL constant
  - Removed unused label parameter in TCC function
  - Marked intentionally unused variables with underscore (`_`)
  
- 🐛 **Menu Alignment** - Removed duplicate menu entry
  - Fixed duplicate "16) fn_15_exit" entry
  
- 📝 **Script Header** - Updated high-level features list
  - Reflects current 15 functions
  - Accurate descriptions
  - Fixed date format

### Improved
- 💎 **Code Quality**
  - Passes shellcheck with zero warnings
  - Better variable naming for unused parameters
  - Cleaner code organization
  
- 📊 **User Experience**
  - Context-aware recommendations in user analysis
  - Better information organization
  - Clearer navigation with multiple exit points

### Documentation
- 📖 Testing Report - Comprehensive validation (12 test categories)
- 📖 Version Explanation - Why 1.7.1 not 1.7.0
- 📖 Function Merge Docs - Detailed rationale for consolidations
- 📖 ShellCheck Fixes - All code quality improvements
- 📖 Improvement Analysis - Optimization opportunities

---

## [1.7.0-Enhanced] - 2025-11-18

### Initial Enhanced Release

### Added
- ✨ **Sophisticated Version Detection**
  - classify_jcmb() for Menu Bar classification
  - classify_jclw() for Login Window classification
  - SSP vs Classic architecture detection
  - Multiple path checking (Self Service+, Legacy, Bundle)
  
- ✨ **Jamf Connect 3.0+ Support**
  - Self Service+ integration detection
  - New daemon paths (com.jamf.connect.daemon.ssp)
  - Hybrid architecture handling
  
- ✨ **Enhanced User Analysis** (Functions 15-18)
  - MDM-managed user status checking
  - Mobile account detection (AD demobilization)
  - Comprehensive user migration reports
  - Multi-attribute detection (Azure, Okta, OIDC)
  
- ✨ **Advanced Diagnostics**
  - Kerberos troubleshooting (Function 11)
  - Local Network Permission checking (macOS 14+)
  - Privilege Elevation Control (Function 12)

### Changed
- 🔄 **Function Count** - Expanded to 17 functions
  - Split user management into 4 specialized functions
  - Added advanced troubleshooting functions
  
- 🔧 **Architecture Support**
  - Handles both JC 2.x (Classic) and 3.x (SSP)
  - Version-aware path detection
  - Threshold-based classification (2.45.1)

### Fixed
- 🐛 Version detection edge cases
- 🐛 Path resolution for Self Service+
- 🐛 LaunchAgent detection accuracy

---

## [1.6.x] - Previous Versions

### Legacy Features
- Basic Jamf Connect detection
- Standard troubleshooting functions
- License validation
- Log collection
- Profile viewing

*(For detailed history of versions prior to 1.7.0, see legacy documentation)*

---

## Version Numbering

This project uses [Semantic Versioning](https://semver.org/):

**MAJOR.MINOR.PATCH**

- **MAJOR** - Incompatible API changes or major rewrites
- **MINOR** - New functionality in a backwards compatible manner
- **PATCH** - Backwards compatible bug fixes

**Current:** v1.7.1
- Major: 1 (Script concept)
- Minor: 7 (Feature set iteration)
- Patch: 1 (Quality improvements)

---

## Upgrade Path

### From 1.7.0-Enhanced to 1.7.1:
1. Download new script
2. No configuration changes needed
3. All functionality preserved
4. Menu now has 15 options (was 17)
5. Better user experience

**Breaking Changes:** None  
**Migration Required:** No  
**Testing Required:** Recommended

---

## Future Roadmap

### Planned for 1.8.0:
- [ ] Command-line arguments support
- [ ] JSON output mode for automation
- [ ] Batch operation mode
- [ ] Enhanced logging options

### Considering for 2.0.0:
- [ ] Modular architecture
- [ ] Plugin system
- [ ] Configuration file support
- [ ] Multi-language support

### Ongoing:
- [ ] Documentation improvements
- [ ] Performance optimization
- [ ] Bug fixes as reported
- [ ] macOS compatibility updates

---

## Contributing

See [README.md](README.md) for contribution guidelines.

---

## Links

- **GitHub Repository:** https://github.com/yourusername/yourrepo
- **Documentation:** [docs/](docs/)
- **Issues:** https://github.com/yourusername/yourrepo/issues
- **Releases:** https://github.com/yourusername/yourrepo/releases

---

**Legend:**
- ✨ Added - New features
- 🔄 Changed - Changes in existing functionality
- 🐛 Fixed - Bug fixes
- 🔧 Improved - Performance or quality improvements
- 📖 Documentation - Documentation only changes
- 💎 Code Quality - Code style, refactoring, etc.
- 🔒 Security - Security improvements
- 🗑️ Deprecated - Soon-to-be removed features
- ❌ Removed - Removed features
