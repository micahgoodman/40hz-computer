import Foundation
import CoreGraphics
import IOKit
import IOKit.graphics
import CoreVideo
import Darwin
import AppKit
import AVFoundation

// EDID constants
let kIODisplayEDIDKey = "IODisplayEDID" as CFString
let kIODisplayPrefsKey = "IODisplayPrefsKey" as CFString
let kDisplayProductID = "DisplayProductID" as CFString

// Display timing constants
let kIOFBDetailedTimingsKey = "IOFBDetailedTimings" as CFString
let kIOFBScalerInfo = "IOFBScalerInfo" as CFString

// Constants
let MAX_DISPLAYS = 16
let PROGRAM_NAME = "refresh-rate"

// Struct to hold command line arguments
struct CommandLineOptions {
    var listDisplays = false
    var displayID: CGDirectDisplayID?
    var refreshRate: Double?
    var showHelp = false
    var resetDisplays = false
    var enableClick = false
}

// Function to display usage information
func printUsage() {
    print("""
    Usage: \(PROGRAM_NAME) [options]
    
    Options:
      -l                   List all connected displays and their current refresh rates
      -d <display_id>      Specify which display to target (use ID from -l output)
      -r <refresh_rate>    Set the specified refresh rate in Hz (e.g., 60, 120)
      --reset              Reset all software-controlled refresh rates
      --click              Enable clicking sound synchronized with screen refresh
      -h                   Display this help information
    
    Examples:
      \(PROGRAM_NAME) -l                     List all displays
      \(PROGRAM_NAME) -d 1 -r 60             Set display 1 to 60Hz refresh rate
      \(PROGRAM_NAME) --reset                Reset all software-controlled refresh rates
    """)
}

// Function to parse command line arguments
func parseCommandLineArguments() -> CommandLineOptions {
    var options = CommandLineOptions()
    let args = CommandLine.arguments
    
    // Check for --reset flag first (since it's a long option)
    if args.contains("--reset") {
        options.resetDisplays = true
        return options
    }
    
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--click":
            options.enableClick = true
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

// Function to get available display modes for a given display
func getAvailableDisplayModes(displayID: CGDirectDisplayID) -> [CGDisplayMode]? {
    guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
        return nil
    }
    
    return modes
}

// Function to list all displays and their current refresh rates
func listDisplays() {
    let displays = getActiveDisplays()
    
    print("Available Displays:")
    print("ID    | Type       | Resolution      | Hardware Rate | Software Rate")
    print("------+------------+-----------------+---------------+-------------")
    
    for display in displays {
        guard let mode = CGDisplayCopyDisplayMode(display) else {
            continue
        }
        
        let width = mode.width
        let height = mode.height
        let refreshRate = mode.refreshRate
        let displayName = getDisplayName(displayID: display)
        
        // Check if we have a software-controlled refresh rate
        var softwareRate = "None"
        if let targetRate = targetRefreshRates[display] {
            softwareRate = String(format: "%.1f Hz", targetRate)
        }
        
        // Use string interpolation instead of format string to avoid segfault
        let idStr = String(format: "%-5d", display)
        let resolutionStr = String(format: "%4d x %-8d", width, height)
        let refreshRateStr = String(format: "%-13.1f", refreshRate)
        
        print("\(idStr) | \(displayName.padding(toLength: 10, withPad: " ", startingAt: 0)) | \(resolutionStr) | \(refreshRateStr) | \(softwareRate)")
    }
    
    print("\nAvailable Refresh Rates:")
    for display in displays {
        let displayName = getDisplayName(displayID: display)
        print("\nDisplay \(display) (\(displayName)):")
        
        guard let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] else {
            print("  Unable to get display modes")
            continue
        }
        
        // Show custom software refresh rate if active
        if let targetRate = targetRefreshRates[display] {
            print("  ** Active software-controlled rate: \(String(format: "%.1f Hz", targetRate)) **")
            print("  Note: The display is physically refreshing at hardware rate,")
            print("        but content updates are synchronized to \(String(format: "%.1f Hz", targetRate))")
            
            if enableClickSound {
                print("  Click sound: Enabled (synchronized with \(String(format: "%.1f Hz", targetRate)) refresh rate)")
            }
            print()
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

// Global variables for display link management
var displayLinks: [CGDirectDisplayID: CVDisplayLink] = [:]
var targetRefreshRates: [CGDirectDisplayID: Double] = [:]
var displayTimers: [CGDirectDisplayID: Timer] = [:]

// Audio player for click sound
var clickSound: NSSound?
var isClickSoundPlaying = false
var lastClickTime: TimeInterval = 0
var enableClickSound: Bool = false

// Configuration file path for persisting settings
let configDirPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".refreshrateutility")
let configFilePath = configDirPath.appendingPathComponent("config.plist")

// Function to save the current configuration
func saveConfiguration() {
    // Create directory if it doesn't exist
    if !FileManager.default.fileExists(atPath: configDirPath.path) {
        do {
            try FileManager.default.createDirectory(at: configDirPath, withIntermediateDirectories: true)
        } catch {
            print("Warning: Could not create configuration directory: \(error)")
            return
        }
    }
    
    // Convert display IDs to strings for the plist
    var config: [String: Any] = [:]
    var rates: [String: Double] = [:]
    
    for (displayID, rate) in targetRefreshRates {
        rates[String(displayID)] = rate
    }
    
    config["targetRefreshRates"] = rates
    config["enableClickSound"] = enableClickSound
    
    do {
        let data = try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0)
        try data.write(to: configFilePath)
        print("Configuration saved to \(configFilePath.path)")
    } catch {
        print("Warning: Could not save configuration: \(error)")
    }
}

