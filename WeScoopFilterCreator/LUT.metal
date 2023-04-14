//
//  lut.metal
//  ARMetal
//
//  Created by joshua bauer on 4/2/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

constant half3 kRec0 = half3(1.0, 1.0, 1.0);
struct MBEImageSaturationParams
{
    int2 offset;
    uint2 clipOrigin;
    uint2 clipMax;
    float saturation;
};

kernel void image_saturation(constant MBEImageSaturationParams *params [[buffer(0)]],
                             texture2d<half, access::sample> sourceTexture [[texture(0)]],
                             texture2d<half, access::write> destTexture [[texture(1)]],
                             sampler samp [[sampler(0)]],
                             uint2 gridPosition [[thread_position_in_grid]])
{
    // Sample the source texture at the offset sample point
    float2 sourceCoords = float2(gridPosition) + float2(params->offset);
    half4 color = sourceTexture.sample(samp, sourceCoords);

    // Calculate the perceptual luminance value of the sampled color.
    // Values taken from Rec. ITU-R BT.601-7
    half4 luminanceWeights = half4(0.299, 0.587, 0.114, 0);
    half luminance = dot(color, luminanceWeights);

    // Build a grayscale color that matches the perceived luminance,
    // then blend between it and the source color to get the desaturated
    // color value.
    half4 gray = half4(luminance, luminance, luminance, 1.0);
    half4 desaturated = mix(gray, color, half(params->saturation));

    uint2 destCoords = gridPosition + params->clipOrigin;

    // Write the blended, desaturated color into the destination texture if
    // the grid position is inside the clip rect.
    if (destCoords.x < params->clipMax.x &&
        destCoords.y < params->clipMax.y)
    {
        destTexture.write(desaturated, destCoords);
    }
}
kernel void lutKernel( texture2d<half, access::write> outputImage  [[texture(0)]],
                     // texture2d<float, access::sample> inputLUT  [[texture(1)]],
                      texture2d<half, access::sample> inputLUT  [[texture(1)]],
                      constant float &intensity  [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    
    constexpr sampler samp(coord::normalized,address::clamp_to_zero, filter::linear);
    // Sample the source texture at the offset sample point
    float2 sourceCoords = float2(gid) ;
    half4 color = inputLUT.sample(samp, sourceCoords);

    // Calculate the perceptual luminance value of the sampled color.
    // Values taken from Rec. ITU-R BT.601-7
    half4 luminanceWeights = half4(0.299, 0.587, 0.114, 0);
    half luminance = dot(color, luminanceWeights);

    // Build a grayscale color that matches the perceived luminance,
    // then blend between it and the source color to get the desaturated
    // color value.
    half4 gray = half4(0, 0, 1, 1.0);
    half4 desaturated = mix(gray, color, 1.0);

    uint2 destCoords = gid + 0;

    // Write the blended, desaturated color into the destination texture if
    // the grid position is inside the clip rect.
    
    outputImage.write(gray, gid);
     
    
    //outputImage.write(newColor42, gid);
        //.write(gray,gid);
    return ;
   // float4 textureColor = clamp(inColor, float4(0.6), float4(1.0));
   //
   // outputImage.write(textureColor,gid);
   // return ;
    /*
    if (  gid.x>100   && gid.x+100<outputImage.get_width()){
        //float4 inColor  = textureColor.read(gid);
       // half  gray     = dot(inColor.rgb, kRec0);
        
        //float4  curcolor0 = (0.0,0.0,0.0,0.0);
        //dot(inColor.rgb, kRec00);
        half  red = 0;
        half  green = 0;
        half  blue = 0;
        int param =0;
        int param_2 = int(param/2);
        int summ=param*param;
        for (int index =  gid.x-param_2; index < gid.x +param_2  ; index++)
        {
            for (int indexY =  gid.y-param_2; indexY < gid.y + param_2 ; indexY++)
                
            {   uint2 gid2 =  uint2(index,indexY);
                
                    float4 inColorTmp  = outputImage.read(gid2);
                //if (inColorTmp[3]>0){

                      red =red+ inColorTmp[0];
                      green = green+inColorTmp[1];
                      blue = blue+ inColorTmp[2];

               // }
              //  else{
              //      summ = summ - 1;
              //  }

               // half  curcolor     = dot(inColorTmp.rgb, kRec0);
               // curcolor0 = curcolor0 +curcolor;
                //half4 inColorTmp  = inTexture.read(gid);
            }
        }
       // curcolor0 = curcolor0/summ;
        if (summ == 0){
            //outputImage.write((inColor[0], inColor[1], inColor[2], 1.0), gid);
            //outputImage.write(inColor,gid);
        }
        else{
            red = red/summ;
            green = green/summ;
            blue = blue/summ;
            
            //inColor[0] = 0.3;
            //outputImage.write((inColor[0], inColor[1], inColor[2], inColor[3]), gid);
           // outputImage.write(inColor,gid);
        }
        inColor.b = 0.0;
        //outputImage.write((inColor[0], inColor[1], inColor[2], inColor[3]), gid);
        outputImage.write(inColor,gid);


       // curcolor0[1];
       // half  gray0     = dot(inColor.rgb, kRec0);
    }
    else{
       // half4 inColor  = inTexture.read(gid);
       // half  gray     = dot(inColor.rgb, kRec0);
        outputImage.write(inColor,gid);
        // outTexture.write(half4(gray, gray, gray, 1.0), gid);
        
    }
    
    return ;
    */
    
    //float4  newColor42 = (0.3,0.3,0.3,0.9);
    //mix(textureColor, float4(newColor.rgb, textureColor.w), intensity);
/*
    outputImage.write(textureColor, gid);
     return ;
    float blueColor = textureColor.b * 63.0;
    
    float2 quad1;
    quad1.y = floor(floor(blueColor) / 8.0);
    quad1.x = floor(blueColor) - (quad1.y * 8.0);
    
    float2 quad2;
    quad2.y = floor(ceil(blueColor) / 8.0);
    quad2.x = ceil(blueColor) - (quad2.y * 8.0);
    
    float2 texPos1;
    texPos1.x = (quad1.x * 0.125) + .0001 + (.12134 * textureColor.r);
    texPos1.y = (quad1.y * 0.125) + .0001 + (.12134 * textureColor.g);
    
    float2 texPos2;
    texPos2.x = (quad2.x * 0.125) + .0001 + (.12134 * textureColor.r);
    texPos2.y = (quad2.y * 0.125) + .0001 + (.12134 * textureColor.g);
 
    
    float4 newColor1 = inputLUT.sample(s, texPos1  );
    float4 newColor2 = inputLUT.sample(s, texPos2  );
   
    float4 newColor = mix(newColor1, newColor2, fract(blueColor));
    
    float4  newColor4 = mix(textureColor, float4(newColor.rgb, textureColor.w), intensity);
     
    float4 inColor  = outputImage.read(gid);
    //half  gray     = dot(inColor.rgb, kRec0);
    float4  res = (0.0,0.0,1.0,1.0);

    outputImage.write(res, gid);
*/
    //outputImage.write(newColor4,gid);
}


kernel void lutKernel2( texture2d<float, access::read_write> outputImage  [[texture(1)]],
                      texture2d<float, access::sample> inputLUT  [[texture(0)]],
                      constant float &intensity  [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    
    constexpr sampler s(coord::normalized,address::clamp_to_zero, filter::linear);

   float4 textureColor = outputImage.read(gid);
 
   //textureColor = clamp(textureColor, float4(0.6), float4(1.0));
    //textureColor.r = 6.0 ;
    //float4 newColor1 = inputLUT.sample(s, .01  );
    float blueColor = textureColor.b * 63.0;

    float2 quad1;
    quad1.y = floor(floor(blueColor) / 8.0);
    quad1.x = floor(blueColor) - (quad1.y * 8.0);

    float2 texPos1;
    texPos1.x = (quad1.x * 0.125) + .0001 + (.12134 * textureColor.r);
    texPos1.y = (quad1.y * 0.125) + .0001 + (.12134 * textureColor.g);
    
    texPos1 = float2(gid);

    float4 newColor1 = inputLUT.sample(s, texPos1  );//texPos1

    float gray = (textureColor.r + textureColor.g + textureColor.b) / 3;
    float4 res =  float4(gray * 1, gray * 1, gray * 1, textureColor.a);
    //textureColor.r = textureColor.r/2;
    float  red = 0;
    float  green = 0;
    float  blue = 0;

   // int param = 6;
    int param_2 = 3;
    float summ= 0 ;//(param+1)*(param+1);
    int w = outputImage.get_width();
    int h = outputImage.get_height();

    for (int index =  gid.x-param_2; index <= gid.x +param_2 && index>-1 &&  index<w ; index++)
    {
        for (int indexY =  gid.y-param_2; indexY <= gid.y + param_2 && indexY>-1 &&  indexY<h  ; indexY++)
            
        {   summ = summ + 1;
            uint2 gid2 =  uint2(index,indexY);
            
                float4 inColorTmp  = outputImage.read(gid2);
            //if (inColorTmp[3]>0){

                  red =red+ inColorTmp.r;
                  green = green+inColorTmp.g;
                  blue = blue+ inColorTmp.b;

           // }
          //  else{
          //      summ = summ - 1;
          //  }

           // half  curcolor     = dot(inColorTmp.rgb, kRec0);
           // curcolor0 = curcolor0 +curcolor;
            //half4 inColorTmp  = inTexture.read(gid);
        }
    }
   // curcolor0 = curcolor0/summ;
    if (summ == 0&& false){
        outputImage.write(textureColor,gid);
        return;
        //outputImage.write((inColor[0], inColor[1], inColor[2], 1.0), gid);
        //outputImage.write(inColor,gid);
    }
    else{
        red = red/summ;
        green = green/summ;
        blue = blue/summ;
        
        //inColor[0] = 0.3;
        //outputImage.write((inColor[0], inColor[1], inColor[2], inColor[3]), gid);
       // outputImage.write(inColor,gid);
    }
    float tmp_d = 0.05;
    int fl = 0;
    if (textureColor.r - red> tmp_d || textureColor.r - red< -tmp_d ){
        //textureColor.r = red;
        //fl = 1;
    }
    else{
        
    }
    if (textureColor.b - blue> tmp_d || textureColor.b - blue< -tmp_d){
       // textureColor.b = red;
        fl = 1;
    }
    else{
        
    }

    if (textureColor.g - green> tmp_d || textureColor.g - green< -tmp_d){
        //textureColor.g = red;
        fl = 1;
    }
    else{
        
    }

    //textureColor.r = red;
    if (fl == 0||true){
        textureColor.r = red;
        textureColor.b = green;
        textureColor.g = blue;
        outputImage.write(textureColor,gid);

    }
    else{
        outputImage.write(textureColor,gid);
    }
   

    //outputImage.write(res, quad1);
    //return ;
   /* float blueColor = textureColor.b * 63.0;
    
    float2 quad1;
    quad1.y = floor(floor(blueColor) / 8.0);
    quad1.x = floor(blueColor) - (quad1.y * 8.0);
    
    float2 quad2;
    quad2.y = floor(ceil(blueColor) / 8.0);
    quad2.x = ceil(blueColor) - (quad2.y * 8.0);
    
    float2 texPos1;
    texPos1.x = (quad1.x * 0.125) + .0001 + (.12134 * textureColor.r);
    texPos1.y = (quad1.y * 0.125) + .0001 + (.12134 * textureColor.g);
    
    float2 texPos2;
    texPos2.x = (quad2.x * 0.125) + .0001 + (.12134 * textureColor.r);
    texPos2.y = (quad2.y * 0.125) + .0001 + (.12134 * textureColor.g);
 
    
    float4 newColor1 = inputLUT.sample(s, texPos1  );
    float4 newColor2 = inputLUT.sample(s, texPos2  );
    
    float4 newColor = mix(newColor1, newColor2, fract(blueColor));
    
    float4  newColor4 = mix(textureColor, float4(newColor.rgb, textureColor.w), intensity);
     
    float4 inColor  = outputImage.read(gid);
    //half  gray     = dot(inColor.rgb, kRec0);*/
    //float4  res = (0.0,0.0,1.0,1.0);

    //outputImage.write(res, gid);

    //outputImage.write(newColor4,gid);
}
