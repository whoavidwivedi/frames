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

    // MARK: - HDR Optical Transfer Functions

    // SMPTE ST 2084 (Perceptual Quantizer / PQ) EOTF
    float3 pq_to_linear(float3 pq) {
        const float m1 = 2610.0 / 16384.0;
        const float m2 = 2523.0 / 4096.0 * 128.0;
        const float c1 = 3424.0 / 4096.0;
        const float c2 = 2413.0 / 4096.0 * 32.0;
        const float c3 = 2392.0 / 4096.0 * 32.0;

        float3 num = max(pow(pq, 1.0 / m2) - c1, 0.0);
        float3 den = c2 - c3 * pow(pq, 1.0 / m2);
        float3 linearSignal = pow(num / den, 1.0 / m1);
        
        return linearSignal * (10000.0 / 100.0);
    }

    // ARIB STD-B67 (Hybrid Log-Gamma / HLG) EOTF
    float3 hlg_to_linear(float3 hlg) {
        const float a = 0.17883277;
        const float b = 1.0 - 4.0 * a;
        const float c = 0.5 - a * log(4.0 * a);
        
        float3 linearVal;
        for (int i = 0; i < 3; ++i) {
            float e = hlg[i];
            if (e <= 0.5) {
                linearVal[i] = (e * e) / 3.0;
            } else {
                linearVal[i] = (exp((e - c) / a) + b) / 12.0;
            }
        }
        
        return linearVal * (1000.0 / 100.0);
    }

    // MARK: - Fragment Shader

    fragment float4 videoFragmentShader(
        VertexOutput in [[stage_in]],
        texture2d<float, access::sample> lumaTexture [[texture(0)]],
        texture2d<float, access::sample> chromaTexture [[texture(1)]],
        constant VideoShaderUniforms &uniforms [[buffer(0)]]
    ) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        
        float y = lumaTexture.sample(s, in.texCoords).r;
        float2 cbcr = chromaTexture.sample(s, in.texCoords).rg;
        
        float3 yuv = float3(y, cbcr) + uniforms.yuvOffset;
        float3 rgb = max(uniforms.colorMatrix * yuv, 0.0);
        
        if (uniforms.colorSpaceMode == 2) {
            rgb = pq_to_linear(rgb);
        } else if (uniforms.colorSpaceMode == 3) {
            rgb = hlg_to_linear(rgb);
        }
        
        return float4(rgb, 1.0);
    }
    """
}
