//
//  LineChartDataSetProtocol.swift
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


@objc
public protocol LineChartDataSetProtocol: LineRadarChartDataSetProtocol
{
    // MARK: - Data functions and accessors
    
    // MARK: - Styling functions and accessors
    
    /// The drawing mode for this line dataset
    ///
    /// **default**: Linear
    var mode: LineChartDataSet.Mode { get set }
    
    /// Intensity for cubic lines (min = 0.05, max = 1)
    ///
    /// **default**: 0.2
    var cubicIntensity: CGFloat { get set }

    /// If true, gradient lines are drawn instead of solid
    var isDrawLineWithGradientEnabled: Bool { get set }

    /// The points where gradient should change color
    var gradientPositions: [CGFloat]? { get set }

    /// The radius of the drawn circles.
    var circleRadius: CGFloat { get set }
    
    /// The hole radius of the drawn circles.
    var circleHoleRadius: CGFloat { get set }
    
    var circleColors: [NSUIColor] { get set }

    /// The radius of the drawn circles for lonely points when there are breaks in
    /// line due to `maximumGapBetweenPoints`.
    var gapCircleRadius: CGFloat { get set }

    /// The width of the drawn circles for lonely points when there are breaks in
    /// line due to `maximumGapBetweenPoints`.
    var gapLineWidth: CGFloat { get set }

    /// - Returns: The color at the given index of the DataSet's circle-color array.
    /// Performs a IndexOutOfBounds check by modulus.
    func getCircleColor(atIndex: Int) -> NSUIColor?
    
    /// Sets the one and ONLY color that should be used for this DataSet.
    /// Internally, this recreates the colors array and adds the specified color.
    func setCircleColor(_ color: NSUIColor)
    
    /// Resets the circle-colors array and creates a new one
    func resetCircleColors(_ index: Int)
    
    /// If true, drawing circles is enabled
    var drawCirclesEnabled: Bool { get set }
    
    /// `true` if drawing circles for this DataSet is enabled, `false` ifnot
    var isDrawCirclesEnabled: Bool { get }
    
    /// The color of the inner circle (the circle-hole).
    var circleHoleColor: NSUIColor? { get set }
    
    /// `true` if drawing circles for this DataSet is enabled, `false` ifnot
    var drawCircleHoleEnabled: Bool { get set }
    
    /// `true` if drawing the circle-holes is enabled, `false` ifnot.
    var isDrawCircleHoleEnabled: Bool { get }
    
    /// This is how much (in pixels) into the dash pattern are we starting from.
    var lineDashPhase: CGFloat { get }
    
    /// This is the actual dash pattern.
    /// I.e. [2, 3] will paint [--   --   ]
    /// [1, 3, 4, 2] will paint [-   ----  -   ----  ]
    var lineDashLengths: [CGFloat]? { get set }
    
    /// Line cap type, default is CGLineCap.Butt
    var lineCapType: CGLineCap { get set }

    /// Whether gaps between points should be rendered in the line.
    /// If True, maximumGapBetweenPoints will be applied to rended the dashed line for the gap.
    var showGapBetweenPoints: Bool { get set }

    /// The maximum gap (in x-value distance) above which the line should break.
    var maximumGapBetweenPoints: CGFloat { get set}

    /// Whether the horizontal alert threshold line should be drawn.
    var drawAlertRangeThresholdLine: Bool { get set }

    /// Whether alert is enabled and the alert range should be drawn.
    var hasAlertRange: Bool { get set }

    /// Optional lower bound – any value **below** this is rendered with `alertColor`.
    var lowerAlertLimit: CGFloat { get set }

    /// Optional upper bound – any value **above** this is rendered with `alertColor`.
    var upperAlertLimit: CGFloat { get set }

    /// Stroke & fill colour applied to out‑of‑range segments.
    var alertColor: NSUIColor { get set }

    /// Sets a custom FillFormatterProtocol to the chart that handles the position of the filled-line for each DataSet. Set this to null to use the default logic.
    var fillFormatter: FillFormatter? { get set }
}
