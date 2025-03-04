import Foundation
import CoreGraphics
import IOKit
import IOKit.graphics

// Constants
let MAX_DISPLAYS = 16
let PROGRAM_NAME = "refresh-rate"

// Struct to hold command line arguments
struct CommandLineOptions {
    var listDisplays = false
    var displayID: CGDirectDisplayID?
    var refreshRate: Double?
    var showHelp = false
}

// Function to display usage information
func printUsage() {
    print("""
    Usage: \(PROGRAM_NAME) [options]
    
    Options:
      -l                   List all connected displays and their current refresh rates
      -d <display_id>      Specify which display to target (use ID from -l output)
      -r <refresh_rate>    Set the specified refresh rate in Hz (e.g., 60, 120)
      -h                   Display this help information
    
    Examples:
      \(PROGRAM_NAME) -l                     List all displays
      \(PROGRAM_NAME) -d 1 -r 60             Set display 1 to 60Hz refresh rate
    """)
}

// Function to parse command line arguments
func parseCommandLineArguments() -> CommandLineOptions {
    var options = CommandLineOptions()
    let args = CommandLine.arguments
    
    var i = 1
    while i < args.count {
        switch args[i] {
        case "-l":
            options.listDisplays = true
        case "-d":
            if i + 1 < args.count, let displayIndex = Int(args[i + 1]) {
                options.displayID = CGDirectDisplayID(displayIndex)
                i += 1
            } else {
                print("Error: -d requires a display ID")
                exit(1)
            }
        case "-r":
            if i + 1 < args.count, let refreshRate = Double(args[i + 1]) {
                options.refreshRate = refreshRate
                i += 1
            } else {
                print("Error: -r requires a refresh rate value")
                exit(1)
            }
        case "-h":
            options.showHelp = true
        default:
            print("Unknown option: \(args[i])")
            printUsage()
            exit(1)
        }
        i += 1
    }
    
    return options
}

// Function to get all active displays
func getActiveDisplays() -> [CGDirectDisplayID] {
    var displayCount: UInt32 = 0
    var displayIDs = [CGDirectDisplayID](repeating: 0, count: MAX_DISPLAYS)
    
    guard CGGetActiveDisplayList(UInt32(MAX_DISPLAYS), &displayIDs, &displayCount) == .success else {
        print("Error: Unable to get display list")
        exit(1)
    }
    
    return Array(displayIDs[0..<Int(displayCount)])
}

// Function to get display name
func getDisplayName(displayID: CGDirectDisplayID) -> String {
    let displayName: String
    
    if displayID == CGMainDisplayID() {
        displayName = "Main Display"
    } else {
        displayName = "Display \(displayID)"
    }
    
    return displayName
}

// Function to list all displays and their current refresh rates
func listDisplays() {
    let displays = getActiveDisplays()
    
    print("Available Displays:")
    print("ID    | Type       | Resolution      | Refresh Rate")
    print("------+------------+-----------------+-------------")
    
    for display in displays {
        guard let mode = CGDisplayCopyDisplayMode(display) else {
            continue
        }
        
        let width = mode.width
        let height = mode.height
        let refreshRate = mode.refreshRate
        let displayName = getDisplayName(displayID: display)
        
        print(String(format: "%-5d | %-10s | %4d x %-8d | %.1f Hz", 
                     display, 
                     displayName, 
                     width, 
                     height, 
                     refreshRate))
    }
    
    print("\nAvailable Refresh Rates:")
    for display in displays {
        let displayName = getDisplayName(displayID: display)
        print("\nDisplay \(display) (\(displayName)):")
        
        guard let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] else {
            print("  Unable to get display modes")
            continue
        }
        
        // Create a set of unique refresh rates
        var refreshRates = Set<Double>()
        for mode in modes {
            let rate = mode.refreshRate
            if rate > 0 {
                refreshRates.insert(rate)
            }
        }
        
        // Sort and print the refresh rates
        let sortedRates = refreshRates.sorted()
        if sortedRates.isEmpty {
            print("  No refresh rates available")
        } else {
            print("  Available rates: \(sortedRates.map { String(format: "%.1f Hz", $0) }.joined(separator: ", "))")
        }
    }
}

