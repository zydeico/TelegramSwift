//
//  UIInputView.swift
//  Telegram
//
//  Created by Mike Renoir on 11.10.2023.
//  Copyright © 2023 Telegram. All rights reserved.
//

import Foundation
import Cocoa
import TGUIKit
import InputView
import ColorPalette
import SwiftSignalKit
import TelegramMedia


final class InputAnimatedEmojiAttach: View {
    
    fileprivate var attachmentValue: TextInputTextCustomEmojiAttribute?
    fileprivate var size: NSSize?
    fileprivate var textColor: NSColor?
    fileprivate var context: AccountContext?
    
    private var media: InlineStickerItemLayer!
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = false
    }
    
    var fileId: Int64 {
        return media.fileId
    }
    
    func set(_ attachment: TextInputTextCustomEmojiAttribute, size: NSSize, context: AccountContext, textColor: NSColor, playPolicy: LottiePlayPolicy = .loop) -> Void {
        
       
        if media != nil {
            self.media.removeFromSuperlayer()
        }
        
        let fileId = attachment.fileId
        let file = attachment.file
        
        self.attachmentValue = attachment

        self.context = context
        self.size = size
        self.textColor = textColor
        
        
        self.media = .init(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: file, emoji: ""), size: size, playPolicy: playPolicy, textColor: textColor)
        
        self.media.superview = self
        let mediaRect = self.focus(media.frame.size)
        
        self.media.isPlayable = !isLite(.emoji)
        self.media.frame = mediaRect
        self.layer?.addSublayer(media)
                
        needsLayout = true
    }
    
    func updatePlayPolicy(_ playPolicy: LottiePlayPolicy) {
        if let attachmentValue, let size, let context, let textColor {
            self.set(attachmentValue, size: size, context: context, textColor: textColor, playPolicy: playPolicy)
        }
    }
    
    override func layout() {
        super.layout()
        guard let media = self.media else {
            return
        }
        media.frame = focus(media.frame.size)

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}



extension Updated_ChatTextInputState : Equatable {
    func textInputState() -> ChatTextInputState {
        return .init(attributedText: self.inputText, selectionRange: self.selectionRange)
    }
    public static func ==(lhs: Updated_ChatTextInputState, rhs: Updated_ChatTextInputState) -> Bool {
        if lhs.inputText.string != rhs.inputText.string {
            return false
        }
        if lhs.textInputState().attributes != rhs.textInputState().attributes {
            return false
        }
        return lhs.selectionRange == rhs.selectionRange
    }
}


final class TextView_Interactions : InterfaceObserver {
    var presentation: Updated_ChatTextInputState
    
    var max_height: CGFloat = 50
    var min_height: CGFloat = 50
    var max_input: Int = 100000
    var supports_continuity_camera: Bool = false
    var inputIsEnabled: Bool = true
    var canTransform: Bool = true
    var simpleTransform: Bool = false
    var emojiPlayPolicy: LottiePlayPolicy = .loop
    
    var allowedLinkHosts: [String] = []
    
    init(presentation: Updated_ChatTextInputState = .init()) {
        self.presentation = presentation
    }
    
    func update(animated:Bool = true, _ f:(Updated_ChatTextInputState)->Updated_ChatTextInputState)->Void {
        let oldValue = self.presentation
        let presentation = f(oldValue)
        self.presentation = presentation
        if oldValue != presentation {
            self.notifyObservers(value: presentation, oldValue:oldValue, animated:animated)
        }
    }
    
    func insertText(_ text: NSAttributedString, selectedRange:Range<Int>? = nil) -> Updated_ChatTextInputState {
        
        var selectedRange = selectedRange ?? presentation.selectionRange
        let inputText = presentation.inputText.mutableCopy() as! NSMutableAttributedString
        
        if selectedRange.upperBound - selectedRange.lowerBound > 0 {
            inputText.replaceCharacters(in: NSMakeRange(selectedRange.lowerBound, selectedRange.upperBound - selectedRange.lowerBound), with: text)
            selectedRange = selectedRange.lowerBound ..< selectedRange.lowerBound
        } else {
            inputText.insert(text, at: selectedRange.lowerBound)
        }
        
        let nRange:Range<Int> = selectedRange.lowerBound + text.length ..< selectedRange.lowerBound + text.length
        return Updated_ChatTextInputState(inputText: inputText, selectionRange: nRange)
    }
    
