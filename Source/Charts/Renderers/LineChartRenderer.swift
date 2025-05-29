//
//  LineChartRenderer.swift
//  Charts
//
//  Copyright 2015 Daniel Cohen Gindi & Philipp Jahoda
//  A port of MPAndroidChart for iOS
//  Licensed under Apache License 2.0
//
//  https://github.com/danielgindi/Charts
//

import Foundation
import CoreGraphics

open class LineChartRenderer: LineRadarRenderer
{
    // TODO: Currently, this nesting isn't necessary for LineCharts. However, it will make it much easier to add a custom rotor
    // that navigates between datasets.
    // NOTE: Unlike the other renderers, LineChartRenderer populates accessibleChartElements in drawCircles due to the nature of its drawing options.
    /// A nested array of elements ordered logically (i.e not in visual/drawing order) for use with VoiceOver.
    private lazy var accessibilityOrderedElements: [[NSUIAccessibilityElement]] = accessibilityCreateEmptyOrderedElements()

    @objc open weak var dataProvider: LineChartDataProvider?
    
    @objc public init(dataProvider: LineChartDataProvider, animator: Animator, viewPortHandler: ViewPortHandler)
    {
        super.init(animator: animator, viewPortHandler: viewPortHandler)
        
        self.dataProvider = dataProvider
    }
    
    open override func drawData(context: CGContext)
    {
        guard let lineData = dataProvider?.lineData else { return }

        let sets = lineData.dataSets as? [LineChartDataSet]
        assert(sets != nil, "Datasets for LineChartRenderer must conform to ILineChartDataSet")

        let drawDataSet = { self.drawDataSet(context: context, dataSet: $0) }
        sets!.lazy
            .filter(\.isVisible)
            .forEach(drawDataSet)
    }
    
    @objc open func drawDataSet(context: CGContext, dataSet: LineChartDataSetProtocol)
    {
        if dataSet.entryCount < 1
        {
            return
        }
        
        context.saveGState()
        
        context.setLineWidth(dataSet.lineWidth)
        if dataSet.lineDashLengths != nil
        {
            context.setLineDash(phase: dataSet.lineDashPhase, lengths: dataSet.lineDashLengths!)
        }
        else
        {
            context.setLineDash(phase: 0.0, lengths: [])
        }
        
        context.setLineCap(dataSet.lineCapType)
        
        // if drawing cubic lines is enabled
        switch dataSet.mode
        {
        case .linear: fallthrough
        case .stepped:
            drawLinear(context: context, dataSet: dataSet)
            
        case .cubicBezier:
            drawCubicBezier(context: context, dataSet: dataSet)
            
        case .horizontalBezier:
            drawHorizontalBezier(context: context, dataSet: dataSet)
        }
        
        context.restoreGState()
    }

    private func drawLine(
        context: CGContext,
        spline: CGMutablePath,
        drawingColor: NSUIColor)
    {
        context.beginPath()
        context.addPath(spline)
        context.setStrokeColor(drawingColor.cgColor)
        context.strokePath()
    }
    
    @objc open func drawCubicBezier(context: CGContext, dataSet: LineChartDataSetProtocol)
    {
        guard let dataProvider = dataProvider else { return }
        
        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
        
        let phaseY = animator.phaseY
        
        _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)
        
        // get the color that is specified for this position from the DataSet
        let drawingColor = dataSet.colors.first!
        
        let intensity = dataSet.cubicIntensity
        
        // the path for the cubic-spline
        let cubicPath = CGMutablePath()
        
        let valueToPixelMatrix = trans.valueToPixelMatrix
        
        if _xBounds.range >= 1
        {
            var prevDx: CGFloat = 0.0
            var prevDy: CGFloat = 0.0
            var curDx: CGFloat = 0.0
            var curDy: CGFloat = 0.0
            
            // Take an extra point from the left, and an extra from the right.
            // That's because we need 4 points for a cubic bezier (cubic=4), otherwise we get lines moving and doing weird stuff on the edges of the chart.
            // So in the starting `prev` and `cur`, go -2, -1
            
            let firstIndex = _xBounds.min + 1
            
            var prevPrev: ChartDataEntry! = nil
            var prev: ChartDataEntry! = dataSet.entryForIndex(max(firstIndex - 2, 0))
            var cur: ChartDataEntry! = dataSet.entryForIndex(max(firstIndex - 1, 0))
            var next: ChartDataEntry! = cur
            var nextIndex: Int = -1
            
            if cur == nil { return }
            
            // let the spline start
            cubicPath.move(to: CGPoint(x: CGFloat(cur.x), y: CGFloat(cur.y * phaseY)), transform: valueToPixelMatrix)
            
            for j in _xBounds.dropFirst()  // same as firstIndex
            {
                prevPrev = prev
                prev = cur
                cur = nextIndex == j ? next : dataSet.entryForIndex(j)
                
                nextIndex = j + 1 < dataSet.entryCount ? j + 1 : j
                next = dataSet.entryForIndex(nextIndex)
                
                if next == nil { break }
                
                prevDx = CGFloat(cur.x - prevPrev.x) * intensity
                prevDy = CGFloat(cur.y - prevPrev.y) * intensity
                curDx = CGFloat(next.x - prev.x) * intensity
                curDy = CGFloat(next.y - prev.y) * intensity
                
                cubicPath.addCurve(
                    to: CGPoint(
                        x: CGFloat(cur.x),
                        y: CGFloat(cur.y) * CGFloat(phaseY)),
                    control1: CGPoint(
                        x: CGFloat(prev.x) + prevDx,
                        y: (CGFloat(prev.y) + prevDy) * CGFloat(phaseY)),
                    control2: CGPoint(
                        x: CGFloat(cur.x) - curDx,
                        y: (CGFloat(cur.y) - curDy) * CGFloat(phaseY)),
                    transform: valueToPixelMatrix)
            }
        }
        
        context.saveGState()
        defer { context.restoreGState() }

        if dataSet.isDrawFilledEnabled
        {
            // Copy this path because we make changes to it
            let fillPath = cubicPath.mutableCopy()
            
            drawCubicFill(context: context, dataSet: dataSet, spline: fillPath!, matrix: valueToPixelMatrix, bounds: _xBounds)
        }

