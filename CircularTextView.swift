import UIKit
import CoreText

public class CircularTextView: UIView
{
    public var attributedText: NSAttributedString?
        {
        didSet
        {
            let rect = self.attributedText?.boundingRect(with: CGSize(width: CGFloat(MAXFLOAT), height: CGFloat(MAXFLOAT)), options: NSStringDrawingOptions.usesLineFragmentOrigin, context: nil)
            self.lineHeight = rect?.height ?? 0.0
            self.setNeedsDisplay()
        }
    }
    
    var lineHeight: CGFloat = 0
    
    public var inset: CGFloat = 0.0
    
    override public init(frame: CGRect)
    {
        super.init(frame: frame)
        assert(self.bounds.width == self.bounds.height, "\(CircularTextView.self) can only draw using a square frame!")
    }
    
    required public init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
    }
    
    override public func draw(_ rect: CGRect)
    {
        super.draw(rect)
        guard let attributedText = self.attributedText else { return }
        let radius = self.bounds.width * 0.5
        let context = UIGraphicsGetCurrentContext()
        context!.textMatrix = CGAffineTransform.identity
        
        context?.translateBy(x: radius, y: radius)
        context?.scaleBy(x: 1.0, y: -1.0)
        context?.rotate(by: CGFloat(M_PI_2))
        
        let line = CTLineCreateWithAttributedString(attributedText)
        let glyphCount = CTLineGetGlyphCount(line)
        let runArray = ((CTLineGetGlyphRuns(line) as [AnyObject]) as! [CTRun])
        let runCount = CFArrayGetCount(runArray as CFArray!)
        
        var widthArray = [CGFloat]()
        var glyphOffset = 0
        
        for i in 0 ..< runCount
        {
            let run: CTRun = runArray[i]
            let runGlyphCount = CTRunGetGlyphCount(run)
            for runGlyphIndex  in 0 ..< runGlyphCount
            {
                let widthValue = CTRunGetTypographicBounds(run, CFRangeMake(runGlyphIndex, 1), nil, nil, nil)
                widthArray.append(CGFloat(widthValue))
            }
            glyphOffset = runGlyphCount
        }
        let lineLength = CTLineGetTypographicBounds(line, nil, nil, nil)
        
        var angleArray = [CGFloat]()
        var prevHalfWidth = widthArray[0] * 0.5
        let angleValue = (prevHalfWidth / CGFloat(lineLength)) * 2 * CGFloat(M_PI)
        angleArray.append(angleValue)
        for lineGlyphIndex in 1 ..< glyphCount
        {
            let halfWidth = widthArray[lineGlyphIndex] * 0.5
            let prevCenterToCenter = prevHalfWidth + halfWidth
            let angleValue  = atan2((prevCenterToCenter + self.kerningForIndex(lineGlyphIndex)) * 0.5, radius) * 2
            angleArray.append(angleValue)
            prevHalfWidth = halfWidth
        }
        var textPosition = CGPoint(x: 0.0, y: radius - lineHeight - self.inset)
        //: Why do I have to switch x and y here?
        context?.textPosition = CGPoint(x: textPosition.y, y: textPosition.x)
        
        glyphOffset = 0
        
        for runIndex in 0 ..< runCount
        {
            let run = runArray[runIndex]
            let runGlyphCount = CTRunGetGlyphCount(run)
            let runFont = unsafeBitCast(CFDictionaryGetValue(CTRunGetAttributes(run), unsafeBitCast(kCTFontAttributeName, to: UnsafePointer.self)), to: CTFont.self)
            
            for runGlyphIndex in 0 ..< runGlyphCount
            {
                let index = glyphOffset + runGlyphIndex
                let fillColor = self.fillColorForIndex(index)
                let strokeColor = self.strokeColorForIndex(index)
                let strokeWidth = self.strokeWidthForIndex(index)
                
                let glyphRange = CFRangeMake(runGlyphIndex, 1)
                context?.rotate(by: -1 * angleArray[index])
                
                let glyphWidth = widthArray[runGlyphIndex + glyphOffset]
                let halfGlyphWidth = glyphWidth * 0.5
                let positionForThisGlyph = CGPoint(x: textPosition.x - halfGlyphWidth + self.kerningForIndex(index), y: textPosition.y + self.baselineOffsetForIndex(index))
                
                textPosition.x -= glyphWidth
                textPosition.x += sin(angleArray[glyphOffset + runGlyphIndex]) * self.kerningForIndex(index)
                
                var textMatrix = CTRunGetTextMatrix(run)
                textMatrix.tx = positionForThisGlyph.x
                textMatrix.ty = positionForThisGlyph.y
                context!.textMatrix = textMatrix
                
                let cgFont = CTFontCopyGraphicsFont(runFont, nil)
                var glyph = CGGlyph()
                var position = CGPoint()
                
                self.setShadowOnContext(context, forIndex: glyphOffset + runGlyphIndex)
                
                CTRunGetGlyphs(run, glyphRange, &glyph)
                CTRunGetPositions(run, glyphRange, &position)
                context?.setFont(cgFont)
                context?.setTextDrawingMode(.fillStroke)
                context?.setLineWidth(strokeWidth)
                context?.setFontSize(CTFontGetSize(runFont))
                context?.setFillColor(fillColor.cgColor)
                context?.setStrokeColor(strokeColor.cgColor)
                CTFontDrawGlyphs(runFont, &glyph, &position, 1, context!)
                
                self.drawUnderlineAndStrikeIfNeededForIndex(glyphOffset + runGlyphIndex, angleArray: angleArray, radius: radius, halfGlyphWidth: halfGlyphWidth)
            }
            glyphOffset += runGlyphCount
        }
    }
    
    func setShadowOnContext(_ context: CGContext?, forIndex index: Int)
    {
        if let shadow = self.shadowForIndex(index)
        {
            let shadowColor: UIColor = shadow.shadowColor as? UIColor ?? UIColor.black
            context?.setShadow(offset: shadow.shadowOffset, blur: shadow.shadowBlurRadius, color: shadowColor.cgColor)
        }
        else
        {
            context?.setShadow(offset: CGSize.zero, blur: 0.0, color: UIColor.clear.cgColor)
        }
    }
    
    func drawUnderlineAndStrikeIfNeededForIndex(_ index: Int, angleArray: [CGFloat], radius: CGFloat, halfGlyphWidth: CGFloat)
    {
        let underlineStyle = self.underlineStyleForIndex(index)
        if underlineStyle != .styleNone
        {
            let underlineColor = self.underlineColorForIndex(index)
            let baselineRadius = radius - lineHeight - self.inset - (lineHeight * 0.06)
            let angleValue  = atan2(halfGlyphWidth, radius)
            let bezierPath = bezierPathForRadius(baselineRadius, angle: angleValue, endAngle: angleArray[index], underlineStyle: underlineStyle)
            underlineColor.setStroke()
            bezierPath.stroke()
        }
        let strikeStyle = self.strikethroughStyleForIndex(index)
        if strikeStyle != .styleNone
        {
            let substring = self.attributedText?.attributedSubstring(from: NSRange(location: index, length: 1))
            let glyphRect = substring!.boundingRect(with: CGSize(width: CGFloat(MAXFLOAT), height: CGFloat(MAXFLOAT)), options: NSStringDrawingOptions.usesLineFragmentOrigin, context: nil)
            let strikeColor = self.strikeThroughColorForIndex(index)
            let baselineRadius = radius - lineHeight - self.inset + (glyphRect.height * 0.25)
            let angleValue  = atan2(halfGlyphWidth, radius)
            let bezierPath = bezierPathForRadius(baselineRadius, angle: angleValue, endAngle: angleArray[index], underlineStyle: strikeStyle)
            strikeColor.setStroke()
            bezierPath.stroke()
        }
    }
    
}

