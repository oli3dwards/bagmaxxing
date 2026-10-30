// Prints macOS's own heat-strain reading for bin/bagmaxxing: nominal, fair, serious or critical.
import Foundation

switch ProcessInfo.processInfo.thermalState {
case .nominal: print("nominal")
case .fair: print("fair")
case .serious: print("serious")
case .critical: print("critical")
@unknown default: print("unknown")
}