    var inputDidUpdate:((Updated_ChatTextInputState)->Void) = { _ in }
    var processEnter:(NSEvent)->Bool = { event in return FastSettings.checkSendingAbility(for: event) }
    var processPaste:(NSPasteboard)->Bool = { _ in return false }
    var processAttriburedCopy: (NSAttributedString) -> Bool = { _ in return false }
    var responderDidUpdate:()->Void = { }
    
    var filterEvent: (NSEvent)->Bool = { _ in return true }
}


final class UITextView : View, Notifable, ChatInputTextViewDelegate {
    func inputViewIsEnabled(_ event: NSEvent) -> Bool {
        return interactions.filterEvent(event) && interactions.inputIsEnabled
    }
    
    func inputViewProcessEnter(_ theEvent: NSEvent) -> Bool {
        return interactions.processEnter(theEvent)
    }
    
    func inputViewMaybeClosed() -> Bool {
        return false
    }
    func inputMaximumHeight() -> CGFloat {
        return max_height
    }
    func inputMaximumLenght() -> Int {
        return max_input_length
    }
    func inputViewSupportsContinuityCamera() -> Bool {
        return supports_continuity_camera
    }
    func inputViewProcessPastepoard(_ pboard: NSPasteboard) -> Bool {
        return self.interactions.processPaste(pboard)
    }
    func inputViewCopyAttributedString(_ attributedString: NSAttributedString) -> Bool {
        return self.interactions.processAttriburedCopy(attributedString)
    }
    
    func inputViewResponderDidUpdate() {
        self.interactions.responderDidUpdate()
    }
    
    var inputTheme: InputViewTheme = theme.inputTheme {
        didSet {
            let placeholder = self.placeholder
            self.placeholder = placeholder
            self.view.theme = inputTheme
            self.chatInputTextViewDidUpdateText()
        }
    }
    var placeholderFontSize: CGFloat? = nil
    var placeholder: String = "" {
        didSet {
            self.view.placeholderString = .initialize(string: placeholder, color: inputTheme.grayTextColor, font: .normal(placeholderFontSize ?? inputTheme.fontSize))
        }
    }
    
    private var revealSpoilers: Bool = false {
        didSet {
            self.updateInput(current: self.interactions.presentation, previous: self.interactions.presentation)
        }
    }
    
    private let delayDisposable = MetaDisposable()
    
    private var updatingInputState: Bool = false
    
    var isEmpty: Bool {
        return self.inputTextState.inputText.string.isEmpty
    }
    
    func chatInputTextViewDidUpdateText() {
        refreshInputView()
        
        let inputTextState = self.inputTextState
     
        self.interactions.update { _ in
            return inputTextState
        }
    }
    
    var inputTextState: Updated_ChatTextInputState {
        let selectionRange: Range<Int> = view.selectedRange.location ..< (view.selectedRange.location + view.selectedRange.length)
        return Updated_ChatTextInputState(inputText: stateAttributedStringForText(view.attributedText.copy() as! NSAttributedString), selectionRange: selectionRange)
    }

    private func refreshInputView() {
        refreshTextInputAttributes(self.view.textView, theme: inputTheme, spoilersRevealed: revealSpoilers, availableEmojis: Set())
       // refreshChatTextInputTypingAttributes(self.view.textView, theme: inputTheme)
    }
    
    func chatInputTextViewDidChangeSelection(dueToEditing: Bool) {
        if !dueToEditing && !self.updatingInputState {
            refreshInputView()
            let inputTextState = self.inputTextState
            interactions.update { _ in
                inputTextState
            }
        }

    }
    