        if dataSet.isDrawLineWithGradientEnabled
        {
            drawGradientLine(context: context, dataSet: dataSet, spline: cubicPath, matrix: valueToPixelMatrix)
        }
        else
        {
            drawLine(context: context, spline: cubicPath, drawingColor: drawingColor)
        }
    }
    
    @objc open func drawHorizontalBezier(context: CGContext, dataSet: LineChartDataSetProtocol)
    {
        guard let dataProvider = dataProvider else { return }
        
        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
        
        let phaseY = animator.phaseY
        
        _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)
        
        // get the color that is specified for this position from the DataSet
        let drawingColor = dataSet.colors.first!
        
        // the path for the cubic-spline
        let cubicPath = CGMutablePath()
        
        let valueToPixelMatrix = trans.valueToPixelMatrix
        
        if _xBounds.range >= 1
        {
            var prev: ChartDataEntry! = dataSet.entryForIndex(_xBounds.min)
            var cur: ChartDataEntry! = prev
            
            if cur == nil { return }
            
            // let the spline start
            cubicPath.move(to: CGPoint(x: CGFloat(cur.x), y: CGFloat(cur.y * phaseY)), transform: valueToPixelMatrix)
            
            for j in _xBounds.dropFirst()
            {
                prev = cur
                cur = dataSet.entryForIndex(j)
                
                let cpx = CGFloat(prev.x + (cur.x - prev.x) / 2.0)
                
                cubicPath.addCurve(
                    to: CGPoint(
                        x: CGFloat(cur.x),
                        y: CGFloat(cur.y * phaseY)),
                    control1: CGPoint(
                        x: cpx,
                        y: CGFloat(prev.y * phaseY)),
                    control2: CGPoint(
                        x: cpx,
                        y: CGFloat(cur.y * phaseY)),
                    transform: valueToPixelMatrix)
            }
        }
        
        context.saveGState()
        defer { context.restoreGState() }
        
        if dataSet.isDrawFilledEnabled
        {
            // Copy this path because we make changes to it
            let fillPath = cubicPath.mutableCopy()
            
            drawCubicFill(context: context, dataSet: dataSet, spline: fillPath!, matrix: valueToPixelMatrix, bounds: _xBounds)
        }

        if dataSet.isDrawLineWithGradientEnabled
        {
            drawGradientLine(context: context, dataSet: dataSet, spline: cubicPath, matrix: valueToPixelMatrix)
        }
        else
        {
            drawLine(context: context, spline: cubicPath, drawingColor: drawingColor)
        }
    }
    
    open func drawCubicFill(
        context: CGContext,
        dataSet: LineChartDataSetProtocol,
        spline: CGMutablePath,
        matrix: CGAffineTransform,
        bounds: XBounds)
    {
        guard
            let dataProvider = dataProvider
        else { return }
        
        if bounds.range <= 0
        {
            return
        }
        
        let fillMin = dataSet.fillFormatter?.getFillLinePosition(dataSet: dataSet, dataProvider: dataProvider) ?? 0.0

        var pt1 = CGPoint(x: CGFloat(dataSet.entryForIndex(bounds.min + bounds.range)?.x ?? 0.0), y: fillMin)
        var pt2 = CGPoint(x: CGFloat(dataSet.entryForIndex(bounds.min)?.x ?? 0.0), y: fillMin)
        pt1 = pt1.applying(matrix)
        pt2 = pt2.applying(matrix)
        
        spline.addLine(to: pt1)
        spline.addLine(to: pt2)
        spline.closeSubpath()
        
        if dataSet.fill != nil
        {
            drawFilledPath(context: context, path: spline, fill: dataSet.fill!, fillAlpha: dataSet.fillAlpha)
        }
        else
        {
            drawFilledPath(context: context, path: spline, fillColor: dataSet.fillColor, fillAlpha: dataSet.fillAlpha)
        }
    }
    
    private var _lineSegments = [CGPoint](repeating: CGPoint(), count: 2)

    // Ruuvi
    @objc open func drawLinear(
        context: CGContext,
        dataSet: LineChartDataSetProtocol
    ) {
        // Constants and early returns remain the same
        let extraPadding: CGFloat = 20.0
        guard let dataProvider = dataProvider,
              dataSet.entryCount > 0 else { return }

        // Common constants
        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
        let toPixel = trans.valueToPixelMatrix
        let phaseY = animator.phaseY
        let maxGap = dataSet.maximumGapBetweenPoints

        // If no alert range is set, delegate to standard drawing method
        if !dataSet.hasAlertRange {
            drawLinearWithoutAlert(
                context: context,
                dataSet: dataSet,
                trans: trans,
                toPixel: toPixel,
                phaseY: phaseY,
                maxGap: maxGap
            )
            return
        }

        // Alert band parameters
        let alertColor = dataSet.alertColor
        let normalColor = dataSet.color(atIndex: 0)
        let lower = dataSet.lowerAlertLimit
        let upper = dataSet.upperAlertLimit

        // Pre-calculate alert check functions for better performance
        let upperInAlert = !upper.isNaN
        let lowerInAlert = !lower.isNaN
        let isInAlertRange: (Double) -> Bool = { y in
            return (upperInAlert && y > upper) || (lowerInAlert && y < lower)
        }

        // Performance optimization: Only draw what's visible plus margins
        let visibleMinX = Double(trans.pixelForValues(x: 0, y: 0).x - extraPadding)
        let visibleMaxX = Double(trans.pixelForValues(x: 0, y: 0).x + extraPadding)

        _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)

        var drawStartIdx = _xBounds.min
        var drawEndIdx = _xBounds.min + _xBounds.range

        // Find more precise start and end indices
        while drawStartIdx > 0, let entry = dataSet.entryForIndex(drawStartIdx - 1), Double(entry.x) >= visibleMinX {
            drawStartIdx -= 1
        }
        while drawEndIdx < dataSet.entryCount - 1, let entry = dataSet.entryForIndex(drawEndIdx + 1), Double(entry.x) <= visibleMaxX {
            drawEndIdx += 1
        }
        drawStartIdx = max(0, drawStartIdx - 2)
        drawEndIdx = min(dataSet.entryCount - 1, drawEndIdx + 2)

        guard drawEndIdx >= drawStartIdx else { return }

        // Pre-calculate reusable values
        let axisMinimum = dataProvider.getAxis(dataSet.axisDependency).axisMinimum
        let baselineY = CGFloat(axisMinimum)

        // Calculate threshold positions in pixel coordinates - do this once
        let upperPoint = upperInAlert ? CGPoint(x: 0, y: upper).applying(toPixel) : CGPoint.zero
        let lowerPoint = lowerInAlert ? CGPoint(x: 0, y: lower).applying(toPixel) : CGPoint.zero
        let y_upper_pixel = upperPoint.y
        let y_lower_pixel = lowerPoint.y

        let extendedLeft = viewPortHandler.contentLeft - extraPadding
        let extendedRight = viewPortHandler.contentRight + extraPadding
        let extendedWidth = extendedRight - extendedLeft

        // Identify continuous segments and lone points
        var segments: [(startIdx: Int, endIdx: Int)] = []
        segments.reserveCapacity(min(20, drawEndIdx - drawStartIdx + 1)) // Better capacity estimation

        var currentStartIdx = drawStartIdx
        for idx in stride(from: drawStartIdx + 1, through: drawEndIdx, by: 1) {
            guard let e1 = dataSet.entryForIndex(idx - 1),
                  let e2 = dataSet.entryForIndex(idx) else { continue }
            let gap = e2.x - e1.x
            if maxGap > 0 && gap > maxGap {
                segments.append((currentStartIdx, idx - 1))
                currentStartIdx = idx
            }
        }
        if currentStartIdx <= drawEndIdx {
            segments.append((currentStartIdx, drawEndIdx))
        }

        // Build filled paths for continuous segments (excluding lone points)
        var filledPaths: [CGPath] = []
        filledPaths.reserveCapacity(segments.count) // Precise capacity

        for (startIdx, endIdx) in segments where startIdx < endIdx {
            let path = generateFilledPath(dataSet: dataSet, startIndex: startIdx, endIndex: endIdx)
            var m = toPixel
            if let transformed = path.copy(using: &m) {
                filledPaths.append(transformed)
            }
        }

        // Draw fills with clipping for continuous segments
        if dataSet.isDrawFilledEnabled && !filledPaths.isEmpty {
            // Draw alert regions
            if upperInAlert || lowerInAlert {
                context.saveGState()
                let alertClipPath = CGMutablePath()

                // Add upper alert region to clip path
                if upperInAlert {
                    let aboveClipRect = CGRect(x: extendedLeft, y: viewPortHandler.contentTop,
                                              width: extendedWidth, height: y_upper_pixel - viewPortHandler.contentTop)
                    if aboveClipRect.height > 0 {
                        alertClipPath.addRect(aboveClipRect)
                    }
                }

                // Add lower alert region to clip path
                if lowerInAlert {
                    let belowClipRect = CGRect(x: extendedLeft, y: y_lower_pixel,
                                              width: extendedWidth, height: viewPortHandler.contentBottom - y_lower_pixel)
                    if belowClipRect.height > 0 {
                        alertClipPath.addRect(belowClipRect)
                    }
                }

                // Draw alert fills if we have clip regions
                if !alertClipPath.isEmpty {
                    context.addPath(alertClipPath)
                    context.clip()
                    for path in filledPaths {
                        if let fill = dataSet.fill {
                            drawFilledPath(context: context, path: path, fill: fill, fillAlpha: dataSet.fillAlpha)
                        } else {
                            drawFilledPath(context: context, path: path, fillColor: alertColor, fillAlpha: dataSet.fillAlpha)
                        }
                    }
                }
                context.restoreGState()
            }

            // Draw normal region
            context.saveGState()
            let normalClipRect: CGRect
            if upperInAlert && lowerInAlert {
                normalClipRect = CGRect(x: extendedLeft, y: y_upper_pixel,
                                       width: extendedWidth, height: y_lower_pixel - y_upper_pixel)
            } else if upperInAlert {
                normalClipRect = CGRect(x: extendedLeft, y: y_upper_pixel,
                                       width: extendedWidth, height: viewPortHandler.contentBottom - y_upper_pixel)
            } else if lowerInAlert {
                normalClipRect = CGRect(x: extendedLeft, y: viewPortHandler.contentTop,
                                       width: extendedWidth, height: y_lower_pixel - viewPortHandler.contentTop)
            } else {
                normalClipRect = viewPortHandler.contentRect
            }

            if normalClipRect.height > 0 {
                context.clip(to: normalClipRect)
                for path in filledPaths {
                    if let fill = dataSet.fill {
                        drawFilledPath(context: context, path: path, fill: fill, fillAlpha: dataSet.fillAlpha)
                    } else {
                        drawFilledPath(context: context, path: path, fillColor: normalColor, fillAlpha: dataSet.fillAlpha)
                    }
                }
            }
            context.restoreGState()
        }

        // Handle lone points - completely separate vertical line segments
        if dataSet.entryCount > 1 {
            for (startIdx, endIdx) in segments where startIdx == endIdx {
                drawLonePoint(
                    context: context,
                    dataSet: dataSet,
                    index: startIdx,
                    baselineY: baselineY,
                    upper: upper,
                    lower: lower,
                    upperInAlert: upperInAlert,
                    lowerInAlert: lowerInAlert,
                    alertColor: alertColor,
                    normalColor: normalColor,
                    phaseY: phaseY,
                    toPixel: toPixel
                )
            }
        }

        // Draw threshold lines
        if upperInAlert || lowerInAlert {
            context.saveGState()
            context.setStrokeColor(alertColor.cgColor)
            context.setLineWidth(1.0)

            if upperInAlert && viewPortHandler.isInBoundsY(y_upper_pixel) {
                context.move(to: CGPoint(x: extendedLeft, y: y_upper_pixel))
                context.addLine(to: CGPoint(x: extendedRight, y: y_upper_pixel))
            }

            if lowerInAlert && viewPortHandler.isInBoundsY(y_lower_pixel) {
                context.move(to: CGPoint(x: extendedLeft, y: y_lower_pixel))
                context.addLine(to: CGPoint(x: extendedRight, y: y_lower_pixel))
            }

            context.strokePath()
            context.restoreGState()
        }

        // Draw connected line segments
        var normalSegments: [CGPoint] = []
        var alertSegments: [CGPoint] = []
        // More precise capacity estimation based on actual data points
        let estimatedPointCount = min(100, (drawEndIdx - drawStartIdx) * 2)
        normalSegments.reserveCapacity(estimatedPointCount)
        alertSegments.reserveCapacity(estimatedPointCount)

        for idx in stride(from: drawStartIdx, through: drawEndIdx - 1, by: 1) {
            guard let e1 = dataSet.entryForIndex(idx),
                  let e2 = dataSet.entryForIndex(idx + 1) else { continue }

            if maxGap > 0, (e2.x - e1.x) > maxGap { continue } // Skip points with too large gaps

            // Convert data points to pixel coordinates
            let p1 = CGPoint(x: CGFloat(e1.x), y: CGFloat(e1.y * phaseY)).applying(toPixel)
            let p2 = CGPoint(x: CGFloat(e2.x), y: CGFloat(e2.y * phaseY)).applying(toPixel)

            // Skip points outside the visible area
            let minX = min(p1.x, p2.x)
            let maxX = max(p1.x, p2.x)
            if maxX < extendedLeft || minX > extendedRight { continue }

            // Check if points are in alert ranges
            let a1 = isInAlertRange(e1.y)
            let a2 = isInAlertRange(e2.y)

            if a1 && a2 {
                // Both points in alert range
                alertSegments.append(p1)
                alertSegments.append(p2)
            } else if !a1 && !a2 {
                // Both points in normal range
                normalSegments.append(p1)
                normalSegments.append(p2)
            } else {
                // Handle transition between alert and normal ranges with intersection point
                // Calculate which threshold is being crossed
                var limitY: Double = .nan

                // Determine which threshold we're crossing
                if a1 {
                    // First point is in alert
                    if upperInAlert && e1.y > upper {
                        limitY = upper
                    } else if lowerInAlert && e1.y < lower {
                        limitY = lower
                    }
                } else {
                    // Second point is in alert
                    if upperInAlert && e2.y > upper {
                        limitY = upper
                    } else if lowerInAlert && e2.y < lower {
                        limitY = lower
                    }
                }

                // Calculate intersection if we have a valid threshold
                if limitY.isFinite {
                    let dy = e2.y - e1.y
                    // Use epsilon for floating point comparison
                    if abs(dy) >= 1e-6 {
                        let t = (limitY - e1.y) / dy
                        // Add small epsilon to avoid missing intersections due to floating point precision
                        let epsilon = 1e-10
                        if t > 0 - epsilon && t < 1 + epsilon {
                            // Clamp t to valid range to prevent floating point errors
                            let tClamped = max(0, min(1, t))
                            let xI = e1.x + tClamped * (e2.x - e1.x)
                            let pI = CGPoint(x: CGFloat(xI), y: CGFloat(limitY * phaseY)).applying(toPixel)

                            if a1 {
                                // First point is in alert range
                                alertSegments.append(p1)
                                alertSegments.append(pI)
                                normalSegments.append(pI)
                                normalSegments.append(p2)
                            } else {
                                // Second point is in alert range
                                normalSegments.append(p1)
                                normalSegments.append(pI)
                                alertSegments.append(pI)
                                alertSegments.append(p2)
                            }
                            continue
                        }
                    }
                }

                // Fallback if intersection calculation fails
                normalSegments.append(p1)
                normalSegments.append(p2)
            }
        }

        // Draw normal and alert segments in batches for better performance
        // Drawing in batches is more efficient than individual line segments
        context.saveGState()
        if !normalSegments.isEmpty {
            context.setStrokeColor(normalColor.cgColor)
            context.setLineWidth(dataSet.lineWidth)
            context.strokeLineSegments(between: normalSegments)
        }
        if !alertSegments.isEmpty {
            context.setStrokeColor(alertColor.cgColor)
            context.setLineWidth(dataSet.lineWidth)
            context.strokeLineSegments(between: alertSegments)
        }
        context.restoreGState()

        // Draw dashed lines for gaps with proper coloring based on alert ranges
        if maxGap > 0 {
            drawDashedLinesForGaps(
                context: context,
                dataSet: dataSet,
                drawStartIdx: drawStartIdx,
                drawEndIdx: drawEndIdx,
                maxGap: maxGap,
                upper: upper,
                lower: lower,
                upperInAlert: upperInAlert,
                lowerInAlert: lowerInAlert,
                alertColor: alertColor,
                normalColor: normalColor,
                phaseY: phaseY,
                toPixel: toPixel,
                extendedLeft: extendedLeft,
                extendedRight: extendedRight
            )
        }
    }

    // Helper method to draw lone points with proper coloring
    private func drawLonePoint(
        context: CGContext,
        dataSet: LineChartDataSetProtocol,
        index: Int,
        baselineY: CGFloat,
        upper: Double,
        lower: Double,
        upperInAlert: Bool,
        lowerInAlert: Bool,
        alertColor: NSUIColor,
        normalColor: NSUIColor,
        phaseY: CGFloat,
        toPixel: CGAffineTransform
    ) {
        guard let entry = dataSet.entryForIndex(index) else { return }

        let baseY = baselineY
        let pointY = CGFloat(entry.y * phaseY)
        let x = CGFloat(entry.x)

        // Convert to pixel coordinates for drawing
        let basePoint = CGPoint(x: x, y: baseY).applying(toPixel)
        let dataPoint = CGPoint(x: x, y: pointY).applying(toPixel)

        // Create intersections where the vertical line crosses thresholds
        var intersections: [(point: CGPoint, isEnteringAlert: Bool)] = []

        // Check for upper threshold crossing
        if upperInAlert && ((baseY <= upper && pointY >= upper) || (baseY >= upper && pointY <= upper)) {
            let upperIntersection = CGPoint(x: x, y: CGFloat(upper)).applying(toPixel)
            // isEnteringAlert is true when moving from normal to alert zone
            let entering = baseY <= upper && pointY >= upper
            intersections.append((upperIntersection, entering))
        }

        // Check for lower threshold crossing
        if lowerInAlert && ((baseY <= lower && pointY >= lower) || (baseY >= lower && pointY <= lower)) {
            let lowerIntersection = CGPoint(x: x, y: CGFloat(lower)).applying(toPixel)
            // isEnteringAlert is true when moving from normal to alert zone
            let entering = baseY >= lower && pointY <= lower
            intersections.append((lowerIntersection, entering))
        }

        // Sort intersections by y-coordinate based on line direction
        if basePoint.y <= dataPoint.y {
            // Line moving up - sort ascending
            intersections.sort { $0.point.y < $1.point.y }
        } else {
            // Line moving down - sort descending
            intersections.sort { $0.point.y > $1.point.y }
        }

        // Determine if starting point is in alert zone
        let isBaseInAlert = (upperInAlert && baseY > upper) || (lowerInAlert && baseY < lower)

        if intersections.isEmpty {
            // No threshold crossings - draw single line
            let color = isBaseInAlert ? alertColor : normalColor
            drawLine(context: context, start: basePoint, stop: dataPoint,
                    fillColor: color, fillAlpha: 1.0, lineWidth: dataSet.lineWidth)
        } else {
            // Draw segments with transitions at threshold crossings
            var prevPoint = basePoint
            var isInAlert = isBaseInAlert

            for (intersection, entering) in intersections {
                // Draw segment to this intersection
                let color = isInAlert ? alertColor : normalColor
                drawLine(context: context, start: prevPoint, stop: intersection,
                        fillColor: color, fillAlpha: 1.0, lineWidth: dataSet.lineWidth)

                // Update for next segment
                prevPoint = intersection
                isInAlert = entering
            }

            // Draw final segment from last intersection to data point
            let finalColor = isInAlert ? alertColor : normalColor
            drawLine(context: context, start: prevPoint, stop: dataPoint,
                    fillColor: finalColor, fillAlpha: 1.0, lineWidth: dataSet.lineWidth)
        }

        // Draw circle at the data point with proper color
        let pointColor = (upperInAlert && entry.y > upper) || (lowerInAlert && entry.y < lower) ?
                        alertColor : normalColor
        drawCircleAtPoint(context: context, center: dataPoint, radius: dataSet.circleRadius,
                         fillColor: pointColor, drawHole: dataSet.isDrawCircleHoleEnabled)
    }

    // Helper method for drawing dashed lines with proper color transitions
    private func drawDashedLinesForGaps(
        context: CGContext,
        dataSet: LineChartDataSetProtocol,
        drawStartIdx: Int,
        drawEndIdx: Int,
        maxGap: Double,
        upper: Double,
        lower: Double,
        upperInAlert: Bool,
        lowerInAlert: Bool,
        alertColor: NSUIColor,
        normalColor: NSUIColor,
        phaseY: CGFloat,
        toPixel: CGAffineTransform,
        extendedLeft: CGFloat,
        extendedRight: CGFloat
    ) {
        // Epsilon value for floating point comparisons
        let epsilon: Double = 1e-10

        for idx in stride(from: drawStartIdx, to: drawEndIdx, by: 1) {
            guard let e1 = dataSet.entryForIndex(idx),
                  let e2 = dataSet.entryForIndex(idx + 1) else { continue }

            // Only process gaps larger than maxGap
            if e2.x - e1.x <= maxGap { continue }

            let p1 = CGPoint(x: CGFloat(e1.x), y: CGFloat(e1.y * phaseY)).applying(toPixel)
            let p2 = CGPoint(x: CGFloat(e2.x), y: CGFloat(e2.y * phaseY)).applying(toPixel)

            // Skip points outside visible area for performance
            let minX = min(p1.x, p2.x)
            let maxX = max(p1.x, p2.x)
            if maxX < extendedLeft || minX > extendedRight { continue }

            let y1 = e1.y
            let y2 = e2.y

            // Find all threshold crossings
            var intersections: [(Double, Bool)] = [] // (t parameter, isEnteringNormalZone)

            // Add crossing with upper threshold if it exists
            if upperInAlert && abs(y2 - y1) > epsilon {
                let t = (upper - y1) / (y2 - y1)
                // Use epsilon to handle floating point precision
                if t >= 0-epsilon && t <= 1+epsilon {
                    // Clamp t to valid range
                    let tClamped = max(0, min(1, t))
                    // isEntering: true means entering normal zone from alert zone
                    let isEnteringNormal = y1 > upper && y2 <= upper
                    intersections.append((tClamped, isEnteringNormal))
                }
            }

            // Add crossing with lower threshold if it exists
            if lowerInAlert && abs(y2 - y1) > epsilon {
                let t = (lower - y1) / (y2 - y1)
                if t >= 0-epsilon && t <= 1+epsilon {
                    // Clamp t to valid range
                    let tClamped = max(0, min(1, t))
                    // isEntering: true means entering normal zone from alert zone
                    let isEnteringNormal = y1 < lower && y2 >= lower
                    intersections.append((tClamped, isEnteringNormal))
                }
            }

            // Determine alert status of first point
            let isPoint1Alert = (upperInAlert && y1 > upper) || (lowerInAlert && y1 < lower)

            if intersections.isEmpty {
                // No threshold crossings
                let color = isPoint1Alert ? alertColor : normalColor
                drawDashedLine(context: context, from: p1, to: p2, color: color, lineWidth: dataSet.lineWidth)
            } else {
                // Sort intersections by t parameter (distance along line)
                let sortedIntersections = intersections.sorted { $0.0 < $1.0 }

                var prevPoint = p1
                var isInAlert = isPoint1Alert

                // Draw each segment with proper color
                for (t, isEnteringNormalZone) in sortedIntersections {
                    let xI = e1.x + t * (e2.x - e1.x)
                    let yI = y1 + t * (y2 - y1)
                    let intersectionPoint = CGPoint(x: CGFloat(xI), y: CGFloat(yI * phaseY)).applying(toPixel)

                    let segmentColor = isInAlert ? alertColor : normalColor
                    drawDashedLine(context: context, from: prevPoint, to: intersectionPoint,
                                  color: segmentColor, lineWidth: dataSet.lineWidth)

                    // Update for next segment
                    prevPoint = intersectionPoint
                    isInAlert = isEnteringNormalZone ? false : true
                }

                // Draw final segment
                let finalColor = isInAlert ? alertColor : normalColor
                drawDashedLine(context: context, from: prevPoint, to: p2,
                              color: finalColor, lineWidth: dataSet.lineWidth)
            }
        }
    }

    // Helper function for drawing dashed lines - moved outside main method for reuse
    private func drawDashedLine(context: CGContext, from: CGPoint, to: CGPoint,
                               color: NSUIColor, lineWidth: CGFloat) {
        context.saveGState()
        context.setLineDash(phase: 0, lengths: [1, 2])
        context.setLineWidth(lineWidth)
        context.setStrokeColor(color.cgColor)
        context.strokeLineSegments(between: [from, to])
        context.restoreGState()
    }

    // Draws the original single‑colour chart when no limits are set.
    private func drawLinearWithoutAlert(context: CGContext,
                                        dataSet: LineChartDataSetProtocol,
                                        trans: Transformer,
                                        toPixel: CGAffineTransform,
                                        phaseY: CGFloat,
                                        maxGap: Double)
    {
        _xBounds.set(chart: dataProvider!, dataSet: dataSet, animator: animator)

        // filled area (unchanged stock helper)
        if dataSet.isDrawFilledEnabled, dataSet.entryCount > 0 {
            drawLinearFill(context: context,
                           dataSet: dataSet,
                           trans: trans,
                           bounds: _xBounds)
        }

        guard let firstEntry = dataSet.entryForIndex(_xBounds.min) else { return }

        var path = CGMutablePath()
        path.move(to: CGPoint(x: CGFloat(firstEntry.x),
                              y: CGFloat(firstEntry.y * phaseY)))

        var prevEntry = firstEntry

        for idx in stride(from: _xBounds.min + 1,
                          through: _xBounds.min + _xBounds.range,
                          by: 1) {
            guard let cur = dataSet.entryForIndex(idx) else { continue }

            let gap = cur.x - prevEntry.x
            if maxGap > 0, gap > maxGap {
                // dashed hint
                context.saveGState()
                context.setLineDash(phase: 0, lengths: [1, 2])
                context.setLineWidth(dataSet.lineWidth)
                context.setStrokeColor(dataSet.color(atIndex: 0).cgColor)

                var dash = CGMutablePath()
                dash.move(to: CGPoint(x: CGFloat(prevEntry.x),
                                      y: CGFloat(prevEntry.y * phaseY)))
                dash.addLine(to: CGPoint(x: CGFloat(cur.x),
                                         y: CGFloat(cur.y * phaseY)))
                var m = toPixel
                if let x = dash.copy(using: &m) { dash = x.mutableCopy()! }
                context.beginPath()
                context.addPath(dash)
                context.strokePath()
                context.restoreGState()

                // restart segment at cur
                prevEntry = cur
                path.move(to: CGPoint(x: CGFloat(cur.x),
                                      y: CGFloat(cur.y * phaseY)))
                continue
            }

            path.addLine(to: CGPoint(x: CGFloat(cur.x),
                                     y: CGFloat(cur.y * phaseY)))
            prevEntry = cur
        }

        // stroke the accumulated path
        var m = toPixel                   // make mutable copy
        if let x = path.copy(using: &m) {    // use &m, not &toPixel
            path = x.mutableCopy()!
        }
        context.saveGState()
        context.setLineWidth(dataSet.lineWidth)
        context.setStrokeColor(dataSet.color(atIndex: 0).cgColor)
        context.beginPath()
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    open func drawLinearFill(
        context: CGContext,
        dataSet: LineChartDataSetProtocol,
        trans: Transformer,
        bounds: XBounds)
    {
        guard dataProvider != nil else { return }

        let maximumGap = dataSet.maximumGapBetweenPoints

        let startIndex = bounds.min
        let endIndex = bounds.min + bounds.range

        let indexInterval = 128
        var currentStartIndex = startIndex

        for index in stride(from: startIndex+1, through: endIndex, by: 1) {
            guard
                let e1 = dataSet.entryForIndex(index-1),
                let e2 = dataSet.entryForIndex(index)
            else { continue }

            let gap = e2.x - e1.x
            let breakInData = (maximumGap > 0.0 && gap > maximumGap)

            if breakInData || (index - currentStartIndex >= indexInterval) || (index == endIndex) {
                // currentEndIndex is the last valid index of this segment
                let currentEndIndex = breakInData ? index - 1 : index

                // Build the subpath for [currentStartIndex..currentEndIndex]
                var subPath = generateFilledPath(
                    dataSet: dataSet,
                    startIndex: currentStartIndex,
                    endIndex: currentEndIndex
                )

                // Transform to screen coords & draw
                var t = trans.valueToPixelMatrix
                if let transformedPath = subPath.copy(using: &t) {
                    subPath = transformedPath.mutableCopy()!
                }

                // Draw a veritcal line from the lone poine to the minY.
                if currentStartIndex == currentEndIndex {
                    guard let entry = dataSet.entryForIndex(currentStartIndex),
                          let dataProvider = dataProvider,
                          let fillMin = dataSet.fillFormatter?.getFillLinePosition(
                            dataSet: dataSet, dataProvider: dataProvider
                          ) else {
                              continue
                          }

                    var p1 = CGPoint(x: CGFloat(entry.x), y: fillMin)
                    var p2 = CGPoint(x: CGFloat(entry.x),
                                     y: CGFloat(entry.y * animator.phaseY))
                    // Transform them
                    p1 = p1.applying(t)
                    p2 = p2.applying(t)

                    // Draw that lone point line
                    drawLine(
                        context: context,
                        start: p1,
                        stop: p2,
                        fillColor: dataSet.fillColor,
                        fillAlpha: dataSet.fillAlpha,
                        lineWidth: dataSet.gapLineWidth
                    )

                    // Draw a circle at the lone point
                    drawCircleAtPoint(
                        context: context,
                        center: p2,
                        radius: dataSet.gapCircleRadius,
                        fillColor: dataSet.color(atIndex: 0),
                        drawHole: dataSet.isDrawCircleHoleEnabled
                    )

                } else {
                    if let drawable = dataSet.fill {
                        drawFilledPath(
                            context: context,
                            path: subPath,
                            fill: drawable,
                            fillAlpha: dataSet.fillAlpha
                        )
                    } else {
                        drawFilledPath(
                            context: context,
                            path: subPath,
                            fillColor: dataSet.fillColor,
                            fillAlpha: dataSet.fillAlpha
                        )
                    }
                }

                currentStartIndex = index
            }
        }
    }

    /// Draws a line from given start and end point. Used for lone points in a line chart.
    func drawLine(
        context: CGContext,
        start: CGPoint,
        stop: CGPoint,
        fillColor: NSUIColor,
        fillAlpha: CGFloat,
        lineWidth: CGFloat
    )
    {
        context.saveGState()
        context.setAlpha(fillAlpha)
        context.setStrokeColor(fillColor.cgColor)
        context.setLineWidth(lineWidth)

        context.beginPath()
        context.move(to: start)
        context.addLine(to: stop)
        context.strokePath()

        context.restoreGState()
    }

    /// Draws a circle at the given point. Used for lone points in a line chart.
    func drawCircleAtPoint(
        context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        fillColor: NSUIColor,
        
        drawHole: Bool
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setFillColor(fillColor.cgColor)
        let diameter = radius * 2
        let circleRect = CGRect(x: center.x - radius,
                                y: center.y - radius,
                                width: diameter,
                                height: diameter)
        context.fillEllipse(in: circleRect)
    }

    /// Generates the path that is used for filled drawing.
    private func generateFilledPath(
        dataSet: LineChartDataSetProtocol,
        startIndex: Int,
        endIndex: Int
    ) -> CGMutablePath
    {
        let filled = CGMutablePath()
        guard let firstEntry = dataSet.entryForIndex(startIndex),
        let dataProvider = dataProvider else { return filled }

        let phaseY = animator.phaseY
        let fillMin = dataSet.fillFormatter?.getFillLinePosition(
            dataSet: dataSet, dataProvider: dataProvider
        ) ?? 0.0
        let isDrawSteppedEnabled = dataSet.mode == .stepped

        // Start by moving from (x, fillMin) up to the first point
        filled.move(to: CGPoint(x: CGFloat(firstEntry.x), y: fillMin))
        filled.addLine(to: CGPoint(x: CGFloat(firstEntry.x), y: CGFloat(firstEntry.y * phaseY)))

        var prevEntry = firstEntry
        for x in stride(from: startIndex+1, through: endIndex, by: 1) {
            guard let curEntry = dataSet.entryForIndex(x) else { continue }

            if isDrawSteppedEnabled {
                filled.addLine(to: CGPoint(x: CGFloat(curEntry.x), y: CGFloat(prevEntry.y * phaseY)))
            }
            // Then go up/down to cur.y
            filled.addLine(to: CGPoint(x: CGFloat(curEntry.x), y: CGFloat(curEntry.y * phaseY)))

            prevEntry = curEntry
        }

        // Finally close the path back down to fillMin
        if let lastEntry = dataSet.entryForIndex(endIndex) {
            filled.addLine(to: CGPoint(x: CGFloat(lastEntry.x), y: fillMin))
        }
        filled.closeSubpath()
        
        return filled
    }
    // End Ruuvi

    open override func drawValues(context: CGContext)
    {
        guard
            let dataProvider = dataProvider,
            let lineData = dataProvider.lineData
        else { return }

        if isDrawingValuesAllowed(dataProvider: dataProvider)
        {
            let phaseY = animator.phaseY
            
            var pt = CGPoint()
            
            for i in lineData.indices
            {
                guard let
                        dataSet = lineData[i] as? LineChartDataSetProtocol,
                      shouldDrawValues(forDataSet: dataSet)
                else { continue }
                
                let valueFont = dataSet.valueFont
                
                let formatter = dataSet.valueFormatter
                
                let angleRadians = dataSet.valueLabelAngle.DEG2RAD
                
                let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
                let valueToPixelMatrix = trans.valueToPixelMatrix
                
                let iconsOffset = dataSet.iconsOffset
                
                // make sure the values do not interfear with the circles
                var valOffset = Int(dataSet.circleRadius * 1.75)
                
                if !dataSet.isDrawCirclesEnabled
                {
                    valOffset = valOffset / 2
                }
                
                _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)

                for j in _xBounds
                {
                    guard let e = dataSet.entryForIndex(j) else { break }
                    
                    pt.x = CGFloat(e.x)
                    pt.y = CGFloat(e.y * phaseY)
                    pt = pt.applying(valueToPixelMatrix)
                    
                    if (!viewPortHandler.isInBoundsRight(pt.x))
                    {
                        break
                    }
                    
                    if (!viewPortHandler.isInBoundsLeft(pt.x) || !viewPortHandler.isInBoundsY(pt.y))
                    {
                        continue
                    }
                    
                    if dataSet.isDrawValuesEnabled
                    {
                        context.drawText(formatter.stringForValue(e.y,
                                                                  entry: e,
                                                                  dataSetIndex: i,
                                                                  viewPortHandler: viewPortHandler),
                                         at: CGPoint(x: pt.x,
                                                     y: pt.y - CGFloat(valOffset) - valueFont.lineHeight),
                                         align: .center,
                                         angleRadians: angleRadians,
                                         attributes: [.font: valueFont,
                                                      .foregroundColor: dataSet.valueTextColorAt(j)])
                    }
                    
                    if let icon = e.icon, dataSet.isDrawIconsEnabled
                    {
                        context.drawImage(icon,
                                          atCenter: CGPoint(x: pt.x + iconsOffset.x,
                                                            y: pt.y + iconsOffset.y),
                                          size: icon.size)
                    }
                }
            }
        }
    }
    
    open override func drawExtras(context: CGContext)
    {
        drawCircles(context: context)
    }
    
    private func drawCircles(context: CGContext)
    {
        guard
            let dataProvider = dataProvider,
            let lineData = dataProvider.lineData
        else { return }
        
        let phaseY = animator.phaseY
        
        var pt = CGPoint()
        var rect = CGRect()
        
        // If we redraw the data, remove and repopulate accessible elements to update label values and frames
        accessibleChartElements.removeAll()
        accessibilityOrderedElements = accessibilityCreateEmptyOrderedElements()

        // Make the chart header the first element in the accessible elements array
        if let chart = dataProvider as? LineChartView {
            let element = createAccessibleHeader(usingChart: chart,
                                                 andData: lineData,
                                                 withDefaultDescription: "Line Chart")
            accessibleChartElements.append(element)
        }

        context.saveGState()

        for i in lineData.indices
        {
            guard let dataSet = lineData[i] as? LineChartDataSetProtocol else { continue }

            // Skip Circles and Accessibility if not enabled,
            // reduces CPU significantly if not needed
            if !dataSet.isVisible || !dataSet.isDrawCirclesEnabled || dataSet.entryCount == 0
            {
                continue
            }
            
            let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
            let valueToPixelMatrix = trans.valueToPixelMatrix
            
            _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)
            
            let circleRadius = dataSet.circleRadius
            let circleDiameter = circleRadius * 2.0
            let circleHoleRadius = dataSet.circleHoleRadius
            let circleHoleDiameter = circleHoleRadius * 2.0
            
            let drawCircleHole = dataSet.isDrawCircleHoleEnabled &&
                circleHoleRadius < circleRadius &&
                circleHoleRadius > 0.0
            let drawTransparentCircleHole = drawCircleHole &&
                (dataSet.circleHoleColor == nil ||
                    dataSet.circleHoleColor == NSUIColor.clear)
            
            for j in _xBounds
            {
                guard let e = dataSet.entryForIndex(j) else { break }

                pt.x = CGFloat(e.x)
                pt.y = CGFloat(e.y * phaseY)
                pt = pt.applying(valueToPixelMatrix)
                
                if (!viewPortHandler.isInBoundsRight(pt.x))
                {
                    break
                }
                
                // make sure the circles don't do shitty things outside bounds
                if (!viewPortHandler.isInBoundsLeft(pt.x) || !viewPortHandler.isInBoundsY(pt.y))
                {
                    continue
                }
                
                // Accessibility element geometry
                let scaleFactor: CGFloat = 3
                let accessibilityRect = CGRect(x: pt.x - (scaleFactor * circleRadius),
                                               y: pt.y - (scaleFactor * circleRadius),
                                               width: scaleFactor * circleDiameter,
                                               height: scaleFactor * circleDiameter)
                // Create and append the corresponding accessibility element to accessibilityOrderedElements
                if let chart = dataProvider as? LineChartView
                {
                    let element = createAccessibleElement(withIndex: j,
                                                          container: chart,
                                                          dataSet: dataSet,
                                                          dataSetIndex: i)
                    { (element) in
                        element.accessibilityFrame = accessibilityRect
                    }

                    accessibilityOrderedElements[i].append(element)
                }

                context.setFillColor(dataSet.getCircleColor(atIndex: j)!.cgColor)

                rect.origin.x = pt.x - circleRadius
                rect.origin.y = pt.y - circleRadius
                rect.size.width = circleDiameter
                rect.size.height = circleDiameter

                if drawTransparentCircleHole
                {
                    // Begin path for circle with hole
                    context.beginPath()
                    context.addEllipse(in: rect)
                    
                    // Cut hole in path
                    rect.origin.x = pt.x - circleHoleRadius
                    rect.origin.y = pt.y - circleHoleRadius
                    rect.size.width = circleHoleDiameter
                    rect.size.height = circleHoleDiameter
                    context.addEllipse(in: rect)
                    
                    // Fill in-between
                    context.fillPath(using: .evenOdd)
                }
                else
                {
                    context.fillEllipse(in: rect)
                    
                    if drawCircleHole
                    {
                        context.setFillColor(dataSet.circleHoleColor!.cgColor)

                        // The hole rect
                        rect.origin.x = pt.x - circleHoleRadius
                        rect.origin.y = pt.y - circleHoleRadius
                        rect.size.width = circleHoleDiameter
                        rect.size.height = circleHoleDiameter
                        
                        context.fillEllipse(in: rect)
                    }
                }
            }
        }
        
        context.restoreGState()

        // Merge nested ordered arrays into the single accessibleChartElements.
        accessibleChartElements.append(contentsOf: accessibilityOrderedElements.flatMap { $0 } )
        accessibilityPostLayoutChangedNotification()
    }
    
    open override func drawHighlighted(context: CGContext, indices: [Highlight])
    {
        guard
            let dataProvider = dataProvider,
            let lineData = dataProvider.lineData
        else { return }
        
        let chartXMax = dataProvider.chartXMax
        
        context.saveGState()
        
        for high in indices
        {
            guard let set = lineData[high.dataSetIndex] as? LineChartDataSetProtocol,
                  set.isHighlightEnabled
            else { continue }
            
            guard let e = set.entryForXValue(high.x, closestToY: high.y) else { continue }
            
            if !isInBoundsX(entry: e, dataSet: set)
            {
                continue
            }

            context.setStrokeColor(set.highlightColor.cgColor)
            context.setLineWidth(set.highlightLineWidth)
            if set.highlightLineDashLengths != nil
            {
                context.setLineDash(phase: set.highlightLineDashPhase, lengths: set.highlightLineDashLengths!)
            }
            else
            {
                context.setLineDash(phase: 0.0, lengths: [])
            }
            
            let x = e.x // get the x-position
            let y = e.y * Double(animator.phaseY)
            
            if x > chartXMax * animator.phaseX
            {
                continue
            }
            
            let trans = dataProvider.getTransformer(forAxis: set.axisDependency)
            
            let pt = trans.pixelForValues(x: x, y: y)
            
            high.setDraw(pt: pt)
            
            // draw the lines
            drawHighlightLines(context: context, point: pt, set: set)
        }
        
        context.restoreGState()
    }

    func drawGradientLine(context: CGContext, dataSet: LineChartDataSetProtocol, spline: CGPath, matrix: CGAffineTransform)
    {
        guard let gradientPositions = dataSet.gradientPositions else
        {
            assertionFailure("Must set `gradientPositions if `dataSet.isDrawLineWithGradientEnabled` is true")
            return
        }

        // `insetBy` is applied since bounding box
        // doesn't take into account line width
        // so that peaks are trimmed since
        // gradient start and gradient end calculated wrong
        let boundingBox = spline.boundingBox
            .insetBy(dx: -dataSet.lineWidth / 2, dy: -dataSet.lineWidth / 2)

        guard !boundingBox.isNull, !boundingBox.isInfinite, !boundingBox.isEmpty else {
            return
        }

        let gradientStart = CGPoint(x: 0, y: boundingBox.minY)
        let gradientEnd = CGPoint(x: 0, y: boundingBox.maxY)
        let gradientColorComponents: [CGFloat] = dataSet.colors
            .reversed()
            .reduce(into: []) { (components, color) in
                guard let (r, g, b, a) = color.nsuirgba else {
                    return
                }
                components += [r, g, b, a]
            }
        let gradientLocations: [CGFloat] = gradientPositions.reversed()
            .map { (position) in
                let location = CGPoint(x: boundingBox.minX, y: position)
                    .applying(matrix)
                let normalizedLocation = (location.y - boundingBox.minY)
                    / (boundingBox.maxY - boundingBox.minY)
                return normalizedLocation.clamped(to: 0...1)
            }

        let baseColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(
                colorSpace: baseColorSpace,
                colorComponents: gradientColorComponents,
                locations: gradientLocations,
                count: gradientLocations.count) else {
            return
        }

        context.saveGState()
        defer { context.restoreGState() }

        context.beginPath()
        context.addPath(spline)
        context.replacePathWithStrokedPath()
        context.clip()
        context.drawLinearGradient(gradient, start: gradientStart, end: gradientEnd, options: [])
    }
    
    /// Creates a nested array of empty subarrays each of which will be populated with NSUIAccessibilityElements.
    /// This is marked internal to support HorizontalBarChartRenderer as well.
    private func accessibilityCreateEmptyOrderedElements() -> [[NSUIAccessibilityElement]]
    {
        guard let chart = dataProvider as? LineChartView else { return [] }

        let dataSetCount = chart.lineData?.dataSetCount ?? 0

        return Array(repeating: [NSUIAccessibilityElement](),
                     count: dataSetCount)
    }

    /// Creates an NSUIAccessibleElement representing the smallest meaningful bar of the chart
    /// i.e. in case of a stacked chart, this returns each stack, not the combined bar.
    /// Note that it is marked internal to support subclass modification in the HorizontalBarChart.
    private func createAccessibleElement(withIndex idx: Int,
                                         container: LineChartView,
                                         dataSet: LineChartDataSetProtocol,
                                         dataSetIndex: Int,
                                         modifier: (NSUIAccessibilityElement) -> ()) -> NSUIAccessibilityElement
    {
        let element = NSUIAccessibilityElement(accessibilityContainer: container)
        let xAxis = container.xAxis

        guard let e = dataSet.entryForIndex(idx) else { return element }
        guard let dataProvider = dataProvider else { return element }

        // NOTE: The formatter can cause issues when the x-axis labels are consecutive ints.
        // i.e. due to the Double conversion, if there are more than one data set that are grouped,
        // there is the possibility of some labels being rounded up. A floor() might fix this, but seems to be a brute force solution.
        let label = xAxis.valueFormatter?.stringForValue(e.x, axis: xAxis) ?? "\(e.x)"

        let elementValueText = dataSet.valueFormatter.stringForValue(e.y,
                                                                     entry: e,
                                                                     dataSetIndex: dataSetIndex,
                                                                     viewPortHandler: viewPortHandler)

        let dataSetCount = dataProvider.lineData?.dataSetCount ?? -1
        let doesContainMultipleDataSets = dataSetCount > 1

        element.accessibilityLabel = "\(doesContainMultipleDataSets ? (dataSet.label ?? "")  + ", " : "") \(label): \(elementValueText)"

        modifier(element)

        return element
    }
}
