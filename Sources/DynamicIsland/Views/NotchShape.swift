import SwiftUI

/// Кастомная геометрическая форма выреза MacBook с вогнутыми верхними «ушками» (плавный переход в верхнюю рамку экрана)
/// и выпуклыми скругленными нижними углами. Полностью поддерживает пружинную интерполяцию SwiftUI.
public struct NotchShape: Shape {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }
    
    public init(topCornerRadius: CGFloat = 10, bottomCornerRadius: CGFloat = 14) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let topR = min(topCornerRadius, rect.width / 4, rect.height / 2)
        let botR = min(bottomCornerRadius, (rect.width - topR * 2) / 2, rect.height - topR)
        
        // Начало в левом верхнем углу (вдоль верхней кромки экрана)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        
        // Левое верхнее вогнутое «ушко»
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
            control: CGPoint(x: rect.minX + topR, y: rect.minY)
        )
        
        // Левая вертикальная грань
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))
        
        // Левый нижний выпуклый угол
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
            control: CGPoint(x: rect.minX + topR, y: rect.maxY)
        )
        
        // Нижняя горизонтальная грань
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))
        
        // Правый нижний выпуклый угол
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
            control: CGPoint(x: rect.maxX - topR, y: rect.maxY)
        )
        
        // Правая вертикальная грань
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))
        
        // Правое верхнее вогнутое «ушко»
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topR, y: rect.minY)
        )
        
        path.closeSubpath()
        return path
    }
}

