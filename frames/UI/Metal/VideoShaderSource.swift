//
//  VideoShaderSource.swift
//  frames
//
//  Pure Metal 3 shading language source code for runtime driver compilation,
//  bypassing static toolchain requirements while unlocking maximum GPU performance.
//

import Foundation

nonisolated public enum VideoShaderSource: Sendable {
    public static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOutput {
        float4 position [[position]];
        float2 texCoords;
    };

    struct VideoShaderUniforms {
        float3x3 colorMatrix;
        float3 yuvOffset;
        int colorSpaceMode; // 0: BT.709 SDR, 1: BT.2020 SDR, 2: BT.2020 PQ, 3: BT.2020 HLG
        float maxContentLightLevel; // in nits, e.g. 1000.0
        float2 aspectScale;
    };

    // MARK: - Vertex Shader

    vertex VertexOutput videoVertexShader(
        uint vertexID [[vertex_id]],
        constant VideoShaderUniforms &uniforms [[buffer(0)]]
    ) {
        const float2 positions[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };
        
        const float2 texCoords[4] = {
            float2(0.0, 1.0),
            float2(1.0, 1.0),
            float2(0.0, 0.0),
            float2(1.0, 0.0)
        };
        
        VertexOutput out;
        out.position = float4(positions[vertexID] * uniforms.aspectScale, 0.0, 1.0);
        out.texCoords = texCoords[vertexID];
        return out;
    }

    // MARK: - HDR Optical Transfer Functions (FP16 Half Precision)

    // SMPTE ST 2084 (Perceptual Quantizer / PQ) EOTF
    half3 pq_to_linear(half3 pq) {
        const half m1 = 2610.0h / 16384.0h;
        const half m2 = 2523.0h / 4096.0h * 128.0h;
        const half c1 = 3424.0h / 4096.0h;
        const half c2 = 2413.0h / 4096.0h * 32.0h;
        const half c3 = 2392.0h / 4096.0h * 32.0h;

        half3 num = max(pow(pq, half3(1.0h / m2)) - c1, half3(0.0h));
        half3 den = c2 - c3 * pow(pq, half3(1.0h / m2));
        half3 linearSignal = pow(num / den, half3(1.0h / m1));
        
        return linearSignal * (10000.0h / 100.0h);
    }

    // ARIB STD-B67 (Hybrid Log-Gamma / HLG) EOTF
    half3 hlg_to_linear(half3 hlg) {
        const half a = 0.17883277h;
        const half b = 1.0h - 4.0h * a;
        const half c = 0.5h - a * log(4.0h * a);
        
        half3 linearVal;
        for (int i = 0; i < 3; ++i) {
            half e = hlg[i];
            if (e <= 0.5h) {
                linearVal[i] = (e * e) / 3.0h;
            } else {
                linearVal[i] = (exp((e - c) / a) + b) / 12.0h;
            }
        }
        
        return linearVal * (1000.0h / 100.0h);
    }

    // MARK: - Fragment Shader (FP16 Half-Precision ALU)

    fragment half4 videoFragmentShader(
        VertexOutput in [[stage_in]],
        texture2d<half, access::sample> lumaTexture [[texture(0)]],
        texture2d<half, access::sample> chromaTexture [[texture(1)]],
        constant VideoShaderUniforms &uniforms [[buffer(0)]]
    ) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        
        half y = lumaTexture.sample(s, in.texCoords).r;
        half2 cbcr = chromaTexture.sample(s, in.texCoords).rg;
        
        half3 yuv = half3(y, cbcr) + half3(uniforms.yuvOffset);
        half3 rgb = max(half3x3(uniforms.colorMatrix) * yuv, half3(0.0h));
        
        if (uniforms.colorSpaceMode == 2) {
            rgb = pq_to_linear(rgb);
        } else if (uniforms.colorSpaceMode == 3) {
            rgb = hlg_to_linear(rgb);
        }
        
        return half4(rgb, 1.0h);
    }
    """
}
