//
//  ViewController.swift
//  OldFilmFilter
//
//  Created by mark lim pak mun on 26/02/2024.
//  Copyright © 2024 Incremental Innovation. All rights reserved.
//
// Code is based on Apple's Core Image Article:
//
//      `Simulating Scratchy Analog Film`
//
// Degrade the quality of an image to make it look like dated, scratchy analog film.

import Cocoa

class OPViewController: NSViewController
{

    @IBOutlet var pictureView: NSImageView!

    override func viewDidLoad()
    {
        super.viewDidLoad()

        guard let image = NSImage(named: "Food_4")
        else {
            fatalError("Couldn't load the graphic image")
        }
        guard let cgImage = image.cgImage(forProposedRect: nil,
                                          context: nil,
                                          hints: nil)
        else {
            fatalError("Couldn't create Core Graphics Object")
        }

        let inputImage = CIImage(cgImage: cgImage, options: nil)
        guard let outputImage = applyFilterChains(ciImage: inputImage)
        else {
            return
        }
        pictureView.image = NSImage(ciImage: outputImage)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    func applyFilterChains(ciImage inputImage: CIImage) -> CIImage?
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
        // The output of the sepia filter will become the background for compositing the grain image

        // 2) Simulate Grain by Creating Randomly Varying Speckle
        guard
            let coloredNoise = CIFilter(name:"CIRandomGenerator"),
            let noiseImage = coloredNoise.outputImage
        else {
            return nil
        }
 
        // 3) Create randomly varying white specks to simulate grain.
        /* 
         Apply a whitening effect by chaining the noise output to a CIColorMatrix filter
         */
        let whitenVector = CIVector(x: 0, y: 1,    z: 0, w: 0)
        let    fineGrain = CIVector(x: 0, y:0.005, z:0,  w: 0)
        let   zeroVector = CIVector(x: 0, y: 0,    z: 0, w: 0)

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

        // The whiteSpecks resulting from the whitening filter have the appearance of spotty grain
        // when viewed as an image.

        /*
         Create the grainy image by compositing the whitened noise as input over the sepia-toned 
         source image using the CISourceOverCompositing filter.
         */
        guard
            let speckCompositor = CIFilter(name:"CISourceOverCompositing",
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
        
        guard
            let darkeningFilter = CIFilter(name:"CIColorMatrix",
                                             withInputParameters: [
                    kCIInputImageKey: transformedNoise,
                    "inputRVector": darkenVector,
                    "inputGVector": zeroVector,
                    "inputBVector": zeroVector,
                    "inputAVector": zeroVector,
                    "inputBiasVector": darkenBias]),
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
        guard
            let oldFilmCompositor = CIFilter(name:"CIMultiplyCompositing",
                                             withInputParameters: [
                    kCIInputImageKey: darkScratches,
                    kCIInputBackgroundImageKey: speckledImage]),
            let oldFilmImage = oldFilmCompositor.outputImage
        else {
            return nil
        }

        let outputImage = oldFilmImage.cropping(to: inputImage.extent)
        return outputImage
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
