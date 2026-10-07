import Foundation

public enum HelperConstants {
    /// Finder/桌面显示的就是这个文件名，改名会让桌面上的 app 也跟着变。
    public static let appFileName = "Focus&Pause"
    public static let machServiceName = "com.focuspause.helper"
    public static let installedBinPath = "/Library/PrivilegedHelperTools/com.focuspause.helper"
    public static let daemonPlistPath = "/Library/LaunchDaemons/com.focuspause.helper.plist"
    public static let tokenPath = "/Library/Application Support/FocusPause/helper.token"
    public static let appBundleId = "com.focuspause.app"
    public static let hostsPath = "/private/etc/hosts"
    public static let appExecutableSuffix = "/\(appFileName).app/Contents/MacOS/FocusPause"
}
