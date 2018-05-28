Shader "RenderLab/AdvanceWater"
{
	Properties
	{
		[Header(Wave Global Setting)]
		_AmplitudeLengthRatio("The ratio of Amplitude and Wave Length",Range(0.0001,0.2)) = 1
		_Steepness("Steepness",Range(0,1)) = 0.1
		[Header(Wave1)]
		_GeometryWave1Theta("Geometry Wave 1 Direction",Range(0,1)) = 0 //极坐标 theta
		_GeometryWave1Length("Geometry Wave 1 Length",Range(1,10)) = 5 //波长
		_GeometryWave1Speed("Geometry Wave 1 Speed",Range(0,50)) = 1
		_GeometryWave1AmplitudeScale("Geometry Wave 1 Amplitude Scale",Range(0.0001,50))=1
		[Header(Wave2)]
		_GeometryWave2Theta("Geometry Wave 2 Direction",Range(0,1)) = 0 //极坐标 theta
		_GeometryWave2Length("Geometry Wave 2 Length",Range(0.5,5)) = 2 //波长
		_GeometryWave2Speed("Geometry Wave 2 Speed",Range(0,50)) = 1
		_GeometryWave2AmplitudeScale("Geometry Wave 2 Amplitude Scale",Range(0.0001,50))=1
		[Header(Wave3)]
		_GeometryWave3Theta("Geometry Wave 3 Direction",Range(0,1)) = 0 //极坐标 theta
		_GeometryWave3Length("Geometry Wave 3 Length",Range(0,3)) = 1 //波长
		_GeometryWave3Speed("Geometry Wave 3 Speed",Range(0,50)) = 1
		_GeometryWave3AmplitudeScale("Geometry Wave 3 Amplitude Scale",Range(0.0001,50))=1
		[Header(Wave4)]
		_BumpTex("Bump Tex", 2D) = "bump" {}
		_BumpWaveTheta("Bump Wave  Direction",Range(0,1)) = 0 //极坐标 theta
		_BumpWaveSpeed("Bump Wave  Speed",Range(0,50)) = 1
		[Header(Churn)]
		_ChurnColor("Churn Color", Color) = (1,1,1,1)
		_ChurnScale("Churn Scale",Range(0,5)) = 1
		_ChurnOffset("Churn Offset",Range(-1,1)) = 0
		[Header(Depth)]
		_DepthColor("Depth Color", Color) = (1,1,1,1)
		_DepthScale("Depth Scale",Range(0,20)) = 1
		_DepthOffset("Depth Offset",Range(-1,1)) = 0
		[Header(Material)]
		_IOR("IOR",Range(0,5)) = 1.33
		_SpecularPower("Specular Power",Range(0,5000)) = 25

	}
		SubShader
		{
			Tags { "RenderType" = "Opaque" }
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

	#define PI 3.1415926
	#define TWO_PI PI*2
	#define PLANER_TO_MODEL(X) X.xzy
	#define MODEL_TO_PLANER(X) X.xzy
	#define GEOM_WAVE_NUM 3
			float _Steepness;
			float _AmplitudeLengthRatio;
			
			sampler2D _BumpTex;
			float4 _BumpTex_ST;
			float _GeometryWave1Theta;
			float _GeometryWave1Length;
			float _GeometryWave1Speed;
			float _GeometryWave1AmplitudeScale;
			float _GeometryWave2Theta;
			float _GeometryWave2Length;
			float _GeometryWave2Speed;
			float _GeometryWave2AmplitudeScale;
			float _GeometryWave3Theta;
			float _GeometryWave3Length;
			float _GeometryWave3Speed;
			float _GeometryWave3AmplitudeScale;

			float _BumpWaveTheta;
			float _BumpWaveSpeed;

			sampler2D RefractionTexture;//折射贴图
			float4 RefractionTexture_ST;
			float _DepthScale;
			float _DepthOffset;
			sampler2D _CameraDepthTexture;
			float _ChurnScale;
			float _ChurnOffset;
			fixed4 _ChurnColor;
			fixed4 _DepthColor;
			float _IOR;
			float _SpecularPower;

			float2 Theta2Vector(float normalizedTheta) {
				//先把Theta转换到弧度
				float theta = normalizedTheta*TWO_PI;
				//从弧度转换到(x,y)
				return float2(cos(theta),sin(theta));
			}
			
			float Steepness(float w, float A, int numWaves,float steepness) {
				return steepness / (w*A*numWaves);
			}

			float3 GestnerWave(float nTheta,float2 xy,float t,float A,float w/*频率*/,float speed,float steepness){
				float2 D = Theta2Vector(nTheta);
				float ddotxy = dot(D, xy);
				float phi = speed * 2 * w;//计算相位
				float radian = w*ddotxy + t*phi;
				float sinValue=sin(radian);
				float cosValue = cos(radian);
				float mulFactor = steepness*A*cosValue;
				return float3(mulFactor*D.x, mulFactor*D.y, A*sinValue);
			}

			float3 GestnerWaveNormalTerm(float3 P, float w, float t, float A, float nTheta, float speed, float steepness) {
				float2 D = Theta2Vector(nTheta);
				float phi = speed * 2 * w;//计算相位

				float WA = w*A;
				float sinValue = sin(w*dot(D, P.xy) + t*phi);
				float cosValue = cos(w*dot(D, P.xy) + t*phi);
				return float3(-D.x*WA*cosValue, -D.y*WA*cosValue, -WA*sinValue*steepness);
			}

			float3 GestnerWaveTangentTerm(float3 P, float w, float t, float A, float nTheta, float speed, float steepness) {
				float2 D = Theta2Vector(nTheta);
				float phi = speed * 2 * w;//计算相位

				float WA = w*A;
				float sinValue = sin(w*dot(D, P.xy) + t*phi);
				float cosValue = cos(w*dot(D, P.xy) + t*phi);
				return float3(-steepness*D.x*D.y*WA*sinValue, -steepness*D.y*D.y*WA*sinValue,D.y*WA*cosValue);
			}


			float3 GestnerWaveBinormalTerm(float3 P, float w, float t, float A, float nTheta, float speed, float steepness) {
				float2 D = Theta2Vector(nTheta);
				float phi = speed * 2 * w;//计算相位

				float WA = w*A;
				float sinValue = sin(w*dot(D, P.xy) + t*phi);
				float cosValue = cos(w*dot(D, P.xy) + t*phi);
				return float3(-steepness*D.x*D.x*WA*sinValue, -steepness*D.x*D.y*WA*sinValue, D.y*WA*cosValue);
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
				float4 reflectionZero:TEXCOORD3;
				float4 normal:TEXCOORD4;
				float4 vertexObj:TEXCOORD6;
				float4 tangent:TEXCOORD5;
				float4 binormal:TEXCOORD7;
				float2 bump_uv :TEXCOORD8;
			};

			
			
			v2f vert (appdata v)
			{
				v2f o;
				

				float3 vertex = MODEL_TO_PLANER(v.vertex);
				//Wave1的参数
				float Theta1 = _GeometryWave1Theta;
				float L1 = _GeometryWave1Length;
				float W1 = 1 / L1;
				float A1 = _AmplitudeLengthRatio*L1*_GeometryWave1AmplitudeScale;//幅度
				float Sp1 = _GeometryWave1Speed;
				float St1 = Steepness(W1, A1, GEOM_WAVE_NUM,_Steepness);
				float3 offset1 = PLANER_TO_MODEL(GestnerWave(Theta1, vertex.xy, _Time.x, A1, W1, Sp1, St1));
				//wave2
				float Theta2 = _GeometryWave2Theta;
				float L2 = _GeometryWave2Length;
				float W2 = 1 / L2;
				float A2 = _AmplitudeLengthRatio*L2*_GeometryWave2AmplitudeScale;//幅度
				float Sp2 = _GeometryWave2Speed;
				float St2 = Steepness(W2, A2, GEOM_WAVE_NUM, _Steepness);
				float3 offset2 = PLANER_TO_MODEL(GestnerWave(Theta2, vertex.xy, _Time.x, A2, W2, Sp2, St2));
				//wave3
				float Theta3 = _GeometryWave3Theta;
				float L3 = _GeometryWave3Length;
				float W3 = 1 / L3;
				float A3 = _AmplitudeLengthRatio*L3*_GeometryWave3AmplitudeScale;//幅度
				float Sp3 = _GeometryWave3Speed;
				float St3 = Steepness(W3, A3, GEOM_WAVE_NUM, _Steepness);
				float3 offset3 = PLANER_TO_MODEL(GestnerWave(Theta3, vertex.xy, _Time.x, A3, W3, Sp3, St3));
				//计算displacement
				float3 waveVertex= v.vertex + offset1 + offset2 + offset3;
				o.vertex = UnityObjectToClipPos(waveVertex);

				float3 N1T = PLANER_TO_MODEL(GestnerWaveNormalTerm(MODEL_TO_PLANER(waveVertex), W1, _Time.x, A1, Theta1, Sp1, St1));
				float3 N2T = PLANER_TO_MODEL(GestnerWaveNormalTerm(MODEL_TO_PLANER(waveVertex), W2, _Time.x, A2, Theta2, Sp2, St2));
				float3 N3T = PLANER_TO_MODEL(GestnerWaveNormalTerm(MODEL_TO_PLANER(waveVertex), W3, _Time.x, A3, Theta3, Sp3, St3));

				float3 T1T = PLANER_TO_MODEL(GestnerWaveTangentTerm(MODEL_TO_PLANER(waveVertex), W1, _Time.x, A1, Theta1, Sp1, St1));
				float3 T2T = PLANER_TO_MODEL(GestnerWaveTangentTerm(MODEL_TO_PLANER(waveVertex), W2, _Time.x, A2, Theta2, Sp2, St2));
				float3 T3T = PLANER_TO_MODEL(GestnerWaveTangentTerm(MODEL_TO_PLANER(waveVertex), W3, _Time.x, A3, Theta3, Sp3, St3));

				float3 B1T = PLANER_TO_MODEL(GestnerWaveBinormalTerm(MODEL_TO_PLANER(waveVertex), W1, _Time.x, A1, Theta1, Sp1, St1));
				float3 B2T = PLANER_TO_MODEL(GestnerWaveBinormalTerm(MODEL_TO_PLANER(waveVertex), W2, _Time.x, A2, Theta2, Sp2, St2));
				float3 B3T = PLANER_TO_MODEL(GestnerWaveBinormalTerm(MODEL_TO_PLANER(waveVertex), W3, _Time.x, A3, Theta3, Sp3, St3));

				float3 waveNormal = N1T + N2T + N3T;
				waveNormal.y = 1 + waveNormal.y;

				float3 waveTangent = T1T + T2T + T3T;
				waveTangent.z = 1 + waveTangent.z;

				float3 waveBinormal = B1T + B2T + B3T;
				waveBinormal.x =1 + waveBinormal.x;

				
				o.uv = TRANSFORM_TEX(v.uv, RefractionTexture);
				float2 bump_dir = Theta2Vector(_BumpWaveTheta);
				o.bump_uv =TRANSFORM_TEX(v.uv, _BumpTex)+ bump_dir*_Time.x*_BumpWaveSpeed;
				//计算屏幕空间坐标
				o.screenPos = ComputeGrabScreenPos(o.vertex);
				COMPUTE_EYEDEPTH(o.screenPos.z);//把深度值放到还没有使用的screenPos.z中
				//计算R0
				o.reflectionZero.x = (1 - _IOR) / (1 + _IOR);
				o.reflectionZero.x = o.reflectionZero.x*o.reflectionZero.x;



				o.normal.xyz = waveNormal;
				o.tangent.xyz = waveTangent;
				o.binormal.xyz = waveBinormal;
				o.vertexObj = float4(waveVertex,v.vertex.w);
				
				UNITY_TRANSFER_FOG(o,o.vertex);
				return o;
			}
			
			fixed4 frag (v2f i) : SV_Target
			{

				float3 normal = UnityObjectToWorldNormal(i.normal);
				float3 tangent = UnityObjectToWorldDir(i.tangent);
				float3 binormal = UnityObjectToWorldDir(i.binormal);

				float4x4 t2w=float4x4(tangent.x, binormal.x, normal.x, 0.0,
					tangent.y, binormal.y, normal.y, 0.0,
					tangent.z, binormal.z, normal.z, 0.0,
					0.0, 0.0, 0.0, 1.0);

				half3 bump_normal = UnpackNormal(tex2D(_BumpTex, i.bump_uv));
				normal = normalize(mul(t2w, bump_normal));


				float3 view = normalize(ObjSpaceViewDir(i.vertexObj));
				float4 vertexWorld= mul(unity_ObjectToWorld, i.vertexObj);

				float4 screenPos = i.screenPos;
				screenPos.xy += normal.xz*0.05*i.screenPos.w;

				float depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(screenPos)));
				float myDepth = (i.screenPos.z);
				//计算水面到solid的距离
				float distance = max(0,(depth - myDepth)*_DepthScale + _DepthOffset);

				//Out-Scatter factor
				fixed3 outScatter = (1 - _DepthColor);
				//投射率
				fixed3 transmitte = exp(-outScatter*distance);

				//采样折射贴图
				fixed4 col = tex2D(RefractionTexture,screenPos.xy/screenPos.w);
			//	col.rgb = col.rgb *transmitte.rgb;
				float height = saturate(i.vertexObj.y*_ChurnScale + _ChurnOffset);
				//height = height;
				col.rgb = height*_ChurnColor.rgb+(1-height)*col.rgb *transmitte.rgb;
				//schlick fresnel
				float cosTheta = saturate(dot(normal, view));

				float R0 = i.reflectionZero;
				float fresnel = R0 + (1 - R0)*pow(1 - cosTheta, 5);
				//反射
				float3 reflectDir = reflect(-view,normal);
				float3 envSample = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0,BoxProjection(reflectDir, vertexWorld,unity_SpecCube0_ProbePosition,unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax));// UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectDir);

																																														   //开始计算高光
				float3 lightDirW = normalize(_WorldSpaceLightPos0).xyz;//wi
				float3 halfVec = normalize(lightDirW + view);
				float cosPhi = saturate(dot(halfVec, normal));


				// apply fog
				UNITY_APPLY_FOG(i.fogCoord, col);
				return float4(envSample*fresnel + (1 - fresnel)*col.rgb + pow(cosPhi,_SpecularPower),1);
			}
			ENDCG
		}
	}
}