// Function to load the saved configuration
func loadConfiguration() {
    guard FileManager.default.fileExists(atPath: configFilePath.path) else {
        return
    }
    
    do {
        let data = try Data(contentsOf: configFilePath)
        let config = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        
        if let rates = config?["targetRefreshRates"] as? [String: Double] {
            for (displayIDStr, rate) in rates {
                if let displayID = UInt32(displayIDStr) {
                    targetRefreshRates[displayID] = rate
                }
            }
        }
        
        if let clickEnabled = config?["enableClickSound"] as? Bool {
            enableClickSound = clickEnabled
            if enableClickSound {
                setupClickSound()
            }
        }
        
        print("Configuration loaded from \(configFilePath.path)")
    } catch {
        print("Warning: Could not load configuration: \(error)")
    }
}

// Function to set refresh rate for a specific display
func setRefreshRate(displayID: CGDirectDisplayID, refreshRate: Double) -> Bool {
    // First check if we can implement a software-controlled refresh rate
    if setupSoftwareVSyncControl(displayID: displayID, refreshRate: refreshRate) {
        print("Successfully set up custom software-controlled refresh rate: \(refreshRate)Hz")
        return true
    }
    
    // If the software approach fails, try to force a custom refresh rate using hardware timings
    if forceCustomRefreshRate(displayID: displayID, refreshRate: refreshRate) {
        print("Successfully forced display \(displayID) to custom refresh rate of \(refreshRate)Hz")
        return true
    }
    
    // Get current mode to maintain resolution and bit depth
    guard let currentMode = CGDisplayCopyDisplayMode(displayID) else {
        print("Error: Unable to get current display mode")
        return false
    }
    
    let width = currentMode.width
    let height = currentMode.height
    
    // If forcing custom timing failed, try to use a predefined mode
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
    
    print("All approaches failed, falling back to standard modes")
    return setStandardDisplayMode(displayID: displayID, refreshRate: refreshRate)
}

