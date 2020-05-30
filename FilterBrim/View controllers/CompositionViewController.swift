//
//  CompositionViewController.swift
//  FilterBrim
//
//  Created by Claudiu Miron on 28/05/2020.
//  Copyright © 2020 Apple. All rights reserved.
//

import AVFoundation
import UIKit

class CompositionViewController: UIViewController {
    
    public var backgroundVideoUrl: URL!
    
    public var foregroundVideoUrl: URL!
    
    private let composition = AVMutableComposition()
    
    private let videoComposition = AVMutableVideoComposition()
    
    private let dataOutputQueue = DispatchQueue(label: "VideoDataQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private var videoOutput: AVPlayerItemVideoOutput!
    
    private var bgAsset: AVAsset?
    
    private var fgAsset: AVAsset?
    
    private var player: AVPlayer!
    
    private var displayLink: CADisplayLink!
    
    @IBOutlet private weak var previewView: PreviewMetalView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let bgAsset = AVAsset(url: backgroundVideoUrl)
        bgAsset.prepare(properties: ["tracks", "duration"]) {
            self.bgAsset = bgAsset
            self.assetLoaded()
        }
        
        let fgAsset = AVAsset(url: foregroundVideoUrl)
        fgAsset.prepare(properties: ["tracks", "duration"]) {
            self.fgAsset = fgAsset
            self.assetLoaded()
        }
    }
    
    private func assetLoaded() {
        guard let bgAsset = bgAsset, let fgAsset = fgAsset else {
            return
        }
        
        guard (bgAsset.duration.isNumeric && fgAsset.duration.isNumeric) else {
            return
        }
        
        var timeRange = CMTimeRange()
        timeRange.start = .zero
        timeRange.duration =
            bgAsset.duration.seconds < fgAsset.duration.seconds ?
                bgAsset.duration : fgAsset.duration
        
        let compBgVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: 2)!
        let assetBgVideoTrack = bgAsset.firstVideoTrack!
        //compBgVideoTrack.preferredTransform = assetBgVideoTrack.preferredTransform
        try! compBgVideoTrack.insertTimeRange(timeRange,
                                              of: assetBgVideoTrack,
                                              at: .zero)
        
        let compFgVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: 1)!
        let assetFgVideoTrack = fgAsset.firstVideoTrack!
        //compFgVideoTrack.preferredTransform = assetFgVideoTrack.preferredTransform
        try! compFgVideoTrack.insertTimeRange(timeRange,
                                              of: assetFgVideoTrack,
                                              at: .zero)
        
        let naturalSize = assetBgVideoTrack.naturalSize
        let transformedSize =
            naturalSize.applying(assetBgVideoTrack.preferredTransform)
        let renderSize = CGSize(width: abs(transformedSize.width),
                                height: abs(transformedSize.height))
        
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration =
            CMTimeMakeWithSeconds(Float64(1.0 / assetBgVideoTrack.nominalFrameRate),
                                  preferredTimescale: assetBgVideoTrack.naturalTimeScale);
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = composition.tracks.first!.timeRange
        
        let fgInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: assetFgVideoTrack)
        fgInstruction.trackID = 1
        
        let bgInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: assetBgVideoTrack)
        bgInstruction.trackID = 2
        
        let scale: CGFloat = 0.5
        var fgTransform = assetFgVideoTrack.preferredTransform
        fgTransform = fgTransform.scaledBy(x: scale, y: scale)
        
        fgInstruction.setOpacity(0.7, at: .zero)
        fgInstruction.setTransform(fgTransform, at: .zero)
        
        let bgTransform = assetBgVideoTrack.preferredTransform
        bgInstruction.setTransform(bgTransform, at: .zero)
        
        instruction.layerInstructions = [fgInstruction, bgInstruction]
        videoComposition.instructions = [instruction]
        
        dataOutputQueue.async {
            let settings =
                [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
            self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)
            
            let playerItem = AVPlayerItem(asset: self.composition)
            //playerItem.customVideoCompositor
            playerItem.videoComposition = self.videoComposition
            playerItem.add(self.videoOutput)
            
            self.player = AVPlayer(playerItem: playerItem)
            self.player.actionAtItemEnd = .none
            self.player.play()
            
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.playerItemDidFinish(notification:)),
                                                   name: .AVPlayerItemDidPlayToEndTime,
                                                   object: playerItem)
            
            self.displayLink = CADisplayLink(target: self,
                                            selector: #selector(self.displayLinkUpdate))
            self.displayLink.add(to: .main, forMode: .common)
        }
        
    }
    
    @objc func playerItemDidFinish(notification: Notification) {
        let item = notification.object as! AVPlayerItem
        item.seek(to: .zero, completionHandler: nil)
    }
    
    @objc func displayLinkUpdate() {
        dataOutputQueue.async {
            guard let item = self.player.currentItem else {
                return
            }
            
            let buffer =
                self.videoOutput.copyPixelBuffer(forItemTime: item.currentTime(),
                                                 itemTimeForDisplay:nil)
            if let unwrappedBuffer = buffer {
                self.previewView.pixelBuffer = unwrappedBuffer
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        self.displayLink.remove(from: .main, forMode: .common)
    }
    
}
