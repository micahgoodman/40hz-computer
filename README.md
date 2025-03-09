# Display Refresh Rate Utility

A simple macOS command-line utility for viewing and changing display refresh rates.

## Features

- List all connected displays with their current refresh rates
- Show available refresh rates for each display
- Set a specific refresh rate for any connected display

## Requirements

- macOS 10.13 or later
- Xcode 10.0 or later (for building from source)

## Installation

### Building from Source

1. Clone this repository:
   ```
   git clone https://github.com/yourusername/refresh-rate-utility.git
   cd refresh-rate-utility
   ```

2. Build the project:
   ```
   swift build -c release
   ```

3. Copy the binary to a location in your PATH:
   ```
   cp .build/release/refresh-rate /usr/local/bin/
   ```

## Usage

```
Usage: refresh-rate [options]

Options:
  -l                   List all connected displays and their current refresh rates
  -d <display_id>      Specify which display to target (use ID from -l output)
  -r <refresh_rate>    Set the specified refresh rate in Hz (e.g., 60, 120)
  -h                   Display this help information

Examples:
  refresh-rate -l                     List all displays
  refresh-rate -d 1 -r 60             Set display 1 to 60Hz refresh rate
```

## Examples

### List all displays and their refresh rates

```
$ refresh-rate -l
```

This will show all connected displays with their current resolution and refresh rate, plus a list of all available refresh rates for each display.

### Set a display to a specific refresh rate

```
$ refresh-rate -d 1 -r 60
```

This sets display ID 1 to a 60Hz refresh rate.

## Notes

- Not all displays support changing refresh rates
- Some displays won't support all refresh rates 
- Some refresh rates may only be available at specific resolutions
