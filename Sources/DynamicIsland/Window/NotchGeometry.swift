import AppKit

/// Вычисляет геометрию физического выреза (Notch) на экране MacBook и размеры областей острова.
public struct NotchGeometry: Equatable {
    /// Экран, на котором располагается остров
    public let screenFrame: NSRect
    /// Есть ли физический вырез на данном экране
    public let hasPhysicalNotch: Bool
    /// Ширина самого физического выреза (камеры)
    public let physicalNotchWidth: CGFloat
    /// Высота самого физического выреза (и Menu Bar)
    public let physicalNotchHeight: CGFloat
    
    /// Размеры холста окна NSPanel (фиксированные с запасом под тени и пружинную анимацию)
    public static let canvasWidth: CGFloat = 660
    public static let canvasHeight: CGFloat = 280
    
    /// Размеры рабочей области острова в развернутом состоянии (без учета верхних ушек)
    public static let expandedWidth: CGFloat = 400
    public static let expandedHeight: CGFloat = 214
    
    /// Определяет геометрию для текущего основного экрана (или экрана с вырезом)
    public static func detect(for preferredScreen: NSScreen? = nil) -> NotchGeometry {
        let screen = preferredScreen
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        
        guard let screen else {
            return NotchGeometry(
                screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
                hasPhysicalNotch: false,
                physicalNotchWidth: 184,
                physicalNotchHeight: 32
            )
        }
        
        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea,
           rightArea.minX > leftArea.maxX {
            let notchWidth = rightArea.minX - leftArea.maxX
            let notchHeight = max(topInset, 32)
            return NotchGeometry(
                screenFrame: screen.frame,
                hasPhysicalNotch: true,
                physicalNotchWidth: notchWidth,
                physicalNotchHeight: notchHeight
            )
        } else {
            let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 32)
            return NotchGeometry(
                screenFrame: screen.frame,
                hasPhysicalNotch: false,
                physicalNotchWidth: 184,
                physicalNotchHeight: min(max(menuBarHeight, 32), 38)
            )
        }
    }
    
    /// Фрейм окна NSPanel в глобальных экранных координатах (прижат к верхнему краю экрана по центру)
    public var panelFrame: NSRect {
        let x = screenFrame.midX - (Self.canvasWidth / 2.0)
        let y = screenFrame.maxY - Self.canvasHeight
        return NSRect(x: x, y: y, width: Self.canvasWidth, height: Self.canvasHeight)
    }
    
    /// Высота компактной капсулы
    public var compactHeight: CGFloat {
        return physicalNotchHeight
    }
    
    /// Глобальный прямоугольник активной зоны острова на экране (для проверки наведения мыши)
    public func activeScreenRect(isExpanded: Bool) -> NSRect {
        let width = isExpanded ? Self.expandedWidth : physicalNotchWidth
        let height = isExpanded ? Self.expandedHeight : compactHeight
        let horizontalPadding: CGFloat = isExpanded ? 18 : 6
        let bottomPadding: CGFloat = isExpanded ? 16 : 4
        
        let x = screenFrame.midX - (width / 2.0) - horizontalPadding
        let y = screenFrame.maxY - height - bottomPadding
        return NSRect(
            x: x,
            y: y,
            width: width + (horizontalPadding * 2),
            height: height + bottomPadding + 4
        )
    }
}
