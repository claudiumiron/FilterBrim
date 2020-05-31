//
//  PictureInPictureRenderer.swift
//  FilterBrim
//
//  Created by Claudiu Miron on 31/05/2020.
//  Copyright © 2020 Apple. All rights reserved.
//

import CoreImage
import CoreMedia
import Foundation

class PictureInPictureRenderer {
    
    private var ciContext: CIContext?
    
    public private(set) var isPrepared: Bool = false
    
    private var outputColorSpace: CGColorSpace?
    
    func prepare(with inputFormatDescription: CMFormatDescription) {
        reset()
        outputColorSpace = colorSpace(for: inputFormatDescription)
        ciContext = CIContext()
        isPrepared = true
    }
    
    func reset() {
        ciContext = nil
        outputColorSpace = nil
        isPrepared = false
    }
    
    func render(bgPixelBuffer: CVPixelBuffer,
                bgCIFilters: [CIFilter],
                fgPixelBuffer: CVPixelBuffer,
                fgCIFilters: [CIFilter],
                in outPixelBuffer: UnsafeMutablePointer<CVPixelBuffer>) {
        guard let ciContext = ciContext, isPrepared else {
                assertionFailure("Invalid state: Not prepared")
                return
        }
        
        var bgImage = CIImage(cvImageBuffer: bgPixelBuffer)
        
        for i in 0..<bgCIFilters.count {
            let filter = bgCIFilters[i]
            filter.setValue(bgImage, forKey: kCIInputImageKey)
            if let filteredImage = filter.outputImage {
                //print("\(filter.name) failed to render image")
                bgImage = filteredImage
            }
        }
        
        var fgImage = CIImage(cvImageBuffer: fgPixelBuffer)
        
        for i in 0..<fgCIFilters.count {
            let filter = fgCIFilters[i]
            filter.setValue(fgImage, forKey: kCIInputImageKey)
            if let filteredImage = filter.outputImage {
                //print("\(filter.name) failed to render image")
                fgImage = filteredImage
            }
        }
        
        let composite = CIFilter(name: "CISourceOverCompositing")
        composite!.setValue(fgImage, forKey: kCIInputImageKey)
        composite!.setValue(bgImage, forKey: kCIInputBackgroundImageKey)
        
        guard let finalImage = composite!.outputImage else {
            print("Coulnd't compose images")
            return
        }
        
        // Render the filtered image out to a pixel buffer (no locking needed, as CIContext's render method will do that)
        ciContext.render(finalImage,
                         to: outPixelBuffer.pointee,
                         bounds: finalImage.extent,
                         colorSpace: outputColorSpace)
    }
    
    func colorSpace(for formatDescription: CMFormatDescription) -> CGColorSpace? {
        let inputMediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
        if inputMediaSubType != kCVPixelFormatType_32BGRA {
            assertionFailure("Invalid input pixel buffer type \(inputMediaSubType)")
            return nil
        }
        
        // Get pixel buffer attributes and color space from the input format description.
        var cgColorSpace = CGColorSpaceCreateDeviceRGB()
        if let inputFormatDescriptionExtension = CMFormatDescriptionGetExtensions(formatDescription) as Dictionary? {
            let colorPrimaries = inputFormatDescriptionExtension[kCVImageBufferColorPrimariesKey]
            
            if let colorPrimaries = colorPrimaries {
                var colorSpaceProperties: [String: AnyObject] = [kCVImageBufferColorPrimariesKey as String: colorPrimaries]
                
                if let yCbCrMatrix = inputFormatDescriptionExtension[kCVImageBufferYCbCrMatrixKey] {
                    colorSpaceProperties[kCVImageBufferYCbCrMatrixKey as String] = yCbCrMatrix
                }
                
                if let transferFunction = inputFormatDescriptionExtension[kCVImageBufferTransferFunctionKey] {
                    colorSpaceProperties[kCVImageBufferTransferFunctionKey as String] = transferFunction
                }
            }
            
            if let cvColorspace = inputFormatDescriptionExtension[kCVImageBufferCGColorSpaceKey] {
                cgColorSpace = cvColorspace as! CGColorSpace
            } else if (colorPrimaries as? String) == (kCVImageBufferColorPrimaries_P3_D65 as String) {
                cgColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
            }
        }
        
        return cgColorSpace
    }
    
}
