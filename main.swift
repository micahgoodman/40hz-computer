import Foundation
import AppKit
import AVFoundation
import IOKit
import IOKit.pwr_mgt
import CoreGraphics

// Constants
let PROGRAM_NAME = "click-sound-utility"
let kIODisplayBrightnessKey = "brightness" as CFString

// Import DisplayServices functions for brightness control (Apple Silicon/macOS 11+)
@_silgen_name("DisplayServicesCanChangeBrightness")
func DisplayServicesCanChangeBrightness(_ display: CGDirectDisplayID) -> Bool

@_silgen_name("DisplayServicesBrightnessChanged")
func DisplayServicesBrightnessChanged(_ display: CGDirectDisplayID, _ brightness: Double)

@_silgen_name("DisplayServicesGetBrightness")
func DisplayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32

@_silgen_name("DisplayServicesSetBrightness")
func DisplayServicesSetBrightness(_ display: CGDirectDisplayID, _ brightness: Float) -> Int32

// Import CoreDisplay functions for brightness control (older macOS versions)
@_silgen_name("CoreDisplay_Display_SetUserBrightness")
func CoreDisplay_Display_SetUserBrightness(_ display: CGDirectDisplayID, _ brightness: Double)

@_silgen_name("CoreDisplay_Display_GetUserBrightness")
func CoreDisplay_Display_GetUserBrightness(_ display: CGDirectDisplayID) -> Double

// CGDisplayIOServicePort is deprecated but still useful for our purposes
@_silgen_name("CGDisplayIOServicePort")
func CGDisplayIOServicePort(_ display: CGDirectDisplayID) -> io_service_t



// Struct to hold command line arguments
struct CommandLineOptions {
    var frequency: Double = 40.0
    var showHelp = false
    var enableClick = true
    var increaseBrightness: Float? = nil // Optional value for brightness increase
    var flashBrightness: Float? = nil // Optional value for brightness flashing
}

// Function to display usage information
func printUsage() {
    print("""
    Usage: \(PROGRAM_NAME) [options]
    
    Options:
      -f <frequency>       Set the clicking sound frequency in Hz (default: 40Hz)
      --no-click           Disable clicking sound
      --increase-bright <amount>  Increase screen brightness by the specified amount (0.0-1.0)
      --flash-bright <amount>     Flash the screen brightness by the specified amount (0.0-1.0)
      -h, --help           Display this help information
    
    Examples:
      \(PROGRAM_NAME)                       Play click sound at default 40Hz
      \(PROGRAM_NAME) -f 40                Play click sound at 40Hz
      \(PROGRAM_NAME) --increase-bright 0.1  Increase screen brightness by 10%
      \(PROGRAM_NAME) --flash-bright 0.1    Flash the screen brightness by 10% with each click
      \(PROGRAM_NAME) --no-click           Run without sound
    """)
}

// Function to parse command line arguments
func parseCommandLineArguments() -> CommandLineOptions {
    var options = CommandLineOptions()
    let args = CommandLine.arguments
    
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--no-click":
            options.enableClick = false
        case "-f", "--frequency":
            if i + 1 < args.count, let frequency = Double(args[i + 1]) {
                options.frequency = frequency
                i += 1
            } else {
                print("Error: -f requires a frequency value")
                exit(1)
            }
        case "--increase-bright":
            if i + 1 < args.count, let amount = Float(args[i + 1]) {
                if amount < 0 || amount > 1 {
                    print("Error: Brightness increase must be between 0.0 and 1.0")
                    exit(1)
                }
                options.increaseBrightness = amount
                i += 1
            } else {
                print("Error: --increase-bright requires a decimal value (e.g., 0.1 for 10%)")
                exit(1)
            }
        case "--flash-bright":
            if i + 1 < args.count, let amount = Float(args[i + 1]) {
                if amount < 0 || amount > 1 {
                    print("Error: Brightness flash amount must be between 0.0 and 1.0")
                    exit(1)
                }
                options.flashBrightness = amount
                i += 1
            } else {
                print("Error: --flash-bright requires a decimal value (e.g., 0.1 for 10%)")
                exit(1)
            }
        case "-h", "--help":
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

// Audio player for click sound
var clickSound: NSSound?
var recentSounds: [NSSound] = []
let maxRecentSounds = 10
var enableClickSound: Bool = false
var clickTimer: Timer?

// Brightness flashing variables
var originalBrightness: Float = 0.5
var flashBrightnessAmount: Float = 0.0
var isBrightnessFlashing: Bool = false

// Configuration file path for persisting settings
let configDirPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".clicksoundutility")
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
    
    let config: [String: Any] = [
        "enableClickSound": enableClickSound,
        "frequency": clickTimer?.timeInterval != nil ? 1.0 / (clickTimer?.timeInterval ?? 1/60) : 40.0
    ]
    
    do {
        let data = try PropertyListSerialization.data(
            fromPropertyList: config,
            format: .xml,
            options: 0
        )
        try data.write(to: configFilePath)
        print("Configuration saved to \(configFilePath.path)")
    } catch {
        print("Warning: Could not save configuration: \(error)")
    }
}

