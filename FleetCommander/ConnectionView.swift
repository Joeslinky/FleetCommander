import UIKit

protocol ConnectionViewDelegate: AnyObject {
    func connectionViewDidReconnect(_ view: ConnectionView)
    func connectionViewDidStartDiscovery(_ view: ConnectionView)
    func connectionViewDidConnect(_ view: ConnectionView, address: String, port: Int)
    func connectionViewDidCancel(_ view: ConnectionView)
    func connectionViewDidRetryDiscovery(_ view: ConnectionView)
}

final class ConnectionView: UIView, UITextFieldDelegate {
    weak var delegate: ConnectionViewDelegate?

    enum Screen {
        case home
        case manual
        case searching
        case connecting
        case failed
    }

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let brandImageView = UIImageView(image: UIImage(named: "C3X"))
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let savedCard = ChoiceCardView()
    private let discoverCard = ChoiceCardView()
    private let manualCard = ChoiceCardView()
    private let addressField = UITextField()
    private let portField = UITextField()
    private let connectButton = UIButton.appFilled(title: "Connect")
    private let backButton = UIButton.appPlain(title: "Back")
    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let logLabel = UILabel()
    private let cancelButton = UIButton.appPlain(title: "Cancel")
    private let retryButton = UIButton.appFilled(title: "Try Again")
    private let enterAddressButton = UIButton.appFilled(title: "Enter Address", color: .secondarySystemFill)
    private let homeButton = UIButton.appPlain(title: "Start Over")

    private var currentScreen: Screen = .home

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func showHome() {
        apply(screen: .home)
    }

    func showManual(address: String? = nil, port: Int? = nil) {
        if let address, !address.isEmpty { addressField.text = address }
        if let port { portField.text = "\(port)" }
        apply(screen: .manual)
        addressField.becomeFirstResponder()
    }

    func showSearching(status: String, detail: String = "Keep this phone and your comma device on the same Wi-Fi.") {
        statusLabel.text = status
        detailLabel.text = detail
        apply(screen: .searching)
        spinner.startAnimating()
    }

    func showConnecting(address: String, port: Int) {
        statusLabel.text = "Connecting"
        detailLabel.text = "\(address):\(port)"
        logLabel.text = "Opening Fleet Manager…"
        apply(screen: .connecting)
        spinner.startAnimating()
    }

    func showFailed(title: String, message: String) {
        statusLabel.text = title
        detailLabel.text = message
        apply(screen: .failed)
        spinner.stopAnimating()
    }

    func updateStatus(_ text: String) {
        statusLabel.text = text
    }

    func appendLog(_ text: String) {
        logLabel.text = text
    }

    func prefill(address: String?, port: Int?) {
        if let address, !address.isEmpty { addressField.text = address }
        if let port { portField.text = "\(port)" }
    }

    var enteredAddress: String {
        AddressValidator.sanitized(addressField.text ?? "")
    }

    var enteredPort: Int? {
        AddressValidator.port(from: portField.text)
    }

