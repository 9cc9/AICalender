import UIKit

struct Schedule {
    let startTime: Date
    let endTime: Date
    let title: String
    
    var duration: TimeInterval {
        return endTime.timeIntervalSince(startTime)
    }
    
    // 格式化的持续时间
    var durationText: String {
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)小时\(remainingMinutes)分钟"
        } else {
            return "\(remainingMinutes)分钟"
        }
    }
}

protocol CalendarViewDelegate: AnyObject {
    func calendarView1(_ calendarView: CalendarView, didSelectDate date: Date)
    // 可选：获取某天的日程安排
    func calendarView1(_ calendarView: CalendarView, schedulesForDate date: Date) -> [Schedule]
}

// 设置可选方法
extension CalendarViewDelegate {
    func calendarView1(_ calendarView: CalendarView, schedulesForDate date: Date) -> [Schedule] {
        return []
    }
}

class CalendarView: UIView {
    weak var delegate: CalendarViewDelegate?
    
    private let calendar = Calendar.current
    private var currentDate = Date()
    private var days: [Date] = []
    private var isAnimating = false
    private var chatHistory: [(role: String, content: String)] = []
    private let aiService = QianwenService.shared
    
    private enum AnimationDirection {
        case up
        case down
    }
    
    private lazy var monthLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 20, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var previousButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.addTarget(self, action: #selector(previousButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        button.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private lazy var weekStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private lazy var daysCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(DayCell.self, forCellWithReuseIdentifier: "DayCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        return collectionView
    }()
    
