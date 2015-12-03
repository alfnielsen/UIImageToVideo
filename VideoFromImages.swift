//
//  VideoFromImages.swift
//
//  Created by Alf Nielsen 29/11/2015
//  Copyright (c) 2015 Alf Nielsen. All rights reserved.
//
//  Base code comes from:
//  https://github.com/justinlevi/imagesToVideo/tree/master

import AVFoundation
import UIKit
import AssetsLibrary
import Photos

let kErrorDomain = "VideoFromImages"
let kFailedToStartAssetWriterError = 0
let kFailedToAppendPixelBufferError = 1

public class VideoFromImages: NSObject {
	
	
	var videoWriter: AVAssetWriter!
	var videoWriterInput: AVAssetWriterInput!
	var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
	var startTime: NSTimeInterval!
	
	var size = CGSizeMake(320, 568)
	var error: NSError!
	var success: (NSURL -> Void)
	var failure: (NSError -> Void)
	var videoOutputURL: NSURL!
	var frameCount: Int64 = 0
	var filename: String = "";
	
	public init(filename: String, size: CGSize, success: (NSURL -> Void), failure: (NSError -> Void)) {
		self.filename = filename;
		self.size = size
		self.success = success
		self.failure = failure
		super.init()
	}
	///Create the valie file (delete if exist!), and return the NSURL to the file.
	///The file is created un the apps document root
	public func createVideoFile(filename: String){
		let fileManager = NSFileManager.defaultManager()
		let urls = fileManager.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
		guard let documentDirectory: NSURL = urls.first else {
			fatalError("documentDir Error")
		}
		
		videoOutputURL = documentDirectory.URLByAppendingPathComponent(filename)
		
		if NSFileManager.defaultManager().fileExistsAtPath(videoOutputURL.path!) {
			do {
				try NSFileManager.defaultManager().removeItemAtPath(videoOutputURL.path!)
			}catch{
				fatalError("Unable to delete file: \(error) : \(__FUNCTION__).")
			}
		}
	}
	///Create the 3 writers that is needed to render video.
	public func createVideoWriters(){
		guard let _videoWriter = try? AVAssetWriter(URL: videoOutputURL, fileType: AVFileTypeQuickTimeMovie) else{
			fatalError("AVAssetWriter error")
		}
		
		let outputSettings = [
			AVVideoCodecKey  : AVVideoCodecH264,
			AVVideoWidthKey  : NSNumber(float: Float(size.width)),
			AVVideoHeightKey : NSNumber(float: Float(size.height)),
		]
		
		guard _videoWriter.canApplyOutputSettings(outputSettings, forMediaType: AVMediaTypeVideo) else {
			fatalError("Negative : Can't apply the Output settings...")
		}
		
		let _videoWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: outputSettings)
		