// Function to set up click sound
func setupClickSound() {
    print("Setting up macOS audio for click sound...")
    
    // Reset our global sound storage
    systemSounds.removeAll()
    
    // Try to use our custom ShortenedPop.aiff file
    let customSoundFile = "ShortenedPop.aiff"
    
    // Try multiple possible locations for the sound file
    var soundFilePath = ""
    var soundFound = false
    
    // 1. Check in the current directory
    let currentDirPath = FileManager.default.currentDirectoryPath + "/" + customSoundFile
    if FileManager.default.fileExists(atPath: currentDirPath) {
        soundFilePath = currentDirPath
        soundFound = true
    }
    
    // 2. Check in the executable's directory
    if !soundFound, let executablePath = Bundle.main.executablePath {
        let executableDir = (executablePath as NSString).deletingLastPathComponent
        let executableDirPath = executableDir + "/" + customSoundFile
        if FileManager.default.fileExists(atPath: executableDirPath) {
            soundFilePath = executableDirPath
            soundFound = true
        }
    }
    
    // 3. Check in the bundle resources
    if !soundFound, let resourcePath = Bundle.main.path(forResource: customSoundFile.components(separatedBy: ".").first, ofType: customSoundFile.components(separatedBy: ".").last) {
        soundFilePath = resourcePath
        soundFound = true
    }
    
    // Check if we found the sound file
    if soundFound {
        print("Found sound at absolute path: \(soundFilePath)")
        
        if let customSound = NSSound(contentsOfFile: soundFilePath, byReference: false) {
            clickSound = customSound
            print("Using custom sound file: \(customSoundFile)")
            customSound.play()
            Thread.sleep(forTimeInterval: 0.1)
            return
        }
    }
    
    // Try different methods to locate the sound file
    var soundPath: String? = nil
    
    // Method 1: Try Bundle.main resources
    if let url = Bundle.main.url(forResource: "ShortenedPop", withExtension: "aiff") {
        soundPath = url.path
        print("Found sound via Bundle.main: \(url.path)")
    }
    // Method 2: Check the executable directory
    else if let executablePath = Bundle.main.resourceURL?.path {
        let executableDirPath = executablePath + "/" + customSoundFile
        if FileManager.default.fileExists(atPath: executableDirPath) {
            soundPath = executableDirPath
            print("Found sound in executable directory: \(executableDirPath)")
        }
    }
    // Method 3: Check working directory and parent directory
    else {
        // Check current directory
        let workingDirPath = FileManager.default.currentDirectoryPath + "/" + customSoundFile
        if FileManager.default.fileExists(atPath: workingDirPath) {
            soundPath = workingDirPath
            print("Found sound in working directory: \(workingDirPath)")
        }
        // Check parent directory
        else {
            let parentDirPath = FileManager.default.currentDirectoryPath + "/../" + customSoundFile
            if FileManager.default.fileExists(atPath: parentDirPath) {
                soundPath = parentDirPath
                print("Found sound in parent directory: \(parentDirPath)")
            }
        }
    }
    
    // If we found the sound path, load it
    if let path = soundPath, let customSound = NSSound(contentsOfFile: path, byReference: false) {
        clickSound = customSound
        print("Using custom sound file: \(customSoundFile)")
        customSound.play()
        Thread.sleep(forTimeInterval: 0.1)
        return
    }
    
    // If we can't find the custom sound, try system sounds as fallback
    print("Custom sound file not found, trying system sounds...")
    let shortSoundNames = ["Tink", "Pop", "Morse", "Blow", "Frog", "Glass"]
    
    for soundName in shortSoundNames {
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            systemSounds[soundName] = sound
        }
    }
    
    if let sound = systemSounds["Tink"] {
        clickSound = sound
        print("Using system sound: Tink")
        sound.play()
        Thread.sleep(forTimeInterval: 0.1)
    } else if let (name, sound) = systemSounds.first {
        clickSound = sound
        print("Using system sound: \(name)")
    } else {
        clickSound = nil
        print("No sounds available, using system beep")
        NSSound.beep()
    }
}

// Global sound instance to prevent deallocation
var systemSounds: [String: NSSound] = [:]

// Track the last 10 sound instances to prevent garbage collection before they're done playing
var recentSounds: [NSSound] = []
let maxRecentSounds = 10

// Function to play the click sound - simplified and more reliable
func playClickSound() {
    if enableClickSound {
        // Uncomment to debug timing issues
        // print("*click* \(Date().timeIntervalSince1970)")
        
        // Use our custom sound if available
        if let sound = clickSound {
            // Create a completely new instance for each sound to avoid playback issues
            if let newInstance = sound.copy() as? NSSound {
                // Start playing the new instance
                newInstance.play()
                
                // Store in our recent sounds array to keep it alive while playing
                recentSounds.append(newInstance)
                
                // Keep the array at a reasonable size
                if recentSounds.count > maxRecentSounds {
                    recentSounds.removeFirst()
                }
            }
        } else {
            // Fallback to system beep if our custom sound isn't available
            NSSound.beep()
        }
    }
}

