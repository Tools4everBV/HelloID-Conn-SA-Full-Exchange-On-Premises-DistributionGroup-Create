# Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-08-21

### Added

- Added support for creating Mail-enabled Security Groups in addition to Distribution Groups
- Added dropdown to select mail domains via new datasource `Exchange-On-Premises-Get-All-MailDomains`
- Added separate validation for display name via datasource `AD-Check-DisplayName-Unique`
- Added separate validation for alias via datasource `Exchange-On-Premises-Check-Alias-Unique`
- Added separate validation for email address via datasource `Exchange-On-Premises-Check-EmailAddress-Unique`
- Added member selection via datasource `Exchange-On-Premises-Get-All-Users`
- Added owner selection via datasource `Exchange-On-Premises-Get-All-Users-Owners`
- Added configuration variable `ADmailenabledSecurityGroupsOU` for mail-enabled security groups
- Added `CopyOwnerToMember` option to automatically include owners as members
- Added `EmailAddressPolicyEnabled` set to false for manual email address control
- Added comprehensive input validation with regex patterns for display name, email prefix, and alias
- Added informational banners in the form to guide users
- Added form validation feedback showing validation status inline

### Changed

- Refactored from single datasource to six specialized datasources for improved separation of concerns
- Improved form structure with three distinct sections: Create group, Group permissions tabs
- Changed email address input to separate prefix and domain selection for better user experience
- Enhanced error handling with try-catch-finally blocks in all scripts
- Improved Exchange session management with proper cleanup in finally blocks
- Updated Exchange connection to use explicit authentication and session option parameters
- Improved audit logging with more detailed messages and error context
- Changed PowerShell session options to use secure defaults (SkipCACheck, SkipCNCheck, SkipRevocationCheck set to false)
- Updated code to use parameter splatting for better readability
- Enhanced logging to include line numbers and more detailed error messages

### Fixed

- Fixed potential memory leaks by ensuring Exchange sessions are properly closed in finally blocks
- Fixed validation to check against all Exchange recipients (mailboxes, distribution groups, etc.) instead of just AD users
- Fixed display name validation to check for mail-enabled objects only in Active Directory

### Removed

- Removed automatic name generation with iteration logic
- Removed hardcoded UPN suffix logic
- Removed Latin character conversion function

## [1.0.2] - 2022-08-03

### Added

- Added version number and updated code for SA-agent and auditlogging

## [1.0.1] - 2021-11-16

### Added

- Added version number and updated all-in-one script

## [1.0.0] - 2021-04-29

Initial release of HelloID-Conn-SA-Full-Exchange-On-Premises-Distribution-Group-Create.

### Added

- Initial release for creating Exchange On-Premises Distribution Groups
- Basic name validation with automatic iteration
- Single datasource for name checking
- Support for creating distribution groups in specified Active Directory OU

### Changed

### Deprecated

### Removed

### Fixed
