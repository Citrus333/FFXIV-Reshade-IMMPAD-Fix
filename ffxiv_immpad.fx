/*=============================================================================
This work is licensed under the 
Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0) License
https://creativecommons.org/licenses/by-nc/4.0/      

This is based around both Crashpad as well as the newer outputs that iMMERSE's Launchpad expects for working RTGI (Diffuse) Shaders. This shader shouldn't include anything directly from iMMERSE
and still requires the original to be present. 

"Edited" by Werin (aka copied parts from Crashpad, added new passes to the technique that iMMERSE now expects)

Original Files for Crashpad (for FFXIV) as well as REST can be found here: https://github.com/4lex4nder/ReshadeEffectShaderToggler-FFXIV
Original Credits and Information as follows:
------------------------------------------------
Original developer: Jak0bPCoder
Optimization by : Marty McFly
Compatibility by : MJ_Ehsan

alex: stripped out most things, lol
=============================================================================*/

uniform bool SHOWME <
    ui_label = "Debug Output";    
> = false;

uniform bool FULLDATA <
    ui_label = "Generate All Launchpad Data";    
> = true;

uniform bool USE_ENGINE_DATA <
    ui_label = "Use True Engine Normals/Motion (breaks DLSS/FSR2/XeSS upscaling)";
    ui_tooltip = "This is the original Crashpad behaviour: it overrides Launchpad's normals/motion vectors "
                 "with data read directly from the game's internal G-buffers via REST.\n\n"
                 "That internal data is captured at the game's INTERNAL render resolution, not your final "
                 "upscaled output resolution. If you use DLSS/FSR2/XeSS quality upscaling, the engine data "
                 "only fills the top-left corner of the frame (matching your internal render res) instead "
                 "of the full output - this is a known limitation of Crashpad/REST, not a bug in this file.\n\n"
                 "Leave this OFF if you use any upscaler. Launchpad's own normals/motion vectors (which ARE "
                 "DLSS-aware) will be used instead, and everything renders full-resolution.\n\n"
                 "If you turn this ON anyway, tune 'Engine Data Render Scale' below using the Debug Output "
                 "view until the colored motion vectors fill the whole screen instead of just a corner.";
> = false;

uniform float2 ENGINE_DATA_RENDER_SCALE <
    ui_type = "slider";
    ui_label = "Engine Data Render Scale (X / Y)";
    ui_tooltip = "Only used when 'Use True Engine Normals/Motion' is enabled.\n"
                 "Set to your DLSS/upscaler internal render resolution divided by your output resolution.\n"
                 "Roughly: DLAA/no upscaling = 1.0, DLSS Quality ~0.667, Balanced ~0.58, Performance ~0.5, Ultra Performance ~0.33.\n"
                 "Tune by eye with the Debug Output toggle on until the color fills the whole frame.";
    ui_min = 0.30; ui_max = 1.0; ui_step = 0.001;
> = float2(1.0, 1.0);

uniform int HELP1 <
ui_type = "radio";
    ui_label = " ";
    ui_category = "README";
    ui_category_closed = false;
    ui_text = 
            "\n\nEverything below is from the original Launchpad settings.\n"
                 "Not all settings below will work still\n"
                 "For example, the NORMAL MAPS section.\n"
            "\n";
>;

// Unlike Crashpad, we want to include Launchpad and just let it do it's thing for most of what we need. So much has been rewritten that someone who
// knows what they are doing would need to redo crashpad itself
#include "MartysMods_LAUNCHPAD.fx"
#include "ffxiv_common.fxh"

// We still want to override the normals that Launchpad will do.
namespace Deferred {
    sampler sNormalsTex { Texture = NormalsTexV4; };
    sampler sGeoNormalsTex { Texture = GeoNormalsTexV4; };
}

// We are still sending motion vectors over as well
texture texMotionVectors { Width = BUFFER_WIDTH;   Height = BUFFER_HEIGHT;   Format = RG16F; };
sampler sMotionVectorTex { Texture = texMotionVectors;  };


/* Original Crashpad Functionality */
struct VS_OUT
{
    float4 vpos : SV_Position;
    float2 uv   : TEXCOORD0;
};

VS_OUT VS_Main(in uint id : SV_VertexID)
{
    VS_OUT o;
    PostProcessVS(id, o.vpos, o.uv);
    return o;
}

float3 HUEtoRGB(in float H)
{
    float R = abs(H * 6.f - 3.f) - 1.f;
    float G = 2 - abs(H * 6.f - 2.f);
    float B = 2 - abs(H * 6.f - 4.f);
    return saturate(float3(R,G,B));
}

