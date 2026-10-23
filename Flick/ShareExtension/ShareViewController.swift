import UIKit
import SwiftUI

final class ShareViewController: UIViewController {
    private let link = PeerLink()
    private let selection = MediaSelection()
    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ComposerScreen(link: link, selection: selection, initialSide: .right, finish: { [weak self] in
            self?.selection.cancel(); self?.link.suspend(); self?.extensionContext?.completeRequest(returningItems: nil)
        })
        let host = UIHostingController(rootView: root.tint(.green))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        preferredContentSize = CGSize(width: 420, height: 760)
        link.activate()
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        selection.load(items.flatMap { $0.attachments ?? [] })
        if selection.items.isEmpty { link.note("请先在照片或文件中多选项目，再分享给一甩。", error: true) }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true { selection.cancel(); link.suspend() }
    }
}
