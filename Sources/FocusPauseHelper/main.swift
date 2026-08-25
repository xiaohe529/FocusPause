import Foundation
import FocusPauseHelperShared

let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
let delegate = HelperServiceDelegate()
listener.delegate = delegate
listener.resume()

RunLoop.main.run()