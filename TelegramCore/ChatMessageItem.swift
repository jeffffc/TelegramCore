import Foundation
import UIKit
import Postbox
import AsyncDisplayKit
import Display
import SwiftSignalKit

private func mediaIsNotMergeable(_ media: Media) -> Bool {
    if let file = media as? TelegramMediaFile, file.isSticker {
        return true
    }
    if let _ = media as? TelegramMediaAction {
        return true
    }
    
    return false
}

private func messagesShouldBeMerged(_ lhs: Message, _ rhs: Message) -> Bool {
    if abs(lhs.timestamp - rhs.timestamp) < 5 * 60 && lhs.author?.id == rhs.author?.id {
        for media in lhs.media {
            if mediaIsNotMergeable(media) {
                return false
            }
        }
        for media in rhs.media {
            if mediaIsNotMergeable(media) {
                return false
            }
        }
        
        return true
    }
    
    return false
}

class ChatMessageItem: ListViewItem, CustomStringConvertible {
    let account: Account
    let peerId: PeerId
    let controllerInteraction: ChatControllerInteraction
    let message: Message
    
    let accessoryItem: ListViewAccessoryItem?
    
    init(account: Account, peerId: PeerId, controllerInteraction: ChatControllerInteraction, message: Message) {
        self.account = account
        self.peerId = peerId
        self.controllerInteraction = controllerInteraction
        self.message = message
        
        var accessoryItem: ListViewAccessoryItem?
        let incoming = account.peerId != message.author?.id
        let displayAuthorInfo = incoming && message.author != nil && peerId.isGroup
        
        if displayAuthorInfo {
            var hasActionMedia = false
            for media in message.media {
                if media is TelegramMediaAction {
                    hasActionMedia = true
                    break
                }
            }
            if !hasActionMedia {
                if let author = message.author {
                    accessoryItem = ChatMessageAvatarAccessoryItem(account: account, peerId: author.id, peer: author, messageTimestamp: message.timestamp)
                }
            }
        }
        self.accessoryItem = accessoryItem
    }
    
    func nodeConfiguredForWidth(async: (() -> Void) -> Void, width: CGFloat, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: (ListViewItemNode, () -> Void) -> Void) {
        var viewClassName: AnyClass = ChatMessageBubbleItemNode.self
        
        for media in message.media {
            if let telegramFile = media as? TelegramMediaFile, telegramFile.isSticker {
                viewClassName = ChatMessageStickerItemNode.self
            } else if let _ = media as? TelegramMediaAction {
                viewClassName = ChatMessageActionItemNode.self
            }
        }
        
        let configure = { () -> Void in
            let node = (viewClassName as! ChatMessageItemView.Type).init()
            node.controllerInteraction = self.controllerInteraction
            node.setupItem(self)
            
            let nodeLayout = node.asyncLayout()
            let (top, bottom) = self.mergedWithItems(top: previousItem, bottom: nextItem)
            let (layout, apply) = nodeLayout(item: self, width: width, mergedTop: top, mergedBottom: bottom)
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            completion(node, {
                apply(.None)
            })
        }
        if Thread.isMainThread {
            async {
                configure()
            }
        } else {
            configure()
        }
    }
    
    final func mergedWithItems(top: ListViewItem?, bottom: ListViewItem?) -> (top: Bool, bottom: Bool) {
        var mergedTop = false
        var mergedBottom = false
        if let top = top as? ChatMessageItem {
            mergedBottom = messagesShouldBeMerged(message, top.message)
        }
        if let bottom = bottom as? ChatMessageItem {
            mergedTop = messagesShouldBeMerged(message, bottom.message)
        }
        
        return (mergedTop, mergedBottom)
    }
    
    func updateNode(async: (() -> Void) -> Void, node: ListViewItemNode, width: CGFloat, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: (ListViewItemNodeLayout, () -> Void) -> Void) {
        if let node = node as? ChatMessageItemView {
            Queue.mainQueue().async {
                node.setupItem(self)
                
                let nodeLayout = node.asyncLayout()
                
                async {
                    let (top, bottom) = self.mergedWithItems(top: previousItem, bottom: nextItem)
                    
                    let (layout, apply) = nodeLayout(item: self, width: width, mergedTop: top, mergedBottom: bottom)
                    Queue.mainQueue().async {
                        completion(layout, {
                            apply(animation)
                        })
                    }
                }
            }
        }
    }
    
    var description: String {
        return "(ChatMessageItem id: \(self.message.id), text: \"\(self.message.text)\")"
    }
}