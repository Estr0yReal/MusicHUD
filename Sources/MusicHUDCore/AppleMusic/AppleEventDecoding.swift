import Foundation

/// Decodes the `NSAppleEventDescriptor` a Music.app script returns.
///
/// This lives in the logic target rather than next to the scripting client for
/// one reason: it is where the subtle bugs are, and here it can be unit tested
/// against hand-built descriptors without Music.app, an Apple Event or
/// Automation permission.
public enum AppleEventDecoding {

    /// Raw four-character codes, declared explicitly rather than pulling in the
    /// Carbon headers for a handful of OSType constants.
    public enum OSType {
        public static let text: DescType = 0x75747874        // 'utxt'
        public static let double: DescType = 0x646F7562      // 'doub'
        public static let float: DescType = 0x73696E67       // 'sing'
        public static let long: DescType = 0x6C6F6E67        // 'long'
        public static let short: DescType = 0x73686F72       // 'shor'
        public static let boolean: DescType = 0x626F6F6C     // 'bool'
        public static let list: DescType = 0x6C697374        // 'list'
        public static let missing: DescType = 0x6D736E67     // 'msng'
    }

    /// The descriptor type AppleScript actually uses for `true`.
    ///
    /// This is the bug that live verification caught. It is natural to assume a
    /// boolean arrives as `'bool'`, and the type is even *named* `boolean` in
    /// Apple's own constants — but a script returning `true` produces a null
    /// descriptor typed `'true'` (0x74727565). Checking only for `'bool'` made
    /// every boolean read back as `false`, which silently turned "a track is
    /// playing" into "nothing is playing" while playback state and position
    /// kept working perfectly, making the failure look like anything but a
    /// decoding problem.
    public static let trueType: DescType = 0x74727565        // 'true'

    /// Likewise for `false`.
    public static let falseType: DescType = 0x66616C73       // 'false'

    // MARK: - Field readers

    /// Reads a text field, mapping `missing value` onto an empty string.
    public static func text(_ descriptor: NSAppleEventDescriptor?) -> String {
        guard let descriptor else { return "" }
        guard descriptor.descriptorType != OSType.missing else { return "" }
        return descriptor.stringValue ?? ""
    }

    /// Reads a numeric field, returning `0` for anything that is not a number.
    ///
    /// The type is checked before asking for the value: `doubleValue` performs a
    /// coercion, and coercing `missing value` is not something worth discovering
    /// at runtime.
    public static func number(_ descriptor: NSAppleEventDescriptor?) -> Double {
        guard let descriptor else { return 0 }
        switch descriptor.descriptorType {
        case OSType.double, OSType.float:
            return descriptor.doubleValue
        case OSType.long, OSType.short:
            return Double(descriptor.int32Value)
        default:
            return 0
        }
    }

    /// Reads a boolean field. Handles all three types AppleScript may use.
    public static func boolean(_ descriptor: NSAppleEventDescriptor?) -> Bool {
        guard let descriptor else { return false }
        switch descriptor.descriptorType {
        case trueType:
            return true
        case falseType:
            return false
        case OSType.boolean:
            return descriptor.booleanValue
        default:
            return false
        }
    }

    // MARK: - Snapshot

    /// Number of fields the metadata script always returns.
    public static let metadataFieldCount = 9

    /// Builds a `MusicRawSnapshot` from the script's result list.
    ///
    /// Field order must match `AppleScriptMusicClient.metadataSource`:
    /// state, hasTrack, title, artist, album, duration, position, id, artworks.
    public static func decodeSnapshot(
        _ descriptor: NSAppleEventDescriptor,
        notRunningSentinel: String
    ) throws -> MusicRawSnapshot {
        guard descriptor.numberOfItems == metadataFieldCount else {
            throw MusicClientError.unexpectedResult(
                "expected \(metadataFieldCount) fields, got \(descriptor.numberOfItems)"
            )
        }

        let stateText = text(descriptor.atIndex(1))
        if stateText == notRunningSentinel {
            throw MusicClientError.musicAppNotRunning
        }

        return MusicRawSnapshot(
            playerStateText: stateText,
            hasTrack: boolean(descriptor.atIndex(2)),
            title: text(descriptor.atIndex(3)),
            artist: text(descriptor.atIndex(4)),
            album: text(descriptor.atIndex(5)),
            duration: number(descriptor.atIndex(6)),
            position: number(descriptor.atIndex(7)),
            persistentID: text(descriptor.atIndex(8))
        )
    }
}
