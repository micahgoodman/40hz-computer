# 40Hz Computer Utility

A simple utility for generating 40Hz clicks/flashes on a computer.

## Usage

```
Usage: swift run 40HzLaptop [options]

Options:
  -f <frequency>       Set the clicking sound frequency in Hz (default: 40Hz)
  --no-click           Disable clicking sound
  --increase-bright <amount>  Increase screen brightness by the specified amount (0.0-1.0)
  --flash-bright <amount>     Flash the screen brightness by the specified amount (0.0-1.0)
  -h, --help           Display this help information

Examples:
  swift run 40HzLaptop                       Play click sound at default 40Hz
  swift run 40HzLaptop -f 40                 Play click sound at 40Hz
  swift run 40HzLaptop --increase-bright 0.1 Increase screen brightness by 10%
  swift run 40HzLaptop --flash-bright 0.1    Flash the screen brightness by 10% with each click
  swift run 40HzLaptop --no-click            Run without sound
```

## Examples

### Generate auditory clicks at 40Hz

```
swift run 40HzLaptop -f 40
```

This will generate auditory clicks at 40Hz frequency until interrupted with Ctrl+C.

### Flash the screen brightness with each click

```
swift run 40HzLaptop --flash-bright 0.2
```

This flashes the screen brightness by 20% with each click at the default 40Hz frequency.

### Combine auditory clicks and visual flashes at 40Hz

```
swift run 40HzLaptop -f 40 --flash-bright 0.1
```

This generates both 40Hz auditory clicks and visual flashes (10% brightness change) simultaneously.

### Increase screen brightness without sound

```
swift run 40HzLaptop --increase-bright 0.3 --no-click
```

This increases the screen brightness by 30% without playing any click sounds.
