//
//  SuggestionLocalizationViewController.swift
//  Telegram
//
//  Created by keepcoder on 27/05/2017.
//  Copyright © 2017 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import TelegramCore
import Localization
import Postbox
import SwiftSignalKit

private class SuggestionControllerView : View {
    let textView:TextView = TextView()
    let suggestTextView:TextView = TextView()
    let separatorView:View = View()
    let tableView:TableView = TableView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        addSubview(separatorView)
        addSubview(tableView)
        addSubview(suggestTextView)
       
        textView.backgroundColor = theme.colors.background
        suggestTextView.backgroundColor = theme.colors.background
        
        tableView.setFrameSize(NSMakeSize(frameRect.width, frameRect.height - 50))
        separatorView.setFrameSize(frameRect.width, .borderSize)
        separatorView.backgroundColor = theme.colors.border
        layout()
    }
    
    func updateHeaderTexts(_ suggestLocalization:String) {
        let headerLayout = TextViewLayout(.initialize(string: suggestLocalization, color: theme.colors.text, font: .normal(.title)))
        headerLayout.measure(width: frame.width - 40)
        textView.update(headerLayout)
        //
        let suggestHeaderLayout = TextViewLayout(.initialize(string: NativeLocalization("Suggest.Localization.Header"), color: theme.colors.grayText, font: .normal(.text)))
        suggestHeaderLayout.measure(width: frame.width - 40)
        suggestTextView.update(suggestHeaderLayout)
        
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        textView.centerX(y: 25 - textView.frame.height - 1)
        suggestTextView.centerX(y: 25 + 1)
        separatorView.setFrameOrigin(0, 50 - .borderSize)
        tableView.setFrameOrigin(0, 50)
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class SuggestionLocalizationViewController: ModalViewController {
    private let context:AccountContext
    private let suggestionInfo:SuggestedLocalizationInfo
    private var languageCode:String = "en"
    init(_ context: AccountContext, suggestionInfo: SuggestedLocalizationInfo) {
        self.context = context
        self.suggestionInfo = suggestionInfo
        super.init(frame: NSMakeRect(0, 0, 280, 198))
        bar = .init(height: 0)
    }
    
    override func viewClass() -> AnyClass {
        return SuggestionControllerView.self
    }
    
    override var modalInteractions: ModalInteractions? {
        return ModalInteractions(acceptTitle: strings().modalOK, accept: { [weak self] in
            if let strongSelf = self {
                strongSelf.close()
                let engine = strongSelf.context.engine.localization
                _ = engine.markSuggestedLocalizationAsSeenInteractively(languageCode: strongSelf.suggestionInfo.languageCode).start()
                _ = showModalProgress(signal: engine.downloadAndApplyLocalization(accountManager: strongSelf.context.sharedContext.accountManager, languageCode: strongSelf.languageCode), for: strongSelf.context.window).start()
            }
        }, singleButton: true)
    }
    
    private var genericView:SuggestionControllerView {
        return self.view as! SuggestionControllerView
    }
    
    override var closable: Bool {
        return false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        

        genericView.updateHeaderTexts(suggestionInfo.localizedKey("Suggest.Localization.Header"))
        let swap = languages.index(of: self.suggestionInfo.languageCode) != nil
        reloadItems(swap ? 1 : 0, swap)
        readyOnce()
    }
    
    var languages:[String] {
        return ["nl", "es", "it", "de", "pt"]
    }
    
    private func reloadItems(_ selected:Int, _ swap:Bool) {
        genericView.tableView.removeAll()
        let initialSize = self.atomicSize.modify({$0})

        var enInfo:LocalizationInfo?
        var currentInfo:LocalizationInfo?
        
        for suggestInfo in suggestionInfo.availableLocalizations {
            if suggestInfo.languageCode == "en" {
                enInfo = suggestInfo
                if selected == 0 {
                    languageCode = suggestInfo.languageCode
                }
            } else if suggestInfo.languageCode == suggestionInfo.languageCode {
                currentInfo = suggestInfo
                if selected == 1 {
                    languageCode = suggestInfo.languageCode
                }
            }
        }
        _ = genericView.tableView.addItem(item: GeneralRowItem(initialSize, height: 5))
        
        
        if let info = enInfo {
            
            _ = genericView.tableView.insert(item: LanguageRowItem(initialSize: initialSize, stableId: 0, selected: selected == 0, deletable: false, value: info, action: { [weak self] in
                self?.reloadItems(0, swap)
            }, reversed: true), at: 0)
            
        }
        if let info = currentInfo {
            _ = genericView.tableView.insert(item: LanguageRowItem(initialSize: initialSize, stableId: 1, selected: selected == 1, deletable: false, value: info, action: { [weak self] in
                self?.reloadItems(1, swap)
            }, reversed: true), at: swap ? 0 : 1)
        }

        //    public init(languageCode: String, baseLanguageCode: String?, customPluralizationCode: String?, title: String, localizedTitle: String, isOfficial: Bool, totalStringCount: Int32, translatedStringCount: Int32, platformUrl: String) {
        let otherInfo = LocalizationInfo(languageCode: "", baseLanguageCode: nil, customPluralizationCode: nil, title: NativeLocalization("Suggest.Localization.Other"), localizedTitle: suggestionInfo.localizedKey("Suggest.Localization.Other"), isOfficial: true, totalStringCount: 0, translatedStringCount: 0, platformUrl: "" )

        _ = genericView.tableView.addItem(item: LanguageRowItem(initialSize: initialSize, stableId: 10, selected: false, deletable: false, value: otherInfo, action: { [weak self] in
            if let strongSelf = self {
                strongSelf.close()
                strongSelf.context.bindings.rootNavigation().push(LanguageController(strongSelf.context))
                let engine = strongSelf.context.engine.localization
                _ = engine.markSuggestedLocalizationAsSeenInteractively(languageCode: strongSelf.suggestionInfo.languageCode).start()
            }
        }, reversed: true))
    
    }
}
