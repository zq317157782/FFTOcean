Shader "Water/Ocean"
{
	Properties
	{
		[Header(Base)]
		_MainTex ("Texture", 2D) = "white" {}
		[NoScaleOffset]_DisplacementMap("DisplacementMap", 2D) = "white" {}
		[Bump][NoScaleOffset]_NormalMap("NormalMap", 2D) = "white" {}
		_IOR("IOR",Range(0,3)) = 1.33
		_Roughness("Roughness",Range(0,1)) = 0.1
		[Header(Foam)]
		_FoldMap("FoldMap", 2D) = "white" {}
		_FoamMap("FoamMap", 2D) = "white" {}
		[Bump][NoScaleOffset]_FoamNormalMap("FoamNormalMap", 2D) = "white" {}
		_FoamScale("FoamScale",Range(0,10)) = 1
		_FoamOffset("FoamOffset",Range(-1,1)) = 0
		[Header(SSS)]
		_SubsurfaceBaseColor("SSS Base Color", Color) = (0,0,0,1)
		_SubsurfaceColor("SSS Color", Color) = (1,1,1,1)
		[Header(Refraction)]
		_DepthColor("Depth Color", Color) = (1,1,1,1)
		_DepthScale("Depth Scale",Range(0,2)) = 1
		_DepthOffset("Depth Offset",Range(-3,3)) = 0
		[Header(Wind)]
		_WindDir("Wind Direction",Range(0,3.1415928))=0
			//_WindDir("Wind Direction",Range(0,3.1415928)) = 0
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
#define PI 3.1415926
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float2 uv2 : TEXCOORD1;
				float3 normal:NORMAL;
				float4 tangent:TANGENT;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				UNITY_FOG_COORDS(1)
				float4 vertex : SV_POSITION;
				float3 normal:TEXCOORD1;
				float3 tangent:TEXCOORD2;
				float3 binormal:TEXCOORD3;
				float4 vertex_objectSpace:TEXCOORD4;
				float4 params:TEXCOORD5;
				float4 screenPos:TEXCOORD6;
				float2 uv2 : TEXCOORD7;
			};

			sampler2D _MainTex;
			float4 _MainTex_ST;
			sampler2D _DisplacementMap;
			sampler2D _NormalMap;
			sampler2D _FoldMap;
			sampler2D _FoamMap;
			float4 _FoamMap_ST;
			sampler2D _FoamNormalMap;
			//float4 _FoamNormalMap_ST;
			float4 _FoamColor;
			float _FoamScale;
			float _FoamOffset;

			float _IOR;
			float _Roughness;

			fixed4 _SubsurfaceBaseColor;
			fixed4 _SubsurfaceColor;
			float3 _LightColor0;

			sampler2D _CameraDepthTexture;
			sampler2D RefractionTexture;


			fixed4 _DepthColor;
			float _DepthScale;
			float _DepthOffset;

			float _WindDir;

			//schlick fresnel
			float Fresnel(float R0,float cosTheta) {
				float one_m_cosTheta = 1 - cosTheta;
				float one_m_cosTheta2 = one_m_cosTheta*one_m_cosTheta;
				return R0 + (1 - R0)*one_m_cosTheta*one_m_cosTheta2*one_m_cosTheta2;
			}

			float GGX_D(float roughness,float ndoth){
				float alpha = roughness*roughness;
				float alpha2 = alpha*alpha;
				float term = 1 + (alpha2 - 1)*ndoth*ndoth;
				return alpha2 / (PI*term*term);
			}

			float Smith_G1(float roughness,float ndotv) {
				float alpha = roughness*roughness;
				float alpha2 = alpha*alpha;
				return (2 * ndotv) / (ndotv + sqrt(alpha2 + (1 - alpha2)*ndotv*ndotv));
			}

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
				float4 vertex = v.vertex;
				float4 offset = tex2Dlod(_DisplacementMap, float4(v.uv.xy, 0, 0));
				//offset.xz = -offset.xz;
				vertex.xyz = vertex.xyz + offset.xyz;

				//计算binormal
				float3 normal = v.normal;
				float3 tangent = v.tangent;
				float3 binormal = cross(normal, tangent)*v.tangent.w;

				o.normal = normal;
				o.tangent = tangent;
				o.binormal = binormal;

				o.vertex_objectSpace = vertex;

				//计算R0
				float r0 = (1 - _IOR) / (1 + _IOR);
				o.params.x=r0*r0;


				o.vertex = UnityObjectToClipPos(vertex);

				o.screenPos = ComputeGrabScreenPos(o.vertex);
				COMPUTE_EYEDEPTH(o.screenPos.z);//把深度值放到还没有使用的screenPos.z中

				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				o.uv2 = TRANSFORM_TEX(v.uv2, _FoamMap);
				UNITY_TRANSFER_FOG(o,o.vertex);
				return o;
			}
			
			fixed4 frag (v2f i) : SV_Target
			{

				float3 wn  = UnityObjectToWorldNormal(i.normal);
				float3 wt = UnityObjectToWorldDir(i.tangent);
				float3 wb = UnityObjectToWorldDir(i.binormal);
				float4x4 t2w = float4x4(wt.x, wn.x, wb.x, 0.0,
					 wt.y, wn.y, wb.y,  0.0,
					 wt.z, wn.z, wb.z,  0.0,
					0.0, 0.0, 0.0, 1.0);
				//float3 normal_tangentSpace = UnpackNormal(tex2D(_NormalMap, i.uv.xy));
				float3 normal_tangentSpace =tex2D(_NormalMap, i.uv.xy);
				normal_tangentSpace.xyz = normalize((normal_tangentSpace.xzy - 0.5) * 2);
				
				
				
				float3 n = mul(t2w, float4(normal_tangentSpace,0)).xyz;
				float3 light = normalize(_WorldSpaceLightPos0).xyz;
				float3 view = normalize(WorldSpaceViewDir(i.vertex_objectSpace));
				float3 wi = light;
				float3 wo = view;
				float ndotl = dot(n, wi);
				float sndotl = saturate(ndotl);
				float ndotv = dot(wo, n);
				float sndotv = saturate(ndotv);
				float R0 = i.params.x;
				float fresnel = Fresnel(R0, sndotv);

				float3 h = normalize(wo + wi);
				float  hdotv = dot(h, wo);
				float  hdotl = dot(h, wi);
				float  ndoth = dot(n, h);
		
				float2 wDir = float2(cos(_WindDir), sin(_WindDir));
				//return _WindDir;
				//FOAM---------------------
				float rawFold = tex2D(_FoldMap, i.uv.xy).r;
				float3 fold = saturate((1 - rawFold)+ _FoamOffset)*_FoamScale;
				/*fold = smoothstep(0, 1, fold);*/
				//fold = saturate(pow(fold) ;
				fixed4 foam = tex2D(_FoamMap, i.uv2.xy + _Time.x*wDir);
				float3 foam_normal = UnpackNormal(tex2D(_FoamNormalMap, i.uv2.xy+ _Time.x*wDir));
				float3 foam_normal_w = mul(t2w, float4(foam_normal, 0)).xyz;
				float  sfndotl = saturate(dot(foam_normal_w, wi));
				float anFoam = fold*foam.a;
				//-------------------------


				float D=GGX_D(_Roughness,saturate(ndoth));
				float F = Fresnel(R0, saturate(hdotl));
				float G1_v = Smith_G1(0.5 + _Roughness*0.5, sndotv);
				float G1_l = Smith_G1(0.5 + _Roughness*0.5, sndotl);
				float G = G1_v*G1_l;
				float div=(4*sndotv*sndotl);
				float3 brdf = saturate(D*F*G /div);
				
			


				float4 vertexWorld = mul(unity_ObjectToWorld, i.vertex_objectSpace);
				//反射
				float3 reflectDir = reflect(-wo, n);
				float3 envSample = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, BoxProjection(reflectDir, vertexWorld, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax));// UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectDir);
				
				//折射
				float4 screenPos = i.screenPos;
				screenPos.xy += n.xz*0.05*i.screenPos.w;
				float depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(screenPos)));
				float myDepth = (i.screenPos.z);
				//计算水面到solid的距离
				float distance = max(0, (depth - myDepth)*_DepthScale + _DepthOffset);
				//Out-Scatter factor
				fixed3 outScatter = (1 - _DepthColor);
				//投射率
				fixed3 transmitte = exp(-outScatter*distance);
				fixed4 refraction = tex2D(RefractionTexture, screenPos.xy / screenPos.w);
				
			


				float3 specular = brdf*sndotl*_LightColor0.rgb;
				float3 foamDiffuse = foam.rgb*sfndotl*_LightColor0.rgb;
				//SSS
				float msvdotl = saturate(dot(wi, -wo));
				fixed3 sss = _SubsurfaceBaseColor+pow(msvdotl, 20)*_LightColor0.rgb*sndotv*_SubsurfaceColor;
				float3 water = envSample*fresnel +specular*(1-anFoam) + foamDiffuse*anFoam + (1 - fresnel)*transmitte*refraction.rgb + sss;

			
				// apply fog
				UNITY_APPLY_FOG(i.fogCoord, water);
				//return float4(light, 0);
				//return float4(specular, 1);
				
				return float4(water,0);
			}
			ENDCG
		}
	}
}