    func chatInputTextViewDidBeginEditing() {
        
    }
    
    func chatInputTextViewDidFinishEditing() {
        
    }
    
    func chatInputTextView(shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return true
    }
    
    func chatInputTextViewShouldCopy() -> Bool {
        return true
    }
    
    func chatInputTextViewShouldPaste() -> Bool {
        return true
    }
    
    func inputTextCanTransform() -> Bool {
        return interactions.canTransform
    }
    
    func inputTextSimpleTransform() -> Bool {
        return interactions.simpleTransform
    }
    
    func inputViewRevealSpoilers() {
        self.revealSpoilers = true
        delayDisposable.set(delaySignal(5.0).start(completed: { [weak self] in
            self?.revealSpoilers = false
        }))
    }
    
    func inputApplyTransform(_ reason: InputViewTransformReason) {
        
        if !interactions.canTransform {
            return
        }
        switch reason {
        case let .attribute(attribute):
            self.interactions.update({ current in
                return chatTextInputAddFormattingAttribute(current, attribute: attribute)
            })
        case .url:
            let range = self.interactions.presentation.selectionRange
            let textRange = NSMakeRange(range.lowerBound, range.upperBound - range.lowerBound)
            guard textRange.min != textRange.max, let window = _window else {
                return
            }
            
            let text = self.interactions.presentation.inputText.attributedSubstring(from: textRange)
            var link: String?
            text.enumerateAttributes(in: NSMakeRange(0, text.length)) { attributes, _, _ in
                if let linkAttribute = attributes[TextInputAttributes.textUrl] as? TextInputTextUrlAttribute {
                    link = linkAttribute.url
                }
            }
            
            showModal(with: InputURLFormatterModalController(string: text.string, defaultUrl: link, completion: { [weak self] text, url in
                
                self?.interactions.update { current in
                    var current = current
                    if let url = url {
                        current = chatTextInputAddLinkAttribute(current, selectionRange: textRange.min ..< textRange.max, url: url, text: text)
                    } else {
                        current = chatTextInputClearFormattingAttributes(current, targetKey: TextInputAttributes.textUrl)
                    }
                    return current
                }
            }, hosts: self.interactions.allowedLinkHosts), for: window)
            
        case .clear:
            self.interactions.update({ current in
                return chatTextInputClearFormattingAttributes(current)
            })
        case let .toggleQuote(quote, range):
            self.interactions.update({ current in
                return chatTextInputAddQuoteAttribute(current, selectionRange: range.min ..< range.max, collapsed: !quote.collapsed, doNotUpdateSelection: true)
            })
            if let window = self._window {
                showModalText(for: window, text: !quote.collapsed ? strings().inputQuoteCollapsed : strings().inputQuoteExpanded)
            }
        }
    }
    
    func insertText(_ string: NSAttributedString, range: Range<Int>? = nil) {
        let updatedText = self.interactions.insertText(string, selectedRange: range)
        self.interactions.update { _ in
            updatedText
        }
    }
    
    func scrollToCursor() {
        self.view.scrollToCursor()
    }
    
    func string() -> String {
        return self.inputTextState.inputText.string
    }
    
    func highlight(for range: NSRange, whole: Bool) -> NSRect {
        return self.view.highlight(for: range, whole: whole)
    }
    
    var inputView:NSTextView {
        return self.view.inputView
    }
    
    var selectedRange: NSRange {
        return self.view.selectedRange
    }
    var scrollView: NSScrollView {
        return self.view
    }
    
    var max_height: CGFloat {
        return interactions.max_height
    }
    var max_input_length: Int {
        return interactions.max_input
    }
    var min_height: CGFloat {
        return interactions.min_height
    }
    var supports_continuity_camera: Bool {
        return interactions.supports_continuity_camera
    }
    
    let view: ChatInputTextView
    
    var interactions: TextView_Interactions {
        didSet {
            oldValue.remove(observer: self)
            interactions.add(observer: self)
        }
    }
    
