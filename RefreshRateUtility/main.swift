import Foundation
import AppKit
import AVFoundation
import IOKit
import IOKit.pwr_mgt

// Constants
let PROGRAM_NAME = "click-sound-utility"
let kIODisplayBrightnessKey = "brightness" as CFString

// Struct to hold command line arguments
struct CommandLineOptions {
    var frequency: Double = 60.0
    var showHelp = false
    var enableClick = true
    var enableBrightnessPulse = true
    var brightnessAmount: Float = 0.05 // 5% brightness change
}

// Function to display usage information
func printUsage() {
    print("""
    Usage: \(PROGRAM_NAME) [options]
    
    Options:
      -f <frequency>       Set the clicking sound frequency in Hz (default: 60Hz)
      --no-click           Disable clicking sound
      --no-brightness      Disable brightness pulsing
      -b <amount>          Set brightness pulse amount (default: 0.05 or 5%)
      -h, --help           Display this help information
    
    Examples:
      \(PROGRAM_NAME)                     Play click sound at default 60Hz with brightness pulsing
      \(PROGRAM_NAME) -f 40              Play click sound at 40Hz with brightness pulsing
      \(PROGRAM_NAME) -b 0.1             Use 10% brightness pulse with click sound
      \(PROGRAM_NAME) --no-brightness    Play click sound without brightness pulsing
      \(PROGRAM_NAME) --no-click         Run without sound or brightness changes
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
        case "--no-brightness":
            options.enableBrightnessPulse = false
        case "-f", "--frequency":
            if i + 1 < args.count, let frequency = Double(args[i + 1]) {
                options.frequency = frequency
                i += 1
            } else {
                print("Error: -f requires a frequency value")
                exit(1)
            }
        case "-b", "--brightness-amount":
            if i + 1 < args.count, let amount = Float(args[i + 1]) {
                options.brightnessAmount = amount
                i += 1
            } else {
                print("Error: -b requires a decimal value (e.g., 0.05 for 5%)")
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

// Brightness control variables
var originalBrightness: Float = 0.0
var enableBrightnessPulse: Bool = true
var brightnessAmount: Float = 0.05 // 5% brightness change by default
var isInBrightPhase: Bool = false

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
        "frequency": clickTimer?.timeInterval != nil ? 1.0 / (clickTimer?.timeInterval ?? 1/60) : 60.0,
        "enableBrightnessPulse": enableBrightnessPulse,
        "brightnessAmount": brightnessAmount
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
        
        if let brightnessPulse = config["enableBrightnessPulse"] as? Bool {
            enableBrightnessPulse = brightnessPulse
        }
        
        if let brightnessValue = config["brightnessAmount"] as? Float {
            brightnessAmount = brightnessValue
        }
        
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
    
    // Pulse the brightness with each click sound
    if enableBrightnessPulse {
        pulseBrightness()
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
    
    // Restore original brightness if needed
    if enableBrightnessPulse && originalBrightness > 0 {
        setBrightness(originalBrightness)
    }
    
    // Save the updated configuration
    saveConfiguration()
}

// Function to get current display brightness
func getCurrentBrightness() -> Float {
    var service: io_object_t = 0
    var iterator: io_iterator_t = 0
    var brightness: Float = 0.5  // Default value if we can't get the actual brightness
    
    let result = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
    
    if result == kIOReturnSuccess {
        service = IOIteratorNext(iterator)
        
        if service != 0 {
            var current: Float = 0
            
            // Get the current brightness
            if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &current) == kIOReturnSuccess {
                brightness = current
            }
            
            IOObjectRelease(service)
        }
        
        IOObjectRelease(iterator)
    }
    
    return brightness
}

// Function to set display brightness
func setBrightness(_ brightness: Float) -> Bool {
    let constrainedBrightness = max(0, min(1, brightness))
    var service: io_object_t = 0
    var iterator: io_iterator_t = 0
    var success = false
    
    let result = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
    
    if result == kIOReturnSuccess {
        service = IOIteratorNext(iterator)
        
        while service != 0 {
            // Set the brightness
            if IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, constrainedBrightness) == kIOReturnSuccess {
                success = true
            }
            
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        
        IOObjectRelease(iterator)
    }
    
    return success
}

// Function to pulse brightness along with click sound
func pulseBrightness() {
    if !enableBrightnessPulse {
        return
    }
    
    // Save the original brightness the first time
    if originalBrightness == 0 {
        originalBrightness = getCurrentBrightness()
        print("Original brightness: \(originalBrightness * 100)%")
    }
    
    // Toggle between original and increased brightness
    if isInBrightPhase {
        // Return to original brightness
        setBrightness(originalBrightness)
        isInBrightPhase = false
    } else {
        // Increase brightness
        let newBrightness = min(1.0, originalBrightness + brightnessAmount)
        setBrightness(newBrightness)
        isInBrightPhase = true
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
    
    // Set click sound state from command line
    enableClickSound = options.enableClick
    
    // Set brightness pulse state from command line
    enableBrightnessPulse = options.enableBrightnessPulse
    brightnessAmount = options.brightnessAmount
    
    if enableClickSound {
        setupClickSound()
    }
    
    // Start timer with the specified frequency
    let frequency = options.frequency
    startClickTimer(frequency: frequency)
    
    if enableClickSound {
        print("\nRunning with click sound at \(frequency)Hz")
        
        if enableBrightnessPulse {
            print("Brightness pulsing enabled (\(brightnessAmount * 100)% change)")
            // Store original brightness at startup
            originalBrightness = getCurrentBrightness()
            print("Original brightness: \(originalBrightness * 100)%")
        } else {
            print("Brightness pulsing disabled")
        }
        
        print("Press Ctrl+C to exit")
        
        // Set up a signal handler for clean exit
        signal(SIGINT) { _ in
            print("\nShutting down...")
            stopClickSound()
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