float3 HSLtoRGB(in float3 HSL)
{
    float3 RGB = HUEtoRGB(HSL.x);
    float C = (1.f - abs(2.f * HSL.z - 1.f)) * HSL.y;
    return (RGB - 0.5f) * C + HSL.z;
}

float4 motionToLgbtq(float2 motion)
{
    float angle = degrees(atan2(motion.y, motion.x));
    float dist = length(motion);
    float3 rgb = HSLtoRGB(float3((angle / 360.f) + 0.5, saturate(dist * 100.0), 0.5));
    return float4(rgb.r, rgb.g, rgb.b, 0);
}

void PSOut(in VSOUT i, out float4 o : SV_Target0)
{
    if(!SHOWME) discard;
    float2 vec = tex2D(Deferred::sMotionVectorsTex, i.uv).rg;
    o = float4(motionToLgbtq(vec).rgb, 1);
}

void PSWriteVectors(in VSOUT i, out float2 o : SV_Target0, out float2 p : SV_Target1, out float4 q : SV_Target2)
{
    // If disabled, bail out without writing anything so Launchpad's own (DLSS-correct) normals
    // and motion vectors that were already written earlier in the technique are left untouched.
    if (!USE_ENGINE_DATA) discard;

    // The game's internal G-buffers are captured at the internal render resolution, not the
    // final upscaled output resolution, so we need to remap our full-resolution 0-1 UV down
    // into the sub-rectangle that actually contains valid data.
    float2 uv = i.uv * ENGINE_DATA_RENDER_SCALE;

    o = FFXIV::get_motion(uv).rg;
    p = o;
    
    // normals need to be reoriented
    float3 blah = FFXIV::get_normal(uv);
    blah.r = 1.0 - blah.r;
    float2 n = FFXIV::_encode(blah - 0.5);
    q = n.rgrg;
}

/* End of original Crashpad Functionality */