    var context: AccountContext?
    
    required init(frame frameRect: NSRect, interactions: TextView_Interactions) {
        self.view = ChatInputTextView(frame: frameRect.size.bounds)
        self.interactions = interactions
        super.init(frame: frameRect)
        self.interactions.add(observer: self)
        addSubview(view)
        view.delegate = self
        
        self.view.emojiViewProvider = { [weak self] attachment, size, theme in
            let rect = size.bounds.insetBy(dx: -1.5, dy: -1.5)
            let view = InputAnimatedEmojiAttach(frame: rect)
            if let context = self?.context, let interactions = self?.interactions {
                view.set(attachment, size: rect.size, context: context, textColor: theme.textColor, playPolicy: interactions.emojiPlayPolicy)
            }
            return view
        }
    }
    
    func updatePlayPolicy(_ playPolicy: LottiePlayPolicy) {
        for emoji in emojis {
            emoji.updatePlayPolicy(playPolicy)
        }
    }
    
    var emojis:[InputAnimatedEmojiAttach] {
        return view.emojis.compactMap { $0 as? InputAnimatedEmojiAttach }
    }
    
    
    override func layout() {
        super.layout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, interactions: .init())
    }
    
    func isEqual(to other: Notifable) -> Bool {
        if let other = other as? UITextView {
            return other === self
        }
        return false
    }
        
    
    func set(_ input: ChatTextInputState) {
        let inputState = input.textInputState()
        if self.interactions.presentation != inputState {
            self.interactions.update { _ in
                return inputState
            }
        }
    }
    
    func notify(with value: Any, oldValue: Any, animated: Bool) {
        if let value = value as? Updated_ChatTextInputState, let oldValue = oldValue as? Updated_ChatTextInputState {
            self.updateInput(current: value, previous: oldValue)
        }
    }
    
    private func updateInput(current: Updated_ChatTextInputState, previous: Updated_ChatTextInputState) {
        
        self.updatingInputState = true
        

        
        let attributedText = textAttributedStringForStateText(current.inputText, fontSize: inputTheme.fontSize, textColor: inputTheme.textColor, accentTextColor: inputTheme.accentColor, writingDirection: nil, spoilersRevealed: revealSpoilers, availableEmojis: Set())
        
        
        let textViewAttributed = textAttributedStringForStateText(view.attributedText.copy() as! NSAttributedString, fontSize: inputTheme.fontSize, textColor: inputTheme.textColor, accentTextColor: inputTheme.accentColor, writingDirection: nil, spoilersRevealed: revealSpoilers, availableEmojis: Set())


        
        let selectionRange = NSMakeRange(current.selectionRange.lowerBound, current.selectionRange.count)

        if attributedText.string != textViewAttributed.string || chatTextAttributes(from: attributedText) != chatTextAttributes(from: textViewAttributed) {
            let undoItem = InputViewUndoItem(was: textViewAttributed, be: attributedText, wasRange: self.view.selectedRange, beRange: selectionRange)
            self.view.addUndoItem(undoItem)
        }
        
        refreshInputView()

        
        if previous != current {
            self.interactions.inputDidUpdate(current)
        }
        self.updatingInputState = false

    }
    
    func updateLayout(size: NSSize, textHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: self.view, frame: size.bounds)
        self.view.updateLayout(size: size, textHeight: textHeight, transition: transition)
    }
    
    func height(for width: CGFloat) -> CGFloat {
        return self.view.textHeightForWidth(width)
    }
    
    func setToEnd() {
        self.interactions.update({ current in
            var current = current
            current.selectionRange = current.inputText.length ..< current.inputText.length
            return current
        })
    }
    
    func selectAll() {
        self.interactions.update({ current in
            var current = current
            current.selectionRange = 0 ..< current.inputText.length
            return current
        })
    }
    
    func makeFirstResponder() {
        self.window?.makeFirstResponder(self.inputView)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.inputTheme = theme.inputTheme
    }
    
    deinit {
        delayDisposable.dispose()
    }
}