// Function to set refresh rate for a specific display
func setRefreshRate(displayID: CGDirectDisplayID, refreshRate: Double) -> Bool {
    // Get current mode to maintain resolution and bit depth
    guard let currentMode = CGDisplayCopyDisplayMode(displayID) else {
        print("Error: Unable to get current display mode")
        return false
    }
    
    // Create a custom timing mode dictionary
    let width = currentMode.width
    let height = currentMode.height
    
    // Try to create a custom mode with the desired refresh rate
    if let customMode = createCustomMode(width: width, height: height, refreshRate: refreshRate, displayID: displayID) {
        // Apply the custom mode
        if applyCustomMode(displayID: displayID, mode: customMode) {
            // Check if we actually got the exact refresh rate or something close
            if abs(customMode.refreshRate - refreshRate) < 0.1 {
                print("Successfully set display \(displayID) to exactly \(refreshRate)Hz")
            } else {
                print("Note: Could not set exact \(refreshRate)Hz. Using closest available: \(customMode.refreshRate)Hz")
            }
            return true
        }
    }
    
    print("Custom mode setting failed, falling back to standard modes")
    return setStandardDisplayMode(displayID: displayID, refreshRate: refreshRate)
}



// Function to create a custom display mode
func createCustomMode(width: Int, height: Int, refreshRate: Double, displayID: CGDirectDisplayID) -> CGDisplayMode? {
    // Get all available modes for this display
    guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
        return nil
    }
    
    // Print all available modes for debugging
    print("\nAvailable modes for display \(displayID):")
    let uniqueRates = Set(modes.map { $0.refreshRate }).sorted()
    print("Available refresh rates: \(uniqueRates.map { String(format: "%.1f", $0) }.joined(separator: ", "))Hz")
    
    // First try to find a mode with the exact refresh rate requested
    for mode in modes {
        if abs(mode.refreshRate - refreshRate) < 0.1 {
            print("Found exact refresh rate match: \(mode.refreshRate)Hz at \(mode.width)x\(mode.height)")
            return mode
        }
    }
    
    // If no exact match, find the closest refresh rate
    print("No exact match for \(refreshRate)Hz. Finding closest available rate...")
    
    // Filter modes to match current resolution if possible
    var candidateModes = modes.filter { $0.width == width && $0.height == height }
    
    // If no modes match the resolution, use all modes
    if candidateModes.isEmpty {
        candidateModes = modes
    }
    
    // Find the closest refresh rate
    if !candidateModes.isEmpty {
        let closestMode = candidateModes.min(by: { abs($0.refreshRate - refreshRate) < abs($1.refreshRate - refreshRate) })!
        print("Selected closest refresh rate: \(closestMode.refreshRate)Hz at \(closestMode.width)x\(closestMode.height)")
        return closestMode
    }
    
    return nil
}

// Function to apply a custom mode
func applyCustomMode(displayID: CGDirectDisplayID, mode: CGDisplayMode) -> Bool {
    // We can't directly set a custom refresh rate in modern macOS
    // We'll use the standard approach but with a special flag
    
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else {
        print("Error: Unable to begin display configuration")
        return false
    }
    
    // Configure the display with the mode
    guard CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil) == .success else {
        print("Error: Unable to configure display with custom mode")
        return false
    }
    
    // Apply the configuration
    let result = CGCompleteDisplayConfiguration(config, .permanently)
    
    return result == .success
}