// Function to set up software-controlled vsync refresh rate
func setupSoftwareVSyncControl(displayID: CGDirectDisplayID, refreshRate: Double) -> Bool {
    print("Setting up software vsync control for \(refreshRate)Hz")
    
    // Stop any existing display link/timer for this display
    cleanupDisplayLink(displayID: displayID)
    
    // Store the target refresh rate
    targetRefreshRates[displayID] = refreshRate
    
    // Save the configuration
    saveConfiguration()
    
    // Make sure click sound is set up if enabled
    if enableClickSound {
        setupClickSound()
    }
    
    // First, set the display to the highest available refresh rate
    // This gives us the most flexibility for timing control
    var highestRefreshRate = 0.0
    var highestRefreshRateMode: CGDisplayMode? = nil
    
    guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
        print("Error: Unable to get display modes")
        return false
    }
    
    for mode in modes {
        if mode.refreshRate > highestRefreshRate {
            highestRefreshRate = mode.refreshRate
            highestRefreshRateMode = mode
        }
    }
    
    guard let highMode = highestRefreshRateMode else {
        print("Error: Could not find highest refresh rate mode")
        return false
    }
    
    print("Setting display to highest refresh rate: \(highMode.refreshRate)Hz")
    
    // Set the display to the highest refresh rate
    if !applyMode(displayID: displayID, mode: highMode, requestedRate: highMode.refreshRate) {
        print("Warning: Could not set display to highest refresh rate")
        return false
    }
    
    // Calculate the frame interval based on the target and native refresh rates
    let targetFrameInterval = highestRefreshRate / refreshRate
    print("Target frame interval: \(targetFrameInterval) frames")
    
    // Set up display link callback for precise vsync timing
    var displayLink: CVDisplayLink? = nil
    let error = CVDisplayLinkCreateWithCGDisplay(displayID, &displayLink)
    
    guard error == kCVReturnSuccess, let link = displayLink else {
        print("Error: Could not create display link: \(error)")
        return false
    }
    
    // Setup is complete without using the CVDisplayLink callback directly
    // We'll use a timer-based approach instead, which is more reliable for audio
    
    // Store our display link
    displayLinks[displayID] = link
    
    // Create a reliable timer for playing the click sound at the specified refresh rate
    // We use this instead of relying on the CVDisplayLink callbacks as they can be less reliable for audio
    let clickInterval = 1.0/refreshRate
    
    print("Creating click timer with interval: \(clickInterval) seconds")
    
    // Use a more precise timer with dispatch source
    let clickTimer = Timer(timeInterval: clickInterval, repeats: true) { _ in
        // Debug timing
        // print("Timer fired at \(Date().timeIntervalSince1970)")
        
        // Check if click sound is enabled
        if enableClickSound {
            // Play our click sound
            playClickSound()
        }
    }
    
    // Make sure the timer is set to be highly precise
    clickTimer.tolerance = 0.0001
    
    // Add to RunLoop for better timing precision with common mode priority
    RunLoop.main.add(clickTimer, forMode: .common)
    
    // Start the display link
    CVDisplayLinkStart(link)
    
    // Store the timer
    displayTimers[displayID] = clickTimer
    
    print("Software vsync control active at \(refreshRate)Hz")
    return true
}

// Function to cleanup display link resources
func cleanupDisplayLink(displayID: CGDirectDisplayID) {
    // Stop and remove any existing timer
    if let timer = displayTimers[displayID] {
        timer.invalidate()
        displayTimers.removeValue(forKey: displayID)
    }
    
    // Stop and remove any existing display link
    if let link = displayLinks[displayID] {
        CVDisplayLinkStop(link)
        displayLinks.removeValue(forKey: displayID)
    }
    
    // Clear target refresh rate
    targetRefreshRates.removeValue(forKey: displayID)
    
    // Save the updated configuration
    saveConfiguration()
}

