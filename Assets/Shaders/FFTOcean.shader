Shader "Unlit/FFTOcean"
{
	Properties
	{
	_MainTex ("Texture", 2D) = "white" {}
	_NormalMap("NormalMap", 2D) = "white" {}
	[Header(Depth)]
	_DepthColor("Depth Color", Color) = (1,1,1,1)
	_DepthScale("Depth Scale",Range(0,2)) = 1
	_DepthOffset("Depth Offset",Range(-3,3)) = 0
	[Header(Material)]
	_IOR("IOR",Range(0,5)) = 1.33
	_Roughness("Roughness",Range(0,1)) = 0.1
	_ChoppyScale("Choppy Scale",Range(0.00001,5)) = 1
	}
	SubShader
	{
		Tags { "RenderType"="Opaque" }
		LOD 100
		GrabPass{ "RefractionTexture" }
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			// make fog work
			#pragma multi_compile_fog
#pragma target 5.0
			#include "UnityCG.cginc"
#define PI 3.1415926
			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float3 normal:NORMAL;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				UNITY_FOG_COORDS(1)
				float4 vertex : SV_POSITION;
				float4 screenPos:TEXCOORD2;
				//float4 normal:TEXCOORD3;
				float4 vertexObj:TEXCOORD4;
				float4 reflectionZero:TEXCOORD5;
			};

			sampler2D _MainTex;
			float4  _MainTex_TexelSize;
			float4 _MainTex_ST;

			sampler2D _NormalMap;
			float4 _NormalMap_ST;

			sampler2D _CameraDepthTexture;
			sampler2D RefractionTexture;


			fixed4 _DepthColor;
			float _DepthScale;
			float _DepthOffset;

			float _IOR;
			float _Roughness;

			float3 _LightColor0;
			float _ChoppyScale;

			float3 BoxProjection(float3 direction, float3 position, float4 cubemapPosition, float3 boxMin, float3 boxMax) {
				if (cubemapPosition.w > 0) {
					float3 factors =
						((direction > 0 ? boxMax : boxMin) - position) / direction;
					float scalar = min(min(factors.x, factors.y), factors.z);
					direction = direction * scalar + (position - cubemapPosition);
				}
				return direction;
			}

			v2f vert (appdata v)
			{
				v2f o;
				float4 heightMap = tex2Dlod(_MainTex, float4(v.uv.xy, 0, 0));
				

				float4 vertex = v.vertex + float4(heightMap.x*_ChoppyScale, heightMap.y, heightMap.z*_ChoppyScale,0);
				o.vertex = UnityObjectToClipPos(vertex);
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				UNITY_TRANSFER_FOG(o,o.vertex);

				


				o.screenPos = ComputeGrabScreenPos(o.vertex);
				COMPUTE_EYEDEPTH(o.screenPos.z);//把深度值放到还没有使用的screenPos.z中
				//o.normal.xyz = normal;
				o.vertexObj = vertex;

				//计算R0
				o.reflectionZero.x = (1 - _IOR) / (1 + _IOR);
				o.reflectionZero.x = o.reflectionZero.x*o.reflectionZero.x;

				//o.normal = tex2Dlod(_NormalMap, float4(v.uv.xy, 0, 0));

				return o;
			}
			
			fixed4 frag (v2f i) : SV_Target
			{
				fixed4 col=tex2D(_MainTex,i.uv);

			/*	float4 heightMap = tex2D(_MainTex, i.uv.xy + float2(_MainTex_TexelSize.x, 0));
				float4 heightMap_r = tex2D(_MainTex, i.uv.xy + float2(_MainTex_TexelSize.x, 0));
				float4 heightMap_t = tex2D(_MainTex, i.uv.xy + float2(0, _MainTex_TexelSize.y));
				float4 heightMap_l = tex2D(_MainTex, i.uv.xy + float2(-_MainTex_TexelSize.x, 0));
				float4 heightMap_b = tex2D(_MainTex, i.uv.xy + float2(0, -_MainTex_TexelSize.y));

				float3 tangent_t = float3(2.0/512, heightMap_r.y - heightMap_l.y, 0);
				float3 binormal_t = float3(0, heightMap_t.y - heightMap_b.y, 2.0/512);
				float3 normal_t = normalize(cross(binormal_t, tangent_t));*/


				float4 normal_t = tex2D(_NormalMap, i.uv.xy);
				normal_t.xyz = (normal_t.xzy - 0.5)* 2;
				//return float4(normal_t.ggg*0.5 + 0.5, 1);
				//return -normal_t.w*10;
				

				float3 normal= normalize(UnityObjectToWorldNormal(normal_t.xyz));
				float3 view = normalize(WorldSpaceViewDir(i.vertexObj));
				float3 lightDirW = normalize(_WorldSpaceLightPos0).xyz;


				float4 vertexWorld = mul(unity_ObjectToWorld, i.vertexObj);

				float4 screenPos = i.screenPos;
				screenPos.xy += normal.xz*0.05*i.screenPos.w;

				float depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(screenPos)));
				float myDepth = (i.screenPos.z);
				//计算水面到solid的距离
				float distance = max(0, (depth - myDepth)*_DepthScale+_DepthOffset);

				//Out-Scatter factor
				fixed3 outScatter = (1 - _DepthColor);
				//投射率
				fixed3 transmitte = exp(-outScatter*distance);

				fixed4 refraction = tex2D(RefractionTexture, screenPos.xy / screenPos.w);

				//schlick fresnel
				float cosThetaAbs = saturate(dot(normal, view));
				float R0 = i.reflectionZero;
				float fresnel = R0 + (1 - R0)*pow(1 - cosThetaAbs, 5);

				//反射
				float3 reflectDir = reflect(-view, normal);
				float3 envSample = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, BoxProjection(reflectDir, vertexWorld, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax));// UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectDir);


				//计算specular brdf
				float3 halfVec = normalize(lightDirW + view);
				float hdotv = saturate(dot(halfVec, view));
				float hdotl= saturate(dot(halfVec, lightDirW));
				float ndoth = saturate(dot(halfVec, normal));
				float ndotl = saturate(dot(normal, lightDirW));
				float ndotv = cosThetaAbs;

				//GGX D
				float alpha = _Roughness*_Roughness;
				float D_GGX = alpha*alpha / (PI*pow(1 + (alpha*alpha - 1)*ndoth*ndoth, 2));
				//GGX Fresnel
				float F= R0 + (1 - R0)*pow(1 - hdotv, 5);
				//GGX G using Disney roughness
				float alphaG = pow(0.5 + _Roughness*0.5, 2);
				float G1 = (2 * ndotv) / (ndotv + sqrt(alphaG*alphaG + (1 - alphaG*alphaG)*ndotv*ndotv));
				float G2 = (2 * ndotl) / (ndotl + sqrt(alphaG*alphaG + (1 - alphaG*alphaG)*ndotl*ndotl));
				float G = G1*G2;
				float term = (4 * ndotv*ndotl);

				float brdf_specular = saturate(D_GGX*F*G/term);

				// apply fog
				UNITY_APPLY_FOG(i.fogCoord, col);
				
				float faomMask = 0;// saturate(-Jacobian) * 10;
				//return float4(heightMap.xz, 0, 0);
				fixed3 ocean = brdf_specular*_LightColor0*ndotl + fresnel* envSample + (1 - fresnel)*transmitte*refraction;
				return fixed4((1-faomMask)*ocean+ faomMask*fixed3(1,1,1),1);
				
			}
			ENDCG
		}
	}
}
