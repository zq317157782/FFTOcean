Shader "RenderLab/Water"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
		_WaveTex("WaveTex", 2D) = "bump" {}
		_DistanceScale("DistanceScale",Range(0,10)) = 1
		_DistanceOffset("DistanceOffset",Range(-1,1)) = 0
		_WaterColor("WaterColor", Color) = (1,1,1,1)
		_IOR("IOR",Range(0,5)) = 1
		_SpecularPower("SpecularPower",Range(0,500)) = 25

		_Amplitude("Amplitude", Range(0,2)) = 1
		_Speed("speed", Range(0,50)) = 1
		_WaveLength("Wave Length",Range(0,50)) = 1
		_DirectionX("DirectionX",Range(-1,1)) = 1
		_DirectionY("DirectionY",Range(-1,1)) = 0
		_TimeScale("Time Scale",Range(0,2)) = 1
		_Stepness("Stepness",Range(0,1)) = 0


		_AmplitudeN("Amplitude Normal", Range(0,5)) = 1
		_SpeedN("speed Normal", Range(0,100)) = 1
		_WaveLengthN("Wave Length Normal",Range(0,50)) = 1
		_DirectionXN("DirectionX Normal",Range(-1,1)) = 1
		_DirectionYN("DirectionY Normal",Range(-1,1)) = 0
		_TimeScaleN("Time Scale Normal",Range(0,2)) = 1
		_StepnessN("Stepness Normal",Range(0,1)) = 0

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
			
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float3 normal:NORMAL;
				float4 tangent:TANGENT;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				UNITY_FOG_COORDS(1)
				float4 vertex : SV_POSITION;
				float4 screenPos:TEXCOORD2;
				float  reflectionZero: TEXCOORD3;
				float3 normalV:TEXCOORD4;
				float3 view : TEXCOORD5;
				float4 worldPos:TEXCOORD6;
				float2 bump_uv : TEXCOORD7;
				float4 tangentV:TEXCOORD8;
				float4 vertexObj:TEXCOORD9;
			};

			sampler2D _MainTex;
			float4 _MainTex_ST;

			sampler2D _WaveTex;
			float4 _WaveTex_ST;

			sampler2D RefractionTexture;//折射贴图
			float4 RefractionTexture_ST;

			float _DistanceScale;
			float _DistanceOffset;

			sampler2D _CameraDepthTexture;

			fixed4 _WaterColor;

			float _IOR;

			float _SpecularPower;


			float _Amplitude;//波浪幅值
			float _Speed;//速度
			float _WaveLength;//波长
			float _DirectionX;
			float _DirectionY;
			float _TimeScale;
			float _Stepness;

			//法线波浪
			float _AmplitudeN;//波浪幅值
			float _SpeedN;//速度
			float _WaveLengthN;//波长
			float _DirectionXN;
			float _DirectionYN;
			float _TimeScaleN;
			float _StepnessN;


			float3 wave(float2 xy, float2 dir, float time) {
				float sinV = sin(((dot(normalize(dir), xy) + time*_Speed) * 2 / _WaveLength));
				float cosV = cos(((dot(normalize(dir), xy) + time*_Speed) * 2 / _WaveLength));
				float Q = _Stepness / (2 / _WaveLength*_Amplitude);
				float x = xy.x + Q*_Amplitude*dir.x*cosV;
				float y = xy.y + Q*_Amplitude*dir.y*cosV;
				return float3(x, _Amplitude *sinV, y);
			}

			float3 waveNormal(float2 xy, float2 dir, float time) {
				float3 P= wave(xy, dir, time);
				float WA = (1.0 / _WaveLength)*_Amplitude;
				float sinV = sin(((dot(normalize(dir), P.xz) + time*_Speed) * 2 / _WaveLength));
				float cosV = cos(((dot(normalize(dir), P.xz) + time*_Speed) * 2 / _WaveLength));
				float Q = _Stepness / (2 / _WaveLength*_Amplitude);
				return float3(-dir.x*WA*cosV, 1 - Q*WA*sinV,-dir.y*WA*cosV);
			}

			float3 normalWave(float2 xy, float2 dir, float time) {
				float3 P = wave(xy, dir, time);
				float WA = (1.0 / _WaveLengthN)*_AmplitudeN;
				float sinV = sin(((dot(normalize(dir), P.xz) + time*_SpeedN) * 2 / _WaveLengthN));
				float cosV = cos(((dot(normalize(dir), P.xz) + time*_SpeedN) * 2 / _WaveLengthN));
				float Q = _StepnessN / (2 / _WaveLengthN*_AmplitudeN);
				return float3(-dir.x*WA*cosV, 1 - Q*WA*sinV, -dir.y*WA*cosV);
			}

			float4x4 TangentToWorldTransform(float3 normal, float4 tangent) {
				float3 worldNormal = UnityObjectToWorldNormal(normal);
				float3 worldTangent = UnityObjectToWorldDir(tangent.xyz);
				float3 worldBinormal = cross(worldNormal, worldTangent) * tangent.w;
				return float4x4(worldTangent.x, worldBinormal.x, worldNormal.x, 0.0,
					worldTangent.y, worldBinormal.y, worldNormal.y, 0.0,
					worldTangent.z, worldBinormal.z, worldNormal.z, 0.0,
					0.0, 0.0, 0.0, 1.0);
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
				float2 dir = normalize(float2(_DirectionX, _DirectionY));
				
				//简单的GerstnerWave增加波浪效果
				//TODO 用更加复杂的模拟技术来实现,比如FFT
				float4 vertex = float4(wave(v.vertex.xz, dir, _Time.x*_TimeScale),1);
				float3 normal = normalize(waveNormal(v.vertex.xz, dir, _Time.x*_TimeScale));
				o.vertex = UnityObjectToClipPos(vertex);

				o.uv = TRANSFORM_TEX(v.uv, RefractionTexture);
				o.bump_uv = TRANSFORM_TEX(v.uv, _WaveTex)- dir*_Time.x*_TimeScale;
				UNITY_TRANSFER_FOG(o,o.vertex);
				
				

				//计算屏幕空间坐标
				o.screenPos = ComputeGrabScreenPos(o.vertex);
				COMPUTE_EYEDEPTH(o.screenPos.z);//把深度值放到还没有使用的screenPos.z中

				//计算R0
				o.reflectionZero = (1 - _IOR) / (1 + _IOR);
				o.reflectionZero = o.reflectionZero*o.reflectionZero;


				//
				o.normalV = (normal);
				o.tangentV = v.tangent;
				o.view = WorldSpaceViewDir(vertex);

				o.worldPos = mul(unity_ObjectToWorld, vertex);
				o.vertexObj = v.vertex;
				return o;
			}
			
			fixed4 frag (v2f i) : SV_Target
			{

				float2 dirN = normalize(float2(_DirectionXN, _DirectionYN));
				float3 normalWaveNormal = normalize(normalWave(i.vertexObj.xz, dirN, _Time.x*_TimeScaleN));

				half3 tnormal = UnpackNormal(tex2D(_WaveTex, i.bump_uv-dirN* _Time.x*_TimeScaleN));
				float4x4 t2w = TangentToWorldTransform(i.normalV+normalWaveNormal,i.tangentV);

				

				float3 normal = normalize(mul(t2w, tnormal));
				float3 view = normalize(i.view);

				float4 screenPos = i.screenPos;
				screenPos.xy += normal.xz*0.05*i.screenPos.w;
				
				float depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(screenPos)));
				float myDepth = (i.screenPos.z);
				//计算水面到solid的距离
				float distance=max(0,(depth-myDepth)*_DistanceScale+ _DistanceOffset);
				
				//Out-Scatter factor
				fixed3 outScatter = (1 - _WaterColor);
				//投射率
				fixed3 transmitte = exp(-outScatter*distance);

				//采样折射贴图
				fixed4 col = tex2D(RefractionTexture,screenPos.xy/screenPos.w);
				col.rgb = col.rgb *transmitte.rgb;

				//schlick fresnel
				float cosTheta = saturate(dot(normal, view));

				float R0 = i.reflectionZero;
				float fresnel = R0 + (1 - R0)*pow(1 - cosTheta, 5);
				//反射
				float3 reflectDir = reflect(-view,normal);
				float3 envSample = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0,BoxProjection(reflectDir,i.worldPos,unity_SpecCube0_ProbePosition,unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax));// UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectDir);

				//开始计算高光
				float3 lightDirW = normalize(_WorldSpaceLightPos0).xyz;//wi
				float3 halfVec = normalize(lightDirW + view);
				float cosPhi = saturate(dot(halfVec, normal));


				// apply fog
				UNITY_APPLY_FOG(i.fogCoord, col);
				return float4(envSample*fresnel + (1-fresnel)*col.rgb+pow(cosPhi,_SpecularPower),1);
			}
			ENDCG
		}
	}
}