extension CircularTextView
{
    func fillColorForIndex(_ index: Int) -> UIColor
    {
        guard let attributedText = self.attributedText else { return UIColor.darkText }
        return (attributedText.attribute(NSForegroundColorAttributeName, at: index, longestEffectiveRange: nil, in: NSRange(location: 0, length: attributedText.string.characters.count)) ?? UIColor.darkText) as! UIColor
    }
    
    func strokeColorForIndex(_ index: Int) -> UIColor
    {
        guard let attributedText = self.attributedText else { return UIColor.darkText }
        return (attributedText.attribute(NSStrokeColorAttributeName, at: index, longestEffectiveRange: nil, in: NSRange(location: 0, length: attributedText.string.characters.count)) ?? UIColor.darkText) as! UIColor
    }
    
    func strokeWidthForIndex(_ index: Int) -> CGFloat
    {
        guard let attributedText = self.attributedText else { return 0.0 }
        let strokeWidth = (attributedText.attribute(NSStrokeWidthAttributeName, at: index, longestEffectiveRange: nil, in: NSRange(location: 0, length: attributedText.string.characters.count)) ?? 0.0) as! NSNumber
        return CGFloat(strokeWidth)
    }
    
    func underlineStyleForIndex(_ index: Int) -> NSUnderlineStyle
    {
        guard let attributedText = self.attributedText else { return .styleNone }
        let underlineStyleNumber: Int = (attributedText.attribute(NSUnderlineStyleAttributeName, at: index, longestEffectiveRange: nil, in: NSRange(location: 0, length: attributedText.string.characters.count)) as? Int) ?? 0
        return NSUnderlineStyle(rawValue: underlineStyleNumber)!
    }
    