    private lazy var chatTableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.register(ChatMessageCell.self, forCellReuseIdentifier: "ChatMessageCell")
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .systemBackground
        table.separatorStyle = .none
        table.estimatedRowHeight = 60
        table.rowHeight = UITableView.automaticDimension
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return table
    }()
    
    private lazy var inputContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.layer.shadowOpacity = 0.1
        view.layer.shadowRadius = 4
        return view
    }()
    
    private lazy var inputTextView: UITextView = {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 16)
        textView.layer.cornerRadius = 20
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.returnKeyType = .send
        textView.enablesReturnKeyAutomatically = true
        textView.backgroundColor = .systemGray6
        return textView
    }()
    
    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("发送", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // 添加输入容器底部约束的引用
    private var inputContainerBottomConstraint: NSLayoutConstraint?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        updateCalendar()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        updateCalendar()
    }
    
    private func setupUI() {
        backgroundColor = .systemBackground
        
        addSubview(monthLabel)
        addSubview(previousButton)
        addSubview(nextButton)
        addSubview(weekStackView)
        addSubview(daysCollectionView)
        addSubview(chatTableView)
        addSubview(inputContainer)
        inputContainer.addSubview(inputTextView)
        inputContainer.addSubview(sendButton)
        
        setupWeekDays()
        setupConstraints()
        setupGestures()
        setupKeyboardObservers()
        
        // 设置输入框的初始高度
        inputTextView.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        // 添加点击手势来隐藏键盘
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)
    }
    
    private func setupWeekDays() {
        let weekDays = ["日", "一", "二", "三", "四", "五", "六"]
        for (index, day) in weekDays.enumerated() {
            let label = UILabel()
            label.text = day
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 14)
            label.textColor = (index == 0 || index == 6) ? .systemRed : .label
            weekStackView.addArrangedSubview(label)
        }
    }
    
    private func setupConstraints() {
        // 修改输入容器的底部约束
        inputContainerBottomConstraint = inputContainer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        
        NSLayoutConstraint.activate([
            monthLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            monthLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            
            previousButton.centerYAnchor.constraint(equalTo: monthLabel.centerYAnchor),
            previousButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            previousButton.widthAnchor.constraint(equalToConstant: 44),
            previousButton.heightAnchor.constraint(equalToConstant: 44),
            
            nextButton.centerYAnchor.constraint(equalTo: monthLabel.centerYAnchor),
            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            nextButton.widthAnchor.constraint(equalToConstant: 44),
            nextButton.heightAnchor.constraint(equalToConstant: 44),
            
            weekStackView.topAnchor.constraint(equalTo: monthLabel.bottomAnchor, constant: 16),
            weekStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            weekStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            weekStackView.heightAnchor.constraint(equalToConstant: 30),
            
            daysCollectionView.topAnchor.constraint(equalTo: weekStackView.bottomAnchor, constant: 8),
            daysCollectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            daysCollectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            daysCollectionView.heightAnchor.constraint(equalTo: daysCollectionView.widthAnchor, multiplier: 6/7),
            
            chatTableView.topAnchor.constraint(equalTo: daysCollectionView.bottomAnchor, constant: 8),
            chatTableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            chatTableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            chatTableView.bottomAnchor.constraint(equalTo: inputContainer.topAnchor),
            
            inputContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputContainerBottomConstraint!,
            inputContainer.heightAnchor.constraint(equalToConstant: 60),
            
            inputTextView.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 8),
            inputTextView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 16),
            inputTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputTextView.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -8),
            inputTextView.heightAnchor.constraint(equalToConstant: 44),
            
            sendButton.centerYAnchor.constraint(equalTo: inputTextView.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -16),
            sendButton.widthAnchor.constraint(equalToConstant: 60),
            sendButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    private func setupGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        daysCollectionView.addGestureRecognizer(panGesture)
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        
        switch gesture.state {
        case .changed:
            if abs(translation.y) > 50 && !isAnimating {
                isAnimating = true
                if translation.y > 0 {
                    // 向下滑动，显示上个月
                    moveToPreviousMonth()
                } else {
                    // 向上滑动，显示下个月
                    moveToNextMonth()
                }
            }
        case .ended:
            isAnimating = false
        default:
            break
        }
    }
    
    @objc private func previousButtonTapped() {
        moveToPreviousMonth()
    }
    
    @objc private func nextButtonTapped() {
        moveToNextMonth()
    }
    
    private func moveToPreviousMonth() {
        guard let newDate = calendar.date(byAdding: .month, value: -1, to: currentDate) else { return }
        animateMonthChange(to: newDate, direction: .down)
    }
    
    private func moveToNextMonth() {
        guard let newDate = calendar.date(byAdding: .month, value: 1, to: currentDate) else { return }
        animateMonthChange(to: newDate, direction: .up)
    }
    
    private func animateMonthChange(to newDate: Date, direction: AnimationDirection) {
        let oldDays = days
        currentDate = newDate
        days = getDaysInMonth()
        
        UIView.animate(withDuration: 0.3, animations: {
            self.monthLabel.alpha = 0
            self.daysCollectionView.alpha = 0
        }) { _ in
            self.updateCalendar()
            self.daysCollectionView.reloadData()
            
            UIView.animate(withDuration: 0.3) {
                self.monthLabel.alpha = 1
                self.daysCollectionView.alpha = 1
            }
        }
    }
    
    private func updateCalendar() {
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy年MM月"
        monthLabel.text = monthFormatter.string(from: currentDate)
        
        days = getDaysInMonth()
        daysCollectionView.reloadData()
    }
    
    private func getDaysInMonth() -> [Date] {
        let interval = calendar.dateInterval(of: .month, for: currentDate)!
        let firstDay = interval.start
        
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let offsetDays = firstWeekday - 1
        
        var days: [Date] = []
        
        if offsetDays > 0 {
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: firstDay)!
            for i in 1...offsetDays {
                if let date = calendar.date(byAdding: .day, value: -i, to: firstDay) {
                    days.insert(date, at: 0)
                }
            }
        }
        
        let currentMonthDays = calendar.range(of: .day, in: .month, for: currentDate)!.count
        for i in 0..<currentMonthDays {
            if let date = calendar.date(byAdding: .day, value: i, to: firstDay) {
                days.append(date)
            }
        }
        
        let remainingDays = 42 - days.count
        if remainingDays > 0 {
            let nextMonthFirstDay = calendar.date(byAdding: .day, value: currentMonthDays, to: firstDay)!
            for i in 0..<remainingDays {
                if let date = calendar.date(byAdding: .day, value: i, to: nextMonthFirstDay) {
                    days.append(date)
                }
            }
        }
        
        return days
    }
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    @objc private func keyboardWillShow(notification: NSNotification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }
        
        // 计算键盘高度
        let keyboardHeight = keyboardFrame.height
        
        // 更新输入容器的底部约束
        inputContainerBottomConstraint?.constant = -keyboardHeight
        
        // 更新表格视图的内容插入
        let insets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
        chatTableView.contentInset = insets
        chatTableView.scrollIndicatorInsets = insets
        
        // 使用动画更新布局
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve), animations: {
            self.layoutIfNeeded()
        }) { _ in
            // 滚动到底部
            if !self.chatHistory.isEmpty {
                let lastIndex = IndexPath(row: self.chatHistory.count - 1, section: 0)
                self.chatTableView.scrollToRow(at: lastIndex, at: .bottom, animated: true)
            }
        }
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }
        
        // 恢复输入容器的底部约束
        inputContainerBottomConstraint?.constant = 0
        
        // 恢复表格视图的内容插入
        chatTableView.contentInset = .zero
        chatTableView.scrollIndicatorInsets = .zero
        
        // 使用动画更新布局
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve), animations: {
            self.layoutIfNeeded()
        })
    }
    
    @objc private func sendButtonTapped() {
        sendMessage()
    }
    
    private func sendMessage() {
        guard let text = inputTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        
        // 添加用户消息到历史记录
        chatHistory.append((role: "user", content: text))
        
        // 清空输入框并隐藏键盘
        inputTextView.text = ""
        inputTextView.resignFirstResponder()
        
        // 刷新表格
        chatTableView.reloadData()
        
        // 滚动到底部
        if !chatHistory.isEmpty {
            let lastIndex = IndexPath(row: chatHistory.count - 1, section: 0)
            chatTableView.scrollToRow(at: lastIndex, at: .bottom, animated: true)
        }
        
        // 添加一个空的 AI 消息，用于流式更新
        chatHistory.append((role: "assistant", content: ""))
        chatTableView.reloadData()
        
        // 调用 AI 服务
        aiService.sendMessageStream(
            prompt: text,
            onReceive: { [weak self] content in
                guard let self = self else { return }
                // 更新最后一条 AI 消息的内容
                if let lastIndex = self.chatHistory.lastIndex(where: { $0.role == "assistant" }) {
                    self.chatHistory[lastIndex].content += content
                    self.chatTableView.reloadData()
                    
                    // 滚动到底部
                    let lastIndexPath = IndexPath(row: self.chatHistory.count - 1, section: 0)
                    self.chatTableView.scrollToRow(at: lastIndexPath, at: .bottom, animated: true)
                }
            },
            onThinking: { [weak self] thought in
                guard let self = self else { return }
                // 更新最后一条 AI 消息的内容，添加思考过程
                if let lastIndex = self.chatHistory.lastIndex(where: { $0.role == "assistant" }) {
                    self.chatHistory[lastIndex].content += thought
                    self.chatTableView.reloadData()
                    
                    // 滚动到底部
                    let lastIndexPath = IndexPath(row: self.chatHistory.count - 1, section: 0)
                    self.chatTableView.scrollToRow(at: lastIndexPath, at: .bottom, animated: true)
                }
            },
            onLoading: { [weak self] isLoading in
                guard let self = self else { return }
                // 可以在这里更新加载状态
                self.sendButton.isEnabled = !isLoading
            },
            onComplete: { [weak self] content, error in
                guard let self = self else { return }
                if let error = error {
                    print("AI 服务错误: \(error)")
                    // 更新最后一条 AI 消息为错误信息
                    if let lastIndex = self.chatHistory.lastIndex(where: { $0.role == "assistant" }) {
                        self.chatHistory[lastIndex].content = "抱歉，发生错误：\(error.localizedDescription)"
                        self.chatTableView.reloadData()
                    }
                }
            }
        )
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // 获取点击位置
        let location = gesture.location(in: self)
        
        // 如果点击位置不在输入框区域内，则隐藏键盘
        if !inputContainer.frame.contains(location) {
            inputTextView.resignFirstResponder()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // 确保表格视图正确显示
        chatTableView.layoutIfNeeded()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension CalendarView: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return days.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "DayCell", for: indexPath) as! DayCell
        let date = days[indexPath.item]
        cell.configure(with: date, isCurrentMonth: calendar.isDate(date, equalTo: currentDate, toGranularity: .month))
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width / 7
        return CGSize(width: width, height: width)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let selectedDate = days[indexPath.item]
        delegate?.calendarView1(self, didSelectDate: selectedDate)
    }
}