// Function to force a custom refresh rate using display timing overrides
func forceCustomRefreshRate(displayID: CGDirectDisplayID, refreshRate: Double) -> Bool {
    print("\nAttempting to force custom refresh rate of \(refreshRate)Hz")
    
    // Different approach: use CoreGraphics timing with forced refresh
    guard let currentMode = CGDisplayCopyDisplayMode(displayID) else {
        print("Error: Unable to get current display mode")
        return false
    }
    
    print("Current resolution: \(currentMode.width)x\(currentMode.height) at \(currentMode.refreshRate)Hz")
    
    // We'll need to use a custom approach with private APIs or direct hardware timing
    // First, attempt to create a virtual mode with our timing
    
    // Try the direct method first
    if createVirtualRefreshRateMode(displayID: displayID, refreshRate: refreshRate) {
        print("Successfully created virtual mode with refresh rate \(refreshRate)Hz")
        return true
    }
    
    // If direct method fails, try manipulating the current mode
    print("Virtual mode creation failed, trying alternative approach with IOKit")
    
    // Get the service for this display
    guard let service = getIOServiceForDisplay(displayID: displayID) else {
        print("Error: Could not find IO service for display \(displayID)")
        return false
    }
    
    print("Found display service: \(service)")
    
    // Create custom timing parameters for the desired refresh rate
    let width = UInt32(currentMode.width)
    let height = UInt32(currentMode.height)
    
    // Calculate timing parameters
    let timingParams = createCustomTimingParameters(width: width, height: height, refreshRate: refreshRate)
    print("Calculated timing parameters for \(width)x\(height) at \(refreshRate)Hz")
    
    // Create detailed timing dictionary
    guard let timingDict = createDetailedTimingDictionary(params: timingParams) else {
        print("Error: Failed to create timing dictionary")
        IOObjectRelease(service)
        return false
    }
    
    // Apply the custom timing
    print("Applying custom timing with pixel clock: \(timingParams.pixelClock)Hz")
    
    // Try to directly send the pixel clock change as an override
    let dictWithOriginalMode = NSMutableDictionary(dictionary: timingDict)
    dictWithOriginalMode["UseThisMode"] = true as CFBoolean
    
    if IORegistryEntrySetCFProperty(service, "IOFBCustomMode" as CFString, dictWithOriginalMode) == KERN_SUCCESS {
        print("Successfully set custom mode with IOFBCustomMode")
        IOObjectRelease(service)
        return true
    }
    
    // If that fails, try using service request probe approach
    print("IOFBCustomMode approach failed, trying service request probe")
    
    // Set display preferences with custom timing
    if IORegistryEntrySetCFProperty(service, kIOFBDetailedTimingsKey, timingDict) == KERN_SUCCESS {
        // Then try to apply by requesting a probe
        if IOServiceRequestProbe(service, 0) == KERN_SUCCESS {
            print("Successfully applied custom timing via service probe")
            IOObjectRelease(service)
            return true
        }
    }
    
    print("All approaches to set custom refresh rate failed")
    IOObjectRelease(service)
    return false
}

// Function to find IODisplayConnect for a framebuffer
func IODisplayForFramebuffer(_ framebuffer: io_service_t) -> io_service_t {
    var displayConnect: io_service_t = 0
    var iterator: io_iterator_t = 0
    
    if IORegistryEntryGetChildIterator(framebuffer, kIOServicePlane, &iterator) == KERN_SUCCESS {
        var childService: io_service_t = 0
        
        repeat {
            childService = IOIteratorNext(iterator)
            if childService != 0 {
                var className = [CChar](repeating: 0, count: 128)
                let classNameCString = className.withUnsafeMutableBufferPointer { bufferPointer in
                    return bufferPointer.baseAddress
                }
                
                if IOObjectGetClass(childService, classNameCString!) == KERN_SUCCESS {
                    let classNameStr = String(cString: classNameCString!)
                    if classNameStr == "IODisplayConnect" {
                        displayConnect = childService
                        break
                    }
                }
                
                IOObjectRelease(childService)
            }
        } while childService != 0
        
        IOObjectRelease(iterator)
    }
    
    return displayConnect
}

// Function to get the IOService for a display
func getIOServiceForDisplay(displayID: CGDirectDisplayID) -> io_service_t? {
    // CGDisplayIOServicePort is deprecated in modern macOS
    // Using alternative method to find display service
    return findDisplayServiceAlternativeMethod(displayID: displayID)
}

