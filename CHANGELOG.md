# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8] - 2024-03-26

### Fixed

- Fixed case where game would hang if the backend server was slow or failed to respond.

## [0.7] - 2024-02-22

### Fixed

- Fixed call to `await handle_exit()` hanging when data collection was turned off.

## [0.6] - 2024-02-20

### Changed

- New project logo!

## [0.5] - 2024-02-12

### Changed

- Moved location where authentication token is saved in anticipation for the introduction of more Quiver services.

## [0.4] - 2024-01-10

### Fixed

- Better handling for when authentication token is not set up correctly.

## [0.3] - 2023-12-01

### Added

- Added new default properties `$debug` and `$export_template` for debug builds and exported builds (i.e. not run in editor), respectively.

## [0.2] - 2023-10-19

### Added

- Added support for automatically sending periodic "Quit game" events for platforms where it is difficult to detect when the game is exiting (e.g. web & mobile games).

## [0.1] - 2023-10-02

### Added

- Initial version.
