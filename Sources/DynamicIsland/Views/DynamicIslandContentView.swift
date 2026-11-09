import SwiftUI

public struct DynamicIslandContentView: View {
    @ObservedObject var viewModel: IslandViewModel
    
    public init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
    }
    
    private var topRadius: CGFloat {
        viewModel.isExpanded ? 16 : 6
    }
    
    private var bottomRadius: CGFloat {
        viewModel.isExpanded ? 26 : 10
    }
    
    private var bodyWidth: CGFloat {
        viewModel.isExpanded
            ? NotchGeometry.expandedWidth
            : viewModel.geometry.physicalNotchWidth
    }
    
    private var shapeWidth: CGFloat {
        bodyWidth + (topRadius * 2)
    }
    
    private var shapeHeight: CGFloat {
        viewModel.isExpanded
            ? NotchGeometry.expandedHeight
            : viewModel.geometry.compactHeight
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Прозрачный холст на всю ширину NSPanel
            Color.clear
                .frame(width: NotchGeometry.canvasWidth, height: NotchGeometry.canvasHeight)
            
            // Главная капсула Dynamic Island: полностью невидима (opacity = 0) в покое,
            // плавно выезжает из физического выреза только при наведении курсора!
            ZStack(alignment: .top) {
                NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                    .fill(Color.black)
                    .shadow(
                        color: Color.black.opacity(viewModel.isExpanded ? 0.5 : 0.0),
                        radius: viewModel.isExpanded ? 22 : 0,
                        x: 0,
                        y: viewModel.isExpanded ? 10 : 0
                    )
                    .frame(width: shapeWidth, height: shapeHeight)
                
                // Размер содержимого постоянный: при раскрытии меняется маска,
                // а текст и кнопки не перевёрстываются в ширину выреза.
                VStack(spacing: 0) {
                    expandedTopBar
                        .frame(width: NotchGeometry.expandedWidth, height: viewModel.geometry.physicalNotchHeight)

                    expandedMainBody
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                        .frame(
                            width: NotchGeometry.expandedWidth,
                            height: NotchGeometry.expandedHeight - viewModel.geometry.physicalNotchHeight,
                            alignment: .top
                        )
                }
                .frame(width: NotchGeometry.expandedWidth, height: NotchGeometry.expandedHeight, alignment: .top)
                .padding(.horizontal, 16)
                .opacity(viewModel.isExpanded ? 1 : 0)
                .offset(y: viewModel.isExpanded ? 0 : -8)
                .animation(
                    .easeInOut(duration: viewModel.isExpanded ? 0.24 : 0.14)
                        .delay(viewModel.isExpanded ? 0.08 : 0),
                    value: viewModel.isExpanded
                )
                .frame(width: shapeWidth, height: shapeHeight, alignment: .top)
                .clipShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
            }
            .frame(width: shapeWidth, height: shapeHeight, alignment: .top)
            .opacity(viewModel.isExpanded ? 1.0 : 0.0)
            .allowsHitTesting(viewModel.isExpanded)
        }
        .frame(width: NotchGeometry.canvasWidth, height: NotchGeometry.canvasHeight, alignment: .top)
        .environment(\.locale, Locale(identifier: "en_US"))
    }
    
    // MARK: - Верхняя полоса в развернутом режиме (слева и справа от физического выреза камеры)
    
    private var expandedTopBar: some View {
        let sideWidth = (NotchGeometry.expandedWidth - viewModel.geometry.physicalNotchWidth) / 2.0
        
        return HStack(spacing: 0) {
            // Музыка слева от физического выреза.
            HStack(spacing: 6) {
                tabButton(for: .music)
                Spacer(minLength: 0)
            }
            .padding(.leading, 14)
            .frame(width: sideWidth, height: viewModel.geometry.physicalNotchHeight)
            
            // Пустое место точно под физическую камеру (Notch)
            Spacer()
                .frame(width: viewModel.geometry.physicalNotchWidth)
            
            // Буфер обмена справа от выреза.
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                tabButton(for: .clipboard)
                
            }
            .padding(.trailing, 14)
            .frame(width: sideWidth, height: viewModel.geometry.physicalNotchHeight)
        }
    }
    
    private func tabButton(for tab: IslandTab) -> some View {
        let isSelected = (viewModel.activeTab == tab)
        return Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                viewModel.activeTab = tab
            }
        }) {
            Image(systemName: tab.iconName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.4))
                .frame(width: 28, height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(isSelected ? 0.07 : 0))
                )
        }
        .buttonStyle(.plain)
        .help(tab.rawValue)
        .accessibilityLabel(tab.rawValue)
    }
    
    // MARK: - Основное тело развернутого острова (под вырезом камеры)
    
    @ViewBuilder
    private var expandedMainBody: some View {
        switch viewModel.activeTab {
        case .music:
            MusicTabView(
                musicManager: viewModel.musicManager,
                isSourcePickerPresented: $viewModel.isSourcePickerPresented
            )
        case .clipboard:
            ClipboardTabView(clipboardManager: viewModel.clipboardManager)
        }
    }
}
