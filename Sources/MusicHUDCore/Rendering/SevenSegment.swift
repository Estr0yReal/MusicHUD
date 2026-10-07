import Foundation

/// One of the seven strokes of a seven-segment display.
///
/// Naming follows the usual convention:
///
/// ```
///        top
///   topLeft  topRight
///       middle
///  bottomLeft bottomRight
///       bottom
/// ```
public enum SevenSegmentPosition: Int, CaseIterable, Sendable {
    case top = 0
    case topRight = 1
    case bottomRight = 2
    case bottom = 3
    case bottomLeft = 4
    case topLeft = 5
    case middle = 6

    /// The bit this stroke occupies in `SevenSegmentMask`.
    public var mask: SevenSegmentMask {
        SevenSegmentMask(rawValue: 1 << UInt8(rawValue))
    }
}

/// A set of lit seven-segment strokes.
public struct SevenSegmentMask: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let top = SevenSegmentMask(rawValue: 1 << 0)
    public static let topRight = SevenSegmentMask(rawValue: 1 << 1)
    public static let bottomRight = SevenSegmentMask(rawValue: 1 << 2)
    public static let bottom = SevenSegmentMask(rawValue: 1 << 3)
    public static let bottomLeft = SevenSegmentMask(rawValue: 1 << 4)
    public static let topLeft = SevenSegmentMask(rawValue: 1 << 5)
    public static let middle = SevenSegmentMask(rawValue: 1 << 6)

    public static let all: SevenSegmentMask = [
        .top, .topRight, .bottomRight, .bottom, .bottomLeft, .topLeft, .middle,
    ]

    public static let none: SevenSegmentMask = []

    /// `true` when the given stroke is lit.
    public func contains(_ position: SevenSegmentPosition) -> Bool {
        contains(position.mask)
    }

    /// Returns a copy with the given stroke lit or unlit.
    public func setting(_ position: SevenSegmentPosition, lit: Bool) -> SevenSegmentMask {
        lit ? union(position.mask) : subtracting(position.mask)
    }
}

/// Maps characters onto segment masks.
///
/// This is pure data, which is why it lives in the logic target and is unit tested:
/// if a digit is wrong, it is wrong here, not in the drawing code.
public enum SevenSegmentFont {

    /// Characters this display can render. Everything else renders as blank.
    public static let supportedCharacters = "0123456789- "

    /// The segment mask for one character. Unsupported characters are blank.
    public static func mask(for character: Character) -> SevenSegmentMask {
        switch character {
        case "0": return [.top, .topLeft, .topRight, .bottomLeft, .bottomRight, .bottom]
        case "1": return [.topRight, .bottomRight]
        case "2": return [.top, .topRight, .middle, .bottomLeft, .bottom]
        case "3": return [.top, .topRight, .middle, .bottomRight, .bottom]
        case "4": return [.topLeft, .middle, .topRight, .bottomRight]
        case "5": return [.top, .topLeft, .middle, .bottomRight, .bottom]
        case "6": return [.top, .topLeft, .middle, .bottomLeft, .bottomRight, .bottom]
        case "7": return [.top, .topRight, .bottomRight]
        case "8": return .all
        case "9": return [.top, .topLeft, .topRight, .middle, .bottomRight, .bottom]
        case "-": return [.middle]
        default: return .none
        }
    }

    /// The masks for a whole string.
    public static func masks(for text: String) -> [SevenSegmentMask] {
        text.map(mask(for:))
    }
}
