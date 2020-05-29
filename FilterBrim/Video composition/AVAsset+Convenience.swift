//
//  AVAsset+Convenience.swift
//  FilterBrim
//
//  Created by Claudiu Miron on 28/05/2020.
//  Copyright © 2020 Apple. All rights reserved.
//

import AVFoundation

extension AVAsset {
    
    var firstVideoTrack: AVAssetTrack? {
        return tracks(withMediaType: .video).first
    }
    
    var firstAudioTrack: AVAssetTrack? {
        return tracks(withMediaType: .audio).first
    }
    
    func prepare(properties: [String], with completion: @escaping () -> Void) {
        self.loadValuesAsynchronously(forKeys: properties) {
            var pendingProperties: [String] = []
            for property in properties {
                switch self.statusOfValue(forKey: property, error: nil) {
                case .loaded, .failed:
                    break
                    
                default:
                    pendingProperties.append(property)
                }
                
            }
            if pendingProperties.count == 0 {
                completion()
            } else {
                self.prepare(properties: properties, with: completion)
            }
        }
    }
    
}
