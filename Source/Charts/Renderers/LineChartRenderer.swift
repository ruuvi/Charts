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
    // MARK: - Linear drawing (alert‑range aware)
    @objc open func drawLinear(
        context: CGContext,
        dataSet: LineChartDataSetProtocol
    )
    {
        let extraPadding: CGFloat = 20.0
        guard let dataProvider = dataProvider,
              dataSet.entryCount > 0 else { return }

        // Common constants
        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
        let toPixel = trans.valueToPixelMatrix
        let phaseY = animator.phaseY
        let maxGap = dataSet.maximumGapBetweenPoints

        // If no alert range is set, draw normally
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

        // ──────────────────────────────
        // Performance optimization: Only draw what's visible plus margins
        // ──────────────────────────────

        // Find visible x-range in chart coordinates
        let visibleMinX = Double(trans.pixelForValues(x: 0, y: 0).x - extraPadding)
        let visibleMaxX = Double(trans.pixelForValues(x: 0, y: 0).x + extraPadding)

        // Set bounds to just visible area plus some margin for smooth scrolling
        _xBounds.set(chart: dataProvider, dataSet: dataSet, animator: animator)

        // Find actual indices to draw based on visibility
        var drawStartIdx = _xBounds.min
        var drawEndIdx = _xBounds.min + _xBounds.range

        // Find more precise start index (optimization for large datasets)
        while drawStartIdx > 0, let entry = dataSet.entryForIndex(drawStartIdx - 1), Double(entry.x) >= Double(visibleMinX) {
            drawStartIdx -= 1
        }

        // Find more precise end index
        while drawEndIdx < dataSet.entryCount - 1, let entry = dataSet.entryForIndex(drawEndIdx + 1), Double(entry.x) <= Double(visibleMaxX) {
            drawEndIdx += 1
        }

        // Add a couple more points on each side to ensure smooth transitions
        drawStartIdx = max(0, drawStartIdx - 2)
        drawEndIdx = min(dataSet.entryCount - 1, drawEndIdx + 2)

        guard drawEndIdx >= drawStartIdx,
              let firstEntry = dataSet.entryForIndex(drawStartIdx),
              let lastEntry = dataSet.entryForIndex(drawEndIdx) else { return }

        // ──────────────────────────────
        // Pre-calculate reusable values
        // ──────────────────────────────
        let axisMinimum = dataProvider.getAxis(dataSet.axisDependency).axisMinimum
        let upperInAlert = !upper.isNaN
        let lowerInAlert = !lower.isNaN
        let baselineY = CGFloat(axisMinimum)

        // Pre-calculate transformed threshold points
        let upperPoint = upperInAlert ? CGPoint(x: 0, y: upper).applying(toPixel) : CGPoint.zero
        let lowerPoint = lowerInAlert ? CGPoint(x: 0, y: lower).applying(toPixel) : CGPoint.zero
        let y_upper_pixel = upperPoint.y
        let y_lower_pixel = lowerPoint.y

        // Extended content area
        let extendedLeft = viewPortHandler.contentLeft - extraPadding
        let extendedRight = viewPortHandler.contentRight + extraPadding
        let extendedWidth = extendedRight - extendedLeft

        // ──────────────────────────────
        // 1. Build the full fill path (once)
        // ──────────────────────────────
        let fullFillPath = autoreleasepool { () -> CGPath in
            let path = CGMutablePath()
            path.move(to: CGPoint(x: CGFloat(firstEntry.x),
                                  y: CGFloat(firstEntry.y * phaseY)))

            var prevEntry = firstEntry
            var prevX = firstEntry.x

            for idx in stride(from: drawStartIdx + 1, through: drawEndIdx, by: 1) {
                guard let cur = dataSet.entryForIndex(idx) else { continue }

                // Skip duplicates for performance
                guard cur.x > prevX else { continue }
                prevX = cur.x

                if maxGap > 0, cur.x - prevEntry.x > maxGap {
                    // Draw dashed hint for gaps (handled separately below for better performance)
                    path.addLine(to: CGPoint(x: CGFloat(cur.x),
                                             y: CGFloat(cur.y * phaseY)))
                } else {
                    path.addLine(to: CGPoint(x: CGFloat(cur.x),
                                             y: CGFloat(cur.y * phaseY)))
                }

                prevEntry = cur
            }

            // Close the path to baseline and back
            path.addLine(to: CGPoint(x: CGFloat(lastEntry.x), y: baselineY))
            path.addLine(to: CGPoint(x: CGFloat(firstEntry.x), y: baselineY))
            path.closeSubpath()

            // Transform only once
            var m = toPixel
            guard let transformed = path.copy(using: &m) else { return path }
            return transformed
        }

        // ──────────────────────────────
        // 2. Draw fills using clipping regions (only when needed)
        // ──────────────────────────────
        if dataSet.isDrawFilledEnabled {

            // Draw alert regions (above upper and below lower)
            if (upperInAlert || lowerInAlert) {
                context.saveGState()

                // Create unified alert clipping region when possible
                if upperInAlert && lowerInAlert {
                    let aboveClipRect = CGRect(x: extendedLeft,
                                              y: viewPortHandler.contentTop,
                                              width: extendedWidth,
                                              height: y_upper_pixel - viewPortHandler.contentTop)

                    let belowClipRect = CGRect(x: extendedLeft,
                                              y: y_lower_pixel,
                                              width: extendedWidth,
                                              height: viewPortHandler.contentBottom - y_lower_pixel)

                    // Create combined path for both alert regions
                    if aboveClipRect.height > 0 && belowClipRect.height > 0 {
                        let combinedClipPath = CGMutablePath()
                        combinedClipPath.addRect(aboveClipRect)
                        combinedClipPath.addRect(belowClipRect)
                        context.addPath(combinedClipPath)
                        context.clip()

                        // Single draw call for both regions
                        if let fill = dataSet.fill {
                            drawFilledPath(context: context,
                                          path: fullFillPath,
                                          fill: fill,
                                          fillAlpha: dataSet.fillAlpha)
                        } else {
                            drawFilledPath(context: context,
                                          path: fullFillPath,
                                          fillColor: alertColor,
                                          fillAlpha: dataSet.fillAlpha)
                        }
                    }
                } else {
                    // Only one threshold - simpler case
                    let alertClipRect: CGRect
                    if upperInAlert {
                        alertClipRect = CGRect(x: extendedLeft,
                                              y: viewPortHandler.contentTop,
                                              width: extendedWidth,
                                              height: y_upper_pixel - viewPortHandler.contentTop)
                    } else {
                        alertClipRect = CGRect(x: extendedLeft,
                                              y: y_lower_pixel,
                                              width: extendedWidth,
                                              height: viewPortHandler.contentBottom - y_lower_pixel)
                    }

                    if alertClipRect.height > 0 {
                        context.clip(to: alertClipRect)
                        if let fill = dataSet.fill {
                            drawFilledPath(context: context,
                                          path: fullFillPath,
                                          fill: fill,
                                          fillAlpha: dataSet.fillAlpha)
                        } else {
                            drawFilledPath(context: context,
                                          path: fullFillPath,
                                          fillColor: alertColor,
                                          fillAlpha: dataSet.fillAlpha)
                        }
                    }
                }

                context.restoreGState()
            }

            // Draw normal region
            if (upperInAlert && lowerInAlert) || (upperInAlert || lowerInAlert) {
                context.saveGState()

                let normalClipRect: CGRect
                if upperInAlert && lowerInAlert {
                    // Between thresholds
                    normalClipRect = CGRect(x: extendedLeft,
                                           y: y_upper_pixel,
                                           width: extendedWidth,
                                           height: y_lower_pixel - y_upper_pixel)
                } else if upperInAlert {
                    // Below upper threshold
                    normalClipRect = CGRect(x: extendedLeft,
                                           y: y_upper_pixel,
                                           width: extendedWidth,
                                           height: viewPortHandler.contentBottom - y_upper_pixel)
                } else {
                    // Above lower threshold
                    normalClipRect = CGRect(x: extendedLeft,
                                           y: viewPortHandler.contentTop,
                                           width: extendedWidth,
                                           height: y_lower_pixel - viewPortHandler.contentTop)
                }

                if normalClipRect.height > 0 {
                    context.clip(to: normalClipRect)
                    if let fill = dataSet.fill {
                        drawFilledPath(context: context,
                                      path: fullFillPath,
                                      fill: fill,
                                      fillAlpha: dataSet.fillAlpha)
                    } else {
                        drawFilledPath(context: context,
                                      path: fullFillPath,
                                      fillColor: normalColor,
                                      fillAlpha: dataSet.fillAlpha)
                    }
                }

                context.restoreGState()
            }
        }

        // ──────────────────────────────
        // 3. Draw threshold lines (performance: use single call when possible)
        // ──────────────────────────────
        if upperInAlert || lowerInAlert {
            context.saveGState()
            context.setStrokeColor(alertColor.cgColor)
            context.setLineWidth(1.0)

            // Draw both lines in a single stroke operation if possible
            if upperInAlert && lowerInAlert &&
               viewPortHandler.isInBoundsY(y_upper_pixel) &&
               viewPortHandler.isInBoundsY(y_lower_pixel) {

                let linesPath = CGMutablePath()
                linesPath.move(to: CGPoint(x: extendedLeft, y: y_upper_pixel))
                linesPath.addLine(to: CGPoint(x: extendedRight, y: y_upper_pixel))
                linesPath.move(to: CGPoint(x: extendedLeft, y: y_lower_pixel))
                linesPath.addLine(to: CGPoint(x: extendedRight, y: y_lower_pixel))
                context.addPath(linesPath)
                context.strokePath()
            } else {
                // Draw lines individually
                if upperInAlert && viewPortHandler.isInBoundsY(y_upper_pixel) {
                    context.move(to: CGPoint(x: extendedLeft, y: y_upper_pixel))
                    context.addLine(to: CGPoint(x: extendedRight, y: y_upper_pixel))
                    context.strokePath()
                }

                if lowerInAlert && viewPortHandler.isInBoundsY(y_lower_pixel) {
                    context.move(to: CGPoint(x: extendedLeft, y: y_lower_pixel))
                    context.addLine(to: CGPoint(x: extendedRight, y: y_lower_pixel))
                    context.strokePath()
                }
            }

            context.restoreGState()
        }

        // ──────────────────────────────
        // 4. Efficiently draw line segments
        // ──────────────────────────────

        // Reusable arrays for segment drawing (avoid repeated allocations)
        var normalSegments: [CGPoint] = []
        var alertSegments: [CGPoint] = []
        normalSegments.reserveCapacity(50) // Pre-allocate reasonable capacity
        alertSegments.reserveCapacity(50)

        // Pre-calculate segments and categorize by color
        autoreleasepool {
            for idx in stride(from: drawStartIdx, through: drawEndIdx - 1, by: 1) {
                guard let e1 = dataSet.entryForIndex(idx),
                      let e2 = dataSet.entryForIndex(idx + 1) else {
                    continue
                }

                // Skip large gaps (will be handled by dashed lines)
                if maxGap > 0, (e2.x - e1.x) > maxGap {
                    continue
                }

                // Convert to screen points
                let p1 = CGPoint(x: CGFloat(e1.x), y: CGFloat(e1.y * phaseY)).applying(toPixel)
                let p2 = CGPoint(x: CGFloat(e2.x), y: CGFloat(e2.y * phaseY)).applying(toPixel)

                // Skip if completely outside viewport (with margin)
                let minX = min(p1.x, p2.x)
                let maxX = max(p1.x, p2.x)
                if maxX < extendedLeft || minX > extendedRight {
                    continue
                }

                // Check alert status
                let a1 = (upperInAlert && e1.y > upper) || (lowerInAlert && e1.y < lower)
                let a2 = (upperInAlert && e2.y > upper) || (lowerInAlert && e2.y < lower)

                // Same state - add to appropriate segment array
                if a1 == a2 {
                    if a1 {
                        alertSegments.append(p1)
                        alertSegments.append(p2)
                    } else {
                        normalSegments.append(p1)
                        normalSegments.append(p2)
                    }
                    continue
                }

                // If crossing threshold, split the segment
                var limitY: Double = .nan
                if upperInAlert && (e1.y - upper) * (e2.y - upper) < 0 {
                    limitY = upper
                } else if lowerInAlert && (e1.y - lower) * (e2.y - lower) < 0 {
                    limitY = lower
                }

                if limitY.isFinite {
                    // Calculate intersection
                    let dy = e2.y - e1.y
                    if abs(dy) >= 1e-6 {  // Avoid division by near-zero
                        let t = (limitY - e1.y) / dy
                        if t > 0 && t < 1 {  // Valid intersection point
                            let xI = e1.x + t * (e2.x - e1.x)
                            let pI = CGPoint(x: CGFloat(xI), y: CGFloat(limitY * phaseY)).applying(toPixel)

                            // Add segments with appropriate colors
                            if (upperInAlert && e1.y > upper) || (lowerInAlert && e1.y < lower) {
                                alertSegments.append(p1)
                                alertSegments.append(pI)
                                normalSegments.append(pI)
                                normalSegments.append(p2)
                            } else {
                                normalSegments.append(p1)
                                normalSegments.append(pI)
                                alertSegments.append(pI)
                                alertSegments.append(p2)
                            }
                            continue
                        }
                    }
                }

                // Fallback (should rarely happen)
                normalSegments.append(p1)
                normalSegments.append(p2)
            }
        }

        // Draw segments in batches (more efficient than one-by-one)
        context.saveGState()

        // Draw normal segments
        if !normalSegments.isEmpty {
            context.setStrokeColor(normalColor.cgColor)
            context.setLineWidth(dataSet.lineWidth)
            context.strokeLineSegments(between: normalSegments)
        }

        // Draw alert segments
        if !alertSegments.isEmpty {
            context.setStrokeColor(alertColor.cgColor)
            context.setLineWidth(dataSet.lineWidth)
            context.strokeLineSegments(between: alertSegments)
        }

        context.restoreGState()

        // ──────────────────────────────
        // 5. Draw dashed lines for gaps (if needed)
        // ──────────────────────────────
        if maxGap > 0 {
            var dashSegments: [CGPoint] = []

            for idx in stride(from: drawStartIdx, to: drawEndIdx, by: 1) {
                guard let e1 = dataSet.entryForIndex(idx),
                      let e2 = dataSet.entryForIndex(idx + 1) else { continue }

                if e2.x - e1.x > maxGap {
                    let p1 = CGPoint(x: CGFloat(e1.x), y: CGFloat(e1.y * phaseY)).applying(toPixel)
                    let p2 = CGPoint(x: CGFloat(e2.x), y: CGFloat(e2.y * phaseY)).applying(toPixel)

                    // Only add if visible
                    let minX = min(p1.x, p2.x)
                    let maxX = max(p1.x, p2.x)
                    if maxX >= extendedLeft && minX <= extendedRight {
                        dashSegments.append(p1)
                        dashSegments.append(p2)
                    }
                }
            }

            if !dashSegments.isEmpty {
                context.saveGState()
                context.setLineDash(phase: 0, lengths: [1, 2])
                context.setLineWidth(dataSet.lineWidth)
                context.setStrokeColor(normalColor.cgColor)
                context.strokeLineSegments(between: dashSegments)
                context.restoreGState()
            }
        }
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