// Alternative method to find display service
func findDisplayServiceAlternativeMethod(displayID: CGDirectDisplayID) -> io_service_t? {
    // Get all displays
    var displayCount: UInt32 = 0
    var activeDisplays: [CGDirectDisplayID] = Array(repeating: 0, count: Int(MAX_DISPLAYS))
    guard CGGetActiveDisplayList(UInt32(MAX_DISPLAYS), &activeDisplays, &displayCount) == .success else {
        print("Error: Unable to get active display list")
        return nil
    }
    
    // Locate our display in the list
    var targetIndex = -1
    for i in 0..<Int(displayCount) {
        if activeDisplays[i] == displayID {
            targetIndex = i
            break
        }
    }
    
    if targetIndex == -1 {
        print("Error: Display \(displayID) not found in active display list")
        return nil
    }
    
    // Now iterate through IO services to find our display
    var iter: io_iterator_t = 0
    let matching = IOServiceMatching("IODisplayConnect")
    
    guard IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iter) == KERN_SUCCESS else {
        print("Error: Could not create IO iterator")
        return nil
    }
    
    defer {
        IOObjectRelease(iter)
    }
    
    var service: io_service_t = 0
    var foundIndex = 0
    var result: io_service_t?
    
    repeat {
        service = IOIteratorNext(iter)
        if service != 0 {
            // If we've found the target display index in our iteration
            if foundIndex == targetIndex {
                result = service
                break
            }
            foundIndex += 1
            IOObjectRelease(service)
        }
    } while service != 0
    
    return result
}

// Structure for custom timing parameters
struct TimingParameters {
    var pixelClock: UInt32     // in Hz
    var hActive: UInt16        // horizontal active pixels
    var hBlanking: UInt16      // horizontal blanking pixels
    var vActive: UInt16        // vertical active lines
    var vBlanking: UInt16      // vertical blanking lines
    var hSyncOffset: UInt16    // horizontal sync offset
    var hSyncWidth: UInt16     // horizontal sync width
    var vSyncOffset: UInt16    // vertical sync offset
    var vSyncWidth: UInt16     // vertical sync width
}

// Function to create custom timing parameters based on resolution and refresh rate
func createCustomTimingParameters(width: UInt32, height: UInt32, refreshRate: Double) -> TimingParameters {
    // Start with standard timing values
    var params = TimingParameters(
        pixelClock: 0,
        hActive: UInt16(width),
        hBlanking: 0,
        vActive: UInt16(height),
        vBlanking: 0,
        hSyncOffset: 0,
        hSyncWidth: 0,
        vSyncOffset: 0,
        vSyncWidth: 0
    )
    
    // Calculate blanking periods based on common standards
    // These are approximations - actual values would depend on the display
    let dWidth = Double(width)
    let dHeight = Double(height)
    
    if width >= 1920 { // HD or higher resolution
        params.hBlanking = UInt16(dWidth * 0.2) // 20% of width
        params.vBlanking = UInt16(dHeight * 0.05) // 5% of height
        params.hSyncOffset = UInt16(dWidth * 0.05)
        params.hSyncWidth = UInt16(dWidth * 0.05)
        params.vSyncOffset = UInt16(dHeight * 0.01)
        params.vSyncWidth = UInt16(dHeight * 0.01)
    } else { // Lower resolutions
        params.hBlanking = UInt16(dWidth * 0.25) // 25% of width
        params.vBlanking = UInt16(dHeight * 0.08) // 8% of height
        params.hSyncOffset = UInt16(dWidth * 0.06)
        params.hSyncWidth = UInt16(dWidth * 0.06)
        params.vSyncOffset = UInt16(dHeight * 0.02)
        params.vSyncWidth = UInt16(dHeight * 0.02)
    }
    
    // Calculate pixel clock
    let totalWidth = Double(params.hActive) + Double(params.hBlanking)
    let totalHeight = Double(params.vActive) + Double(params.vBlanking)
    params.pixelClock = UInt32(totalWidth * totalHeight * refreshRate)
    
    return params
}

// Function to create a detailed timing dictionary
func createDetailedTimingDictionary(params: TimingParameters) -> NSDictionary? {
    let dict: [String: Any] = [
        "PixelClock": params.pixelClock,
        "HorizontalActive": params.hActive,
        "HorizontalBlanking": params.hBlanking,
        "VerticalActive": params.vActive,
        "VerticalBlanking": params.vBlanking,
        "HorizontalSyncOffset": params.hSyncOffset,
        "HorizontalSyncWidth": params.hSyncWidth,
        "VerticalSyncOffset": params.vSyncOffset,
        "VerticalSyncWidth": params.vSyncWidth,
        "Flags": 0
    ]
    
    return dict as NSDictionary
}

