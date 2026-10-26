import SwiftUI
import UIKit

final class TVZRootController: UIHostingController<TVZRootView> {

    private weak var primaryScrollView: UIScrollView?

    // 装载设置视图，不再创建滚动视图订阅。
    init() {
        super.init(rootView: TVZRootView())
    }

    // 禁止通过归档创建设置控制器。
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // 导航栏请求时查找列表，弱缓存仍在当前视图中的结果。
    @objc var contentScrollView: UIScrollView? {
        guard let rootView = viewIfLoaded else { return nil }
        if let primaryScrollView, primaryScrollView.isDescendant(of: rootView) {
            return primaryScrollView
        }
        primaryScrollView = findScrollView(in: rootView)
        return primaryScrollView
    }

    // 返回最外层滚动容器，兼容列表使用表格或集合视图的系统版本。
    private func findScrollView(in rootView: UIView) -> UIScrollView? {
        if let scrollView = rootView as? UIScrollView {
            return scrollView
        }
        for subview in rootView.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }
}

@objc(TVZRootListController)
final class TVZRootListController: PSListController {

    // 将 SwiftUI 设置视图嵌入系统偏好控制器。
    override func viewDidLoad() {
        super.viewDidLoad()
        addNavigationBarImage()

        navigationItem.title = ""
        navigationItem.largeTitleDisplayMode = .never

        let controller = TVZRootController()
        addChild(controller)

        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(controller.view)

        controller.didMove(toParent: self)
    }

    // 设置导航栏图标。
    private func addNavigationBarImage() {
        guard let image = UIImage(named: "icon", in: Bundle.tvz_support, with: nil) else {
            return
        }
        let imageView = UIImageView(image: image)
        let bannerWidth: CGFloat = 32
        let bannerHeight: CGFloat = 32
        let bannerX = bannerWidth / 2 - image.size.width / 2
        let bannerY = bannerHeight / 2 - image.size.height / 2
        imageView.frame = CGRect(x: bannerX, y: bannerY, width: bannerWidth, height: bannerHeight)
        imageView.contentMode = .scaleAspectFit
        navigationItem.titleView = imageView
    }

    // 将系统导航栏的滚动查询交给设置内容控制器。
    @objc var contentScrollView: UIScrollView? {
        (children.first as? TVZRootController)?.contentScrollView
    }
}
