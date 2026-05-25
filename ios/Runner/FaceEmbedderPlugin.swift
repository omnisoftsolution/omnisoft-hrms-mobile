//
// FaceEmbedderPlugin.swift
//
// Native Swift bridge for face-embedding inference on iOS.
//
// Why this exists:
//   tflite_flutter on iOS uses dart:ffi + DynamicLibrary.process() +
//   dlsym(RTLD_DEFAULT, ...) to find TFLite C symbols. Apple's
//   release-build linker (Xcode 26) dead-strips those symbols
//   because no Obj-C / Swift / C code visibly references them.
//   9 attempts to force-keep the symbols via -force_load,
//   -Wl,-all_load, @_silgen_name, C __attribute__((used)),
//   __attribute__((constructor)) were all dead-stripped.
//
//   This plugin sidesteps the entire problem by using the
//   TensorFlowLiteSwift Swift API directly. The Interpreter class
//   gets pulled in via Flutter's plugin-registration code (a real
//   live root the linker can't strip), and its calls to TFLite C
//   symbols are normal Swift-to-C bridging — not runtime dlsym
//   lookups. The whole symbol chain stays alive in the binary.
//
// Channel contract:
//   - Channel: 'omnihr/face_embed' (shared with the spoof detector
//              even though the name says embed; one channel, two
//              methods to keep the plugin surface area small)
//   - Method 'extractEmbedding':
//       Args: { imagePath: String, left: Double, top: Double,
//               width: Double, height: Double }
//               (the box is the ML Kit-detected face bounding box,
//                in pixel coordinates of the image at imagePath)
//       Returns: List<Double> — L2-normalized embedding (192 dims
//                for the bundled FaceNet model)
//   - Method 'detectSpoof':
//       Args: same shape as extractEmbedding
//       Returns: { isLive: Bool, score: Double, elapsedMs: Int }
//                where isLive is true iff the MiniVision-style
//                two-model ensemble's argmax landed on the live
//                class. See lib/services/face_spoof_detector.dart
//                for the full ensemble logic.
//   - Errors via FlutterError with code: INVALID_ARGS,
//     MODEL_LOAD_FAIL, DECODE_FAIL, CROP_FAIL, INFER_FAIL,
//     ZERO_EMBEDDING, SPOOF_INFER_FAIL.
//
// Android still uses the Dart-side tflite_flutter path — only iOS
// goes through this plugin. The Dart engine branches on
// Platform.isIOS in lib/services/face_recognition_engine.dart and
// face_spoof_detector.dart.

import Flutter
import UIKit
import TensorFlowLite

// FlutterError isn't a Swift Error, so internal helpers can't throw
// it directly. Use this local error type for the helper layer and
// convert to FlutterError at the FlutterResult callback boundary.
private enum FaceEmbedderError: Error {
    case modelLoadFail(String)
    case decodeFail(String)
    case cropFail(String)
    case inferFail(String)
    case zeroEmbedding
    case spoofInferFail(String)

    var code: String {
        switch self {
        case .modelLoadFail:   return "MODEL_LOAD_FAIL"
        case .decodeFail:      return "DECODE_FAIL"
        case .cropFail:        return "CROP_FAIL"
        case .inferFail:       return "INFER_FAIL"
        case .zeroEmbedding:   return "ZERO_EMBEDDING"
        case .spoofInferFail:  return "SPOOF_INFER_FAIL"
        }
    }

    var message: String {
        switch self {
        case .modelLoadFail(let m):  return m
        case .decodeFail(let m):     return m
        case .cropFail(let m):       return m
        case .inferFail(let m):      return m
        case .zeroEmbedding:
            return "Embedding L2 norm was zero — likely a degenerate image."
        case .spoofInferFail(let m): return m
        }
    }

    func asFlutterError() -> FlutterError {
        return FlutterError(code: code, message: message, details: nil)
    }
}