    func strikethroughStyleForIndex(_ index: Int) -> NSUnderlineStyle
    {
        guard let attributedText = self.attributedText else { return .styleNone }
        let underlineStyleNumber: Int = (attributedText.attribute(NSStrikethroughStyleAttributeName, at: index, longestEffectiveRange: nil, in: NSRange(location: 0, length: attributedText.string.characters.count)) as? Int) ?? 0
        return NSUnderlineStyle(rawValue: underlineStyleNumber)!
    }
    
    func underlineColorForIndex(_ index: Int) -> UIColor
    {
        guard let attributedText = self.attributedText else { return UIColor.darkText }
        return (attributedText.attribute(NSUnderlineColorAttributeName, at: index, longestEffectiveRange: nil, in: NSRange(location: 0, length: attributedText.string.characters.count)) ?? UIColor.darkText) as! UIColor
    }
    
    func strikeThroughColorForIndex(_ index: Int) -> UIColor
    {
        guard let attributedText = self.attributedText else { return UIColor.darkText }
        return (attributedText.attribute(NSStrikethroughColorAttributeName, at: index, longestEffectiveRange: nil, in: NSRange(location: 0, length: attributedText.string.characters.count)) ?? UIColor.darkText) as! UIColor
    }
    
    func kerningForIndex(_ index: Int) -> CGFloat
    {
        guard let attributedText = self.attributedText else { return 0.0 }
        let kerning = (attributedText.attribute(NSKernAttributeName, at: index, longestEffectiveRange: nil, in: NSRange(location: 0, length: attributedText.string.characters.count)) ?? 0.0) as! CGFloat
        return kerning
    }
    
    func baselineOffsetForIndex(_ index: Int) -> CGFloat
    {
        guard let attributedText = self.attributedText else { return 0.0 }
        let baselineOffset = (attributedText.attribute(NSBaselineOffsetAttributeName, at: index, longestEffectiveRange: nil, in: NSRange(location: 0, length: attributedText.string.characters.count)) ?? 0.0) as! NSNumber
        return CGFloat(baselineOffset)
    }
    
    func shadowForIndex(_ index: Int) -> NSShadow?
    {
        guard let attributedText = self.attributedText else { return nil }
        return attributedText.attribute(NSShadowAttributeName, at: index, longestEffectiveRange: nil, in: NSRange(location: 0, length: attributedText.string.characters.count)) as? NSShadow
    }
    
    func bezierPathForRadius(_ radius: CGFloat, angle: CGFloat, endAngle: CGFloat, underlineStyle: NSUnderlineStyle) -> UIBezierPath
    {
        let halfPi: CGFloat = CGFloat(M_PI_2) - 0.045 * CGFloat(M_PI_2)
        let lineWidth = self.lineHeight * 0.025
        let bezierPath = UIBezierPath(arcCenter: CGPoint.zero, radius: radius, startAngle: 0 + halfPi - angle, endAngle: endAngle + halfPi + angle, clockwise: true)
        switch underlineStyle {
        case .styleSingle, .byWord:
            bezierPath.lineWidth = lineWidth
            return bezierPath
        case .styleThick:
            bezierPath.lineWidth = lineWidth * 2
            return bezierPath
        case .styleDouble:
            let bezierPath2 = UIBezierPath(arcCenter: CGPoint.zero, radius: radius - lineWidth * 2, startAngle: 0 + halfPi - angle, endAngle: endAngle + halfPi + angle, clockwise: true)
            bezierPath.append(bezierPath2)
            bezierPath.lineWidth = lineWidth
            return bezierPath
        case .patternDot:
            let pattern: [CGFloat] = [1.0, 1.0]
            bezierPath.setLineDash(pattern, count: 2, phase: 0.0)
            bezierPath.lineWidth = lineWidth
            return bezierPath
        case .patternDashDot:
            let pattern: [CGFloat] = [3.0, 1.0, 1.0, 1.0]
            bezierPath.setLineDash(pattern, count: 4, phase: 0.0)
            bezierPath.lineWidth = lineWidth
            return bezierPath
        case .patternDashDotDot:
            let pattern: [CGFloat] = [3.0, 1.0, 1.0, 1.0, 1.0, 1.0]
            bezierPath.setLineDash(pattern, count: 6, phase: 0.0)
            bezierPath.lineWidth = lineWidth
            return bezierPath
        default:
            return UIBezierPath()
        }
    }
}
