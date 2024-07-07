//
//  ViewController.swift
//  OldFilmMovieDemo
//
//  Created by mark lim pak mun on 27/02/2024.
//  Copyright © 2024 Incremental Innovation. All rights reserved.
//
// Code is based on Apple's Core Image Article:
//
//      `Simulating Scratchy Analog Film`

import Cocoa
import AVFoundation

class OMViewController: NSViewController
{
    @IBOutlet var videoView: NSImageView!

    private var displayLink: CVDisplayLink?
    private var displaySource: DispatchSource!
    private var avVideoOutput: AVPlayerItemVideoOutput!
    private var avPlayerItem: AVPlayerItem!
    private var avPlayer: AVPlayer!

    // Key-value observing context
    private var playerItemContext = 0
    

    override func viewDidLoad()
    {
        super.viewDidLoad()

        let mainBundle = Bundle.main
        guard let movieURL = mainBundle.url(forResource: "ElephantSeals",
                                            withExtension: "mov")
        else {
            print("Can't load the movie")
            return
        }
        avPlayerItem = AVPlayerItem(url: movieURL)
        avPlayer = AVPlayer(playerItem: avPlayerItem)
        avVideoOutput = AVPlayerItemVideoOutput(outputSettings: nil)

        let pixelBufferAttrs = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA) as Any,
            kCVPixelBufferMetalCompatibilityKey as String : true
        ]
        avVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttrs)

        avVideoOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: 1.0 / TimeInterval(30))
        avPlayerItem.add(avVideoOutput)

        // Register a`ViewController` object as an observer of the player item's status property
        avPlayerItem.addObserver(self,
                                 forKeyPath: #keyPath(AVPlayerItem.status),
                                 options: [.old, .new],
                                 context: &playerItemContext)

        setupDisplayLink()
    }

    deinit
    {
        NotificationCenter.default.removeObserver(self,
                                                  name: .AVPlayerItemDidPlayToEndTime,
                                                  object: nil)
        avPlayerItem.removeObserver(self,
                                    forKeyPath: #keyPath(AVPlayerItem.status),
                                    context: nil)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    @objc private func newFrame(_ fps: Double)
    {
        if avVideoOutput.hasNewPixelBuffer(forItemTime: avPlayerItem.currentTime()) {
            let pixelBuffer = avVideoOutput.copyPixelBuffer(forItemTime: avPlayerItem.currentTime(),
                                                            itemTimeForDisplay: nil)
            let inputImage = CIImage(cvPixelBuffer: pixelBuffer!, options: nil)
            guard let outputImage = applyFilterChain(ciImage: inputImage)
            else {
                return
            }
            guard let image = NSImage(ciImage: outputImage)
            else {
                return
            }
            videoView.image = image
        }
    }

    // KIV. Convert it with a CIFilter class
    func applyFilterChain(ciImage inputImage: CIImage) -> CIImage?
    {
        // 1) Apply the Sepia Tone Filter to the Original Image
        guard let sepiaFilter = CIFilter(name:"CISepiaTone",
                                         withInputParameters: [
                kCIInputImageKey: inputImage,
                kCIInputIntensityKey: 1.0
            ])
        else {
            return nil
        }

        guard let sepiaCIImage = sepiaFilter.outputImage
        else {
            return nil
        }

        // 2) Simulate Grain by Creating Randomly Varying Speckles
        guard let coloredNoise = CIFilter(name:"CIRandomGenerator"),
              let noiseImage = coloredNoise.outputImage
        else {
            return nil
        }

        // 3) Create randomly varying white specks to simulate grain.
        let whitenVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        let fineGrain = CIVector(x:0, y:0.005, z:0, w:0)
        let zeroVector = CIVector(x: 0, y: 0, z: 0, w: 0)

        guard let whiteningFilter = CIFilter(name:"CIColorMatrix",
                                             withInputParameters: [
                kCIInputImageKey: noiseImage,
                "inputRVector": whitenVector,
                "inputGVector": whitenVector,
                "inputBVector": whitenVector,
                "inputAVector": fineGrain,
                "inputBiasVector": zeroVector
            ]),
              let whiteSpecks = whiteningFilter.outputImage
        else {
            return nil
        }

        guard let speckCompositor = CIFilter(name:"CISourceOverCompositing",
                                             withInputParameters: [
                kCIInputImageKey: whiteSpecks,
                kCIInputBackgroundImageKey: sepiaCIImage
            ]),
              let speckledImage = speckCompositor.outputImage
        else {
            return nil
        }

        // 4) Simulate Scratch by Scaling Randomly Varying Noise
        let verticalScale = CGAffineTransform(scaleX: 1.5, y: 25)
        let transformedNoise = noiseImage.applying(verticalScale)

        let darkenVector = CIVector(x: 4, y: 0, z: 0, w: 0)
        let darkenBias = CIVector(x: 0, y: 1, z: 1, w: 1)

        guard let darkeningFilter = CIFilter(name:"CIColorMatrix",
                                             withInputParameters: [
                kCIInputImageKey: transformedNoise,
                "inputRVector": darkenVector,
                "inputGVector": zeroVector,
                "inputBVector": zeroVector,
                "inputAVector": zeroVector,
                "inputBiasVector": darkenBias
            ]),
              let randomScratches = darkeningFilter.outputImage
        else {
            return nil
        }
        // This results in cyan-colored scratches.

        // To make the scratches dark, apply the CIMinimumComponent filter to the cyan-colored scratches
        guard let grayscaleFilter = CIFilter(name:"CIMinimumComponent",
                                             withInputParameters: [
                kCIInputImageKey: randomScratches
            ]),
            let darkScratches = grayscaleFilter.outputImage
        else {
            return nil
        }

        // 5) Composite the Specks and Scratches to the Sepia Image
        guard let oldFilmCompositor = CIFilter(name:"CIMultiplyCompositing",
                                               withInputParameters: [
                kCIInputImageKey: darkScratches,
                kCIInputBackgroundImageKey: speckledImage
            ]),
              let oldFilmImage = oldFilmCompositor.outputImage
        else {
            return nil
        }

        let outputImage = oldFilmImage.cropping(to: inputImage.extent)
        return outputImage
    }

    private func setupDisplayLink()
    {
        // Create a display link capable of being used with all active displays
        var cvReturn = CVDisplayLinkCreateWithActiveCGDisplays(&self.displayLink)
        let queue = DispatchQueue.main
        displaySource = DispatchSource.makeUserDataAddSource(queue: queue) as? DispatchSource
        displaySource.setEventHandler {
            // Get the current "now" time of the display link.
            var currentTime = CVTimeStamp()
            CVDisplayLinkGetCurrentTime(self.displayLink!, &currentTime)
            // We should be getting 60 frames/s
            let fps = (currentTime.rateScalar * Double(currentTime.videoTimeScale) / Double(currentTime.videoRefreshPeriod))
            self.newFrame(fps)
        }
        displaySource.resume()

        cvReturn = CVDisplayLinkSetCurrentCGDisplay(displayLink!, CGMainDisplayID())
        cvReturn = CVDisplayLinkSetOutputCallback(displayLink!, {
            (timer: CVDisplayLink,
            inNow: UnsafePointer<CVTimeStamp>,
            inOutputTime: UnsafePointer<CVTimeStamp>,
            flagsIn: CVOptionFlags,
            flagsOut: UnsafeMutablePointer<CVOptionFlags>,
            displayLinkContext: UnsafeMutableRawPointer?) -> CVReturn in

            // CVDisplayLink callback merges the dispatch source in each call
            // to execute rendering on the main thread.
            let sourceUnmanaged = Unmanaged<DispatchSourceUserDataAdd>.fromOpaque(displayLinkContext!)
            sourceUnmanaged.takeUnretainedValue().add(data: 1)
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(displaySource).toOpaque())

        CVDisplayLinkStart(self.displayLink!)
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?)
    {

        // Only handle observations for the playerItemContext
        guard context == &playerItemContext else {
            super.observeValue(forKeyPath: keyPath,
                               of: object,
                               change: change,
                               context: context)
            return
        }

        if keyPath == #keyPath(AVPlayerItem.status) {
            let status: AVPlayerItemStatus
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayerItemStatus(rawValue: statusNumber.intValue)!
            }
            else {
                status = .unknown
            }

            // Switch over status value
            switch status {
            case .readyToPlay:
                // Player item is ready to play.
                print("Ready to play")
                avPlayer.play()
                break
            case .failed:
                // Player item failed. See error.
                break
            case .unknown:
                // Player item is not yet ready.
                break
            }
        }
    }
}

extension NSImage
{
    convenience init?(ciImage: CIImage)
    {
        let imageRep = NSCIImageRep(ciImage: ciImage)
        let size = imageRep.size
        self.init(size: size)
        self.addRepresentation(imageRep)
    }
}
