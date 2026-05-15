import AppKit

enum SnapZone: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case maximize, center

    var displayName: String {
        switch self {
        case .leftHalf:            return "Left Half"
        case .rightHalf:           return "Right Half"
        case .topHalf:             return "Top Half"
        case .bottomHalf:          return "Bottom Half"
        case .topLeftQuarter:      return "Top-Left ¼"
        case .topRightQuarter:     return "Top-Right ¼"
        case .bottomLeftQuarter:   return "Bottom-Left ¼"
        case .bottomRightQuarter:  return "Bottom-Right ¼"
        case .maximize:            return "Maximize"
        case .center:              return "Center"
        }
    }

    /// Compute the target frame in screen coordinates (origin = bottom-left).
    func frame(in screen: NSScreen) -> CGRect {
        let v = screen.visibleFrame
        let half = CGSize(width: v.width / 2, height: v.height / 2)

        switch self {
        case .leftHalf:
            return CGRect(x: v.minX, y: v.minY, width: half.width, height: v.height)
        case .rightHalf:
            return CGRect(x: v.midX, y: v.minY, width: half.width, height: v.height)
        case .topHalf:
            return CGRect(x: v.minX, y: v.midY, width: v.width, height: half.height)
        case .bottomHalf:
            return CGRect(x: v.minX, y: v.minY, width: v.width, height: half.height)
        case .topLeftQuarter:
            return CGRect(x: v.minX, y: v.midY, width: half.width, height: half.height)
        case .topRightQuarter:
            return CGRect(x: v.midX, y: v.midY, width: half.width, height: half.height)
        case .bottomLeftQuarter:
            return CGRect(x: v.minX, y: v.minY, width: half.width, height: half.height)
        case .bottomRightQuarter:
            return CGRect(x: v.midX, y: v.minY, width: half.width, height: half.height)
        case .maximize:
            return v
        case .center:
            let w = v.width * 0.6
            let h = v.height * 0.7
            return CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h)
        }
    }

    /// Pick a zone when the cursor is near a screen edge / corner.
    /// `cursor` is in global screen coordinates (origin = bottom-left of primary screen).
    static func zoneForCursor(_ cursor: CGPoint, on screen: NSScreen) -> SnapZone? {
        let frame = screen.frame
        let cornerSize: CGFloat = 30
        let edgeThreshold: CGFloat = 6

        let nearLeft   = cursor.x <= frame.minX + edgeThreshold
        let nearRight  = cursor.x >= frame.maxX - edgeThreshold
        let nearTop    = cursor.y >= frame.maxY - edgeThreshold
        let nearBottom = cursor.y <= frame.minY + edgeThreshold

        let inTopLeftCorner     = cursor.x <= frame.minX + cornerSize && cursor.y >= frame.maxY - cornerSize
        let inTopRightCorner    = cursor.x >= frame.maxX - cornerSize && cursor.y >= frame.maxY - cornerSize
        let inBottomLeftCorner  = cursor.x <= frame.minX + cornerSize && cursor.y <= frame.minY + cornerSize
        let inBottomRightCorner = cursor.x >= frame.maxX - cornerSize && cursor.y <= frame.minY + cornerSize

        if inTopLeftCorner     { return .topLeftQuarter }
        if inTopRightCorner    { return .topRightQuarter }
        if inBottomLeftCorner  { return .bottomLeftQuarter }
        if inBottomRightCorner { return .bottomRightQuarter }

        if nearTop    { return .maximize }
        if nearLeft   { return .leftHalf }
        if nearRight  { return .rightHalf }
        if nearBottom { return .bottomHalf }

        return nil
    }
}