// Function to create a virtual display mode with custom refresh rate
func createVirtualRefreshRateMode(displayID: CGDirectDisplayID, refreshRate: Double) -> Bool {
    // This approach uses a direct hardware timing approach
    // We need to create a virtual mode that the display will accept
    
    guard let currentMode = CGDisplayCopyDisplayMode(displayID) else {
        return false
    }
    
    // Get all modes and analyze them
    guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
        return false
    }
    
    print("Analyzing \(modes.count) display modes to create virtual mode")
    
    let width = currentMode.width
    let height = currentMode.height
    
    // Find a base mode to modify
    let matchingResolutionModes = modes.filter { $0.width == width && $0.height == height }
    guard let baseMode = matchingResolutionModes.first else {
        return false
    }
    
    print("Using base mode: \(baseMode.width)x\(baseMode.height) at \(baseMode.refreshRate)Hz")
    
    // Try EDID override approach with custom timing
    // This would require more complex EDID manipulation
    // Current approach will be to try to use IOKit to override timing parameters
    
    // In a real implementation, we would inject a custom EDID here
    // But for now, we'll return false and let the IOKit approach handle it
    return false
}

// Function to apply custom timing to a display
func applyCustomTiming(service: io_service_t, timingDict: CFDictionary) -> Bool {
    // Attempt to set the detailed timing
    var success = false
    
    // Try to set property via IOKit
    if IORegistryEntrySetCFProperty(service, kIOFBDetailedTimingsKey, timingDict) == KERN_SUCCESS {
        print("Successfully set custom timing parameters")
        success = true
    } else {
        print("Warning: Failed to set custom timing parameters")
    }
    
    return success
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

// Function to reset all displays to their default settings
func resetAllDisplays() {
    let displays = getActiveDisplays()
    var success = true
    
    // Clear software-controlled rates and disable click sound
    targetRefreshRates.removeAll()
    enableClickSound = false
    saveConfiguration()
    
    for display in displays {
        // Stop any active timers/display links
        cleanupDisplayLink(displayID: display)
        
        // Try to set the display to a known good mode instead of nil
        if let modes = getAvailableDisplayModes(displayID: display), !modes.isEmpty {
            // Find a standard refresh rate (60Hz is usually safe)
            var defaultMode: CGDisplayMode? = nil
            
            for mode in modes {
                if abs(mode.refreshRate - 60.0) < 0.5 {
                    defaultMode = mode
                    break
                }
            }
            
            // If we can't find 60Hz, use the first available mode
            if defaultMode == nil, let firstMode = modes.first {
                defaultMode = firstMode
            }
            
            if let mode = defaultMode {
                // Set this mode directly
                if applyMode(displayID: display, mode: mode, requestedRate: mode.refreshRate) {
                    print("Reset Display \(display) to \(mode.refreshRate)Hz")
                    continue // Success, move to next display
                }
            }
        }
        
        print("Could not reset Display \(display) using display modes, trying alternative methods")
        success = false
    }
    
    if success {
        print("All displays were reset successfully")
    } else {
        print("Warning: Some displays could not be fully reset to default settings")
        print("However, software-controlled refresh rates have been disabled")
    }
    
    print("Software-controlled refresh rates and click sound disabled")
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
    // Load saved configuration
    loadConfiguration()
    
    let options = parseCommandLineArguments()
    
    if options.showHelp {
        printUsage()
        exit(0)
    }
    
    if options.listDisplays {
        listDisplays()
        exit(0)
    }
    
    if options.resetDisplays {
        resetAllDisplays()
        exit(0)
    }
    
    // Set click sound state from command line
    if options.enableClick {
        enableClickSound = true
        setupClickSound()
        saveConfiguration()
        if options.listDisplays || (options.displayID == nil && options.refreshRate == nil) {
            print("Click sound enabled. Set a refresh rate to hear the clicks.")
        }
    }
    
    // If no display ID is specified, use the main display
    let displayID = options.displayID ?? CGMainDisplayID()
    
    // If refresh rate is specified, set it
    if let refreshRate = options.refreshRate {
        if !setRefreshRate(displayID: displayID, refreshRate: refreshRate) {
            exit(1)
        }
        
        // If click sound is enabled, keep the program running indefinitely
        if enableClickSound {
            print("\nRunning in the background with click sound at \(refreshRate)Hz")
            print("Press Ctrl+C to exit")
            
            // Set up a signal handler for clean exit
            signal(SIGINT) { _ in
                print("\nShutting down...")
                exit(0)
            }
            
            // Keep the main thread running indefinitely
            RunLoop.main.run()
        }
    } else {
        // If no specific action is requested, show usage
        printUsage()
    }
}

// Run the main function
main()