    private func setup() {
        backgroundColor = .systemGroupedBackground
        scrollView.keyboardDismissMode = .onDrag
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        brandImageView.contentMode = .scaleAspectFit
        brandImageView.translatesAutoresizingMaskIntoConstraints = false
        brandImageView.heightAnchor.constraint(equalToConstant: 88).isActive = true

        titleLabel.text = "FleetCommander"
        titleLabel.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        subtitleLabel.text = "Connect to Fleet Manager on your comma device."
        subtitleLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        savedCard.configure(
            symbol: "link.circle.fill",
            title: "Reconnect",
            subtitle: "Use the last device you opened."
        )
        discoverCard.configure(
            symbol: "wifi",
            title: "Find on this network",
            subtitle: "Looks for Fleet Manager on port 8082."
        )
        manualCard.configure(
            symbol: "keyboard",
            title: "Enter address",
            subtitle: "Use an IP address or hostname."
        )

        savedCard.addTarget(self, action: #selector(reconnectTapped), for: .touchUpInside)
        discoverCard.addTarget(self, action: #selector(discoverTapped), for: .touchUpInside)
        manualCard.addTarget(self, action: #selector(manualTapped), for: .touchUpInside)

        configureField(addressField, placeholder: "IP address or hostname", keyboard: .URL)
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.returnKeyType = .next
        addressField.delegate = self
        addressField.textContentType = .URL

        configureField(portField, placeholder: "Port (8082)", keyboard: .numberPad)
        portField.delegate = self
        portField.text = "\(AddressValidator.defaultPort)"
        addDoneToolbar(to: portField)

        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        var enterConfiguration = UIButton.Configuration.filled()
        enterConfiguration.title = "Enter Address"
        enterConfiguration.baseBackgroundColor = .tertiarySystemFill
        enterConfiguration.baseForegroundColor = .label
        enterConfiguration.cornerStyle = .fixed
        enterConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        enterAddressButton.configuration = enterConfiguration
        enterAddressButton.layer.cornerRadius = AppTheme.controlCornerRadius
        enterAddressButton.clipsToBounds = true
        enterAddressButton.addTarget(self, action: #selector(manualTapped), for: .touchUpInside)
        homeButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        spinner.color = AppTheme.accent
        spinner.hidesWhenStopped = true

        statusLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        detailLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        logLabel.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        logLabel.textColor = .tertiaryLabel
        logLabel.textAlignment = .center
        logLabel.numberOfLines = 3

        [
            brandImageView, titleLabel, subtitleLabel, savedCard, discoverCard, manualCard,
            addressField, portField, connectButton, backButton, spinner, statusLabel,
            detailLabel, logLabel, cancelButton, retryButton, enterAddressButton, homeButton
        ].forEach { contentStack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 28),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48)
        ])

        contentStack.setCustomSpacing(8, after: titleLabel)
        contentStack.setCustomSpacing(24, after: subtitleLabel)
        apply(screen: .home)
    }

    private func apply(screen: Screen) {
        currentScreen = screen
        endEditing(true)

        let saved = ConnectionStore.savedConnection
        savedCard.isHidden = saved == nil
        if let saved {
            savedCard.configure(
                symbol: "link.circle.fill",
                title: "Reconnect",
                subtitle: "\(saved.address):\(saved.port)"
            )
        }

        let home = screen == .home
        let manual = screen == .manual
        let searching = screen == .searching
        let connecting = screen == .connecting
        let failed = screen == .failed
        let progress = searching || connecting

        brandImageView.isHidden = !home && !manual
        titleLabel.isHidden = !home && !manual
        detailLabel.textColor = .secondaryLabel
        subtitleLabel.text = manual
            ? "Enter the address shown in Fleet Manager."
            : "Connect to Fleet Manager on your comma device."
        subtitleLabel.isHidden = !home && !manual
        savedCard.isHidden = !home || saved == nil
        discoverCard.isHidden = !home
        manualCard.isHidden = !home
        addressField.isHidden = !manual
        portField.isHidden = !manual
        connectButton.isHidden = !manual
        backButton.isHidden = !manual
        spinner.isHidden = !progress
        if progress { spinner.startAnimating() } else { spinner.stopAnimating() }
        statusLabel.isHidden = !progress && !failed
        detailLabel.isHidden = !progress && !failed
        logLabel.isHidden = !searching
        cancelButton.isHidden = !progress
        retryButton.isHidden = !failed
        enterAddressButton.isHidden = !failed
        homeButton.isHidden = !failed
        backButton.setTitle(manual ? "Back" : "Start Over", for: .normal)
    }

    private func configureField(_ field: UITextField, placeholder: String, keyboard: UIKeyboardType) {
        field.placeholder = placeholder
        field.keyboardType = keyboard
        field.borderStyle = .none
        field.backgroundColor = .secondarySystemGroupedBackground
        field.layer.cornerRadius = 12
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.rightViewMode = .always
        field.heightAnchor.constraint(equalToConstant: 50).isActive = true
        field.font = UIFont.systemFont(ofSize: 16)
        field.textColor = .label
    }

    private func addDoneToolbar(to field: UITextField) {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneEditing))
        ]
        toolbar.tintColor = AppTheme.accent
        field.inputAccessoryView = toolbar
    }

    @objc private func doneEditing() {
        endEditing(true)
    }

    @objc private func reconnectTapped() {
        delegate?.connectionViewDidReconnect(self)
    }

    @objc private func discoverTapped() {
        delegate?.connectionViewDidStartDiscovery(self)
    }

    @objc private func manualTapped() {
        showManual(address: enteredAddress.isEmpty ? ConnectionStore.savedAddress : enteredAddress,
                   port: enteredPort ?? ConnectionStore.savedPort)
    }

    @objc private func connectTapped() {
        endEditing(true)
        let address = enteredAddress
        guard !address.isEmpty else {
            presentInlineError("Enter an IP address or hostname.")
            return
        }
        guard AddressValidator.isValid(address) else {
            presentInlineError("That doesn’t look like a valid IP or hostname.")
            return
        }
        guard let port = enteredPort else {
            presentInlineError("Enter a port between 1 and 65535.")
            return
        }
        delegate?.connectionViewDidConnect(self, address: address, port: port)
    }

    @objc private func backTapped() {
        showHome()
    }

    @objc private func cancelTapped() {
        delegate?.connectionViewDidCancel(self)
    }

    @objc private func retryTapped() {
        delegate?.connectionViewDidRetryDiscovery(self)
    }

    private func presentInlineError(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        detailLabel.text = message
        detailLabel.textColor = .systemRed
        detailLabel.isHidden = false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === addressField {
            portField.becomeFirstResponder()
        } else {
            connectTapped()
        }
        return true
    }
}

final class ChoiceCardView: UIControl {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.alpha = self.isHighlighted ? 0.72 : 1
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = AppTheme.cardCornerRadius
        layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = AppTheme.accent
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label

        subtitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let stack = UIStackView(arrangedSubviews: [iconView, textStack])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 14
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 76)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(symbol: String, title: String, subtitle: String) {
        iconView.image = UIImage(systemName: symbol)
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }
}