technique FFXIV_ImmPad
{
    // All of these outputs are in Launchpad. It's possible some of this could be removed or cleaned up but that's a future someone problem
    pass {VertexShader = OpticalFlowVS;PixelShader = WriteCurrFeatureAndDepthPS;RenderTarget0 = FlowFeaturesCurrL0;RenderTarget1 = LinearDepthCurr; }
	pass {VertexShader = OpticalFlowVS;PixelShader = DownsampleFeaturesPS1;RenderTarget0 = FlowFeaturesCurrL1;RenderTarget1 = FlowFeaturesPrevL1;}
	pass {VertexShader = OpticalFlowVS;PixelShader = DownsampleFeaturesPS2;RenderTarget0 = FlowFeaturesCurrL2;RenderTarget1 = FlowFeaturesPrevL2;}
	pass {VertexShader = OpticalFlowVS;PixelShader = DownsampleFeaturesPS3;RenderTarget0 = FlowFeaturesCurrL3;RenderTarget1 = FlowFeaturesPrevL3;}
	pass {VertexShader = OpticalFlowVS;PixelShader = DownsampleFeaturesPS4;RenderTarget0 = FlowFeaturesCurrL4;RenderTarget1 = FlowFeaturesPrevL4;}
	pass {VertexShader = OpticalFlowVS;PixelShader = DownsampleFeaturesPS5;RenderTarget0 = FlowFeaturesCurrL5;RenderTarget1 = FlowFeaturesPrevL5;}
	pass {VertexShader = OpticalFlowVS;PixelShader = DownsampleFeaturesPS6;RenderTarget0 = FlowFeaturesCurrL6;RenderTarget1 = FlowFeaturesPrevL6;}
	pass {VertexShader = OpticalFlowVS;PixelShader = DownsampleFeaturesPS7;RenderTarget0 = FlowFeaturesCurrL7;RenderTarget1 = FlowFeaturesPrevL7;}	

	pass Flow7 {VertexShader = OpticalFlowVS;PixelShader = BlockMatchingPassNewPS7V2;	RenderTarget = MotionTexLA7;}
	pass {VertexShader = OpticalFlowVS;PixelShader = FilterFlowPS7;	RenderTarget = MotionTexLB7;}	//sMotionTexLA7 -> MotionTexLB7
	pass Flow6 {VertexShader = OpticalFlowVS;PixelShader = BlockMatchingPassNewPS6V2;	RenderTarget = MotionTexLA6;}
	pass {VertexShader = OpticalFlowVS;PixelShader = FilterFlowPS6;	RenderTarget = MotionTexLB6;}
	pass Flow5 {VertexShader = OpticalFlowVS;PixelShader = BlockMatchingPassNewPS5V2;	RenderTarget = MotionTexLA5;}
	pass {VertexShader = OpticalFlowVS;PixelShader = FilterFlowPS5;	RenderTarget = MotionTexLB5;}
	pass Flow4 {VertexShader = OpticalFlowVS;PixelShader = BlockMatchingPassNewPS4V2;	RenderTarget = MotionTexLA4;}
	pass {VertexShader = OpticalFlowVS;PixelShader = FilterFlowPS4;	RenderTarget = MotionTexLB4;}	
	pass Flow3 {VertexShader = OpticalFlowVS;PixelShader = BlockMatchingPassNewPS3V2;	RenderTarget = MotionTexLA3;}
	pass {VertexShader = OpticalFlowVS;PixelShader = FilterFlowPS3;	RenderTarget = MotionTexLB3;}	
	pass Flow2 {VertexShader = OpticalFlowVS;PixelShader = BlockMatchingPassNewPS2V2;	RenderTarget = MotionTexLA2;}
	pass {VertexShader = OpticalFlowVS;PixelShader = FilterFlowPS2;	RenderTarget = MotionTexLB2;}	
	pass Flow1 {VertexShader = OpticalFlowVS;PixelShader = BlockMatchingPassNewPS1V2;	RenderTarget = MotionTexLA1;}
	pass {VertexShader = OpticalFlowVS;PixelShader = FilterFlowPS1;	RenderTarget = MotionTexLB1;}	
	pass Flow0 {VertexShader = OpticalFlowVS;PixelShader = BlockMatchingPassNewPS0V2;	RenderTarget = MotionTexLA0;}

	pass {VertexShader = OpticalFlowVS;PixelShader = UpscaleFilter8to4PS;	RenderTarget = MotionTexUpscale;}
	pass {VertexShader = OpticalFlowVS;PixelShader = UpscaleFilter4to2PS;	RenderTarget = MotionTexUpscale2;}
	pass {VertexShader = OpticalFlowVS;PixelShader = UpscaleFilter2to1PS;	RenderTarget = Deferred::MotionVectorsTex;}

	pass {VertexShader = OpticalFlowVS;PixelShader = WritePrevFeaturePS;RenderTarget0 = FlowFeaturesPrevL0;}
	pass {VertexShader = OpticalFlowVS;PixelShader = WritePrevDepthMipPS;RenderTarget0 = LinearDepthPrevLo;}

    //Albedo
	pass AlbedoPyramidInit   {VertexShader = AlbedoVS;PixelShader = InitAlbedoPyramidPS;  RenderTarget0 = AlbedoPyramidL0; }     
#if LOWEST_LEVEL >= 1
    pass AlbedoDownsample0A  {VertexShader = AlbedoVS;PixelShader = DownsamplePS0H;  RenderTarget0 = AlbedoPyramidL1Tmp; } 
    pass AlbedoDownsample0B  {VertexShader = AlbedoVS;PixelShader = DownsamplePS0V;  RenderTarget0 = AlbedoPyramidL1; } 
#endif
#if LOWEST_LEVEL >= 2
    pass AlbedoDownsample1A  {VertexShader = AlbedoVS;PixelShader = DownsamplePS1H;  RenderTarget0 = AlbedoPyramidL2Tmp; } 
    pass AlbedoDownsample1B  {VertexShader = AlbedoVS;PixelShader = DownsamplePS1V;  RenderTarget0 = AlbedoPyramidL2; }
#endif
#if LOWEST_LEVEL >= 3 
    pass AlbedoDownsample2A  {VertexShader = AlbedoVS;PixelShader = DownsamplePS2H;  RenderTarget0 = AlbedoPyramidL3Tmp; } 
    pass AlbedoDownsample2B  {VertexShader = AlbedoVS;PixelShader = DownsamplePS2V;  RenderTarget0 = AlbedoPyramidL3; }
#endif
#if LOWEST_LEVEL >= 4 
    pass AlbedoDownsample3A  {VertexShader = AlbedoVS;PixelShader = DownsamplePS3H;  RenderTarget0 = AlbedoPyramidL4Tmp; } 
    pass AlbedoDownsample3B  {VertexShader = AlbedoVS;PixelShader = DownsamplePS3V;  RenderTarget0 = AlbedoPyramidL4; } 
#endif
#if LOWEST_LEVEL >= 5 
    pass AlbedoDownsample4A  {VertexShader = AlbedoVS;PixelShader = DownsamplePS4H;  RenderTarget0 = AlbedoPyramidL5Tmp; } 
    pass AlbedoDownsample4B  {VertexShader = AlbedoVS;PixelShader = DownsamplePS4V;  RenderTarget0 = AlbedoPyramidL5; }
#endif
#if LOWEST_LEVEL >= 6 
    pass AlbedoDownsample5A  {VertexShader = AlbedoVS;PixelShader = DownsamplePS5H;  RenderTarget0 = AlbedoPyramidL6Tmp; } 
    pass AlbedoDownsample5B  {VertexShader = AlbedoVS;PixelShader = DownsamplePS5V;  RenderTarget0 = AlbedoPyramidL6; }
#endif
#if LOWEST_LEVEL >= 7 
    pass AlbedoDownsample6A  {VertexShader = AlbedoVS;PixelShader = DownsamplePS6H;  RenderTarget0 = AlbedoPyramidL7Tmp; } 
    pass AlbedoDownsample6B  {VertexShader = AlbedoVS;PixelShader = DownsamplePS6V;  RenderTarget0 = AlbedoPyramidL7; }
#endif
#if LOWEST_LEVEL >= 8 
    pass AlbedoDownsample7A  {VertexShader = AlbedoVS;PixelShader = DownsamplePS7H;  RenderTarget0 = AlbedoPyramidL8Tmp; } 
    pass AlbedoDownsample7B  {VertexShader = AlbedoVS;PixelShader = DownsamplePS7V;  RenderTarget0 = AlbedoPyramidL8; }
#endif 
#if LOWEST_LEVEL >= 9 
    pass AlbedoDownsample8A  {VertexShader = AlbedoVS;PixelShader = DownsamplePS8H;  RenderTarget0 = AlbedoPyramidL9Tmp; } 
    pass AlbedoDownsample8B  {VertexShader = AlbedoVS;PixelShader = DownsamplePS8V;  RenderTarget0 = AlbedoPyramidL9; }
#endif
    pass FuseAlbedoPyramid   {VertexShader = AlbedoVS; PixelShader = FusePS; RenderTarget0 = FusedAlbedoPyramid; }
    pass UpscaleAlbedoPyramid{VertexShader = AlbedoVS; PixelShader = AlbedoMainPS; RenderTarget = Deferred::AlbedoTex;}

    pass Normals 		{VertexShader = NormalsVS;      PixelShader = NormalsPS; RenderTarget0 = Deferred::GeoNormalsTexV4; RenderTarget1 = Deferred::NormalsTexV4; }	
	pass SmoothNormals0 {VertexShader = SmoothNormalsVS;PixelShader = SmoothNormalsMakeGbufPS;  RenderTarget = SmoothNormalsTempTex0;}
	pass SmoothNormals1 {VertexShader = SmoothNormalsVS;PixelShader = SmoothNormalsPass0PS;  RenderTarget = SmoothNormalsTempTex1;}
	pass SmoothNormals2 {VertexShader = SmoothNormalsVS;PixelShader = SmoothNormalsPass1PS;  RenderTarget = Deferred::GeoNormalsTexV4;}
	pass CopyNormals    {VertexShader = NormalsVS;	    PixelShader = CopyNormalsPS; RenderTarget = Deferred::NormalsTexV4; }	


    #if LAUNCHPAD_DEBUG_OUTPUT != 0 //why waste perf for this pass in normal mode
	
	//debug may or may not need all of them.
	IPC_REQUEST_FEATURE(MARTYSMODS_IPC_FEATURE_NORMALS | MARTYSMODS_IPC_FEATURE_ALBEDO | MARTYSMODS_IPC_FEATURE_OPTICALFLOW)

	pass {VertexShader = MainVS;PixelShader  = DebugPS;  }	
	pass 
	{
		PrimitiveTopology = TRIANGLELIST;
		VertexCount = NUM_VECTORS_X * NUM_VECTORS_Y * 3;
		VertexShader = FlowVectorDebugVS;
		PixelShader  = FlowVectorDebugPS;
		BlendEnable=true;
		BlendOp=ADD;
		SrcBlend=SRCALPHA;
		DestBlend=INVSRCALPHA;
	} 		
#endif

// Everything here is normally in Crashpad.
    pass  
    {
        VertexShader = VS_Main;
        PixelShader  = PSWriteVectors; 
        RenderTarget0 = texMotionVectors;
        RenderTarget1 = Deferred::MotionVectorsTex;
        RenderTarget2 = Deferred::NormalsTexV4;
        RenderTarget3 = Deferred::GeoNormalsTexV4;
    }

    pass 
    {
        VertexShader = VS_Main;
        PixelShader  = PSOut; 
    }     
}