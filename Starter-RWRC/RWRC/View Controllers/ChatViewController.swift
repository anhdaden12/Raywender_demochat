/// Copyright (c) 2018 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import Firebase
import MessageKit
import FirebaseFirestore
import Photos

final class ChatViewController: MessagesViewController {
  
  private var isSendingPhoto = false {
    didSet {
      DispatchQueue.main.async {
        self.messageInputBar.leftStackViewItems.forEach { item in
          item.isEnabled = !self.isSendingPhoto
        }
      }
    }
  }
  
  private let storage = Storage.storage().reference()
  
  private let db = Firestore.firestore()
  private var reference: CollectionReference?
  
  private var messages: [Message] = []
  private var messageListener: ListenerRegistration?
  
  
  private let user: User
  private let channel: Channel
  
  init(user: User, channel: Channel) {
    self.user = user
    self.channel = channel
    super.init(nibName: nil, bundle: nil)
    
    title = channel.name
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    guard let id = channel.id else {
      navigationController?.popViewController(animated: true)
      return
    }
    reference = db.collection(["chanel", id, "thread"].joined(separator: "/"))
    
    messageInputBar.delegate = self
    messagesCollectionView.messagesDataSource = self
    messagesCollectionView.messagesLayoutDelegate = self
    messagesCollectionView.messagesDisplayDelegate = self
    
    navigationItem.largeTitleDisplayMode = .never
    
    maintainPositionOnKeyboardFrameChanged = true
    messageInputBar.inputTextView.tintColor = .primary
    messageInputBar.sendButton.setTitleColor(.primary, for: .normal)
    
    
    messageListener = reference?.addSnapshotListener({ querrySnapshot, error in
      guard let snapshot = querrySnapshot else {
        print("error listening for chanel update: \(error?.localizedDescription ?? "No error")")
        return
      }
      
      snapshot.documentChanges.forEach { change in
        self.DocumentChange(change)
      }
    })
    
    let camerabuttonItem = InputBarButtonItem(type: .system)
    camerabuttonItem.tintColor = .primary
    camerabuttonItem.image = #imageLiteral(resourceName: "camera")
    
    camerabuttonItem.addTarget(self, action: #selector(cameraButtonPressed), for: .primaryActionTriggered)
    camerabuttonItem.setSize(CGSize(width: 60, height: 30), animated: false)
    messageInputBar.leftStackView.alignment = .center
    messageInputBar.setLeftStackViewWidthConstant(to: 50, animated: false)
    messageInputBar.setStackViewItems([camerabuttonItem], forStack: .left, animated: true)
  }
  
  
  private func insertNewMessage(_ message: Message) {
    guard !messages.contains(message) else { return }
    
    messages.append(message)
    messages.sort()
    
    let isLastestMessage = messages.index(of: message) == (messages.count - 1)
    let shouldScrolltoBottom = messagesCollectionView.isAtBottom && isLastestMessage
    messagesCollectionView.reloadData()
    
    if shouldScrolltoBottom {
      DispatchQueue.main.async {
        self.messagesCollectionView.scrollToBottom(animated: true)
      }
    }
  }
  
  
  //mark: Action
  
  @objc private func cameraButtonPressed() {
    let picker = UIImagePickerController()
    picker.delegate = self
    
    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      picker.sourceType = .camera
    } else {
      picker.sourceType = .photoLibrary
    }
    
    present(picker, animated: true, completion: nil)
  }
  
  //mark: helper
  
  
  private func save(_ message: Message) {
    reference?.addDocument(data: message.representation) { error in
      if let err = error {
        print("error sending messages: \(err.localizedDescription)")
        return
      }
      self.messagesCollectionView.scrollToBottom()
    }
  }
  
  
  private func DocumentChange(_ change: DocumentChange) {
    guard var message = Message(document: change.document) else { return }
    switch change.type {
    case .added:
      if let url = message.downloadURL {
        downloadImage(at: url) { [weak self] image in
          guard let self = self else {
            return
          }
          guard let image = image else {
            return
          }
          
          message.image = image
          self.insertNewMessage(message)
        }
      } else {
        insertNewMessage(message)
      }
    default:
      break
    }
  }
  
  deinit {
    messageListener?.remove()
  }
  
  
  
