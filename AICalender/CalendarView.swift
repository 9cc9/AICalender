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
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.estimatedRowHeight = 60
        table.rowHeight = UITableView.automaticDimension
        return table
    }()
    
    private lazy var inputContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var inputTextView: UITextView = {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 16)
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()
    
    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("发送", for: .normal)
        button.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
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
        
        // 添加测试消息
        addTestMessage()
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
            inputContainer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 60),
            
            inputTextView.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 8),
            inputTextView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 16),
            inputTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputTextView.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -8),
            
            sendButton.centerYAnchor.constraint(equalTo: inputTextView.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -16),
            sendButton.widthAnchor.constraint(equalToConstant: 60)
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
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
        let insets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardFrame.height, right: 0)
        chatTableView.contentInset = insets
        chatTableView.scrollIndicatorInsets = insets
        
        // 滚动到底部
        if !chatHistory.isEmpty {
            let lastIndex = IndexPath(row: chatHistory.count - 1, section: 0)
            chatTableView.scrollToRow(at: lastIndex, at: .bottom, animated: true)
        }
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        chatTableView.contentInset = .zero
        chatTableView.scrollIndicatorInsets = .zero
    }
    
    @objc private func sendButtonTapped() {
        guard let text = inputTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        
        // 添加用户消息到历史记录
        chatHistory.append((role: "user", content: text))
        
        // 清空输入框
        inputTextView.text = ""
        
        // 刷新表格
        chatTableView.reloadData()
        
        // 滚动到底部
        if !chatHistory.isEmpty {
            let lastIndex = IndexPath(row: chatHistory.count - 1, section: 0)
            chatTableView.scrollToRow(at: lastIndex, at: .bottom, animated: true)
        }
        
        // TODO: 调用 AI 服务处理用户输入
        // 这里需要实现与 LocalAIService 的集成
    }
    
    // 添加测试消息
    private func addTestMessage() {
        chatHistory.append((role: "user", content: "你好，我想安排一个会议"))
        chatHistory.append((role: "assistant", content: "好的，请告诉我会议的具体时间和要求"))
        chatTableView.reloadData()
        
        // 确保消息显示在底部
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !self.chatHistory.isEmpty {
                let lastIndex = IndexPath(row: self.chatHistory.count - 1, section: 0)
                self.chatTableView.scrollToRow(at: lastIndex, at: .bottom, animated: false)
            }
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
        view.layer.cornerRadius = 12
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
            bubbleView.backgroundColor = .systemGray5
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