// Fallback function to set standard display mode
func setStandardDisplayMode(displayID: CGDirectDisplayID, refreshRate: Double) -> Bool {
    guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
        print("Error: Unable to get display modes")
        return false
    }
    
    // Get current mode to maintain resolution and bit depth
    guard let currentMode = CGDisplayCopyDisplayMode(displayID) else {
        print("Error: Unable to get current display mode")
        return false
    }
    
    // First try to find a mode with the exact refresh rate, regardless of resolution
    var exactRateMode: CGDisplayMode?
    for mode in modes {
        if abs(mode.refreshRate - refreshRate) < 0.1 {
            exactRateMode = mode
            print("Found mode with exact refresh rate: \(mode.refreshRate)Hz at resolution \(mode.width)x\(mode.height)")
            break
        }
    }
    
    // If we found a mode with the exact refresh rate, use it
    if exactRateMode != nil {
        return applyMode(displayID: displayID, mode: exactRateMode!, requestedRate: refreshRate)
    }
    
    // If no exact refresh rate match, try to find modes with the current resolution
    let currentWidth = currentMode.width
    let currentHeight = currentMode.height
    
    // Try to find modes that match the current resolution exactly
    var matchingResolutionModes = modes.filter { mode in
        return mode.width == currentWidth && mode.height == currentHeight
    }
    
    // If no exact resolution matches, try to find modes with any resolution
    if matchingResolutionModes.isEmpty {
        print("Note: No exact resolution matches found for \(currentWidth)x\(currentHeight)")
        print("Looking for modes with any resolution...")
        
        // Use all available modes
        matchingResolutionModes = modes
        
        // Print available resolutions for debugging
        let availableResolutions = Set(modes.map { "\($0.width)x\($0.height)" }).sorted()
        print("Available resolutions: \(availableResolutions.joined(separator: ", "))")
    }
    
    if matchingResolutionModes.isEmpty {
        print("Error: No display modes found at all")
        return false
    }
    
    // Get available rates
    let availableRates = matchingResolutionModes.map { $0.refreshRate }.filter { $0 > 0 }.sorted()
    print("Note: Custom refresh rate setting failed. Falling back to standard modes.")
    print("Available refresh rates: \(availableRates.map { String(format: "%.1f", $0) }.joined(separator: ", "))Hz")
    
    // Find exact match first
    var targetMode: CGDisplayMode?
    for mode in matchingResolutionModes {
        if abs(mode.refreshRate - refreshRate) < 0.1 {
            targetMode = mode
            break
        }
    }
    
    // If no exact match, find closest refresh rate
    if targetMode == nil {
        print("Warning: No exact match found for \(refreshRate)Hz refresh rate")
        
        if !availableRates.isEmpty {
            // Find the closest available refresh rate
            let closestRate = availableRates.min(by: { abs($0 - refreshRate) < abs($1 - refreshRate) })!
            print("Using closest available refresh rate: \(closestRate)Hz")
            
            for mode in matchingResolutionModes {
                if abs(mode.refreshRate - closestRate) < 0.1 {
                    targetMode = mode
                    break
                }
            }
        }
    }
    
    guard let newMode = targetMode else {
        print("Error: No suitable display mode found")
        return false
    }
    
    // Set up the configuration
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else {
        print("Error: Unable to begin display configuration")
        return false
    }
    
    // Configure the display with the new mode
    guard CGConfigureDisplayWithDisplayMode(config, displayID, newMode, nil) == .success else {
        print("Error: Unable to configure display with new mode")
        return false
    }
    
    // Apply the configuration
    let result = CGCompleteDisplayConfiguration(config, .permanently)
    
    if result == .success {
        print("Successfully set display \(displayID) to \(newMode.refreshRate)Hz")
        return true
    } else {
        print("Error: Unable to apply display configuration (error code: \(result))")
        return false
    }
}

// Helper function to apply a display mode
func applyMode(displayID: CGDirectDisplayID, mode: CGDisplayMode, requestedRate: Double) -> Bool {
    // Set up the configuration
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else {
        print("Error: Unable to begin display configuration")
        return false
    }
    
    // Configure the display with the mode
    guard CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil) == .success else {
        print("Error: Unable to configure display with mode")
        return false
    }
    
    // Apply the configuration
    let result = CGCompleteDisplayConfiguration(config, .permanently)
    
    if result == .success {
        print("Successfully set display \(displayID) to \(mode.refreshRate)Hz (requested: \(requestedRate)Hz)")
        return true
    } else {
        print("Error: Unable to apply display configuration (error code: \(result))")
        return false
    }
}

// Main function
func main() {
    let options = parseCommandLineArguments()
    
    if options.showHelp {
        printUsage()
        exit(0)
    }
    
    if options.listDisplays {
        listDisplays()
        exit(0)
    }
    
    // If no display ID is specified, use the main display
    let displayID = options.displayID ?? CGMainDisplayID()
    
    // If refresh rate is specified, set it
    if let refreshRate = options.refreshRate {
        if !setRefreshRate(displayID: displayID, refreshRate: refreshRate) {
            exit(1)
        }
    } else {
        // If no specific action is requested, show usage
        printUsage()
    }
}

// Run the main function
main()
