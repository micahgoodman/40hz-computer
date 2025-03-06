import Foundation
import AppKit
import AVFoundation

// Constants
let PROGRAM_NAME = "click-sound-utility"

// Struct to hold command line arguments
struct CommandLineOptions {
    var frequency: Double = 60.0
    var showHelp = false
    var enableClick = true
}

// Function to display usage information
func printUsage() {
    print("""
    Usage: \(PROGRAM_NAME) [options]
    
    Options:
      -f <frequency>       Set the clicking sound frequency in Hz (default: 60Hz)
      --no-click           Disable clicking sound
      -h, --help           Display this help information
    
    Examples:
      \(PROGRAM_NAME)                     Play click sound at default 60Hz
      \(PROGRAM_NAME) -f 40              Play click sound at 40Hz
      \(PROGRAM_NAME) --no-click         Run without sound (for testing)
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
        "frequency": clickTimer?.timeInterval != nil ? 1.0 / (clickTimer?.timeInterval ?? 1/60) : 60.0
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
    
    if enableClickSound {
        setupClickSound()
    }
    
    // Start timer with the specified frequency
    let frequency = options.frequency
    startClickTimer(frequency: frequency)
    
    if enableClickSound {
        print("\nRunning with click sound at \(frequency)Hz")
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
        print("Click sound is disabled. Use --no-click to enable it.")
        stopClickSound()
        exit(0)
    }
}

// Run the main function
main()