class DayCell: UICollectionViewCell {
    private let dayLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(dayLabel)
        NSLayoutConstraint.activate([
            dayLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dayLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    func configure(with date: Date, isCurrentMonth: Bool) {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d"
        dayLabel.text = dayFormatter.string(from: date)
        
        let weekday = Calendar.current.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        
        if Calendar.current.isDateInToday(date) {
            dayLabel.textColor = .systemBlue
            dayLabel.font = .systemFont(ofSize: 16, weight: .bold)
        } else if isWeekend {
            dayLabel.textColor = isCurrentMonth ? .systemRed : .systemRed.withAlphaComponent(0.3)
            dayLabel.font = .systemFont(ofSize: 16)
        } else {
            dayLabel.textColor = isCurrentMonth ? .label : .secondaryLabel
            dayLabel.font = .systemFont(ofSize: 16)
        }
    }
}

extension CalendarView: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return chatHistory.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatMessageCell", for: indexPath) as! ChatMessageCell
        let message = chatHistory[indexPath.row]
        cell.configure(with: message)
        return cell
    }
}

class ChatMessageCell: UITableViewCell {
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bubbleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 16
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        
        contentView.addSubview(bubbleView)
        bubbleView.addSubview(messageLabel)
        
        // 设置消息标签的约束
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),
            
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.75)
        ])
        
        // 初始化约束
        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
    }
    
    func configure(with message: (role: String, content: String)) {
        messageLabel.text = message.content
        
        // 移除旧的约束
        leadingConstraint?.isActive = false
        trailingConstraint?.isActive = false
        
        if message.role == "user" {
            bubbleView.backgroundColor = .systemBlue
            messageLabel.textColor = .white
            leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
            trailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16)
        } else {
            bubbleView.backgroundColor = .systemGray6
            messageLabel.textColor = .label
            leadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16)
            trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        }
        
        // 激活新的约束
        leadingConstraint?.isActive = true
        trailingConstraint?.isActive = true
        
        // 强制更新布局
        layoutIfNeeded()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        messageLabel.text = nil
        bubbleView.backgroundColor = nil
    }
}

extension CalendarView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            sendMessage()
            return false
        }
        return true
    }
}