  private func uploadImage(_ image: UIImage, to chanel: Channel, completion: @escaping (URL?) -> Void) {
    guard let chanelId = chanel.id else {
      completion(nil)
      return
    }
    
    
    guard let scaledImage = image.scaledToSafeUploadSize, let data = scaledImage.jpegData(compressionQuality: 0.4) else {
      
      completion(nil)
      
      return
    }
    
    let metadata = StorageMetadata()
    metadata.contentType = "image/jpeg"
    let imageName = [UUID().uuidString, String(Date().timeIntervalSince1970)].joined()
    storage.child(chanelId).child(imageName).putData(data , metadata: metadata) {
      meta, error in
      completion(meta?.downloadURL())
    }
  }
  
  private func sendPhoto(_ image: UIImage) {
    isSendingPhoto = true
    
    uploadImage(image, to: channel) { [weak self] url in
      guard let `self` = self else {
        return
      }
      self.isSendingPhoto = false
      
      guard let url = url else {
        return
      }
      
      var message = Message(user: self.user, image: image)
      message.downloadURL = url
      
      self.save(message)
      self.messagesCollectionView.scrollToBottom()
    }
  }
  
  
  private func downloadImage(at url: URL, completion: @escaping (UIImage?) -> Void) {
    let ref = Storage.storage().reference(forURL: url.absoluteString)
    let megaByte = Int64(1 * 1024 * 1024)
    
    ref.getData(maxSize: megaByte) { data, error in
      guard let imageData = data else {
        completion(nil)
        return
      }
      
      completion(UIImage(data: imageData))
    }
  }
  
}

// MARK: - MessagesDisplayDelegate

extension ChatViewController: MessagesDisplayDelegate {
  
  func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
    return isFromCurrentSender(message: message) ? .primary : .incomingMessage
  }
  
  func shouldDisplayHeader(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> Bool {
    return false
  }
  
  func messageStyle(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageStyle {
    let corner: MessageStyle.TailCorner = isFromCurrentSender(message: message) ? .bottomRight : .bottomLeft
    return .bubbleTail(corner, .curved)
  }
}

extension ChatViewController: MessagesLayoutDelegate {
  //3
  func heightForLocation(message: MessageType, at indexPath: IndexPath, with maxWidth: CGFloat, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
    return 0
  }
  
  //1
  func avatarSize(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGSize {
    return CGSize(width: 20, height: 20)
  }
  
  //2
  func footerViewSize(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGSize {
    return CGSize(width: 0, height: 8)
  }
  
  
}

// MARK: - MessageInputBarDelegate

extension ChatViewController: MessageInputBarDelegate {
  
  func messageInputBar(_ inputBar: MessageInputBar, didPressSendButtonWith text: String) {
    //1
    let message = Message(user: user, content: text)
    //2
    save(message)
    //3
    inputBar.inputTextView.text = ""
  }
  
}

// MARK: - UIImagePickerControllerDelegate

extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerController(_ picker: UIImagePickerController,
                             didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
    picker.dismiss(animated: true, completion: nil)
    
    // 1
    if let asset = info[.phAsset] as? PHAsset {
      let size = CGSize(width: 500, height: 500)
      PHImageManager.default().requestImage(
        for: asset,
        targetSize: size,
        contentMode: .aspectFit,
        options: nil) { result, info in
          
        guard let image = result else {
          return
        }
        
        self.sendPhoto(image)
      }

    // 2
    } else if let image = info[.originalImage] as? UIImage {
      sendPhoto(image)
    }
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true, completion: nil)
  }
}


extension ChatViewController: MessagesDataSource {
  //1
  func currentSender() -> Sender {
    return Sender(id: user.uid, displayName: AppSettings.displayName)
  }
  //3
  func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
    return messages[indexPath.section]
  }
  
  //2
  func numberOfMessages(in messagesCollectionView: MessagesCollectionView) -> Int {
    messages.count
  }
  
  //4
  
  func cellTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
    let name = message.sender.displayName
    return NSAttributedString(string: name, attributes: [
      .font: UIFont.preferredFont(forTextStyle: .caption1),
      .foregroundColor: UIColor(white: 0.3, alpha: 1)
      ]
    )
  }
  
  
}