// Pixel-normalization scheme — different face-embedding models
// expect different preprocessing. Detected from the loaded model's
// input tensor shape, mirroring the Dart-side engine's logic in
// lib/services/face_recognition_engine.dart.
private enum Normalization {
    /// MobileFaceNet / ArcFace etc. — (p - 127.5) / 128 → range [-1, 1].
    case minusOneToOne
    /// FaceNet (Sandberg / DeepFace) — per-image mean/std
    /// standardization (a.k.a. "prewhitening"), with floor of
    /// 1/sqrt(N) on the divisor per Sandberg's reference impl.
    case perImageStandardization
}

class FaceEmbedderPlugin: NSObject, FlutterPlugin {
    private static var cachedInterpreter: Interpreter?
    // Detected at model load — see ensureInterpreter().
    private static var cachedInputSize: Int = 112
    private static var cachedNorm: Normalization = .minusOneToOne

    // Two-model spoof ensemble (MiniVision Silent-Face-Anti-Spoofing).
    // Both fixed at 80×80 float32 [0, 255] BGR input, 3-class softmax
    // output. Loaded lazily on first detectSpoof call.
    private static var cachedSpoofInterpreter1: Interpreter?
    private static var cachedSpoofInterpreter2: Interpreter?
    private static let spoofInputSize: Int = 80
    private static let spoofOutputDim: Int = 3
    // Class index in the model's 3-way softmax that represents a live
    // face (vs print spoof / replay spoof). Same as the Dart side.
    private static let spoofLiveClassIndex: Int = 1
    // Crop expansion factors — tight + wide, matching the MiniVision
    // training pipeline. Identical to the Dart-side detector so iOS
    // and Android results are comparable.
    private static let spoofScale1: Double = 2.7
    private static let spoofScale2: Double = 4.0

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "omnihr/face_embed",
            binaryMessenger: registrar.messenger())
        let instance = FaceEmbedderPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall,
                result: @escaping FlutterResult) {
        switch call.method {
        case "extractEmbedding":
            extractEmbedding(call: call, result: result)
        case "detectSpoof":
            detectSpoof(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func extractEmbedding(call: FlutterMethodCall,
                                  result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let imagePath = args["imagePath"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing or invalid imagePath",
                details: nil))
            return
        }
        let left = (args["left"] as? Double) ?? 0
        let top = (args["top"] as? Double) ?? 0
        let width = (args["width"] as? Double) ?? 0
        let height = (args["height"] as? Double) ?? 0

        do {
            let interpreter = try Self.ensureInterpreter()

            // 1. Decode the (orientation-normalized — Dart's
            //    _normalizeOrientation ran already) JPEG.
            guard let image = UIImage(contentsOfFile: imagePath),
                  let cgImage = image.cgImage else {
                result(FlutterError(
                    code: "DECODE_FAIL",
                    message: "Could not decode image at \(imagePath)",
                    details: nil))
                return
            }

            // 2. Crop to the face bounding box with 20% padding
            //    (matches Dart-side `pad = 0.2` so embeddings from
            //    iOS and Android compare cleanly).
            let pad: Double = 0.2
            let cx = left + width / 2.0
            let cy = top + height / 2.0
            let half = max(width, height) * (0.5 + pad)
            let imgW = Double(cgImage.width)
            let imgH = Double(cgImage.height)
            let x0 = max(0.0, cx - half)
            let y0 = max(0.0, cy - half)
            let w0 = min(imgW - x0, half * 2.0)
            let h0 = min(imgH - y0, half * 2.0)
            let cropRect = CGRect(x: x0, y: y0, width: w0, height: h0)
            guard w0 >= 1, h0 >= 1,
                  let cropped = cgImage.cropping(to: cropRect) else {
                result(FlutterError(
                    code: "CROP_FAIL",
                    message: "Crop to face box failed: rect=\(cropRect) imgSize=(\(imgW),\(imgH))",
                    details: nil))
                return
            }

            // 3. Resize to the model's expected size + produce a
            //    Float32 tensor with the appropriate normalization.
            //    Both detected at model-load time.
            let inputData = try Self.preprocess(
                cgImage: cropped,
                size: Self.cachedInputSize,
                norm: Self.cachedNorm)

            // 4. Run inference.
            try interpreter.copy(inputData, toInputAt: 0)
            try interpreter.invoke()
            let outputTensor = try interpreter.output(at: 0)

            // 5. Read output as Float32 array.
            let outputBytes = outputTensor.data
            let outputDim = outputTensor.shape.dimensions.reduce(1, *)
            var embedding = [Float](repeating: 0, count: outputDim)
            _ = embedding.withUnsafeMutableBytes {
                outputBytes.copyBytes(to: $0)
            }

            // 6. L2-normalize so cosine similarity == dot product.
            var sumSq: Float = 0
            for v in embedding { sumSq += v * v }
            let norm = sqrtf(sumSq)
            guard norm > 0 else {
                result(FlutterError(
                    code: "ZERO_EMBEDDING",
                    message: "Embedding L2 norm was zero — likely a degenerate image",
                    details: nil))
                return
            }
            let normalized: [Double] =
                embedding.map { Double($0 / norm) }
            result(normalized)
        } catch let error as FaceEmbedderError {
            result(error.asFlutterError())
        } catch {
            result(FlutterError(
                code: "INFER_FAIL",
                message: "TFLite inference failed: \(error)",
                details: nil))
        }
    }

    // ----------------------------------------------------------
    // Model loading
    // ----------------------------------------------------------

    private static func ensureInterpreter() throws -> Interpreter {
        if let i = cachedInterpreter { return i }

        // Flutter assets land at a bundle-relative path. lookupKey
        // gives us that key; Bundle.main.path resolves it to an
        // absolute filesystem location TFLite can read.
        let assetKey = FlutterDartProject.lookupKey(
            forAsset: "assets/models/mobilefacenet.tflite")
        guard let modelPath = Bundle.main.path(
            forResource: assetKey, ofType: nil) else {
            throw FaceEmbedderError.modelLoadFail(
                "Could not locate mobilefacenet.tflite in bundle (lookupKey=\(assetKey))")
        }

        var options = Interpreter.Options()
        // CPU inference only — no Metal/CoreML delegate. Same
        // posture as Dart-side _ensureEmbedder. The delegate path
        // is what caused the original iOS load failures in the
        // earlier dart:ffi attempt.
        options.threadCount = 2

        let interpreter: Interpreter
        do {
            interpreter = try Interpreter(
                modelPath: modelPath, options: options)
            try interpreter.allocateTensors()
        } catch {
            throw FaceEmbedderError.modelLoadFail(
                "TFLite Interpreter init failed at \(modelPath): \(error)")
        }

        // Detect input geometry and preprocessing scheme from the
        // model's actual input tensor shape. Mirrors the Dart-side
        // engine's logic — 160×160 → FaceNet (per-image standardization);
        // smaller (typically 112×112) → MobileFaceNet ([-1, 1]).
        do {
            let inputTensor = try interpreter.input(at: 0)
            let dims = inputTensor.shape.dimensions  // [1, H, W, 3]
            let size = dims.count >= 3 ? dims[1] : 112
            cachedInputSize = size
            cachedNorm = size >= 160
                ? .perImageStandardization
                : .minusOneToOne
            NSLog("[FaceEmbedderPlugin] Model loaded — inputShape=\(dims) inputSize=\(size) norm=\(cachedNorm)")
        } catch {
            throw FaceEmbedderError.modelLoadFail(
                "Could not read input tensor shape: \(error)")
        }

        cachedInterpreter = interpreter
        return interpreter
    }

    // ----------------------------------------------------------
    // Spoof detection — two-model MiniVision ensemble
    // ----------------------------------------------------------

    private func detectSpoof(call: FlutterMethodCall,
                             result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let imagePath = args["imagePath"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing or invalid imagePath",
                details: nil))
            return
        }
        let left = (args["left"] as? Double) ?? 0
        let top = (args["top"] as? Double) ?? 0
        let width = (args["width"] as? Double) ?? 0
        let height = (args["height"] as? Double) ?? 0

        do {
            let (interp1, interp2) = try Self.ensureSpoofInterpreters()

            guard let image = UIImage(contentsOfFile: imagePath),
                  let cgImage = image.cgImage else {
                result(FlutterError(
                    code: "DECODE_FAIL",
                    message: "Could not decode image at \(imagePath)",
                    details: nil))
                return
            }

            let start = Date()

            // Two crops at different expansion factors. The wider one
            // (scale 4.0) is the key signal — it lets the model see
            // edges of phone screens / paper prints around the face.
            guard let crop1 = Self.spoofCrop(
                cgImage: cgImage,
                left: left, top: top, width: width, height: height,
                scale: Self.spoofScale1) else {
                result(FlutterError(
                    code: "CROP_FAIL",
                    message: "Spoof scale-2.7 crop failed",
                    details: nil))
                return
            }
            guard let crop2 = Self.spoofCrop(
                cgImage: cgImage,
                left: left, top: top, width: width, height: height,
                scale: Self.spoofScale2) else {
                result(FlutterError(
                    code: "CROP_FAIL",
                    message: "Spoof scale-4.0 crop failed",
                    details: nil))
                return
            }

            let input1 = try Self.spoofPreprocess(cgImage: crop1)
            let input2 = try Self.spoofPreprocess(cgImage: crop2)

            try interp1.copy(input1, toInputAt: 0)
            try interp1.invoke()
            let outTensor1 = try interp1.output(at: 0)

            try interp2.copy(input2, toInputAt: 0)
            try interp2.invoke()
            let outTensor2 = try interp2.output(at: 0)

            let out1 = Self.readFloatOutput(
                outTensor1, count: Self.spoofOutputDim)
            let out2 = Self.readFloatOutput(
                outTensor2, count: Self.spoofOutputDim)

            // Element-wise sum of softmaxes, argmax, label-1 = live.
            let s1 = Self.softmax(out1)
            let s2 = Self.softmax(out2)
            var summed = [Float](repeating: 0, count: Self.spoofOutputDim)
            for i in 0..<Self.spoofOutputDim {
                summed[i] = s1[i] + s2[i]
            }
            var maxIdx = 0
            for i in 1..<Self.spoofOutputDim where summed[i] > summed[maxIdx] {
                maxIdx = i
            }
            let isLive = (maxIdx == Self.spoofLiveClassIndex)
            let score = Double(summed[maxIdx]) / 2.0
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

            NSLog("[FaceEmbedderPlugin] detectSpoof isLive=\(isLive) "
                + "score=\(score) elapsedMs=\(elapsedMs) "
                + "argmax=\(maxIdx) s1=\(s1) s2=\(s2)")

            // Surface the raw softmax arrays + argmax so the Dart
            // side can show them in a capture-screen debug overlay.
            // Used to empirically verify the live-class index (the
            // Kotlin reference assumes 1, may not hold for these
            // specific model files).
            result([
                "isLive": isLive,
                "score": score,
                "elapsedMs": elapsedMs,
                "argmax": maxIdx,
                "softmax1": s1.map { Double($0) },
                "softmax2": s2.map { Double($0) },
            ] as [String: Any])
        } catch let error as FaceEmbedderError {
            result(error.asFlutterError())
        } catch {
            result(FlutterError(
                code: "SPOOF_INFER_FAIL",
                message: "Spoof inference failed: \(error)",
                details: nil))
        }
    }

    private static func ensureSpoofInterpreters() throws
        -> (Interpreter, Interpreter)
    {
        if let a = cachedSpoofInterpreter1, let b = cachedSpoofInterpreter2 {
            return (a, b)
        }
        let key1 = FlutterDartProject.lookupKey(
            forAsset: "assets/models/spoof_model_scale_2_7.tflite")
        let key2 = FlutterDartProject.lookupKey(
            forAsset: "assets/models/spoof_model_scale_4_0.tflite")
        guard let path1 = Bundle.main.path(forResource: key1, ofType: nil),
              let path2 = Bundle.main.path(forResource: key2, ofType: nil) else {
            throw FaceEmbedderError.modelLoadFail(
                "Could not locate spoof_model_scale_2_7.tflite or "
                + "spoof_model_scale_4_0.tflite in bundle")
        }

        var options = Interpreter.Options()
        options.threadCount = 2

        let interp1: Interpreter
        let interp2: Interpreter
        // Per-step try/catch so the surfaced error tells us which
        // call actually fails. Empirically Python's tf.lite reports
        // both models as static [1, 80, 80, 3] float32 — yet the
        // iOS Swift TFLite 2.12 runtime throws "Failed to allocate
        // memory for input tensors" on one of these steps. v52 tried
        // explicit resizeInput; it didn't help. v53 isolates the
        // failing line so we can target the actual root cause.
        do {
            interp1 = try Interpreter(modelPath: path1, options: options)
        } catch {
            throw FaceEmbedderError.modelLoadFail(
                "spoof interp1 init: \(error)")
        }
        do {
            try interp1.allocateTensors()
        } catch {
            throw FaceEmbedderError.modelLoadFail(
                "spoof interp1 allocateTensors: \(error)")
        }
        do {
            interp2 = try Interpreter(modelPath: path2, options: options)
        } catch {
            throw FaceEmbedderError.modelLoadFail(
                "spoof interp2 init: \(error)")
        }
        do {
            try interp2.allocateTensors()
        } catch {
            throw FaceEmbedderError.modelLoadFail(
                "spoof interp2 allocateTensors: \(error)")
        }

        cachedSpoofInterpreter1 = interp1
        cachedSpoofInterpreter2 = interp2
        NSLog("[FaceEmbedderPlugin] Spoof models loaded "
            + "(2.7 + 4.0, 80×80, 3-class softmax)")
        return (interp1, interp2)
    }

    /// Mirror of the Kotlin reference's `getScaledBox` + `crop`:
    /// expand the face box by `scale`, clamp to the image bounds by
    /// shifting (not just clipping — preserves the aspect ratio), then
    /// crop. Returns nil on degenerate input.
    private static func spoofCrop(
        cgImage: CGImage,
        left: Double, top: Double, width: Double, height: Double,
        scale: Double
    ) -> CGImage? {
        let srcW = Double(cgImage.width)
        let srcH = Double(cgImage.height)
        let effScale = min(min((srcH - 1) / height, (srcW - 1) / width), scale)
        let newW = width * effScale
        let newH = height * effScale
        let cx = width / 2.0 + left
        let cy = height / 2.0 + top
        var x0 = cx - newW / 2.0
        var y0 = cy - newH / 2.0
        var x1 = cx + newW / 2.0
        var y1 = cy + newH / 2.0
        if x0 < 0 { x1 -= x0; x0 = 0 }
        if y0 < 0 { y1 -= y0; y0 = 0 }
        if x1 > srcW - 1 { x0 -= (x1 - (srcW - 1)); x1 = srcW - 1 }
        if y1 > srcH - 1 { y0 -= (y1 - (srcH - 1)); y1 = srcH - 1 }
        let w = x1 - x0
        let h = y1 - y0
        guard w >= 1, h >= 1 else { return nil }
        return cgImage.cropping(to: CGRect(x: x0, y: y0, width: w, height: h))
    }

    /// Resize to 80×80, swap R↔B (the model was trained on
    /// OpenCV-loaded BGR images), keep values in [0, 255] (no
    /// normalization — matches the Kotlin's CastOp(FLOAT32)-only
    /// pipeline). Output is the float32 NHWC byte buffer TFLite
    /// expects.
    private static func spoofPreprocess(cgImage: CGImage) throws -> Data {
        let size = spoofInputSize
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * size
        let totalBytes = size * size * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: totalBytes)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FaceEmbedderError.spoofInferFail(
                "Failed to create CGContext for spoof preprocessing")
        }
        ctx.draw(cgImage,
                 in: CGRect(x: 0, y: 0, width: size, height: size))

        let channels = 3
        let floatCount = size * size * channels
        var floats = [Float](repeating: 0, count: floatCount)
        for y in 0..<size {
            for x in 0..<size {
                let pIdx = (y * size + x) * bytesPerPixel
                let oIdx = (y * size + x) * channels
                // R↔B swap → BGR ordering. Values stay in [0, 255].
                floats[oIdx]     = Float(pixels[pIdx + 2]) // B
                floats[oIdx + 1] = Float(pixels[pIdx + 1]) // G
                floats[oIdx + 2] = Float(pixels[pIdx])     // R
            }
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func readFloatOutput(_ tensor: Tensor, count: Int)
        -> [Float]
    {
        var out = [Float](repeating: 0, count: count)
        _ = out.withUnsafeMutableBytes {
            tensor.data.copyBytes(to: $0)
        }
        return out
    }

    /// Numerically-stable softmax — subtract max before exp() so big
    /// logits don't blow up.
    private static func softmax(_ x: [Float]) -> [Float] {
        guard let mx = x.max() else { return x }
        let exps = x.map { expf($0 - mx) }
        let sum = exps.reduce(0, +)
        guard sum > 0 else { return x }
        return exps.map { $0 / sum }
    }

    // ----------------------------------------------------------
    // Image preprocessing
    // ----------------------------------------------------------

    /// Resize cgImage to size×size and produce a Data buffer of
    /// Float32 RGB pixels normalized for the chosen scheme. Pixel
    /// order is the standard TFLite NHWC: row-major, channels-last.
    private static func preprocess(
        cgImage: CGImage, size: Int, norm: Normalization) throws -> Data
    {
        let bytesPerPixel = 4 // RGBA bitmap context
        let bytesPerRow = bytesPerPixel * size
        let totalBytes = size * size * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: totalBytes)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FaceEmbedderError.inferFail(
                "Failed to create CGContext for preprocessing")
        }
        ctx.draw(cgImage,
                 in: CGRect(x: 0, y: 0, width: size, height: size))

        // Stage 1: flatten RGBA8 pixels into raw Float32 RGB
        // (channels-last) without normalization yet. We'll apply
        // the normalization in a second pass — per-image
        // standardization needs the full sample to compute
        // mean/std first.
        let channels = 3
        let floatCount = size * size * channels
        var floats = [Float](repeating: 0, count: floatCount)
        for y in 0..<size {
            for x in 0..<size {
                let pIdx = (y * size + x) * bytesPerPixel
                let oIdx = (y * size + x) * channels
                floats[oIdx]     = Float(pixels[pIdx])
                floats[oIdx + 1] = Float(pixels[pIdx + 1])
                floats[oIdx + 2] = Float(pixels[pIdx + 2])
            }
        }

        // Stage 2: apply normalization.
        switch norm {
        case .minusOneToOne:
            for i in 0..<floatCount {
                floats[i] = (floats[i] - 127.5) / 128.0
            }
        case .perImageStandardization:
            // FaceNet "prewhitening" — per-image mean/std with
            // floor of 1/sqrt(N) on the divisor (Sandberg's impl).
            var sum: Float = 0
            for v in floats { sum += v }
            let mean = sum / Float(floatCount)
            var sqDev: Float = 0
            for v in floats {
                let d = v - mean
                sqDev += d * d
            }
            let std = sqrtf(sqDev / Float(floatCount))
            let stdAdj = max(std, 1.0 / sqrtf(Float(floatCount)))
            for i in 0..<floatCount {
                floats[i] = (floats[i] - mean) / stdAdj
            }
        }

        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