// Function to load the configuration
func loadConfiguration() {
    guard FileManager.default.fileExists(atPath: configFilePath.path) else {
        print("No configuration file found, using defaults")
        return
    }
    
    do {
        let data = try Data(contentsOf: configFilePath)
        guard let config = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            print("Warning: Invalid configuration format")
            return
        }
        
        if let clickEnabled = config["enableClickSound"] as? Bool {
            enableClickSound = clickEnabled
        }
        
        if let frequency = config["frequency"] as? Double {
            // This will be used when starting the timer
            print("Loaded frequency: \(frequency)Hz")
        }
        
        // No more brightness pulse settings to load
        
        print("Configuration loaded from \(configFilePath.path)")
    } catch {
        print("Warning: Could not load configuration: \(error)")
    }
}

// Function to set up click sound
func setupClickSound() {
    print("Setting up macOS audio for click sound...")
    
    // Reset our global sound storage
    recentSounds.removeAll()
    
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
    
    // If we can't find the custom sound, try system sounds as fallback
    print("Custom sound file not found, trying system sounds...")
    let shortSoundNames = ["Tink", "Pop", "Morse", "Blow", "Frog", "Glass"]
    
    var systemSounds: [String: NSSound] = [:]
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

// Function to play the click sound - simplified and more reliable
func playClickSound() {
    if enableClickSound {
        // Use our custom sound if available
        if let sound = clickSound {
            // Create a completely new instance for each sound to avoid playback issues
            if let newInstance = sound.copy() as? NSSound {
                // If brightness flashing is enabled, increase brightness when sound starts
                if isBrightnessFlashing && flashBrightnessAmount > 0 {
                    // Get current brightness if we don't have it stored
                    if originalBrightness <= 0 {
                        originalBrightness = getCurrentBrightness()
                    }
                    
                    // Calculate the increased brightness (constrained to 0-1 range)
                    let increasedBrightness = min(1.0, originalBrightness + flashBrightnessAmount)
                    
                    // Set the increased brightness
                    _ = setBrightness(increasedBrightness)
                }
                
                // Set up a delegate to handle when sound finishes playing
                newInstance.delegate = SoundDelegate.shared
                
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

// Sound delegate to handle when sound finishes playing
class SoundDelegate: NSObject, NSSoundDelegate {
    static let shared = SoundDelegate()
    
    func sound(_ sound: NSSound, didFinishPlaying successfully: Bool) {
        // If brightness flashing is enabled, restore original brightness when sound finishes
        if isBrightnessFlashing && flashBrightnessAmount > 0 {
            // Restore original brightness
            _ = setBrightness(originalBrightness)
        }
        
        // Remove this sound from our recent sounds array
        if let index = recentSounds.firstIndex(of: sound) {
            recentSounds.remove(at: index)
        }
    }
}

// Function to start the click sound timer
func startClickTimer(frequency: Double) {
    // Stop any existing timer
    clickTimer?.invalidate()
    
    // Calculate the interval
    let interval = 1.0 / frequency
    
    print("Starting click sound timer at \(frequency)Hz (interval: \(interval) seconds)")
    
    // Create a new timer
    clickTimer = Timer(timeInterval: interval, repeats: true) { _ in
        playClickSound()
    }
    
    // Add to the run loop
    if let timer = clickTimer {
        RunLoop.main.add(timer, forMode: .common)
    }
}

// Function to stop click sound timer
func stopClickSound() {
    // Stop the timer
    clickTimer?.invalidate()
    clickTimer = nil
    
    // Save the updated configuration
    saveConfiguration()
}

// Helper function to get the IO service port for a display
func getIOServicePortForDisplay(_ displayID: CGDirectDisplayID) -> io_service_t {
    var service: io_service_t = 0
    var iterator: io_iterator_t = 0
    
    // Try to match IODisplayConnect service
    let result = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
    if result != kIOReturnSuccess {
        return 0
    }
    
    // Iterate through all display services
    service = IOIteratorNext(iterator)
    while service != 0 {
        // Get the service for the main display
        if CGDisplayIOServicePort(displayID) == service {
            IOObjectRelease(iterator)
            return service
        }
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
    
    IOObjectRelease(iterator)
    return 0
}

// Function to get current display brightness
func getCurrentBrightness() -> Float {
    let mainDisplay = CGMainDisplayID()
    var brightness: Float = 0.5  // Default value if we can't get the actual brightness
    
    // 1. Try DisplayServices API (Apple Silicon/macOS 11+)
    if let getFunc = unsafeBitCast(DisplayServicesGetBrightness, to: Optional<(CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32>.self) {
        var currentBrightness: Float = 0
        if getFunc(mainDisplay, &currentBrightness) == 0 {
            print("Got brightness using DisplayServices API: \(currentBrightness)")
            return currentBrightness
        }
    }
    
    // 2. Try CoreDisplay API
    if let getFunc = unsafeBitCast(CoreDisplay_Display_GetUserBrightness, to: Optional<(CGDirectDisplayID) -> Double>.self) {
        if let canChangeFunc = unsafeBitCast(DisplayServicesCanChangeBrightness, to: Optional<(CGDirectDisplayID) -> Bool>.self) {
            if !canChangeFunc(mainDisplay) {
                print("Display cannot change brightness")
            } else {
                let currentBrightness = Float(getFunc(mainDisplay))
                print("Got brightness using CoreDisplay API: \(currentBrightness)")
                return currentBrightness
            }
        } else {
            // Try without checking if we can change brightness
            let currentBrightness = Float(getFunc(mainDisplay))
            print("Got brightness using CoreDisplay API: \(currentBrightness)")
            return currentBrightness
        }
    }
    
    // 3. Fall back to IOKit API
    let service = getIOServicePortForDisplay(mainDisplay)
    if service != 0 {
        var current: Float = 0
        if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey, &current) == kIOReturnSuccess {
            brightness = current
            print("Got brightness using IOKit API: \(brightness)")
            IOObjectRelease(service)
            return brightness
        }
        IOObjectRelease(service)
    }
    
    print("Warning: Could not get current brightness from any API")
    return brightness
}

// Function to set display brightness
func setBrightness(_ brightness: Float) -> Bool {
    let constrainedBrightness = max(0, min(1, brightness))
    let mainDisplay = CGMainDisplayID()
    
    // 1. Try DisplayServices API (Apple Silicon/macOS 11+)
    if let setFunc = unsafeBitCast(DisplayServicesSetBrightness, to: Optional<(CGDirectDisplayID, Float) -> Int32>.self) {
        if setFunc(mainDisplay, constrainedBrightness) == 0 {
            return true
        }
    }
    
    // 2. Try CoreDisplay API
    if let setFunc = unsafeBitCast(CoreDisplay_Display_SetUserBrightness, to: Optional<(CGDirectDisplayID, Double) -> Void>.self) {
        if let canChangeFunc = unsafeBitCast(DisplayServicesCanChangeBrightness, to: Optional<(CGDirectDisplayID) -> Bool>.self) {
            if !canChangeFunc(mainDisplay) {
                print("Display cannot change brightness")
            } else {
                setFunc(mainDisplay, Double(constrainedBrightness))
                
                // Notify system about brightness change
                if let notifyFunc = unsafeBitCast(DisplayServicesBrightnessChanged, to: Optional<(CGDirectDisplayID, Double) -> Void>.self) {
                    notifyFunc(mainDisplay, Double(constrainedBrightness))
                }
                
                print("Set brightness using CoreDisplay API: \(constrainedBrightness)")
                return true
            }
        } else {
            // Try without checking if we can change brightness
            setFunc(mainDisplay, Double(constrainedBrightness))
            print("Set brightness using CoreDisplay API: \(constrainedBrightness)")
            return true
        }
    }
    
    // 3. Fall back to IOKit API
    let service = getIOServicePortForDisplay(mainDisplay)
    if service != 0 {
        let result = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey, constrainedBrightness)
        IOObjectRelease(service)
        
        if result == kIOReturnSuccess {
            print("Set brightness using IOKit API: \(constrainedBrightness)")
            return true
        } else {
            print("Failed to set brightness using IOKit API: error \(result)")
        }
    }
    
    print("Warning: Could not set brightness using any API")
    return false
}



// Function to increase the screen brightness by a specified amount
func increaseBrightness(amount: Float) -> Bool {
    // Get current brightness
    let currentBrightness = getCurrentBrightness()
    print("Current brightness: \(currentBrightness * 100)%")
    
    // Calculate new brightness level (constrained to 0-1 range)
    let newBrightness = min(1.0, currentBrightness + amount)
    
    // Set the new brightness
    let success = setBrightness(newBrightness)
    
    if success {
        print("Brightness increased from \(currentBrightness * 100)% to \(newBrightness * 100)%")
        return true
    } else {
        print("Failed to increase brightness")
        print("Note: On some Macs, brightness control requires special permissions or may not be supported.")
        print("You might need to run this command with sudo privileges.")
        return false
    }
}

// Main function
func main() {
    // Load saved configuration
    loadConfiguration()
    
    var options = parseCommandLineArguments()
    
    if options.showHelp {
        printUsage()
        exit(0)
    }
    
    // Check if we need to increase brightness
    if let brightnessAmount = options.increaseBrightness {
        let success = increaseBrightness(amount: brightnessAmount)
        if !success {
            print("Warning: Failed to increase brightness. This might be due to:")
            print("  - Your Mac model not supporting this method of brightness control")
            print("  - Insufficient permissions (try running with sudo)")
            print("  - System security settings preventing display brightness changes")
        }
        
        // If we're only adjusting brightness and not playing sound, exit now
        if !options.enableClick && options.flashBrightness == nil {
            exit(success ? 0 : 1)
        }
    }
    
    // Set up brightness flashing if requested
    if let flashAmount = options.flashBrightness {
        // Store the original brightness
        originalBrightness = getCurrentBrightness()
        print("Original brightness: \(originalBrightness * 100)%")
        
        // Set the flash amount
        flashBrightnessAmount = flashAmount
        isBrightnessFlashing = true
        
        print("Brightness will flash by \(flashAmount * 100)% with each click")
        
        // If we're only flashing brightness and not playing sound, enable click sound
        if !options.enableClick {
            print("Enabling click sound for brightness flashing")
            options.enableClick = true
            enableClickSound = true
        }
    }
    
    // Set click sound state from command line
    enableClickSound = options.enableClick
    
    if enableClickSound {
        setupClickSound()
    }
    
    // Start timer with the specified frequency
    let frequency = options.frequency
    startClickTimer(frequency: frequency)
    
    if enableClickSound || isBrightnessFlashing {
        print("\nRunning with \(enableClickSound ? "click sound" : "")\(enableClickSound && isBrightnessFlashing ? " and " : "")\(isBrightnessFlashing ? "brightness flashing" : "") at \(frequency)Hz")
        print("Press Ctrl+C to exit")
        
        // Set up a signal handler for clean exit
        signal(SIGINT) { _ in
            print("\nShutting down...")
            stopClickSound()
            
            // Restore original brightness if we were flashing
            if isBrightnessFlashing {
                _ = setBrightness(originalBrightness)
                print("Restored original brightness: \(originalBrightness * 100)%")
            }
            
            exit(0)
        }
        
        // Keep the application running
        RunLoop.main.run()
    } else {
        print("Click sound is disabled. Use without --no-click to enable it.")
        stopClickSound()
        exit(0)
    }
}

// Run the main function
main()