		let sourcePixelBufferAttributesDictionary = [
			kCVPixelBufferPixelFormatTypeKey as String: NSNumber(unsignedInt: kCVPixelFormatType_32ARGB),
			kCVPixelBufferWidthKey as String: NSNumber(float: Float(size.width)),
			kCVPixelBufferHeightKey as String: NSNumber(float: Float(size.height)),
		]
		videoWriter = _videoWriter
		videoWriterInput = _videoWriterInput;
		pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
			assetWriterInput: videoWriterInput,
			sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary
		)
		videoWriter.addInput(videoWriterInput)
	}
	
	public func start(){
		startTime = NSDate.timeIntervalSinceReferenceDate()
		createVideoFile(filename);
		//create the videowriter elements
		createVideoWriters();
		
		assert(videoWriter.canAddInput(videoWriterInput))
		
		if videoWriter.startWriting() {
			videoWriter.startSessionAtSourceTime(kCMTimeZero)
			assert(pixelBufferAdaptor.pixelBufferPool != nil)
			let media_queue = dispatch_queue_create("mediaInputQueue", nil)
			videoWriterInput.requestMediaDataWhenReadyOnQueue(media_queue, usingBlock: {})
		} else {
			error = NSError(domain: kErrorDomain, code: kFailedToStartAssetWriterError,
				userInfo: ["description": "AVAssetWriter failed to start writing"]
			)
		}
		if let error = error {
			failure(error)
		}
		
	}
	
	public func addImage(image: UIImage){
		let fps: Int32 = 24
		let frameDuration = CMTimeMake(1, fps)
		while (!videoWriterInput.readyForMoreMediaData) {}
		print("\(videoWriterInput.readyForMoreMediaData) : \(frameCount)")
		let lastFrameTime = CMTimeMake(frameCount, fps)
		let presentationTime = frameCount == 0 ? lastFrameTime : CMTimeAdd(lastFrameTime, frameDuration)
		if !self.appendPixelBufferForImage(image, pixelBufferAdaptor: pixelBufferAdaptor, presentationTime: presentationTime) {
			error = NSError(domain: kErrorDomain, code: kFailedToAppendPixelBufferError,
				userInfo: [
					"description": "AVAssetWriterInputPixelBufferAdapter failed to append pixel buffer",
					"rawError": videoWriter.error ?? "(none)"
				])
			
		}
		frameCount++
	}
	public func finish(){
		videoWriterInput.markAsFinished()
		videoWriter.finishWritingWithCompletionHandler { () -> Void in
			if self.error == nil {
				UISaveVideoAtPathToSavedPhotosAlbum(self.videoOutputURL.path!, nil, nil, nil)
				//ALAssetsLibrary().writeVideoAtPathToSavedPhotosAlbum(self.videoOutputURL, completionBlock: nil)
				self.success(self.videoOutputURL)
			}
		}
	}
	
	public func appendPixelBufferForImageAtURL(urlString: String, pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor, presentationTime: CMTime) -> Bool {
		var appendSucceeded = true
		
		autoreleasepool {
			
			if let image = UIImage(contentsOfFile: urlString) {
				var pixelBuffer: CVPixelBuffer? = nil
				let status: CVReturn = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferAdaptor.pixelBufferPool!, &pixelBuffer)
				
				if let pixelBuffer = pixelBuffer where status == 0 {
					let managedPixelBuffer = pixelBuffer
					
					fillPixelBufferFromImage(image, pixelBuffer: managedPixelBuffer, contentMode: UIViewContentMode.ScaleAspectFit)
					
					appendSucceeded = pixelBufferAdaptor.appendPixelBuffer(pixelBuffer, withPresentationTime: presentationTime)
					
				} else {
					NSLog("error: Failed to allocate pixel buffer from pool")
				}
			}
		}
		
		return appendSucceeded
	}
	
	public func appendPixelBufferForImage(image: UIImage, pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor, presentationTime: CMTime) -> Bool {
		var appendSucceeded = true
		autoreleasepool {
			var pixelBuffer: CVPixelBuffer? = nil
			let status: CVReturn = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferAdaptor.pixelBufferPool!, &pixelBuffer)
			
			if let pixelBuffer = pixelBuffer where status == 0 {
				let managedPixelBuffer = pixelBuffer
				
				fillPixelBufferFromImage(image, pixelBuffer: managedPixelBuffer, contentMode: UIViewContentMode.ScaleAspectFit)
				
				appendSucceeded = pixelBufferAdaptor.appendPixelBuffer(pixelBuffer, withPresentationTime: presentationTime)
				
			} else {
				NSLog("error: Failed to allocate pixel buffer from pool")
			}
		}
		return appendSucceeded
	}
	
	// http://stackoverflow.com/questions/7645454
	
	func fillPixelBufferFromImage(image: UIImage, pixelBuffer: CVPixelBuffer, contentMode:UIViewContentMode){
		
		CVPixelBufferLockBaseAddress(pixelBuffer, 0)
		
		let data = CVPixelBufferGetBaseAddress(pixelBuffer)
		let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
		let context = CGBitmapContextCreate(data, Int(self.size.width), Int(self.size.height), 8, CVPixelBufferGetBytesPerRow(pixelBuffer), rgbColorSpace, CGImageAlphaInfo.PremultipliedFirst.rawValue)
		
		CGContextClearRect(context, CGRectMake(0, 0, CGFloat(self.size.width), CGFloat(self.size.height)))
		
		let horizontalRatio = CGFloat(self.size.width) / image.size.width
		let verticalRatio = CGFloat(self.size.height) / image.size.height
		var ratio: CGFloat = 1
		
		switch(contentMode) {
		case .ScaleAspectFill:
			ratio = max(horizontalRatio, verticalRatio)
		case .ScaleAspectFit:
			ratio = min(horizontalRatio, verticalRatio)
		default:
			ratio = min(horizontalRatio, verticalRatio)
		}
		
		let newSize:CGSize = CGSizeMake(image.size.width * ratio, image.size.height * ratio)
		
		let x = newSize.width < self.size.width ? (self.size.width - newSize.width) / 2 : 0
		let y = newSize.height < self.size.height ? (self.size.height - newSize.height) / 2 : 0
		
		CGContextDrawImage(context, CGRectMake(x, y, newSize.width, newSize.height), image.CGImage)
		
		CVPixelBufferUnlockBaseAddress(pixelBuffer, 0)
	}
	
	
	func stringFromTimeInterval(interval: NSTimeInterval) -> String {
		let ti = NSInteger(interval)
		let ms = Int((interval % 1) * 1000)
		let seconds = ti % 60
		let minutes = (ti / 60) % 60
		let hours = (ti / 3600)
		
		if hours > 0 {
			return NSString(format: "%0.2d:%0.2d:%0.2d.%0.2d", hours, minutes, seconds, ms) as String
		}else if minutes > 0 {
			return NSString(format: "%0.2d:%0.2d.%0.2d", minutes, seconds, ms) as String
		}else {
			return NSString(format: "%0.2d.%0.2d", seconds, ms) as String
		}
	}
	
}
